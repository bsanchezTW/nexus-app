import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tw_tokens.dart';
import '../../../core/utils/version_utils.dart';
import '../../../core/widgets/app_image_skeleton.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/tw_components.dart';
import '../../../data/models/github_release.dart';
import '../../../data/repositories/github_release_repository.dart';
import '../providers/update_providers.dart';
import '../services/update_platform.dart';
import '../services/update_service.dart';
import '../widgets/update_progress_view.dart';

IconData get _platformVersionIcon {
  final desktop =
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;
  if (kIsWeb || desktop) {
    return Symbols.desktop_windows_rounded;
  }
  return Symbols.smartphone_rounded;
}

/// Actualizaciones: versión instalada, la nueva (si hay) lista para bajar e
/// instalar ahí mismo, y el historial.
///
/// Es el destino del aviso de versión nueva del inicio: las actualizaciones
/// ya no llegan como modal, así que la descarga, el permiso de instalar y los
/// reintentos viven en esta pantalla.
class ActualizacionesScreen extends StatelessWidget {
  const ActualizacionesScreen({super.key});

  @override
  Widget build(BuildContext context) => const _ActualizacionesBody();
}

class _ActualizacionesBody extends ConsumerStatefulWidget {
  const _ActualizacionesBody();

  @override
  ConsumerState<_ActualizacionesBody> createState() =>
      _ActualizacionesBodyState();
}

class _ActualizacionesBodyState extends ConsumerState<_ActualizacionesBody> {
  bool _loadingVersion = true;
  bool _loadingNotes = true;
  bool _loadingHistory = true;
  String _installedVersion = '';
  String? _releaseNotes;
  String? _notesError;
  String? _historyError;
  List<GitHubRelease> _previousReleases = const [];
  String? _expandedTag;

  @override
  void initState() {
    super.initState();
    _loadCurrentReleaseInfo();
  }

  Future<void> _loadCurrentReleaseInfo() async {
    setState(() {
      _loadingVersion = true;
      _loadingNotes = true;
      _loadingHistory = true;
      _notesError = null;
      _historyError = null;
      _releaseNotes = null;
      _previousReleases = const [];
      _expandedTag = null;
    });

    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _installedVersion = info.version;
        _loadingVersion = false;
      });

      final releases = await ref
          .read(githubReleaseRepositoryProvider)
          .fetchReleases();
      if (!mounted) return;

      final installed = tryParseVersion(info.version);
      GitHubRelease? current;
      final previous = <GitHubRelease>[];

      for (final release in releases) {
        final remote = tryParseVersion(release.tagName);
        if (installed != null && remote != null) {
          if (remote == installed) {
            current ??= release;
            continue;
          }
          if (remote < installed) {
            previous.add(release);
          }
          continue;
        }

        // Sin SemVer comparable: tratar coincidencia exacta de tag como actual.
        final tag = stripVersionPrefix(release.tagName);
        final installedTag = stripVersionPrefix(info.version);
        if (tag == installedTag) {
          current ??= release;
        } else {
          previous.add(release);
        }
      }

      if (current != null) {
        final notes = current.notesForDisplay;
        setState(() {
          _releaseNotes = notes.isEmpty ? null : notes;
          _notesError = notes.isEmpty
              ? 'Este release no incluye descripción.'
              : null;
          _loadingNotes = false;
          _previousReleases = previous;
          _loadingHistory = false;
        });
      } else {
        // Fallback: notas del tag exacto si no apareció en la lista paginada.
        try {
          final byTag = await ref
              .read(githubReleaseRepositoryProvider)
              .fetchByTag(info.version);
          if (!mounted) return;
          final notes = byTag.notesForDisplay;
          setState(() {
            _releaseNotes = notes.isEmpty ? null : notes;
            _notesError = notes.isEmpty
                ? 'Este release no incluye descripción.'
                : null;
            _loadingNotes = false;
            _previousReleases = previous;
            _loadingHistory = false;
          });
        } on GitHubReleaseException catch (e) {
          if (!mounted) return;
          setState(() {
            _notesError = e.statusCode == 404
                ? 'No se encontró la descripción de esta versión en GitHub.'
                : e.message;
            _loadingNotes = false;
            _previousReleases = previous;
            _loadingHistory = false;
          });
        }
      }
    } on GitHubReleaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingVersion = false;
        _loadingNotes = false;
        _loadingHistory = false;
        _notesError = e.statusCode == 404
            ? 'No se encontró la descripción de esta versión en GitHub.'
            : e.message;
        _historyError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingVersion = false;
        _loadingNotes = false;
        _loadingHistory = false;
        _notesError =
            'No se encontró la descripción de esta versión en GitHub.';
        _historyError = 'No se pudo cargar el historial de versiones.';
      });
    }
  }

  Future<void> _buscar() async {
    final controller = ref.read(updateControllerProvider.notifier);
    await controller.checkManual();
    if (!mounted) return;

    final state = ref.read(updateControllerProvider);
    if (state.status == UpdateStatus.upToDate) {
      showAppSnackBar(context, 'Ya tienes la última versión.');
      return;
    }
    if (state.status == UpdateStatus.failed && state.info == null) {
      showAppSnackBar(
        context,
        state.errorMessage ?? 'No se pudo buscar actualizaciones.',
        isError: true,
      );
    }
    // Con versión nueva no hay modal: la tarjeta aparece en esta pantalla.
  }

  void _reintentar() {
    final controller = ref.read(updateControllerProvider.notifier);
    final s = ref.read(updateControllerProvider);
    if (s.needsInstallPermission || s.downloadedFilePath != null) {
      controller.retryInstall();
    } else {
      controller.downloadAndInstall();
    }
  }

  String _versionLabel(String tagOrVersion) {
    final stripped = stripVersionPrefix(tagOrVersion);
    return stripped.isEmpty ? tagOrVersion : 'v$stripped';
  }

  @override
  Widget build(BuildContext context) {
    final updateState = ref.watch(updateControllerProvider);
    final controller = ref.read(updateControllerProvider.notifier);
    final pendiente = otaUpdatesSupported && updateState.hasPendingUpdate;

    return AppScaffold(
      title: otaUpdatesSupported ? 'Actualizaciones' : 'Historial de versiones',
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _loadCurrentReleaseInfo,
        child: ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: AppSpacing.form,
          children: [
            _VersionInstalada(
              cargando: _loadingVersion,
              version: _installedVersion.isEmpty
                  ? ''
                  : _versionLabel(_installedVersion),
              estado: updateState,
              pendiente: pendiente,
              onBuscar: otaUpdatesSupported && !pendiente ? _buscar : null,
            ),
            if (pendiente) ...[
              const SizedBox(height: 12),
              _NuevaVersion(
                estado: updateState,
                onDescargar: controller.downloadAndInstall,
                onCancelar: controller.cancelDownload,
                onReintentar: _reintentar,
                onAbrirAjustes: controller.openInstallSettings,
              ),
            ],
            const TwSectionLabel('En esta versión'),
            _NotasActuales(
              cargando: _loadingNotes,
              notas: _releaseNotes,
              error: _notesError,
            ),
            const TwSectionLabel('Versiones anteriores'),
            if (_loadingHistory)
              const _HistorialEsqueleto()
            else if (_historyError != null || _previousReleases.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Text(
                  _historyError ?? 'No hay versiones anteriores publicadas.',
                  style: TwText.tileSubtitle,
                ),
              )
            else
              TwCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < _previousReleases.length; i++) ...[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: TwColors.border07,
                        ),
                      _FilaVersion(
                        release: _previousReleases[i],
                        versionLabel: _versionLabel(
                          _previousReleases[i].tagName,
                        ),
                        expandida: _expandedTag == _previousReleases[i].tagName,
                        onToggle: () => setState(() {
                          final tag = _previousReleases[i].tagName;
                          _expandedTag = _expandedTag == tag ? null : tag;
                        }),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Cabecera: icono de la plataforma, versión instalada y una línea de estado.
class _VersionInstalada extends StatelessWidget {
  const _VersionInstalada({
    required this.cargando,
    required this.version,
    required this.estado,
    required this.pendiente,
    required this.onBuscar,
  });

  final bool cargando;
  final String version;
  final UpdateState estado;
  final bool pendiente;

  /// `null` oculta el botón (sin OTA, o ya hay una versión nueva a la vista).
  final VoidCallback? onBuscar;

  static final _estiloVersion = TwText.tileTitle.copyWith(
    fontSize: 19,
    fontWeight: FontWeight.w800,
  );

  @override
  Widget build(BuildContext context) {
    final buscando = estado.status == UpdateStatus.checking && !pendiente;
    final (puntoColor, textoEstado) = pendiente
        ? (TwColors.blueInk, 'Hay una versión nueva')
        : estado.status == UpdateStatus.upToDate
        ? (TwColors.greenInk, 'Estás al día')
        : (TwColors.chevron, 'Versión instalada');

    return TwCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: TwColors.blueTint,
                  borderRadius: TwRadii.iconLg,
                ),
                child: Icon(
                  _platformVersionIcon,
                  size: 24,
                  color: TwColors.hero700,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (cargando)
                      AppSkeletonText(
                        muestra: 'RegisPro v1.0.0',
                        style: _estiloVersion,
                        width: 150,
                      )
                    else
                      Text('RegisPro $version', style: _estiloVersion),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: puntoColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          textoEstado,
                          style: TwText.tileSubtitle.copyWith(
                            color: TwColors.secondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (onBuscar != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: buscando ? null : onBuscar,
              icon: buscando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Symbols.refresh_rounded, size: 20),
              label: Text(buscando ? 'Buscando…' : 'Buscar actualizaciones'),
            ),
          ],
        ],
      ),
    );
  }
}

/// La versión nueva, lista para bajar. Aquí se descarga, se concede el
/// permiso de instalar y se reintenta; nada de esto bloquea el resto de la
/// app.
class _NuevaVersion extends StatelessWidget {
  const _NuevaVersion({
    required this.estado,
    required this.onDescargar,
    required this.onCancelar,
    required this.onReintentar,
    required this.onAbrirAjustes,
  });

  final UpdateState estado;
  final VoidCallback onDescargar;
  final VoidCallback onCancelar;
  final VoidCallback onReintentar;
  final VoidCallback onAbrirAjustes;

  @override
  Widget build(BuildContext context) {
    final info = estado.info!;
    final status = estado.status;
    final descargando = status == UpdateStatus.downloading;
    final verificando = status == UpdateStatus.verifying;
    final instalando = status == UpdateStatus.installing;
    final fallo = status == UpdateStatus.failed;
    final faltaPermiso =
        status == UpdateStatus.awaitingInstallPermission ||
        (fallo && estado.needsInstallPermission);

    final Widget acciones;
    if (descargando || verificando || instalando) {
      acciones = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UpdateProgressView(
            progress: descargando ? estado.progress : 1,
            label: verificando
                ? 'Verificando integridad…'
                : instalando
                ? otaInstallingLabel
                : null,
          ),
          if (descargando)
            TextButton(onPressed: onCancelar, child: const Text('Cancelar')),
        ],
      );
    } else if (faltaPermiso) {
      acciones = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Aviso(
            texto:
                estado.errorMessage ??
                'Para actualizar RegisPro debes permitir la instalación de '
                    'aplicaciones. Actívalo en Configuración y vuelve aquí.',
            color: TwColors.hero700,
            fondo: TwColors.blueTint,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onAbrirAjustes,
                  child: const Text('Configuración'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: onReintentar,
                  child: const Text('Reintentar'),
                ),
              ),
            ],
          ),
        ],
      );
    } else if (fallo) {
      acciones = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (estado.errorMessage != null) ...[
            _Aviso(
              texto: estado.errorMessage!,
              color: TwColors.danger,
              fondo: TwColors.dangerTint,
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            onPressed: onReintentar,
            icon: const Icon(Symbols.refresh_rounded, size: 20),
            label: const Text('Reintentar'),
          ),
        ],
      );
    } else {
      acciones = FilledButton.icon(
        key: const Key('actualizaciones_descargar'),
        onPressed: onDescargar,
        icon: const Icon(Symbols.download_rounded, size: 20),
        label: const Text('Descargar e instalar'),
      );
    }

    return TwCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'v${info.remoteVersion} disponible',
                  style: TwText.tileTitle.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(info.formattedSize, style: TwText.tileSubtitle),
            ],
          ),
          if (info.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            _NotasPlegables(notas: info.notes),
          ],
          const SizedBox(height: 16),
          acciones,
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto, required this.color, required this.fondo});

  final String texto;
  final Color color;
  final Color fondo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: fondo, borderRadius: TwRadii.field),
      child: Text(
        texto,
        style: TwText.supportTitle.copyWith(color: color, height: 1.4),
      ),
    );
  }
}

/// Estilo de las notas de versión: más aire entre líneas que un subtítulo.
const _estiloNotas = TextStyle(
  fontSize: 13.5,
  height: 1.5,
  fontWeight: FontWeight.w500,
  color: TwColors.secondary,
);

/// Notas de una versión recortadas a unas líneas, con "Ver todo".
class _NotasPlegables extends StatefulWidget {
  const _NotasPlegables({required this.notas});

  final String notas;

  @override
  State<_NotasPlegables> createState() => _NotasPlegablesState();
}

class _NotasPlegablesState extends State<_NotasPlegables> {
  static const _lineas = 5;

  bool _abiertas = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.notas, style: _estiloNotas),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: _lineas,
        )..layout(maxWidth: constraints.maxWidth);
        final recortadas = painter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSize(
              duration: AppMotion.toggle,
              curve: AppMotion.ease,
              alignment: Alignment.topCenter,
              child: Text(
                widget.notas,
                style: _estiloNotas,
                maxLines: _abiertas ? null : _lineas,
                overflow: _abiertas ? null : TextOverflow.ellipsis,
              ),
            ),
            if (recortadas)
              TwPressable(
                onTap: () => setState(() => _abiertas = !_abiertas),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 2),
                  child: Text(
                    _abiertas ? 'Ver menos' : 'Ver todo',
                    style: TwText.supportTitle.copyWith(
                      color: TwColors.blueInk,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _NotasActuales extends StatelessWidget {
  const _NotasActuales({
    required this.cargando,
    required this.notas,
    required this.error,
  });

  final bool cargando;
  final String? notas;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (cargando) {
      return const TwCard(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSkeletonText(muestra: 'Notas', style: _estiloNotas),
            SizedBox(height: 4),
            AppSkeletonText(muestra: 'Notas', style: _estiloNotas, width: 180),
          ],
        ),
      );
    }
    return TwCard(
      padding: const EdgeInsets.all(16),
      child: notas != null
          ? _NotasPlegables(notas: notas!)
          : Text(
              error ??
                  'No se encontró la descripción de esta versión en GitHub.',
              style: TwText.tileSubtitle,
            ),
    );
  }
}

/// Versión anterior: una fila que se despliega con sus notas.
class _FilaVersion extends StatelessWidget {
  const _FilaVersion({
    required this.release,
    required this.versionLabel,
    required this.expandida,
    required this.onToggle,
  });

  final GitHubRelease release;
  final String versionLabel;
  final bool expandida;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final nombre = release.name.trim();
    final notas = release.notesForDisplay;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Text(versionLabel, style: TwText.supportTitle),
                const SizedBox(width: 8),
                Expanded(
                  child: nombre.isNotEmpty && nombre != versionLabel
                      ? Text(
                          nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TwText.tileSubtitle,
                        )
                      : const SizedBox.shrink(),
                ),
                AnimatedRotation(
                  turns: expandida ? 0.5 : 0,
                  duration: AppMotion.toggle,
                  curve: AppMotion.ease,
                  child: const Icon(
                    Symbols.expand_more_rounded,
                    size: 20,
                    color: TwColors.chevron,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: AppMotion.toggle,
          curve: AppMotion.ease,
          alignment: Alignment.topCenter,
          child: expandida
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text(
                    notas.isEmpty
                        ? 'Este release no incluye descripción.'
                        : notas,
                    style: _estiloNotas,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _HistorialEsqueleto extends StatelessWidget {
  const _HistorialEsqueleto();

  @override
  Widget build(BuildContext context) {
    return TwCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: TwColors.border07,
              ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  AppSkeletonText(
                    muestra: 'v1.0.0',
                    style: TwText.supportTitle,
                    width: 52,
                  ),
                  SizedBox(width: 8),
                  AppSkeletonText(
                    muestra: 'Nombre',
                    style: TwText.tileSubtitle,
                    width: 120,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
