import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/supabase_tables.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../data/models/ocupacion_evento.dart';
import '../../../data/models/subevento.dart';
import '../../../data/offline/offline_cache_tables.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/repositories/subeventos_repository.dart';

final subeventosPorEventoProvider = FutureProvider.autoDispose
    .family<List<Subevento>, String>((ref, eventoId) {
      return leerCacheFirstConRef(
        ref: ref,
        tabla: SupabaseTables.subeventos,
        eventoId: eventoId,
        desdeServidor: () =>
            ref.read(subeventosRepositoryProvider).listarPorEvento(eventoId),
        aFila: (subevento) => subevento.toCacheMap(),
        desdeFila: Subevento.fromMap,
      );
    });

/// Talleres de todos los eventos visibles. La lista de eventos los cuelga de
/// su evento principal.
final subeventosTodosProvider = FutureProvider.autoDispose<List<Subevento>>((
  ref,
) {
  return leerCacheFirstConRef(
    ref: ref,
    tabla: OfflineCacheTables.catalogoSubeventos,
    desdeServidor: () => ref.read(subeventosRepositoryProvider).listarTodos(),
    aFila: (subevento) => subevento.toCacheMap(),
    desdeFila: Subevento.fromMap,
  );
});

final ocupacionEventoProvider = FutureProvider.autoDispose
    .family<OcupacionEvento, String>((ref, eventoId) async {
      if (!ref.watch(isOnlineProvider)) {
        throw StateError('La ocupación solo está disponible con conexión.');
      }
      return ref.read(subeventosRepositoryProvider).ocupacion(eventoId);
    });
