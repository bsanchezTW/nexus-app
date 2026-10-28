import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/avisos/aviso_sistema.dart';
import '../../../core/conexion/monitor_conexion.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/network/offline_policy.dart';
import '../../../data/offline/snapshot_service.dart';
import '../../../data/offline/sync_queue_service.dart';

/// Avisos de conexión y copia local vigentes, del más urgente al menos.
///
/// Lo leen la zona de avisos de las pantallas principales y el indicador
/// compacto de las demás, así ambos dicen siempre lo mismo.
final avisosSistemaProvider = Provider<List<AvisoSistema>>((ref) {
  final snapshot = ref.watch(snapshotServiceProvider);
  final progreso = snapshot.enCurso ? snapshot.progreso : null;
  return avisosDelSistema(
    EntradaAvisos(
      estado: ref.watch(estadoConexionProvider),
      enLinea: ref.watch(isOnlineProvider),
      soportaCopiaLocal: supportsOfflineCacheAqui,
      conflictos: ref.watch(syncConflictsProvider).length,
      pendientes: ref.watch(pendingSyncCountProvider),
      subiendo: ref.watch(syncEnCursoProvider),
      descargaEnCurso: progreso != null,
      descargaEtapa: progreso?.etapa.titulo,
      descargaFraccion: progreso?.fraccion ?? 0,
      descargaConErrores: !snapshot.enCurso && snapshot.errores.isNotEmpty,
    ),
  );
});
