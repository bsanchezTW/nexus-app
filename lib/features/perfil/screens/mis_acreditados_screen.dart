import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tw_tokens.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/tw_skeletons.dart';
import '../../../core/widgets/nexus_components.dart';
import '../../../data/models/mi_acreditacion.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../providers/perfil_providers.dart';

/// Asistentes que acreditó el usuario en sesión, seccionados por evento.
///
/// Se abre desde la tarjeta "Acreditaciones" de Mi perfil y comparte su fuente
/// (`rpe_mis_acreditados`), de modo que el número de la tarjeta y el largo de
/// esta lista siempre coinciden.
class MisAcreditadosScreen extends ConsumerWidget {
  const MisAcreditadosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acreditadosAsync = ref.watch(misAcreditadosProvider);

    return AppScaffold(
      title: 'Mis acreditaciones',
      body: acreditadosAsync.when(
        loading: () =>
            const TwListSkeletonView(leading: TwSkeletonLeading.avatar),
        error: (e, _) => ErrorView(
          message: 'No se pudieron cargar tus acreditaciones.',
          onRetry: () => ref.invalidate(misAcreditadosProvider),
        ),
        data: (grupos) {
          if (grupos.isEmpty) {
            return const EmptyStateView(
              icon: Symbols.verified_rounded,
              message: 'Todavía no has acreditado a nadie.',
            );
          }

          final total = grupos.fold<int>(
            0,
            (suma, grupo) => suma + grupo.acreditados.length,
          );

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => refrescarLecturas(
              ref,
              context: context,
              invalidar: () => ref.invalidate(misAcreditadosProvider),
              pendientes: () => [ref.read(misAcreditadosProvider.future)],
            ),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              padding: AppSpacing.form,
              children: [
                _Resumen(total: total, eventos: grupos.length),
                for (final grupo in grupos) ...[
                  const SizedBox(height: AppSpacing.sectionGap),
                  _EncabezadoEvento(grupo: grupo),
                  const SizedBox(height: 10),
                  for (var i = 0; i < grupo.acreditados.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _FilaAcreditado(
                      acreditacion: grupo.acreditados[i],
                      index: i,
                    ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Resumen extends StatelessWidget {
  const _Resumen({required this.total, required this.eventos});

  final int total;
  final int eventos;

  @override
  Widget build(BuildContext context) {
    final personas = total == 1 ? '1 persona' : '$total personas';
    final donde = eventos == 1 ? '1 evento' : '$eventos eventos';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.successTint,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          const Icon(
            Symbols.verified_rounded,
            color: AppColors.success,
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Acreditaste a $personas en $donde.',
              style: const TextStyle(
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EncabezadoEvento extends StatelessWidget {
  const _EncabezadoEvento({required this.grupo});

  final AcreditacionesPorEvento grupo;

  @override
  Widget build(BuildContext context) {
    final cantidad = grupo.acreditados.length;
    final fecha = grupo.eventoFecha;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionLabel(grupo.eventoNombre),
              const SizedBox(height: 4),
              Text(
                fecha == null
                    ? '${_plural(cantidad)} acreditadas'
                    : '${formatearFechaLarga(fecha)} · ${_plural(cantidad)}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _plural(int n) => n == 1 ? '1 persona' : '$n personas';
}

class _FilaAcreditado extends StatelessWidget {
  const _FilaAcreditado({required this.acreditacion, required this.index});

  final MiAcreditacion acreditacion;
  final int index;

  @override
  Widget build(BuildContext context) {
    final detalle = acreditacion.detalle;
    final hora = acreditacion.acreditadoEn;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          AvatarInitials(
            name: acreditacion.nombreCompleto,
            size: 40,
            index: index,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  acreditacion.nombreCompleto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                if (detalle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detalle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (hora != null) ...[
            const SizedBox(width: 8),
            Text(
              DateFormat('d MMM · HH:mm', 'es').format(hora.toLocal()),
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
