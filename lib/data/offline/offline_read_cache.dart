import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/connectivity_service.dart';
import '../../core/network/offline_guard.dart';
import '../../core/widgets/app_widgets.dart';
import 'sync_queue_service.dart';

/// `eventoId` reservado para las tablas que no se particionan por evento
/// (perfil, catálogo de eventos, usuarios, fijados).
///
/// No puede colisionar con un id real: los eventos son UUID.
const String cacheAmbitoGlobal = '__global__';

/// Tiempo máximo que la UI espera al servidor antes de servir la copia local.
///
/// Sin esto, un wifi cautivo —el escenario exacto de feria— deja la pantalla
/// en `loading` indefinidamente aunque el disco tenga una copia buena: la
/// petición no falla, simplemente nunca responde. `connectivity_plus` informa
/// que hay interfaz, así que tampoco hay una señal de "offline" que corte.
const Duration esperaMaximaServidorPorDefecto = Duration(seconds: 5);

/// Presupuesto de una revalidación en segundo plano. No bloquea la UI, así que
/// puede esperar mucho más que [esperaMaximaServidorPorDefecto]: con 5 s una
/// red lenta descartaba siempre la respuesta y la pantalla quedaba congelada
/// en la copia del disco sin avisar.
const Duration esperaMaximaRevalidacion = Duration(seconds: 30);

/// Último lector vivo de una entrada (`tabla:evento`). Una revalidación puede
/// terminar después de que el provider que la lanzó se reconstruyera; el aviso
/// tiene que llegarle al lector actual, no al que ya no existe.
class _Lector {
  _Lector(this.revision, this.onActualizado);

  final int revision;
  final void Function()? onActualizado;

  /// Está esperando en línea la respuesta del servidor y leerá el disco él
  /// mismo al terminar: avisarle sería una reconstrucción de más.
  bool esperando = false;
}

const String _prefijoV3 = 'offline_read_cache_v3';
const String _prefijoV2 = 'offline_read_cache_v2';
const String _prefijoV1 = 'offline_read_cache_v1_';
const String _sufijoIndice = '__idx';

/// Última copia conocida de las listas por evento, para poder LEER sin
/// conexión.
///
/// [SyncQueueService] resuelve la escritura offline (lo capturado sin red se
/// sube después), pero no la lectura: sin esto, `listarPorEvento` falla al
/// quedarse sin señal y la lista —y el detalle de cada fila— quedan
/// inutilizables justo donde más se usan, en ferias y recintos con cobertura
/// intermitente.
///
/// El almacenamiento es **una clave por `(tabla, evento)`** más un índice de
/// eventos por tabla. El formato v2 guardaba un único blob por tabla y lo
/// re-serializaba entero en cada escritura de un evento; con el snapshot
/// completo (~10 eventos × cientos de filas) eso reescribía megabytes de JSON
/// por cada evento guardado.
class OfflineReadCache {
  OfflineReadCache(this._prefs, {this.ownerId});

  final SharedPreferences _prefs;
  final String? ownerId;

  /// Tablas cuya migración desde v2 ya se comprobó en esta instancia.
  final Set<String> _tablasMigradas = <String>{};

  /// Revalidaciones en vuelo por `tabla:evento`. Evita que dos lectores del
  /// mismo dato disparen dos consultas, y deja al snapshot esperarlas.
  final Map<String, Future<void>> _revalidaciones = <String, Future<void>>{};

  /// Revisión que dejó cada revalidación al traer datos nuevos. La lectura que
  /// llega con esa revisión ya está viendo el disco fresco y no vuelve a
  /// consultar (ver [leerCacheFirst]).
  final Map<String, int> _revisionAutoRefresco = <String, int>{};

  final Map<String, _Lector> _lectores = <String, _Lector>{};

  /// Época de servidor en la que cada entrada se confirmó contra Supabase.
  /// Mientras no alcance la época vigente, la lectura espera al servidor
  /// antes de servir el disco (ver [leerCacheFirst]).
  final Map<String, int> _epocaConfirmada = <String, int>{};

  /// Entradas cuyo disco cambió y cuyo lector todavía no se enteró.
  final Set<String> _cambiosSinEntregar = <String>{};

  /// Revalidaciones que fallaron por red desde la última consulta.
  final Map<String, Object> _fallos = <String, Object>{};

  /// Sube con cada parche local de una entrada. Una consulta lanzada antes del
  /// parche descarta su respuesta en vez de pisar la mutación.
  final Map<String, int> _generaciones = <String, int>{};
  final Map<String, int> _generacionEnVuelo = <String, int>{};

  String? get _owner {
    final owner = ownerId?.trim();
    if (owner == null || owner.isEmpty) return null;
    return owner;
  }

  /// Clave de datos de un evento concreto. `:` separa tabla de evento porque
  /// ningún nombre de tabla lo contiene; así dos pares distintos no pueden
  /// producir la misma clave.
  String? _claveDatos(String tabla, String eventoId) {
    final owner = _owner;
    if (owner == null) return null;
    return '${_prefijoV3}_${owner}_$tabla:$eventoId';
  }

  /// Índice de eventos guardados de una tabla. Sin él no se puede recorrer la
  /// tabla para purgar (`retenerEventos`, `retenerFilasPropias`).
  String? _claveIndice(String tabla) {
    final owner = _owner;
    if (owner == null) return null;
    return '${_prefijoV3}_${owner}_$tabla$_sufijoIndice';
  }

  Set<String> _indice(String tabla) {
    final key = _claveIndice(tabla);
    if (key == null) return {};
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      return (jsonDecode(raw) as List<dynamic>).map((e) => '$e').toSet();
    } catch (e) {
      developer.log(
        'Índice de $tabla corrupto, se descarta: $e',
        name: 'OfflineReadCache',
      );
      return {};
    }
  }

  Future<void> _guardarIndice(String tabla, Set<String> eventos) async {
    final key = _claveIndice(tabla);
    if (key == null) return;
    if (eventos.isEmpty) {
      await _prefs.remove(key);
      return;
    }
    await _prefs.setString(key, jsonEncode(eventos.toList()));
  }

  /// Copia local sin tocar la red. Null si este evento nunca se cacheó.
  List<T>? leerLocal<T>({
    required String tabla,
    required String eventoId,
    required T Function(Map<String, dynamic>) desdeFila,
  }) {
    return _respaldo(tabla, eventoId, desdeFila);
  }

  /// Variante de [leerLocal] para tablas que no se particionan por evento.
  List<T>? leerGlobal<T>({
    required String tabla,
    required T Function(Map<String, dynamic>) desdeFila,
  }) {
    return _respaldo(tabla, cacheAmbitoGlobal, desdeFila);
  }

  /// Lectura de la UI: copia local con el servidor como autoridad.
  ///
  /// Con red, la primera lectura de cada entrada en la época vigente
  /// ([epoca], ver `epocaServidorProvider`) **espera al servidor** hasta
  /// [esperaMaximaServidor]: al abrir la app, volver a ella, recibir un cambio
  /// en vivo o tras una mutación, lo que se pinta es lo que hay en Supabase.
  /// Si el servidor no contesta a tiempo —wifi cautivo de feria— se sirve el
  /// disco y la consulta sigue por detrás hasta [esperaMaximaRevalidacion];
  /// cuando llega, el lector vivo se reconstruye con lo nuevo.
  ///
  /// Ya confirmada la época, las reconstrucciones sirven el disco al instante
  /// y revalidan por detrás.
  ///
  /// Sin copia local no hay nada que mostrar y se cae al camino clásico
  /// ([leerConRespaldo]): ahí sí hay que esperar al servidor.
  ///
  /// [revision] y [onActualizado] son el vínculo con el provider que llama:
  /// cuando la revalidación trae algo distinto se invoca [onActualizado] del
  /// lector vivo para que se recomponga leyendo el disco ya fresco. Esa
  /// recomposición llega con la revisión que dejó la propia revalidación, y
  /// entonces la consulta se omite: si no, cada cambio dispararía la misma
  /// petición dos veces.
  Future<List<T>> leerCacheFirst<T>({
    required String tabla,
    required String eventoId,
    required Future<List<T>> Function() desdeServidor,
    required Map<String, dynamic> Function(T) aFila,
    required T Function(Map<String, dynamic>) desdeFila,
    required bool isOnline,
    Duration esperaMaximaServidor = esperaMaximaServidorPorDefecto,
    int revision = 0,
    int epoca = 0,
    void Function()? onActualizado,
  }) async {
    final clave = '$tabla:$eventoId';
    final lector = _Lector(revision, onActualizado);
    _lectores[clave] = lector;

    final local = _respaldo(tabla, eventoId, desdeFila);
    if (local == null) {
      final frescos = await leerConRespaldo<T>(
        tabla: tabla,
        eventoId: eventoId,
        desdeServidor: desdeServidor,
        aFila: aFila,
        desdeFila: desdeFila,
        isOnline: isOnline,
        esperaMaximaServidor: esperaMaximaServidor,
      );
      if (isOnline) _epocaConfirmada[clave] = epoca;
      return frescos;
    }

    final omitir = _revisionAutoRefresco.remove(clave) == revision;
    if (!isOnline) return local;

    // Recomposición que ya trae el disco fresco (revalidación entregada o
    // parche de una mutación propia): no hay nada que preguntar.
    if (omitir) return local;

    final confirmada = (_epocaConfirmada[clave] ?? -1) >= epoca;

    final pendiente = _revalidar<T>(
      clave: clave,
      tabla: tabla,
      eventoId: eventoId,
      desdeServidor: desdeServidor,
      aFila: aFila,
      epoca: epoca,
    );
    if (confirmada) return local;

    lector.esperando = true;
    try {
      await pendiente.timeout(esperaMaximaServidor);
    } on TimeoutException {
      // Sigue en vuelo: al terminar avisa al lector vivo.
    } finally {
      lector.esperando = false;
    }
    if (identical(_lectores[clave], lector)) {
      _cambiosSinEntregar.remove(clave);
    } else {
      _entregar(clave);
    }
    return _respaldo(tabla, eventoId, desdeFila) ?? const [];
  }

  /// Variante de [leerCacheFirst] para tablas sin partición por evento.
  Future<List<T>> leerCacheFirstGlobal<T>({
    required String tabla,
    required Future<List<T>> Function() desdeServidor,
    required Map<String, dynamic> Function(T) aFila,
    required T Function(Map<String, dynamic>) desdeFila,
    required bool isOnline,
    Duration esperaMaximaServidor = esperaMaximaServidorPorDefecto,
    int revision = 0,
    int epoca = 0,
    void Function()? onActualizado,
  }) {
    return leerCacheFirst<T>(
      tabla: tabla,
      eventoId: cacheAmbitoGlobal,
      desdeServidor: desdeServidor,
      aFila: aFila,
      desdeFila: desdeFila,
      isOnline: isOnline,
      esperaMaximaServidor: esperaMaximaServidor,
      revision: revision,
      epoca: epoca,
      onActualizado: onActualizado,
    );
  }

  /// Consulta compartida por todos los lectores de una entrada: si ya hay una
  /// en vuelo, se reutiliza en vez de lanzar otra.
  Future<void> _revalidar<T>({
    required String clave,
    required String tabla,
    required String eventoId,
    required Future<List<T>> Function() desdeServidor,
    required Map<String, dynamic> Function(T) aFila,
    required int epoca,
  }) {
    final generacion = _generaciones[clave] ?? 0;
    final enVuelo = _revalidaciones[clave];
    if (enVuelo != null && _generacionEnVuelo[clave] == generacion) {
      return enVuelo;
    }

    Future<void> revalidar() async {
      try {
        final frescos = await desdeServidor().timeout(
          esperaMaximaRevalidacion,
        );
        // Un parche local llegó mientras la consulta viajaba: su respuesta
        // puede ser anterior a la mutación y no debe pisarla.
        if ((_generaciones[clave] ?? 0) != generacion) return;
        final cambio = await _guardarSiCambia(
          tabla,
          eventoId,
          frescos.map(aFila).toList(),
        );
        _epocaConfirmada[clave] = epoca;
        _fallos.remove(clave);
        if (cambio) _cambiosSinEntregar.add(clave);
      } catch (error) {
        // Acceso revocado: la copia se va aunque nadie la esté mirando, y el
        // provider tiene que enterarse para dejar de servirla.
        if (_esRevocacionConfirmada(error) ||
            _esCredencialInvalidaConServidor(error, isOnline: true)) {
          await eliminarEvento(tabla, eventoId);
          _cambiosSinEntregar.add(clave);
        } else {
          _fallos[clave] = error;
          developer.log(
            'Revalidación de $tabla/$eventoId descartada: $error',
            name: 'OfflineReadCache',
          );
        }
      } finally {
        // Solo la consulta vigente se retira: una de generación vieja ya fue
        // reemplazada por otra que sigue en vuelo.
        if (_generacionEnVuelo[clave] == generacion) {
          _revalidaciones.remove(clave);
          _generacionEnVuelo.remove(clave);
        }
      }
      _entregar(clave);
    }

    final futuro = revalidar();
    _revalidaciones[clave] = futuro;
    _generacionEnVuelo[clave] = generacion;
    return futuro;
  }

  /// Avisa al lector vivo de [clave] si el disco cambió y no está esperando
  /// en línea (ese lee el disco por su cuenta al terminar).
  void _entregar(String clave) {
    if (!_cambiosSinEntregar.contains(clave)) return;
    final lector = _lectores[clave];
    if (lector == null || lector.esperando) return;
    _cambiosSinEntregar.remove(clave);
    _revisionAutoRefresco[clave] = lector.revision + 1;
    lector.onActualizado?.call();
  }

  /// La próxima lectura de esta entrada vuelve a esperar al servidor, aunque
  /// la época vigente ya se hubiera confirmado. Para cambios en vivo que solo
  /// tocan un evento (p. ej. un lead nuevo de otro capturador).
  void marcarPendienteDeServidor(String tabla, String eventoId) {
    _epocaConfirmada.remove('$tabla:$eventoId');
  }

  /// Tras un write-through local, el rebuild inmediato debe leer disco y no
  /// disparar un GET que todavía puede traer el valor viejo.
  void omitirProximaRevalidacion(String tabla, String eventoId, int revision) {
    _revisionAutoRefresco['$tabla:$eventoId'] = revision;
  }

  /// Espera las revalidaciones en vuelo.
  ///
  /// El snapshot lo necesita para no dar por bajada una etapa cuya consulta
  /// sigue en el aire: sus lecturas devuelven disco al instante igual que las
  /// de la UI. El tope de rondas evita quedarse enganchado si una revalidación
  /// encadena otra.
  Future<void> esperarRevalidaciones({int rondasMaximas = 3}) async {
    for (var ronda = 0; ronda < rondasMaximas; ronda++) {
      if (_revalidaciones.isEmpty) return;
      await Future.wait(_revalidaciones.values.toList());
    }
  }

  /// Revalidaciones que fallaron por red desde la última llamada. Las vacía.
  int consumirFallos() {
    final total = _fallos.length;
    _fallos.clear();
    return total;
  }

  /// Entrega lo del servidor y refresca la copia local. Si el servidor falla
  /// —típicamente por falta de red— devuelve la última copia guardada, y solo
  /// propaga el error cuando no hay ninguna.
  ///
  /// La llamada al servidor está acotada por [esperaMaximaServidor]: una
  /// petición que nunca responde se trata como fallo de transporte y cae a la
  /// copia local en vez de dejar la UI colgada.
  Future<List<T>> leerConRespaldo<T>({
    required String tabla,
    required String eventoId,
    required Future<List<T>> Function() desdeServidor,
    required Map<String, dynamic> Function(T) aFila,
    required T Function(Map<String, dynamic>) desdeFila,
    required bool isOnline,
    Duration esperaMaximaServidor = esperaMaximaServidorPorDefecto,
  }) async {
    if (!isOnline) {
      final respaldo = _respaldo(tabla, eventoId, desdeFila);
      if (respaldo != null) return respaldo;
      throw TimeoutException('Sin conexión', esperaMaximaServidor);
    }

    try {
      final frescos = await desdeServidor().timeout(esperaMaximaServidor);
      await guardar(tabla, eventoId, frescos.map(aFila).toList());
      return frescos;
    } catch (error) {
      if (_esRevocacionConfirmada(error) ||
          _esCredencialInvalidaConServidor(error, isOnline: isOnline)) {
        await eliminarEvento(tabla, eventoId);
        rethrow;
      }
      if (isOnline && !isNetworkTransportError(error)) {
        rethrow;
      }
      final respaldo = _respaldo(tabla, eventoId, desdeFila);
      if (respaldo == null) rethrow;
      developer.log(
        '$tabla/$eventoId servido desde la caché offline: $error',
        name: 'OfflineReadCache',
      );
      return respaldo;
    }
  }

  /// Variante de [leerConRespaldo] para tablas sin partición por evento.
  Future<List<T>> leerConRespaldoGlobal<T>({
    required String tabla,
    required Future<List<T>> Function() desdeServidor,
    required Map<String, dynamic> Function(T) aFila,
    required T Function(Map<String, dynamic>) desdeFila,
    required bool isOnline,
    Duration esperaMaximaServidor = esperaMaximaServidorPorDefecto,
  }) {
    return leerConRespaldo<T>(
      tabla: tabla,
      eventoId: cacheAmbitoGlobal,
      desdeServidor: desdeServidor,
      aFila: aFila,
      desdeFila: desdeFila,
      isOnline: isOnline,
      esperaMaximaServidor: esperaMaximaServidor,
    );
  }

  /// La caché v1 mezclaba cuentas. Sus filas no contienen evidencia suficiente
  /// del lector original, por lo que nunca se adoptan: se mueven en bruto a una
  /// cuarentena diagnóstica y se quitan de las claves activas.
  Future<int> quarantineLegacy() async {
    if (_owner == null) return 0;
    final keys = _prefs
        .getKeys()
        .where((key) => key.startsWith(_prefijoV1))
        .toList();
    for (final key in keys) {
      final raw = _prefs.getString(key);
      if (raw != null) {
        await _prefs.setString(
          '${_prefijoV3}_quarantine_${key.substring(_prefijoV1.length)}',
          raw,
        );
      }
      await _prefs.remove(key);
    }
    return keys.length;
  }

  Future<void> guardar(
    String tabla,
    String eventoId,
    List<Map<String, dynamic>> filas,
  ) => _guardarSiCambia(tabla, eventoId, filas);

  /// Escribe solo si el contenido cambió y responde si lo hizo.
  ///
  /// La comparación es sobre el JSON ya serializado: `toCacheMap` produce las
  /// claves siempre en el mismo orden, así que dos listas iguales dan el mismo
  /// texto. Sirve para dos cosas: no reescribir megabytes idénticos en cada
  /// refresco y saber si la UI tiene algo nuevo que mostrar.
  Future<bool> _guardarSiCambia(
    String tabla,
    String eventoId,
    List<Map<String, dynamic>> filas,
  ) async {
    _migrarV2SiHaceFalta(tabla);
    final key = _claveDatos(tabla, eventoId);
    if (key == null) return false;
    final nuevo = jsonEncode(filas);
    if (_prefs.getString(key) == nuevo) return false;
    await _prefs.setString(key, nuevo);
    final indice = _indice(tabla);
    if (indice.add(eventoId)) await _guardarIndice(tabla, indice);
    return true;
  }

  /// Variante de [guardar] para tablas sin partición por evento.
  Future<void> guardarGlobal(String tabla, List<Map<String, dynamic>> filas) {
    return guardar(tabla, cacheAmbitoGlobal, filas);
  }

  /// Reescribe una fila ya cacheada. Si no hay copia local, no inventa una.
  Future<bool> parchearFila({
    required String tabla,
    required String eventoId,
    required String id,
    required Map<String, dynamic> cambios,
  }) async {
    _migrarV2SiHaceFalta(tabla);
    final key = _claveDatos(tabla, eventoId);
    if (key == null) return false;
    final filas = _filasCrudas(key);
    if (filas == null) return false;
    var encontro = false;
    final actualizadas = <Map<String, dynamic>>[];
    for (final item in filas) {
      if (item is! Map) continue;
      final fila = Map<String, dynamic>.from(item);
      if (fila['id'] == id) {
        encontro = true;
        actualizadas.add({...fila, ...cambios});
      } else {
        actualizadas.add(fila);
      }
    }
    if (!encontro) return false;
    final clave = '$tabla:$eventoId';
    _generaciones[clave] = (_generaciones[clave] ?? 0) + 1;
    return _guardarSiCambia(tabla, eventoId, actualizadas);
  }

  /// `true` si esta tabla tiene copia local de [eventoId].
  ///
  /// Sin red la UI la usa para distinguir lo que se puede abrir de lo que ya se
  /// purgó: entrar a un evento sin caché solo lleva a una pantalla vacía.
  bool tieneEvento(String tabla, String eventoId) {
    _migrarV2SiHaceFalta(tabla);
    return _indice(tabla).contains(eventoId);
  }

  /// Elimina inmediatamente una copia cuyo acceso fue rechazado por RLS.
  Future<void> eliminarEvento(String tabla, String eventoId) async {
    _migrarV2SiHaceFalta(tabla);
    final key = _claveDatos(tabla, eventoId);
    if (key == null) return;
    await _prefs.remove(key);
    final indice = _indice(tabla);
    if (indice.remove(eventoId)) await _guardarIndice(tabla, indice);
  }

  /// Conserva solo eventos que siguen autorizados. Debe llamarse únicamente
  /// después de resolver la lista desde servidor; un error de red nunca se
  /// interpreta como una revocación.
  ///
  /// El ámbito global no se toca: no representa un evento y no está sujeto a
  /// la lista de autorizaciones.
  Future<void> retenerEventos(
    String tabla,
    Set<String> eventosAutorizados,
  ) async {
    _migrarV2SiHaceFalta(tabla);
    final indice = _indice(tabla);
    final sobrantes = indice
        .where(
          (eventoId) =>
              eventoId != cacheAmbitoGlobal &&
              !eventosAutorizados.contains(eventoId),
        )
        .toList();
    if (sobrantes.isEmpty) return;
    for (final eventoId in sobrantes) {
      final key = _claveDatos(tabla, eventoId);
      if (key != null) await _prefs.remove(key);
      indice.remove(eventoId);
    }
    await _guardarIndice(tabla, indice);
  }

  /// Purga filas cacheadas que pertenecen a otros perfiles. Se usa al cargar
  /// un rol con visibilidad privada de leads, incluido un downgrade de rol.
  Future<void> retenerFilasPropias(String tabla, String perfilId) async {
    _migrarV2SiHaceFalta(tabla);
    for (final eventoId in _indice(tabla)) {
      final key = _claveDatos(tabla, eventoId);
      if (key == null) continue;
      final filas = _filasCrudas(key);
      if (filas == null) continue;
      final propias = filas.where((fila) {
        if (fila is! Map) return false;
        return fila['perfil_id']?.toString() == perfilId;
      }).toList();
      if (propias.length != filas.length) {
        await _prefs.setString(key, jsonEncode(propias));
      }
    }
  }

  List<T>? _respaldo<T>(
    String tabla,
    String eventoId,
    T Function(Map<String, dynamic>) desdeFila,
  ) {
    _migrarV2SiHaceFalta(tabla);
    final key = _claveDatos(tabla, eventoId);
    if (key == null) return null;
    final filas = _filasCrudas(key);
    if (filas == null) return null;
    try {
      return filas
          .map((fila) => desdeFila(Map<String, dynamic>.from(fila as Map)))
          .toList();
    } catch (e) {
      developer.log(
        'Caché de $tabla ilegible, se descarta: $e',
        name: 'OfflineReadCache',
      );
      return null;
    }
  }

  List<dynamic>? _filasCrudas(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as List<dynamic>;
    } catch (e) {
      developer.log(
        'Caché corrupta en $key, se descarta: $e',
        name: 'OfflineReadCache',
      );
      return null;
    }
  }

  /// Reparte el blob v2 de [tabla] en una clave por evento.
  ///
  /// Es perezosa y síncrona a efectos de lectura: `SharedPreferences` publica
  /// el valor en su mapa en memoria al invocar `setString`, así que la lectura
  /// inmediatamente posterior ya ve las claves nuevas aunque la escritura en
  /// disco siga en vuelo. Migrar en el constructor obligaría a que todo lector
  /// esperara un future que hoy nadie espera.
  void _migrarV2SiHaceFalta(String tabla) {
    if (!_tablasMigradas.add(tabla)) return;
    final owner = _owner;
    if (owner == null) {
      // Sin sesión no hay namespace: no marcarla como migrada, para reintentar
      // cuando el owner exista.
      _tablasMigradas.remove(tabla);
      return;
    }

    final claveV2 = '${_prefijoV2}_${owner}_$tabla';
    final raw = _prefs.getString(claveV2);
    if (raw == null || raw.isEmpty) return;

    try {
      final todo = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final indice = _indice(tabla);
      for (final entry in todo.entries) {
        if (entry.value is! List) continue;
        final key = _claveDatos(tabla, entry.key);
        if (key == null) continue;
        unawaited(_prefs.setString(key, jsonEncode(entry.value)));
        indice.add(entry.key);
      }
      unawaited(_guardarIndice(tabla, indice));
    } catch (e) {
      developer.log(
        'Caché v2 de $tabla ilegible, se descarta: $e',
        name: 'OfflineReadCache',
      );
    }
    unawaited(_prefs.remove(claveV2));
  }

  /// Denegación que solo puede venir de una respuesta del servidor. Purgar es
  /// obligatorio aunque el dispositivo figure offline: si el acceso fue
  /// revocado, una desconexión posterior no puede revivir el evento.
  bool _esRevocacionConfirmada(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('401') ||
        message.contains('403') ||
        message.contains('row level security') ||
        message.contains('permission denied');
  }

  /// Fallo de credencial que el SDK también levanta en local, sin que el
  /// servidor haya dicho nada: un token vencido mientras el teléfono estuvo
  /// días sin abrirse produce exactamente esto. Sin evidencia de respuesta del
  /// servidor no es una revocación, y borrar ahí la caché destruiría los datos
  /// de la feria justo cuando no hay red para recuperarlos.
  bool _esCredencialInvalidaConServidor(
    Object error, {
    required bool isOnline,
  }) {
    if (!isOnline || isNetworkTransportError(error)) return false;
    final message = error.toString().toLowerCase();
    return message.contains('jwt') || message.contains('not authenticated');
  }
}

final offlineReadCacheProvider = Provider<OfflineReadCache>((ref) {
  final cache = OfflineReadCache(
    ref.watch(sharedPreferencesProvider),
    ownerId: ref.watch(syncQueueActiveOwnerIdProvider),
  );
  unawaited(cache.quarantineLegacy());
  return cache;
});


/// Época de servidor. Cada vez que sube, toda lectura viva vuelve a pedirle
/// los datos a Supabase y espera su respuesta antes de servir el disco (ver
/// [OfflineReadCache.leerCacheFirst]). Es lo que mantiene la app 1:1 con la
/// base mientras hay red: sube al volver a la app, al recuperar conexión, con
/// cada cambio en vivo y tras cada mutación propia.
final epocaServidorProvider = StateProvider<int>((ref) => 0);

/// Pide que las lecturas vivas se vuelvan a confirmar contra el servidor.
void exigirLecturaDelServidor(StateController<int> epoca) => epoca.state++;

/// Recarga del usuario (pull-to-refresh): exige el servidor, espera a que las
/// lecturas vuelvan a resolver y a que terminen las consultas en vuelo. El
/// [RefreshIndicator] tiene que esperar esto: si solo se hace `invalidate`, el
/// spinner se cierra al instante y la UI no llega a mostrar datos nuevos.
///
/// Si alguna consulta no pudo llegar al servidor se avisa en [context]: antes
/// el fallo era silencioso y la lista vieja parecía la verdadera.
Future<void> refrescarLecturas(
  WidgetRef ref, {
  BuildContext? context,
  required void Function() invalidar,
  required List<Future<Object?>> Function() pendientes,
}) async {
  final cache = ref.read(offlineReadCacheProvider);
  cache.consumirFallos();
  exigirLecturaDelServidor(ref.read(epocaServidorProvider.notifier));
  invalidar();

  var fallo = false;
  try {
    await Future.wait(pendientes());
  } catch (_) {
    // La pantalla ya muestra el error de su provider; aquí solo se avisa.
    fallo = true;
  }
  try {
    await cache.esperarRevalidaciones().timeout(esperaMaximaRevalidacion);
  } on TimeoutException {
    fallo = true;
  }
  if (cache.consumirFallos() > 0) fallo = true;

  if (fallo && context != null && context.mounted) {
    showAppSnackBar(
      context,
      ref.read(isOnlineProvider)
          ? 'No se pudo actualizar desde el servidor. Revisa tu conexión.'
          : kMensajeSinConexion,
      isError: true,
    );
  }
}

/// Refleja una mutación confirmada en la copia que la lista pinta primero.
///
/// El parche y la revisión hacen visible el cambio inmediatamente; además se
/// exige el servidor para que todas las lecturas vivas (listas, home,
/// contadores) queden alineadas con la base sin esperar a otra recarga.
Future<void> publicarCambioEnLecturaCacheada(
  WidgetRef ref, {
  required String tabla,
  required String eventoId,
  required String id,
  required Map<String, dynamic> cambios,
  required void Function() invalidar,
}) async {
  final cache = ref.read(offlineReadCacheProvider);
  final parcheado = await cache.parchearFila(
    tabla: tabla,
    eventoId: eventoId,
    id: id,
    cambios: cambios,
  );

  if (parcheado) {
    final clave = '$tabla:$eventoId';
    final siguiente = ref.read(cacheRevisionProvider(clave)) + 1;
    cache.omitirProximaRevalidacion(tabla, eventoId, siguiente);
    ref.read(cacheRevisionProvider(clave).notifier).state = siguiente;
  }
  invalidar();
  exigirLecturaDelServidor(ref.read(epocaServidorProvider.notifier));
}

/// Revisión de una entrada de caché (`tabla:evento`).
///
/// Sube cuando una revalidación en segundo plano trae datos distintos a los
/// que ya se pintaron. Los providers la observan para recomponerse leyendo el
/// disco recién actualizado, sin volver a pasar por `loading`.
final cacheRevisionProvider = StateProvider.family<int, String>(
  (ref, clave) => 0,
);

/// Lectura para providers: con red y época sin confirmar espera al servidor
/// (con tope); si no, entrega el disco al instante y revalida por detrás.
/// Cuando el servidor trae algo distinto sube la revisión y el provider se
/// recompone con lo nuevo.
///
/// No observa [isOnlineProvider]: un emit de conectividad reiniciaría el
/// [FutureProvider] y la UI pasaría por `loading`. Al recuperar la red sube la
/// época (ver `sincronizacionEnVivoProvider`) y las lecturas vuelven a pedir.
Future<List<T>> leerCacheFirstConRef<T>({
  required Ref ref,
  required String tabla,
  String eventoId = cacheAmbitoGlobal,
  required Future<List<T>> Function() desdeServidor,
  required Map<String, dynamic> Function(T) aFila,
  required T Function(Map<String, dynamic>) desdeFila,
  Duration esperaMaximaServidor = esperaMaximaServidorPorDefecto,
}) {
  final cache = ref.watch(offlineReadCacheProvider);
  final isOnline = ref.read(isOnlineProvider);
  final clave = '$tabla:$eventoId';
  final revision = ref.watch(cacheRevisionProvider(clave));
  final epoca = ref.watch(epocaServidorProvider);

  // La revalidación sobrevive al provider (escribe en disco de todos modos),
  // así que puede terminar cuando este ya no existe: notificar entonces sería
  // usar un `Ref` muerto.
  var vivo = true;
  ref.onDispose(() => vivo = false);

  return cache.leerCacheFirst<T>(
    tabla: tabla,
    eventoId: eventoId,
    desdeServidor: desdeServidor,
    aFila: aFila,
    desdeFila: desdeFila,
    isOnline: isOnline,
    esperaMaximaServidor: esperaMaximaServidor,
    revision: revision,
    epoca: epoca,
    onActualizado: () {
      if (!vivo) return;
      ref.read(cacheRevisionProvider(clave).notifier).state++;
    },
  );
}
