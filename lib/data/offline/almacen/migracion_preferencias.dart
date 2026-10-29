import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

import '../sync_queue_service.dart';
import 'almacen_copia_local.dart';

const _prefijoV3 = 'offline_read_cache_v3_';
const _prefijoV2 = 'offline_read_cache_v2_';
const _prefijoV1 = 'offline_read_cache_v1_';
const _sufijoIndice = '__idx';

/// Cuarentena de la caché v1, que mezclaba cuentas. Se deja en
/// `SharedPreferences` como diagnóstico: nunca se adopta.
const _prefijoCuarentena = '${_prefijoV3}quarantine_';

/// Lleva la copia local y la cola de pendientes de `SharedPreferences` al
/// [almacen] y las borra de ahí.
///
/// Solo borra una clave después de que su contenido llegó al disco: si la app
/// se cierra a mitad, la próxima vez se repite y [AlmacenCopiaLocal.guardar]
/// no duplica nada. Lee los dos formatos que pudo dejar una versión anterior:
///
/// - v3: `offline_read_cache_v3_<perfil>_<tabla>:<evento>`, una clave por
///   evento, más un índice `..._<tabla>__idx` que aquí sobra.
/// - v2: `offline_read_cache_v2_<perfil>_<tabla>`, un mapa evento → filas.
///
/// La v1 se mueve a la cuarentena, como hacía la caché antes. La cola
/// (`sync_queue_v2_<perfil>`) se fusiona con la del almacén; su cuarentena y la
/// cola v1 sin dueño se quedan: las maneja `SyncQueueService`.
///
/// Devuelve cuántas entradas migró.
Future<int> migrarCopiaDesdePreferencias(
  SharedPreferences prefs,
  AlmacenCopiaLocal almacen,
) async {
  final migradas = <String>[];
  var entradas = 0;

  // La v2 primero: si un evento quedó en ambos formatos, gana la v3, que es
  // más nueva.
  int formato(String clave) => clave.startsWith(_prefijoV2) ? 0 : 1;
  final claves = prefs.getKeys().toList()
    ..sort((a, b) => formato(a).compareTo(formato(b)));

  for (final clave in claves) {
    if (clave.startsWith(_prefijoCuarentena)) continue;

    if (clave.startsWith(_prefijoV3)) {
      migradas.add(clave);
      if (clave.endsWith(_sufijoIndice)) continue;
      final partes = _partes(clave.substring(_prefijoV3.length));
      final separador = partes?.$2.indexOf(':') ?? -1;
      if (partes == null || separador < 0) continue;
      final filas = _filas(prefs.getString(clave), clave);
      if (filas == null) continue;
      await almacen.guardar(
        partes.$1,
        partes.$2.substring(0, separador),
        partes.$2.substring(separador + 1),
        filas,
      );
      entradas++;
      continue;
    }

    if (clave.startsWith(_prefijoV2)) {
      migradas.add(clave);
      final partes = _partes(clave.substring(_prefijoV2.length));
      if (partes == null) continue;
      try {
        final porEvento = jsonDecode(prefs.getString(clave) ?? '') as Map;
        for (final MapEntry(:key, :value) in porEvento.entries) {
          if (value is! List) continue;
          await almacen.guardar(partes.$1, partes.$2, '$key', [
            for (final fila in value)
              if (fila is Map) Map<String, dynamic>.from(fila),
          ]);
          entradas++;
        }
      } catch (e) {
        developer.log('Caché v2 $clave ilegible: $e', name: 'Migracion');
      }
      continue;
    }

    if (clave.startsWith(prefijoColaEnPreferencias) &&
        !clave.startsWith('${prefijoColaEnPreferencias}quarantine')) {
      final owner = clave.substring(prefijoColaEnPreferencias.length);
      final items = _filas(prefs.getString(clave), clave);
      // Ilegible: se deja en SharedPreferences. Es lo único que podría
      // quedar de esos pendientes y no se borra lo que no se pudo copiar.
      if (owner.isEmpty || items == null) continue;
      await _fusionarCola(almacen, owner, items);
      migradas.add(clave);
      entradas++;
      continue;
    }

    if (clave.startsWith(_prefijoV1)) {
      final raw = prefs.getString(clave);
      if (raw != null) {
        await prefs.setString(
          '$_prefijoCuarentena${clave.substring(_prefijoV1.length)}',
          raw,
        );
      }
      migradas.add(clave);
    }
  }

  if (migradas.isEmpty) return 0;
  await almacen.esperarEscrituras();
  for (final clave in migradas) {
    await prefs.remove(clave);
  }
  developer.log(
    '$entradas entradas de la copia local pasaron a la base nueva.',
    name: 'Migracion',
  );
  return entradas;
}

/// Suma a la cola del almacén los pendientes que había en SharedPreferences.
///
/// Fusiona en vez de reemplazar: si una migración anterior alcanzó a copiar
/// la cola pero no a borrar la clave, el almacén puede tener pendientes más
/// nuevos que no se pueden perder. Ante el mismo id gana el del almacén.
Future<void> _fusionarCola(
  AlmacenCopiaLocal almacen,
  String owner,
  List<Map<String, dynamic>> deSharedPreferences,
) async {
  final actuales =
      almacen.leer(owner, tablaColaPendientes, entradaColaPendientes) ??
      const <Map<String, dynamic>>[];
  final ids = {for (final item in actuales) item['id']};
  await almacen.guardar(owner, tablaColaPendientes, entradaColaPendientes, [
    ...deSharedPreferences.where((item) => !ids.contains(item['id'])),
    ...actuales,
  ]);
}

/// `<perfil>_<resto>`. El perfil es un UUID y no tiene `_`.
(String, String)? _partes(String sinPrefijo) {
  final i = sinPrefijo.indexOf('_');
  if (i <= 0) return null;
  return (sinPrefijo.substring(0, i), sinPrefijo.substring(i + 1));
}

List<Map<String, dynamic>>? _filas(String? raw, String clave) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return [
      for (final fila in jsonDecode(raw) as List)
        if (fila is Map) Map<String, dynamic>.from(fila),
    ];
  } catch (e) {
    developer.log('Caché $clave ilegible: $e', name: 'Migracion');
    return null;
  }
}
