import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/offline_guard.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/registro_asistente.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/nexus_components.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/tw_toast.dart';
import '../../../data/repositories/registrados_repository.dart';
import '../../eventos/providers/eventos_providers.dart';
import '../../exportacion/services/excel_import_registrados.dart';
import '../../registrados/providers/registrados_providers.dart';

/// Comparte el enlace público del evento (`/eventos/<slug>`) y permite
/// cargar un Excel con registros masivos.
class RegistroPorClienteScreen extends ConsumerStatefulWidget {
  const RegistroPorClienteScreen({super.key, required this.eventoId});

  final String eventoId;

  @override
  ConsumerState<RegistroPorClienteScreen> createState() =>
      _RegistroPorClienteScreenState();
}

class _RegistroPorClienteScreenState
    extends ConsumerState<RegistroPorClienteScreen> {
  bool _importando = false;

  String _link(String slug) => RoutePaths.urlPublicaEvento(slug);

  Future<void> _compartir(String nombreEvento, String slug) async {
    if (!requireOnline(context, ref)) return;
    final link = _link(slug);
    await SharePlus.instance.share(
      ShareParams(text: '¡Regístrate al evento "$nombreEvento" aquí!\n$link'),
    );
  }

  Future<void> _copiar(String slug) async {
    await Clipboard.setData(ClipboardData(text: _link(slug)));
    if (mounted) showAppSnackBar(context, 'Enlace copiado al portapapeles.');
  }

  Future<void> _abrir(String slug) async {
    final uri = Uri.parse(_link(slug));
    try {
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_blank',
      );
      if (!ok && mounted) {
        showAppSnackBar(context, 'No se pudo abrir el enlace.', isError: true);
      }
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'No se pudo abrir el enlace.', isError: true);
      }
    }
  }

  Future<void> _cargarExcel() async {
    if (!requireOnline(context, ref)) return;
    final evento = ref.read(eventoByIdProvider(widget.eventoId)).valueOrNull;
    if (evento != null && evento.yaOcurrio) {
      TwToast.info(context, kMensajeEventoFinalizado);
      return;
    }

    final archivo = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Excel', extensions: ['xlsx']),
      ],
    );
    if (archivo == null) return;

    setState(() => _importando = true);
    try {
      final bytes = await archivo.readAsBytes();
      final registros = const ExcelImportRegistrados().parsear(
        bytes,
        eventoId: widget.eventoId,
      );

      final filas = [
        for (final r in registros)
          {
            'nombre_completo': r.nombreCompleto,
            'email': r.email,
            'empresa': r.empresa,
            'cargo': r.cargo,
            'telefono': r.telefono,
            'rut': r.rut,
            'patente': r.patente,
          },
      ];
      var resultado = await ref
          .read(registradosRepositoryProvider)
          .importar(eventoId: widget.eventoId, filas: filas);
      if (resultado.excedeCupo > 0 && resultado.puedeForzar && mounted) {
        final forzar = await confirmDialog(
          context,
          title: 'Cupo insuficiente',
          message:
              'Faltan ${resultado.excedeCupo} cupos. ¿Importar el resto en sobrecupo?',
          confirmLabel: 'Importar',
        );
        if (forzar) {
          resultado = await ref
              .read(registradosRepositoryProvider)
              .importar(
                eventoId: widget.eventoId,
                filas: filas,
                forzarSobrecupo: true,
              );
        }
      }
      if (resultado.excedeCupo > 0) {
        if (mounted) {
          showAppSnackBar(
            context,
            'No se importó nadie: el cupo no alcanza.',
            isError: true,
          );
        }
        return;
      }

      ref.invalidate(registradosPorEventoProvider(widget.eventoId));

      if (mounted) {
        showAppSnackBar(
          context,
          'Se registraron ${resultado.insertados} personas'
          '${resultado.omitidosDuplicado > 0 ? ' (${resultado.omitidosDuplicado} omitidas por duplicado)' : ''}.',
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          'No se pudo procesar el Excel: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _importando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventoAsync = ref.watch(eventoByIdProvider(widget.eventoId));

    return AppScaffold(
      title: 'Registro por cliente',
      body: eventoAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            const ErrorView(message: 'No se pudo cargar el evento.'),
        data: (evento) => ListView(
          padding: AppSpacing.form,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.border),
                boxShadow: AppColors.shadowRest,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Enlace público'),
                  const SizedBox(height: 10),
                  Text(
                    'Enlace de autoregistro',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _link(evento.slug),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ActionChipButton(
                        icon: Symbols.share_rounded,
                        label: 'Compartir',
                        filled: true,
                        onTap: () => _compartir(evento.nombre, evento.slug),
                      ),
                      _ActionChipButton(
                        icon: Symbols.content_copy_rounded,
                        label: 'Copiar',
                        onTap: () => _copiar(evento.slug),
                      ),
                      _ActionChipButton(
                        icon: Symbols.open_in_new_rounded,
                        label: 'Abrir',
                        onTap: () => _abrir(evento.slug),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.cardGap + 6),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.border),
                boxShadow: AppColors.shadowRest,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('Carga masiva'),
                  const SizedBox(height: 10),
                  Text(
                    'Carga masiva por Excel',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    ExcelImportRegistrados.descripcionColumnas,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  PrimaryGradientButton(
                    label: _importando
                        ? 'Procesando...'
                        : 'Elegir archivo .xlsx',
                    loading: _importando,
                    onPressed: _importando ? null : _cargarExcel,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.cardGap + 6),
            NexusActionRow(
              icon: Symbols.person_add_rounded,
              title: 'Registrar manualmente',
              subtitle: 'Formulario individual de asistente',
              onTap: () {
                if (!requireOnline(context, ref)) return;
                context.push(RoutePaths.registrar(widget.eventoId));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionChipButton extends StatelessWidget {
  const _ActionChipButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      scale: 0.96,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: filled ? AppColors.primaryDeep : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: filled ? AppColors.primaryDeep : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: filled ? Colors.white : AppColors.primary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: filled ? Colors.white : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
