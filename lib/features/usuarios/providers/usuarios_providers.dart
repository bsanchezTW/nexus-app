import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/connectivity_service.dart';
import '../../../data/models/perfil.dart';
import '../../../data/offline/offline_cache_tables.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/repositories/auth_repository.dart';

/// Perfiles visibles. Se respalda en disco porque el nombre del vendedor y el
/// avatar se usan en listas que tienen que seguir pintándose sin red.
final usuariosListProvider = FutureProvider.autoDispose<List<Perfil>>((
  ref,
) async {
  final repo = ref.watch(authRepositoryProvider);

  return leerCacheFirstConRef(
    ref: ref,
    tabla: OfflineCacheTables.usuarios,
    desdeServidor: repo.obtenerTodosLosUsuarios,
    aFila: (perfil) => perfil.toCacheMap(),
    desdeFila: Perfil.fromMap,
  );
});

final usuarioPorIdProvider = FutureProvider.autoDispose.family<Perfil, String>((
  ref,
  id,
) async {
  final repo = ref.watch(authRepositoryProvider);
  try {
    return await repo.obtenerUsuarioPorId(id);
  } catch (error) {
    if (ref.read(usaServidorProvider) && !isNetworkTransportError(error)) {
      rethrow;
    }
    final cacheados = ref
        .read(offlineReadCacheProvider)
        .leerGlobal(
          tabla: OfflineCacheTables.usuarios,
          desdeFila: Perfil.fromMap,
        );
    for (final perfil in cacheados ?? const <Perfil>[]) {
      if (perfil.id == id) return perfil;
    }
    rethrow;
  }
});
