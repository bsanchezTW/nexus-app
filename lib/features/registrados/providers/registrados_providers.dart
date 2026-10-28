import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/supabase_tables.dart';
import '../../../core/conexion/senal_fallos_red.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../data/models/registrado.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/offline/sync_queue_item.dart';
import '../../../data/offline/sync_queue_service.dart';
import '../../../data/repositories/registrados_repository.dart';

/// Combina los registrados que ya confirmó el servidor con los que siguen
/// pendientes en la cola offline unificada (ver
/// data/offline/sync_queue_service.dart), para que la UI los muestre de
/// inmediato con una insignia de "pendiente de sincronizar" — sin esto, el
/// bug de cola huérfana del proyecto legado (Sección 3.8/17.3) habría sido
/// invisible para el usuario hasta perder los datos.
List<Registrado> fusionarRegistradosConCola({
  required List<Registrado> servidor,
  required Iterable<SyncQueueItem> cola,
  required String eventoId,
}) {
  final colaDeEsteEvento = cola.where(
    (item) => item.table == SupabaseTables.registrados,
  );

  final inserts = colaDeEsteEvento
      .where(
        (i) =>
            i.operation == SyncOperation.insert &&
            i.payload['evento_id'] == eventoId,
      )
      .map(
        (i) => Registrado.fromMap(
          i.payload,
        ).copyWith(pendienteDeSincronizar: true),
      )
      .toList();

  final updatesPorId = <String, Map<String, dynamic>>{};
  for (final item in colaDeEsteEvento) {
    if (item.operation != SyncOperation.update) continue;
    final id = item.payload['id'] as String;
    final changes = Map<String, dynamic>.from(item.payload['changes'] as Map);
    updatesPorId[id] = {...updatesPorId[id] ?? {}, ...changes};
  }

  final servidorConCambios = servidor.map((r) {
    final changes = updatesPorId[r.id];
    return changes == null ? r : r.conCambiosPendientes(changes);
  }).toList();

  return [...inserts, ...servidorConCambios];
}

class RegistradosResumen {
  const RegistradosResumen({
    required this.total,
    required this.acreditados,
    required this.pendientes,
  });

  final int total;
  final int acreditados;
  final int pendientes;
}

RegistradosResumen resumenDesdeRegistrados(List<Registrado> registrados) {
  final acreditados = registrados.where((r) => r.acreditado).length;
  return RegistradosResumen(
    total: registrados.length,
    acreditados: acreditados,
    pendientes: registrados.length - acreditados,
  );
}

/// Conteos para el hub del evento: solo caché local + cola, sin red.
final registradosResumenLocalProvider = Provider.autoDispose
    .family<RegistradosResumen?, String>((ref, eventoId) {
      final local = ref
          .watch(offlineReadCacheProvider)
          .leerLocal(
            tabla: SupabaseTables.registrados,
            eventoId: eventoId,
            desdeFila: Registrado.fromMap,
          );
      final fusionados = fusionarRegistradosConCola(
        servidor: local ?? const [],
        cola: ref.watch(syncQueueServiceProvider),
        eventoId: eventoId,
      );
      if (local == null && fusionados.isEmpty) return null;
      return resumenDesdeRegistrados(fusionados);
    });

/// Conteos del hub del evento.
///
/// Observa la lista completa, de modo que abrir el evento ya dispara su carga
/// (y de paso deja lista la caché offline). Antes solo se leía la caché, que
/// se llenaba recién al entrar a "Registrados": hasta entonces las tarjetas
/// mostraban 0 aunque el evento tuviera gente inscrita.
final registradosResumenProvider = Provider.autoDispose
    .family<RegistradosResumen?, String>((ref, eventoId) {
      final lista = ref
          .watch(registradosPorEventoProvider(eventoId))
          .valueOrNull;
      if (lista != null) return resumenDesdeRegistrados(lista);
      // Mientras el servidor responde se muestra lo último conocido.
      return ref.watch(registradosResumenLocalProvider(eventoId));
    });

final registradosPorEventoProvider = FutureProvider.autoDispose
    .family<List<Registrado>, String>((ref, eventoId) async {
      final repo = ref.watch(registradosRepositoryProvider);

      final servidor = await leerCacheFirstConRef(
        ref: ref,
        tabla: SupabaseTables.registrados,
        eventoId: eventoId,
        desdeServidor: () => repo.listarPorEvento(eventoId),
        aFila: (registrado) => registrado.toCacheMap(),
        desdeFila: Registrado.fromMap,
      );

      return fusionarRegistradosConCola(
        servidor: servidor,
        cola: ref.watch(syncQueueServiceProvider),
        eventoId: eventoId,
      );
    });

/// Acredita o quita la acreditación: servidor o cola, y write-through a caché.
///
/// Si el servidor no contesta a tiempo o la red falla a mitad de camino, la
/// acreditación va a la cola igual que sin conexión: en la puerta de una feria
/// no se puede dejar a alguien sin acreditar porque el wifi del recinto no
/// deja salir. El UPDATE es idempotente, así que reenviarlo no duplica nada.
Future<void> persistirAcreditacion(
  WidgetRef ref, {
  required Registrado registrado,
  required bool acreditado,
  required String acreditadoPorId,
}) async {
  final isOnline = ref.read(isOnlineProvider);
  final cache = ref.read(offlineReadCacheProvider);
  // `parchearFila` toma turno, así que una consulta en vuelo ya no puede pisar
  // el parche. Con un wifi cautivo cada una aguanta hasta 30 s: esperarlas sin
  // tope dejaba la acreditación colgada antes de intentar nada.
  await cache.esperarRevalidaciones().timeout(
    esperaMaximaServidorPorDefecto,
    onTimeout: () {},
  );

  var enCola = !isOnline || esIdSoloLocal(registrado.id);
  if (!enCola) {
    final repo = ref.read(registradosRepositoryProvider);
    try {
      await (acreditado
              ? repo.acreditar(registrado.id, acreditadoPorId: acreditadoPorId)
              : repo.desacreditar(registrado.id))
          .timeout(esperaMaximaEscrituraDirecta);
    } catch (error) {
      if (!isNetworkTransportError(error)) rethrow;
      // El tope de 10 s no lo ve el cliente HTTP: se avisa aquí.
      reportarFalloDeRed();
      enCola = true;
    }
  }
  if (enCola) {
    await ref
        .read(syncQueueServiceProvider.notifier)
        .enqueueUpdate(
          table: SupabaseTables.registrados,
          entityId: registrado.id,
          changes: {
            'acreditado': acreditado,
            'acreditado_por': acreditado ? acreditadoPorId : null,
          },
        );
  }

  await cache.parchearFila(
    tabla: SupabaseTables.registrados,
    eventoId: registrado.eventoId,
    id: registrado.id,
    cambios: {'acreditado': acreditado},
  );
  final clave = '${SupabaseTables.registrados}:${registrado.eventoId}';
  final siguiente = ref.read(cacheRevisionProvider(clave)) + 1;
  cache.omitirProximaRevalidacion(
    SupabaseTables.registrados,
    registrado.eventoId,
    siguiente,
  );
  ref.read(cacheRevisionProvider(clave).notifier).state = siguiente;
  ref.invalidate(registradosPorEventoProvider(registrado.eventoId));
}
