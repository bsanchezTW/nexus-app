import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tw_tokens.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/nexus_components.dart';
import '../../../core/widgets/tw_components.dart';
import '../../../data/models/evento.dart';
import '../../eventos/providers/eventos_providers.dart';
import '../providers/kpi_providers.dart';

class KpiScreen extends ConsumerWidget {
  const KpiScreen({super.key, required this.eventoId});

  final String eventoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpiDataAsync = ref.watch(kpiDataPorEventoProvider(eventoId));
    final eventoAsync = ref.watch(eventoByIdProvider(eventoId));

    return AppScaffold(
      title: 'KPI del evento',
      body: kpiDataAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            const ErrorView(message: 'No se pudieron cargar los datos.'),
        data: (kpi) {
          final total = kpi.total;
          final acreditados = kpi.acreditados;
          final pendientesDeSync = kpi.pendientesDeSync;
          final porcentaje = kpi.porcentaje;
          final topEmpresas = kpi.topEmpresas;

          return ListView(
            padding: AppSpacing.form,
            children: [
              eventoAsync.maybeWhen(
                data: (e) => Text(
                  e.nombre,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                orElse: () => const SizedBox.shrink(),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      value: '$total',
                      label: 'Registrados',
                      icon: Symbols.group_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      value: '$acreditados',
                      label: 'Acreditados',
                      icon: Symbols.check_circle_rounded,
                      tint: AppColors.successTint,
                      iconColor: AppColors.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      value: '${(porcentaje * 100).toStringAsFixed(0)}%',
                      label: '% Acreditación',
                      icon: Symbols.percent_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      value: '$pendientesDeSync',
                      label: 'Sin sincronizar',
                      icon: Symbols.sync_problem_rounded,
                      tint: pendientesDeSync > 0
                          ? AppColors.dangerTint
                          : AppColors.tintNavy,
                      iconColor: pendientesDeSync > 0
                          ? AppColors.danger
                          : AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(
                  value: porcentaje,
                  minHeight: 10,
                  backgroundColor: AppColors.surfaceMuted,
                  color: AppColors.success,
                ),
              ),
              if (kpi.talleres.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sectionGap + 6),
                const SectionLabel('Talleres'),
                const SizedBox(height: 10),
                for (final taller in kpi.talleres) ...[
                  _TarjetaTaller(taller: taller),
                  const SizedBox(height: 12),
                ],
              ],
              if (topEmpresas.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sectionGap + 6),
                const SectionLabel('Empresas'),
                const SizedBox(height: 10),
                Text(
                  'Empresas con más asistentes',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                ...topEmpresas.take(10).toList().asMap().entries.map((entry) {
                  final e = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: AppColors.border),
                        boxShadow: AppColors.shadowRest,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.key,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          StatusChip(
                            label: '${e.value}',
                            variant: StatusChipVariant.neutral,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TarjetaTaller extends StatelessWidget {
  const _TarjetaTaller({required this.taller});

  final KpiSubevento taller;

  @override
  Widget build(BuildContext context) {
    final sub = taller.subevento;
    final inicio = horaATexto(sub.horaInicio)?.substring(0, 5) ?? '';
    final fin = horaATexto(sub.horaFin)?.substring(0, 5) ?? '';
    final dia =
        '${sub.dia.day.toString().padLeft(2, '0')}/'
        '${sub.dia.month.toString().padLeft(2, '0')}/${sub.dia.year}';
    final cupo = taller.cupo == null ? 'Sin límite' : 'Cupo ${taller.cupo}';
    final sobrecupo = taller.sobrecupo > 0
        ? ' · Sobrecupo ${taller.sobrecupo}'
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(sub.nombre, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(
          '$dia · $inicio–$fin · $cupo$sobrecupo',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: TwKpiCard(
                  value: '${taller.inscritos}',
                  label: 'Inscritos',
                  icon: Symbols.group_rounded,
                  tint: TwColors.blueTint,
                  iconColor: TwColors.blueInk,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TwKpiCard(
                  value: '${taller.asistentes}',
                  label: 'Asistentes',
                  icon: Symbols.how_to_reg_rounded,
                  tint: TwColors.greenTint,
                  iconColor: TwColors.greenInk,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TwKpiCard(
                  value:
                      '${(taller.porcentajeAsistencia * 100).toStringAsFixed(0)}%',
                  label: 'Asistencia',
                  icon: Symbols.percent_rounded,
                  tint: TwColors.amberTint,
                  iconColor: TwColors.amberInk,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
