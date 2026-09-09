import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/env.dart';
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

/// Comparte el enlace de autoregistro público y permite cargar un Excel con
/// registros masivos. Reemplaza a `registro-por-cliente.tsx`/
/// `RegistroPorCliente.tsx`: en el proyecto legado esta pantalla enlazaba a
/// un formulario externo (`intranet-transworld-dc.onrender.com`) fuera de
/// ambos ZIP (ver Sección 17.5 de la auditoría). Acá el formulario público
/// vive dentro de la misma app (`/registro-forms?id=…`, sin sesión).
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

  String get _link {
    final base = Env.appPublicBaseUrl.replaceAll(RegExp(r'/$'), '');
    return '$base${RoutePaths.registroPublico(widget.eventoId)}';
  }

  Future<void> _compartir(String nombreEvento) async {
    if (!requireOnline(context, ref)) return;
    await SharePlus.instance.share(
      ShareParams(text: '¡Regístrate al evento "$nombreEvento" aquí!\n$_link'),
    );
  }

  Future<void> _copiar() async {
    await Clipboard.setData(ClipboardData(text: _link));
    if (mounted) showAppSnackBar(context, 'Enlace copiado al portapapeles.');
  }

  Future<void> _abrir() async {
    final uri = Uri.parse(_link);
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

      final resultado = await ref
          .read(registradosRepositoryProvider)
          .importarLote(widget.eventoId, registros);

      ref.invalidate(registradosPorEventoProvider(widget.eventoId));

      if (mounted) {
        showAppSnackBar(
          context,
          'Se registraron ${resultado.insertados} personas'
          '${resultado.omitidos > 0 ? ' (${resultado.omitidos} omitidas por duplicado)' : ''}.',
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
                    _link,
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
                        onTap: () => _compartir(evento.nombre),
                      ),
                      _ActionChipButton(
                        icon: Symbols.content_copy_rounded,
                        label: 'Copiar',
                        onTap: _copiar,
                      ),
                      _ActionChipButton(
                        icon: Symbols.open_in_new_rounded,
                        label: 'Abrir',
                        onTap: _abrir,
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
