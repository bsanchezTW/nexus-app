import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/connectivity_service.dart';
import '../../../data/models/evento.dart';
import '../../../data/offline/offline_cache_tables.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/repositories/eventos_repository.dart';

/// Catálogo de eventos visible para el perfil.
///
/// Lee del servidor y respalda en disco: sin esto la lista quedaba vacía al
/// recargar sin red, que es donde más se usa (feria, recinto sin cobertura).
/// RLS sigue recortando qué eventos llegan; la caché solo conserva lo que el
/// servidor ya había autorizado.
final eventosListProvider = FutureProvider.autoDispose<List<Evento>>((
  ref,
) async {
  final cache = ref.watch(offlineReadCacheProvider);
  final repo = ref.watch(eventosRepositoryProvider);

  return leerCacheFirstConRef(
    ref: ref,
    tabla: OfflineCacheTables.eventos,
    desdeServidor: () async {
      final eventos = await repo.listarTodos();
      // Guardar también cada evento por separado deja listo el detalle: entrar
      // a un evento sin red no debería depender de haberlo abierto antes.
      for (final evento in eventos) {
        await cache.guardar(OfflineCacheTables.eventoDetalle, evento.id, [
          evento.toCacheMap(),
        ]);
      }
      return eventos;
    },
    aFila: (evento) => evento.toCacheMap(),
    desdeFila: Evento.fromMap,
  );
});

final eventoByIdProvider = FutureProvider.autoDispose.family<Evento, String>((
  ref,
  id,
) async {
  final isOnline = ref.read(isOnlineProvider);
  final cache = ref.watch(offlineReadCacheProvider);
  final repo = ref.watch(eventosRepositoryProvider);

  try {
    final filas = await leerCacheFirstConRef(
      ref: ref,
      tabla: OfflineCacheTables.eventoDetalle,
      eventoId: id,
      desdeServidor: () async => [await repo.obtenerPorId(id)],
      aFila: (evento) => evento.toCacheMap(),
      desdeFila: Evento.fromMap,
    );
    if (filas.isNotEmpty) return filas.first;
  } catch (error) {
    if (isOnline && !isNetworkTransportError(error)) rethrow;
  }

  // Último recurso: el evento puede estar en el catálogo aunque su detalle
  // nunca se haya pedido (p. ej. se sincronizó la lista y se abre sin red).
  final delCatalogo = cache.leerGlobal(
    tabla: OfflineCacheTables.eventos,
    desdeFila: Evento.fromMap,
  );
  for (final evento in delCatalogo ?? const <Evento>[]) {
    if (evento.id == id) return evento;
  }
  throw Exception('No se pudo cargar el evento.');
});
