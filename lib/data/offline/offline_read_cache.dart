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

/// Presupuesto total de una consulta. La UI deja de esperarla a los
/// [esperaMaximaServidorPorDefecto], pero la consulta sigue por detrás hasta
/// este tope: cuando llega, la pantalla se reconstruye con lo del servidor.
const Duration esperaMaximaRevalidacion = Duration(seconds: 30);

/// Tras un timeout o un error de red, durante este tiempo las lecturas con
/// copia local la sirven al instante y consultan por detrás. Sin esto, con un
/// wifi cautivo cada pantalla esperaría [esperaMaximaServidorPorDefecto] antes
/// de mostrar nada.
const Duration ventanaServidorInalcanzable = Duration(seconds: 20);

/// Último lector vivo de una entrada (`tabla:evento`). Una consulta puede
/// terminar después de que el provider que la lanzó se reconstruyera; el aviso
/// tiene que llegarle al lector actual, no al que ya no existe.
class _Lector {
  _Lector(this.revision, this.onActualizado);

  final int revision;
  final void Function()? onActualizado;
}

/// Respuesta del servidor con su respaldo en disco, que corre aparte.
class _Respuesta<T> {
  const _Respuesta(this.frescos, this.respaldo);

  final List<T> frescos;

  /// `true` si la copia local cambió.
  final Future<bool> respaldo;
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
/// Con red la copia **no** es la fuente: cada lectura le pregunta a Supabase
/// y lo que se pinta es su respuesta. El disco solo se usa sin red, cuando el
/// servidor no contesta a tiempo, o para la reconstrucción inmediata tras un
/// parche local.
///
/// El almacenamiento es **una clave por `(tabla, evento)`** más un índice de
/// eventos por tabla. El formato v2 guardaba un único blob por tabla y lo
/// re-serializaba entero en cada escritura de un evento; con el snapshot
/// completo (~10 eventos × cientos de filas) eso reescribía megabytes de JSON
/// por cada evento guardado.
class OfflineReadCache {
  OfflineReadCache(this._prefs, {this.ownerId, DateTime Function()? reloj})
    : _ahora = reloj ?? DateTime.now;

  final SharedPreferences _prefs;
  final String? ownerId;
  final DateTime Function() _ahora;

  /// Tablas cuya migración desde v2 ya se comprobó en esta instancia.
  final Set<String> _tablasMigradas = <String>{};

  /// Consultas y respaldos en vuelo. Quien va a escribir (acreditar, editar)
  /// puede esperarlos para que una respuesta vieja no llegue después.
  final Set<Future<void>> _pendientes = <Future<void>>{};

  /// Revisión que dejó una entrega tardía o un parche. La lectura que llega
  /// con esa revisión ya está viendo el disco fresco y no vuelve a consultar.
  final Map<String, int> _revisionAutoRefresco = <String, int>{};

  final Map<String, _Lector> _lectores = <String, _Lector>{};

  /// Consultas que no llegaron al servidor desde la última vez que se
  /// preguntó (ver [consumirFallos]).
  final Map<String, Object> _fallos = <String, Object>{};

  /// Turno de cada consulta o parche por entrada. Solo se escribe en disco una
  /// respuesta más nueva que lo último escrito: una consulta lenta lanzada
  /// antes no pisa ni a otra posterior ni a un parche local.
  final Map<String, int> _turnos = <String, int>{};
  final Map<String, int> _turnoEscrito = <String, int>{};

  DateTime? _servidorInalcanzableHasta;

  bool get _servidorInalcanzable {
    final hasta = _servidorInalcanzableHasta;
    return hasta != null && _ahora().isBefore(hasta);
  }

  /// La próxima lectura vuelve a esperar al servidor aunque haya fallado hace
  /// poco. Para cuando el usuario pide recargar a mano.
  void olvidarServidorInalcanzable() => _servidorInalcanzableHasta = null;

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

  /// Lectura de la UI: con red, **Supabase primero**; el disco es el respaldo.
  ///
  /// - Con red, cada lectura consulta al servidor y entrega su respuesta tal
  ///   cual. La copia local se actualiza después, en segundo plano.
  /// - Si el servidor no contesta en [esperaMaximaServidor] —wifi cautivo de
  ///   feria— se sirve el disco y la consulta sigue por detrás hasta
  ///   [esperaMaximaRevalidacion]; cuando llega, el lector vivo se reconstruye
  ///   con lo nuevo. Durante [ventanaServidorInalcanzable] las lecturas
  ///   siguientes ya no esperan: sirven el disco y consultan por detrás.
  /// - Sin red, el disco. Sin copia local no hay nada que mostrar y se propaga
  ///   el error.
  ///
  /// [revision] y [onActualizado] son el vínculo con el provider que llama:
  /// una respuesta tardía invoca [onActualizado] del lector vivo para que se
  /// recomponga leyendo el disco ya fresco. Esa recomposición llega con la
  /// revisión que dejó la entrega y se resuelve desde el disco; si no, cada
  /// respuesta tardía dispararía otra consulta.
  Future<List<T>> leerCacheFirst<T>({
    required String tabla,
    required String eventoId,
    required Future<List<T>> Function() desdeServidor,
    required Map<String, dynamic> Function(T) aFila,
    required T Function(Map<String, dynamic>) desdeFila,
    required bool isOnline,
    Duration esperaMaximaServidor = esperaMaximaServidorPorDefecto,
    int revision = 0,
    void Function()? onActualizado,
  }) async {
    final clave = '$tabla:$eventoId';
    _lectores[clave] = _Lector(revision, onActualizado);

    final local = _respaldo(tabla, eventoId, desdeFila);
    final omitir = _revisionAutoRefresco.remove(clave) == revision;

    if (!isOnline) {
      if (local != null) return local;
      throw TimeoutException('Sin conexión', esperaMaximaServidor);
    }

    // Recomposición que ya trae el disco fresco (respuesta tardía entregada o
    // parche de una mutación propia): no hay nada que preguntar.
    if (omitir && local != null) return local;

    final consulta = _consultar<T>(
      clave: clave,
      tabla: tabla,
      eventoId: eventoId,
      desdeServidor: desdeServidor,
      aFila: aFila,
    );

    if (local != null && _servidorInalcanzable) {
      unawaited(_entregarAlTerminar(clave, consulta));
      return local;
    }

    try {
      final respuesta = await consulta.timeout(esperaMaximaServidor);
      return respuesta.frescos;
    } on TimeoutException catch (error) {
      // La consulta sigue en vuelo: al terminar avisa al lector vivo.
      _servidorInalcanzableHasta = _ahora().add(ventanaServidorInalcanzable);
      _fallos[clave] = error;
      unawaited(_entregarAlTerminar(clave, consulta));
      if (local == null) rethrow;
      return local;
    } catch (error) {
      // Acceso revocado: la copia ya se borró y la pantalla tiene que saberlo.
      if (local == null ||
          _esRevocacionConfirmada(error) ||
          _esCredencialInvalidaConServidor(error, isOnline: true)) {
        rethrow;
      }
      // Cualquier otro fallo con copia local: se sirve la copia, pero queda
      // registrado para que recargar a mano avise que no llegó al servidor.
      _fallos[clave] = error;
      developer.log(
        '$clave servido desde la caché por un error del servidor: $error',
        name: 'OfflineReadCache',
      );
      return local;
    }
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
      onActualizado: onActualizado,
    );
  }

  /// Una consulta al servidor con su propio turno. No se comparte entre
  /// lectores: cada build trae sus propios parámetros (el home, por ejemplo,
  /// arma los destacados con el catálogo que acaba de resolver) y reutilizar
  /// una consulta en vuelo de otro build entregaba datos armados con valores
  /// viejos.
  Future<_Respuesta<T>> _consultar<T>({
    required String clave,
    required String tabla,
    required String eventoId,
    required Future<List<T>> Function() desdeServidor,
    required Map<String, dynamic> Function(T) aFila,
  }) {
    final turno = (_turnos[clave] ?? 0) + 1;
    _turnos[clave] = turno;

    Future<_Respuesta<T>> consultar() async {
      try {
        final frescos = await desdeServidor().timeout(esperaMaximaRevalidacion);
        _servidorInalcanzableHasta = null;
        _fallos.remove(clave);
        final respaldo = _respaldar(
          clave: clave,
          tabla: tabla,
          eventoId: eventoId,
          turno: turno,
          filas: () => frescos.map(aFila).toList(),
        );
        return _Respuesta<T>(frescos, respaldo);
      } catch (error) {
        // Acceso revocado: la copia se va aunque nadie la esté mirando.
        if (_esRevocacionConfirmada(error) ||
            _esCredencialInvalidaConServidor(error, isOnline: true)) {
          _turnoEscrito[clave] = turno;
          await eliminarEvento(tabla, eventoId);
        } else if (isNetworkTransportError(error)) {
          _servidorInalcanzableHasta = _ahora().add(
            ventanaServidorInalcanzable,
          );
          _fallos[clave] = error;
        }
        rethrow;
      }
    }

    final futuro = consultar();
    _registrarPendiente(futuro);
    return futuro;
  }

  /// Escribe la respuesta en disco en segundo plano, después de entregarla.
  /// Se descarta si mientras tanto se escribió algo más nuevo (otra consulta
  /// o un parche).
  Future<bool> _respaldar({
    required String clave,
    required String tabla,
    required String eventoId,
    required int turno,
    required List<Map<String, dynamic>> Function() filas,
  }) {
    final escritura = Future<bool>(() {
      if (turno <= (_turnoEscrito[clave] ?? 0)) return false;
      _turnoEscrito[clave] = turno;
      return _guardarSiCambia(tabla, eventoId, filas());
    });
    _registrarPendiente(escritura);
    return escritura;
  }

  void _registrarPendiente(Future<Object?> futuro) {
    final pendiente = futuro.then<void>((_) {}, onError: (Object _) {});
    _pendientes.add(pendiente);
    pendiente.whenComplete(() => _pendientes.remove(pendiente));
  }

  /// Respuesta que la UI dejó de esperar: cuando llega y cambió el disco, el
  /// lector vivo se reconstruye con ella.
  Future<void> _entregarAlTerminar<T>(
    String clave,
    Future<_Respuesta<T>> consulta,
  ) async {
    try {
      final respuesta = await consulta;
      if (await respuesta.respaldo) _entregar(clave);
    } catch (error) {
      if (_esRevocacionConfirmada(error) ||
          _esCredencialInvalidaConServidor(error, isOnline: true)) {
        _entregar(clave);
        return;
      }
      developer.log(
        'Consulta de $clave sin respuesta del servidor: $error',
        name: 'OfflineReadCache',
      );
    }
  }

  /// Avisa al lector vivo de [clave] que el disco cambió.
  void _entregar(String clave) {
    final lector = _lectores[clave];
    if (lector == null) return;
    _revisionAutoRefresco[clave] = lector.revision + 1;
    lector.onActualizado?.call();
  }

  /// Tras un write-through local, el rebuild inmediato debe leer disco y no
  /// disparar un GET que todavía puede traer el valor viejo.
  void omitirProximaRevalidacion(String tabla, String eventoId, int revision) {
    _revisionAutoRefresco['$tabla:$eventoId'] = revision;
  }

  /// Espera las consultas y respaldos en vuelo.
  ///
  /// Quien va a escribir lo usa para que una consulta lanzada antes no
  /// termine después y deje en disco la versión anterior. El tope de rondas
  /// evita quedarse enganchado si una consulta encadena otra.
  Future<void> esperarRevalidaciones({int rondasMaximas = 3}) async {
    for (var ronda = 0; ronda < rondasMaximas; ronda++) {
      if (_pendientes.isEmpty) return;
      await Future.wait(_pendientes.toList());
    }
  }

  /// Consultas que no llegaron al servidor desde la última llamada. Las vacía.
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
    // Toma turno: una consulta lanzada antes del parche puede traer la fila
    // anterior a la mutación y no debe pisarlo al terminar.
    final clave = '$tabla:$eventoId';
    final turno = (_turnos[clave] ?? 0) + 1;
    _turnos[clave] = turno;
    _turnoEscrito[clave] = turno;
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

/// Época de servidor. Cada vez que sube, todo provider que lee con
/// [leerCacheFirstConRef] se reconstruye y vuelve a consultar Supabase. Sube
/// al volver a la app, al recuperar conexión, con cada cambio en vivo y tras
/// cada mutación propia.
final epocaServidorProvider = StateProvider<int>((ref) => 0);

/// Pide que las lecturas vivas se vuelvan a confirmar contra el servidor.
void exigirLecturaDelServidor(StateController<int> epoca) => epoca.state++;

/// Recarga del usuario (pull-to-refresh): exige el servidor y espera a que las
/// lecturas vuelvan a resolver. El [RefreshIndicator] tiene que esperar esto:
/// si solo se hace `invalidate`, el spinner se cierra al instante y la UI no
/// llega a mostrar datos nuevos.
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
  // Quien recarga a mano quiere al servidor aunque haya fallado hace poco.
  cache.olvidarServidorInalcanzable();
  exigirLecturaDelServidor(ref.read(epocaServidorProvider.notifier));
  invalidar();

  var fallo = false;
  try {
    await Future.wait(pendientes());
  } catch (_) {
    // La pantalla ya muestra el error de su provider; aquí solo se avisa.
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
/// Sube cuando una respuesta que la UI dejó de esperar trae datos distintos a
/// los que ya se pintaron. Los providers la observan para recomponerse leyendo el
/// disco recién actualizado, sin volver a pasar por `loading`.
final cacheRevisionProvider = StateProvider.family<int, String>(
  (ref, clave) => 0,
);

/// Lectura para providers: con red, lo que diga Supabase (ver
/// [OfflineReadCache.leerCacheFirst]); sin red o sin respuesta a tiempo, el
/// disco. Si la respuesta llega tarde sube la revisión y el provider se
/// recompone con lo nuevo.
///
/// Observa [epocaServidorProvider] para volver a consultar cuando sube. No
/// observa [isOnlineProvider]: un emit de conectividad reiniciaría el
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
  ref.watch(epocaServidorProvider);

  // La consulta sobrevive al provider (escribe en disco de todos modos),
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
    onActualizado: () {
      if (!vivo) return;
      ref.read(cacheRevisionProvider(clave).notifier).state++;
    },
  );
}
