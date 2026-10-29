import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/connectivity_service.dart';
import '../../../data/offline/offline_cache_tables.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/repositories/fijados_repository.dart';
import '../../auth/providers/auth_providers.dart';
import '../../capturador/providers/capturador_providers.dart';

/// Los fijados son un `Set<String>`; en disco se guardan como filas con una
/// sola columna para poder reusar el mismo mecanismo que el resto del
/// catálogo.
const String _columnaId = 'id';

Map<String, dynamic> _aFila(String id) => {_columnaId: id};

String _desdeFila(Map<String, dynamic> fila) => '${fila[_columnaId]}';

/// Ids de eventos fijados por el usuario, con respaldo en disco.
final eventosFijadosProvider = FutureProvider.autoDispose<Set<String>>((
  ref,
) async {
  ref.watch(authStateChangesProvider);
  final isOnline = ref.read(usaServidorProvider);
  final repo = ref.watch(fijadosRepositoryProvider);
  final perfil = await ref.watch(currentPerfilProvider.future);

  final fijados = (await leerCacheFirstConRef(
    ref: ref,
    tabla: OfflineCacheTables.eventosFijados,
    desdeServidor: () async => (await repo.listarEventosFijados()).toList(),
    aFila: _aFila,
    desdeFila: _desdeFila,
  )).toSet();

  if (perfil == null || !perfil.rol.isUsuario) return fijados;

  // Una revocación no debe dejar fijados invisibles consumiendo el límite,
  // pero un error de red tampoco puede leerse como revocación: sin
  // autorizaciones resueltas se muestran los fijados tal cual.
  final Set<String> autorizados;
  try {
    autorizados = await ref.watch(usuarioEventosAutorizadosProvider.future);
  } catch (_) {
    return fijados;
  }

  final obsoletos = fijados.difference(autorizados);
  if (isOnline) {
    for (final eventoId in obsoletos) {
      await repo.desfijarEvento(eventoId);
    }
  }
  return fijados.intersection(autorizados);
});

final campanasFijadasProvider = FutureProvider.autoDispose<Set<String>>((
  ref,
) async {
  ref.watch(authStateChangesProvider);
  final isOnline = ref.read(usaServidorProvider);
  final repo = ref.watch(fijadosRepositoryProvider);
  final perfil = await ref.watch(currentPerfilProvider.future);

  final fijadas = await leerCacheFirstConRef(
    ref: ref,
    tabla: OfflineCacheTables.campanasFijadas,
    desdeServidor: () async => (await repo.listarCampanasFijadas()).toList(),
    aFila: _aFila,
    desdeFila: _desdeFila,
  );
  final setFijadas = fijadas.toSet();
  if (perfil == null || !perfil.requiresEventAssignment) return setFijadas;

  final autorizadas = (await ref.watch(
    eventosLeadsListProvider.future,
  )).map((actividad) => actividad.id).toSet();
  final obsoletas = setFijadas.difference(autorizadas);
  if (isOnline) {
    for (final campanaId in obsoletas) {
      await repo.desfijarCampana(campanaId);
    }
  }
  final visibles = setFijadas.intersection(autorizadas);
  if (visibles.length != setFijadas.length) {
    await ref
        .read(offlineReadCacheProvider)
        .guardarGlobal(
          OfflineCacheTables.campanasFijadas,
          visibles.map(_aFila).toList(),
        );
  }
  return visibles;
});
