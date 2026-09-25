import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/network/offline_guard.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/nexus_components.dart';
import '../../../core/widgets/require_permission.dart';
import '../../../data/repositories/registrados_repository.dart';
import '../../auth/providers/auth_providers.dart';
import '../../eventos/providers/eventos_providers.dart';
import '../../registrados/providers/registrados_providers.dart';
import '../services/excel_export_service.dart';
import '../services/excel_import_registrados.dart';
import '../services/export_file_delivery.dart';

class ExportarScreen extends ConsumerStatefulWidget {
  const ExportarScreen({super.key, required this.eventoId});

  final String eventoId;

  @override
  ConsumerState<ExportarScreen> createState() => _ExportarScreenState();
}

class _ExportarScreenState extends ConsumerState<ExportarScreen> {
  static const _exportService = ExcelExportService();
  static const _importService = ExcelImportRegistrados();
  bool _generando = false;
  bool _importando = false;

  bool get _ocupado => _generando || _importando;

  Future<void> _exportar({required bool soloAcreditados}) async {
    if (!requireOnline(context, ref)) return;
    if (!ref.read(canExportDataProvider)) {
      showAppSnackBar(
        context,
        'No tienes permiso para exportar datos.',
        isError: true,
      );
      return;
    }
    setState(() => _generando = true);
    try {
      final registrados = await ref.read(
        registradosPorEventoProvider(widget.eventoId).future,
      );
      final evento = await ref.read(eventoByIdProvider(widget.eventoId).future);

      final filtrados = soloAcreditados
          ? registrados.where((r) => r.acreditado).toList()
          : registrados;

      if (filtrados.isEmpty) {
        if (mounted) {
          showAppSnackBar(
            context,
            'No hay datos para exportar.',
            isError: true,
          );
        }
        return;
      }

      final bytes = _exportService.generar(
        filtrados,
        tituloHoja: soloAcreditados ? 'Acreditados' : 'Registrados',
      );
      final nombreArchivo =
          '${evento.nombre.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}_${soloAcreditados ? 'acreditados' : 'registrados'}.xlsx';

      if (!mounted) return;
      final entrega = await entregarExportacion(
        context: context,
        bytes: bytes,
        nombreArchivo: nombreArchivo,
      );
      if (entrega == EntregaExportacion.cancelada || !mounted) return;
      if (entrega == EntregaExportacion.guardada) {
        showAppSnackBar(context, 'Archivo guardado.');
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 'No se pudo exportar: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  Future<void> _cargarExcel() async {
    if (!requireOnline(context, ref)) return;

    final archivo = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Excel', extensions: ['xlsx']),
      ],
    );
    if (archivo == null) return;

    setState(() => _importando = true);
    try {
      final bytes = await archivo.readAsBytes();
      final registros = _importService.parsear(
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
    return RequirePermission(
      allowed: (perfil) => perfil.canExportData,
      deniedMessage: 'Tu rol no permite exportar datos del evento.',
      builder: (_) => AppScaffold(
        title: 'Importar o exportar',
        body: ListView(
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
                  const SectionLabel('Exportación'),
                  const SizedBox(height: 10),
                  const Text(
                    'Descarga la lista de asistentes del evento para '
                    'guardarla o enviarla a quien necesites.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  PrimaryGradientButton(
                    label: 'Exportar todos los registrados',
                    loading: _generando,
                    onPressed: _ocupado
                        ? null
                        : () => _exportar(soloAcreditados: false),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  NexusActionRow(
                    icon: Symbols.verified_rounded,
                    title: 'Exportar solo acreditados',
                    subtitle: 'Incluye únicamente asistentes ya acreditados',
                    onTap: () {
                      if (!_ocupado) _exportar(soloAcreditados: true);
                    },
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
                    onPressed: _ocupado ? null : _cargarExcel,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
