import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/supabase_tables.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../data/models/inscripcion_subevento.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/offline/sync_queue_item.dart';
import '../../../data/offline/sync_queue_service.dart';
import '../../../data/repositories/inscripciones_subevento_repository.dart';
import '../../registrados/providers/registrados_providers.dart';

List<InscripcionSubevento> fusionarInscripcionesConCola({
  required List<InscripcionSubevento> servidor,
  required Iterable<SyncQueueItem> cola,
  required String eventoId,
}) {
  final pendientes = cola.where(
    (item) =>
        item.table == SupabaseTables.inscripcionesSubevento &&
        item.operation == SyncOperation.insert &&
        item.payload['evento_id'] == eventoId,
  );
  final extras = <InscripcionSubevento>[];
  for (final item in pendientes) {
    final registradoId = item.payload['registrado_id'] as String?;
    final subeventoId = item.payload['subevento_id'] as String?;
    if (registradoId == null || subeventoId == null) continue;
    final yaEsta = servidor.any(
      (fila) =>
          fila.registradoId == registradoId && fila.subeventoId == subeventoId,
    );
    if (yaEsta) continue;
    extras.add(
      InscripcionSubevento(
        id: item.id,
        eventoId: eventoId,
        registradoId: registradoId,
        subeventoId: subeventoId,
        origen: 'app',
        asistio: true,
        pendienteDeSincronizar: true,
      ),
    );
  }
  return [...servidor, ...extras];
}

class AsistenciaRechazada implements Exception {
  const AsistenciaRechazada(this.motivo, {this.conflictos = const []});

  final String motivo;
  final List<String> conflictos;

  @override
  String toString() => motivo;
}

List<String> idsDeConflictos(Object? valor) {
  if (valor is! List) return const [];
  return [
    for (final item in valor)
      if ('$item'.isNotEmpty) '$item',
  ];
}

final inscripcionesPorEventoProvider = FutureProvider.autoDispose
    .family<List<InscripcionSubevento>, String>((ref, eventoId) async {
      final repo = ref.watch(inscripcionesSubeventoRepositoryProvider);
      final servidor = await leerCacheFirstConRef(
        ref: ref,
        tabla: SupabaseTables.inscripcionesSubevento,
        eventoId: eventoId,
        desdeServidor: () => repo.listarPorEvento(eventoId),
        aFila: (fila) => {
          'id': fila.id,
          'evento_id': fila.eventoId,
          'registrado_id': fila.registradoId,
          'subevento_id': fila.subeventoId,
          'origen': fila.origen,
          'sobrecupo': fila.sobrecupo,
          'asistio': fila.asistio,
          'asistio_en': fila.asistioEn?.toIso8601String(),
          'asistio_por': fila.asistioPor,
        },
        desdeFila: InscripcionSubevento.fromMap,
      );
      return fusionarInscripcionesConCola(
        servidor: servidor,
        cola: ref.watch(syncQueueServiceProvider),
        eventoId: eventoId,
      );
    });

Future<void> persistirAsistenciaSubevento(
  WidgetRef ref, {
  required String eventoId,
  required String registradoId,
  required String subeventoId,
  required String accion,
  bool forzar = false,
  bool reemplazar = false,
}) async {
  final online = ref.read(isOnlineProvider);
  final cache = ref.read(offlineReadCacheProvider);
  if (online && !esIdSoloLocal(registradoId)) {
    final repo = ref.read(inscripcionesSubeventoRepositoryProvider);
    if (accion == 'inscribir_y_marcar') {
      final resultado = await repo.inscribir(
        registradoId: registradoId,
        subeventoId: subeventoId,
        forzarSobrecupo: forzar,
        marcarAsistencia: true,
        reemplazarSuperpuestos: reemplazar,
      );
      if (resultado['ok'] == false) {
        throw AsistenciaRechazada(
          resultado['motivo']?.toString() ?? 'rechazo',
          conflictos: idsDeConflictos(resultado['conflictos']),
        );
      }
    } else {
      await repo.marcarAsistencia(
        registradoId: registradoId,
        subeventoId: subeventoId,
      );
    }
  } else {
    await ref.read(syncQueueServiceProvider.notifier).enqueueInsert(
      table: SupabaseTables.inscripcionesSubevento,
      payload: {
        'accion': accion,
        'evento_id': eventoId,
        'registrado_id': registradoId,
        'subevento_id': subeventoId,
        'forzar': forzar,
        'reemplazar': reemplazar,
      },
    );
  }

  await cache.parchearFila(
    tabla: SupabaseTables.registrados,
    eventoId: eventoId,
    id: registradoId,
    cambios: {'acreditado': true},
  );
  final clave = '${SupabaseTables.registrados}:$eventoId';
  ref.read(cacheRevisionProvider(clave).notifier).state++;
  ref.invalidate(registradosPorEventoProvider(eventoId));
  ref.invalidate(inscripcionesPorEventoProvider(eventoId));
}
