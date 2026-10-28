import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/offline/snapshot_service.dart';
import '../../data/offline/sync_coordinator.dart';
import '../../data/offline/sync_queue_service.dart';
import '../network/connectivity_service.dart';
import '../router/route_paths.dart';
import 'sync_conflict_listener.dart';
import 'tw_offline_notice_card.dart';

/// Lo que el usuario necesita saber de la copia local y de la cola: cambios
/// que esperan subir, conflictos y la bajada del snapshot.
///
/// Reemplaza al banner superior que se retiró en el pulido de avisos: sin él,
/// los pendientes solo se veían entrando a Sincronización, y la bajada de la
/// copia local corría sin ninguna señal. Va junto a [TwOfflineNoticeCard] y
/// muestra un solo aviso a la vez, el más urgente.
class TwSyncNoticeCard extends ConsumerWidget {
  const TwSyncNoticeCard({super.key, this.topGap = 0, this.bottomGap = 0});

  final double topGap;
  final double bottomGap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aviso = _aviso(context, ref);
    return TwNoticeSlot(
      visible: aviso != null,
      topGap: topGap,
      bottomGap: bottomGap,
      child: aviso ?? const SizedBox.shrink(),
    );
  }

  TwNoticeCard? _aviso(BuildContext context, WidgetRef ref) {
    final conflictos = ref.watch(syncConflictsProvider).length;
    final pendientes = ref.watch(pendingSyncCountProvider);
    final subiendo = ref.watch(syncEnCursoProvider);
    final hayRed = ref.watch(isOnlineProvider);
    final snapshot = ref.watch(snapshotServiceProvider);

    if (conflictos > 0) {
      return TwNoticeCard(
        key: const Key('aviso_sync_conflictos'),
        icon: Symbols.sync_problem_rounded,
        title: conflictos == 1
            ? 'Un cambio necesita revisión'
            : '$conflictos cambios necesitan revisión',
        subtitle: 'El servidor no los aceptó. Toca para revisarlos.',
        palette: TwNoticePalette.offline,
        onTap: () => showSyncConflictsSheet(context, ref),
      );
    }

    if (pendientes > 0) {
      final cambios = pendientes == 1 ? '1 cambio' : '$pendientes cambios';
      if (subiendo) {
        return TwNoticeCard(
          key: const Key('aviso_sync_subiendo'),
          icon: Symbols.cloud_upload_rounded,
          title: 'Subiendo cambios',
          subtitle: '$cambios guardados en el teléfono',
          palette: TwNoticePalette.update,
          progress: 0,
        );
      }
      if (!hayRed) {
        return TwNoticeCard(
          key: const Key('aviso_sync_pendientes'),
          icon: Symbols.cloud_off_rounded,
          title: '$cambios guardados en el teléfono',
          subtitle: 'Se subirán solos cuando vuelva la conexión.',
          palette: TwNoticePalette.offline,
        );
      }
      return TwNoticeCard(
        key: const Key('aviso_sync_pendientes'),
        icon: Symbols.cloud_upload_rounded,
        title: '$cambios sin subir',
        subtitle: 'No se pudieron enviar al servidor. Toca para reintentar.',
        palette: TwNoticePalette.offline,
        onTap: () => ref.read(syncCoordinatorProvider).sincronizarAhora(),
      );
    }

    final progreso = snapshot.progreso;
    if (snapshot.enCurso && progreso != null) {
      final pct = (progreso.fraccion * 100).clamp(0, 100).toStringAsFixed(0);
      return TwNoticeCard(
        key: const Key('aviso_sync_descarga'),
        icon: Symbols.cloud_download_rounded,
        title: 'Descargando copia para usar sin conexión',
        subtitle: '${progreso.etapa.titulo} · $pct %',
        palette: TwNoticePalette.update,
        progress: progreso.fraccion,
        onTap: () => context.push(RoutePaths.sincronizacion),
      );
    }

    if (!snapshot.enCurso && snapshot.errores.isNotEmpty) {
      return TwNoticeCard(
        key: const Key('aviso_sync_descarga_incompleta'),
        icon: Symbols.cloud_off_rounded,
        title: 'Copia sin conexión incompleta',
        subtitle:
            'Parte de los datos no se descargó. Toca para ver el detalle.',
        palette: TwNoticePalette.offline,
        onTap: () => context.push(RoutePaths.sincronizacion),
      );
    }

    return null;
  }
}
