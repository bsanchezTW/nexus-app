import 'dart:developer' as developer;
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/conexion/senal_fallos_red.dart';
import '../../core/network/connectivity_service.dart';
import '../../core/network/offline_guard.dart';
import '../../core/widgets/app_widgets.dart';
import 'almacen/almacen_copia_local.dart';
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
/// El almacenamiento es [AlmacenCopiaLocal]: una entrada por `(tabla,
/// evento)` guardada fila por fila en SQLite. Antes vivía en
/// `SharedPreferences`; `migrarCopiaDesdePreferencias` la traspasa al arrancar.
class OfflineReadCache {
  OfflineReadCache(this._almacen, {this.ownerId, DateTime Function()? reloj})
    : _ahora = reloj ?? DateTime.now;

  final AlmacenCopiaLocal _almacen;
  final String? ownerId;
  final DateTime Function() _ahora;

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

  final ValueNotifier<Map<String, DateTime?>> _copiasServidas = ValueNotifier(
    const {},
  );

  /// Entradas (`tabla:evento`) que la app está mostrando desde la copia local
  /// en vez de desde el servidor, con la hora de su última confirmación
  /// (`null` si no se sabe).
  ///
  /// Una entrada entra cuando una lectura cae a la copia —sin red, servidor
  /// lento, error— y sale en cuanto el servidor vuelve a responderla. Es lo
  /// que permite avisar "Mostrando copia local · actualizada hace X".
  ValueListenable<Map<String, DateTime?>> get copiasServidas => _copiasServidas;

  final Map<String, DateTime?> _copias = {};
  bool _avisoProgramado = false;

  void _marcarCopiaServida(String tabla, String eventoId) {
    final owner = _owner;
    if (owner == null) return;
    final clave = '$tabla:$eventoId';
    final hora = _almacen.actualizadaEn(owner, tabla, eventoId);
    if (_copias.containsKey(clave) && _copias[clave] == hora) return;
    _copias[clave] = hora;
    _programarAviso();
  }

  void _desmarcarCopiaServida(String clave) {
    if (!_copias.containsKey(clave)) return;
    _copias.remove(clave);
    _programarAviso();
  }

  /// Publica el cambio en un microtask: una lectura puede marcar la copia
  /// mientras un provider se está construyendo, y avisar ahí mismo haría que
  /// otro provider se invalide en plena construcción.
  void _programarAviso() {
    if (_avisoProgramado) return;
    _avisoProgramado = true;
    scheduleMicrotask(() {
      _avisoProgramado = false;
      if (!mapEquals(_copias, _copiasServidas.value)) {
        _copiasServidas.value = Map.unmodifiable(_copias);
      }
    });
  }

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

  /// Olvida qué se está mostrando desde la copia. Al volver la conexión o al
  /// recargar a mano, cada pantalla viva vuelve a consultar y se marca de
  /// nuevo solo si su consulta vuelve a fallar; así no queda el aviso pegado
  /// por una pantalla que ya se cerró.
  void olvidarCopiasServidas() {
    if (_copias.isEmpty) return;
    _copias.clear();
    _programarAviso();
  }

  /// La pantalla que leía [tabla]/[eventoId] se cerró.
  void dejarDeMostrar(String tabla, String eventoId) =>
      _desmarcarCopiaServida('$tabla:$eventoId');

  String? get _owner {
    final owner = ownerId?.trim();
    if (owner == null || owner.isEmpty) return null;
    return owner;
  }

  /// Eventos con copia local en [tabla] para el perfil en sesión.
  Set<String> _indice(String tabla) {
    final owner = _owner;
    if (owner == null) return {};
    return _almacen.eventos(owner, tabla);
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
      if (local == null) {
        throw TimeoutException('Sin conexión', esperaMaximaServidor);
      }
      _marcarCopiaServida(tabla, eventoId);
      return local;
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
      _marcarCopiaServida(tabla, eventoId);
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
      _marcarCopiaServida(tabla, eventoId);
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
      _marcarCopiaServida(tabla, eventoId);
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
        _desmarcarCopiaServida(clave);
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
          _desmarcarCopiaServida(clave);
        } else if (isNetworkTransportError(error)) {
          _servidorInalcanzableHasta = _ahora().add(
            ventanaServidorInalcanzable,
          );
          _fallos[clave] = error;
          // Agotó el presupuesto completo (30 s), no la espera corta de la
          // UI: eso sí es una red mala y la conexión pasa a inestable.
          reportarFalloDeRed();
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
      return _guardarSiCambia(tabla, eventoId, filas(), confirmada: true);
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
      if (respaldo == null) {
        throw TimeoutException('Sin conexión', esperaMaximaServidor);
      }
      _marcarCopiaServida(tabla, eventoId);
      return respaldo;
    }

    try {
      final frescos = await desdeServidor().timeout(esperaMaximaServidor);
      await guardar(tabla, eventoId, frescos.map(aFila).toList());
      _desmarcarCopiaServida('$tabla:$eventoId');
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
      _marcarCopiaServida(tabla, eventoId);
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

  /// Guarda lo que acaba de entregar el servidor. Registra la hora como
  /// confirmación (ver [copiasServidas]).
  Future<void> guardar(
    String tabla,
    String eventoId,
    List<Map<String, dynamic>> filas,
  ) => _guardarSiCambia(tabla, eventoId, filas, confirmada: true);

  /// Escribe solo si el contenido cambió y responde si lo hizo.
  ///
  /// El almacén compara fila a fila (ver [AlmacenCopiaLocal.guardar]): un
  /// refresco idéntico no escribe nada, y uno que cambia una fila escribe esa
  /// fila. La respuesta dice si la UI tiene algo nuevo que mostrar.
  ///
  /// [confirmada] marca que [filas] vienen del servidor; un parche local no lo
  /// es y no mueve la hora de "actualizada hace X".
  Future<bool> _guardarSiCambia(
    String tabla,
    String eventoId,
    List<Map<String, dynamic>> filas, {
    bool confirmada = false,
  }) async {
    final owner = _owner;
    if (owner == null) return false;
    return _almacen.guardar(
      owner,
      tabla,
      eventoId,
      filas,
      confirmadaEn: confirmada ? _ahora() : null,
    );
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
    final owner = _owner;
    if (owner == null) return false;
    final filas = _almacen.leer(owner, tabla, eventoId);
    if (filas == null) return false;
    var encontro = false;
    final actualizadas = <Map<String, dynamic>>[];
    for (final fila in filas) {
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
    return _indice(tabla).contains(eventoId);
  }

  /// Elimina inmediatamente una copia cuyo acceso fue rechazado por RLS.
  Future<void> eliminarEvento(String tabla, String eventoId) async {
    final owner = _owner;
    if (owner == null) return;
    await _almacen.borrar(owner, tabla, eventoId);
    _desmarcarCopiaServida('$tabla:$eventoId');
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
    final owner = _owner;
    if (owner == null) return;
    final sobrantes = _indice(tabla).where(
      (eventoId) =>
          eventoId != cacheAmbitoGlobal &&
          !eventosAutorizados.contains(eventoId),
    );
    for (final eventoId in sobrantes.toList()) {
      await _almacen.borrar(owner, tabla, eventoId);
    }
  }

  /// Purga filas cacheadas que pertenecen a otros perfiles. Se usa al cargar
  /// un rol con visibilidad privada de leads, incluido un downgrade de rol.
  Future<void> retenerFilasPropias(String tabla, String perfilId) async {
    final owner = _owner;
    if (owner == null) return;
    for (final eventoId in _indice(tabla).toList()) {
      final filas = _almacen.leer(owner, tabla, eventoId);
      if (filas == null) continue;
      final propias = filas
          .where((fila) => fila['perfil_id']?.toString() == perfilId)
          .toList();
      if (propias.length != filas.length) {
        await _almacen.guardar(owner, tabla, eventoId, propias);
      }
    }
  }

  List<T>? _respaldo<T>(
    String tabla,
    String eventoId,
    T Function(Map<String, dynamic>) desdeFila,
  ) {
    final owner = _owner;
    if (owner == null) return null;
    final filas = _almacen.leer(owner, tabla, eventoId);
    if (filas == null) return null;
    try {
      return filas.map(desdeFila).toList();
    } catch (e) {
      developer.log(
        'Caché de $tabla ilegible, se descarta: $e',
        name: 'OfflineReadCache',
      );
      return null;
    }
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
  return OfflineReadCache(
    ref.watch(almacenCopiaLocalProvider),
    ownerId: ref.watch(syncQueueActiveOwnerIdProvider),
  );
});

/// Entradas que se están mostrando desde la copia local, con la hora de su
/// última confirmación del servidor (ver [OfflineReadCache.copiasServidas]).
final copiasServidasProvider = Provider<Map<String, DateTime?>>((ref) {
  final ValueListenable<Map<String, DateTime?>> copias;
  try {
    copias = ref.watch(offlineReadCacheProvider).copiasServidas;
  } catch (_) {
    // Igual que `pendingSyncCountProvider`: hay widgets que se prueban sin
    // Supabase ni bootstrap. En la app real la caché siempre existe.
    return const {};
  }
  void cambio() => ref.invalidateSelf();
  copias.addListener(cambio);
  ref.onDispose(() => copias.removeListener(cambio));
  return copias.value;
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
  cache.olvidarCopiasServidas();
  exigirLecturaDelServidor(ref.read(epocaServidorProvider.notifier));
  invalidar();

  var fallo = false;
  try {
    await esperarLecturasVigentes(pendientes);
  } catch (_) {
    // La pantalla ya muestra el error de su provider; aquí solo se avisa.
    fallo = true;
  }
  if (cache.consumirFallos() > 0) fallo = true;

  if (fallo && context != null && context.mounted) {
    if (ref.read(isOnlineProvider)) {
      showAppSnackBar(
        context,
        'No se pudo actualizar desde el servidor. Revisa tu conexión.',
        isError: true,
      );
    } else {
      showOfflineUnavailableToast(context, ref: ref);
    }
  }
}

/// Espera las lecturas de [pendientes] y, si alguna carga fue reemplazada
/// mientras corría, espera la que la reemplazó.
///
/// Al recargar se invalidan a la vez lecturas que dependen unas de otras (el
/// perfil y los fijados, el resumen y los destacados). La dependiente arranca
/// con la dependencia todavía recargándose; cuando esta termina, la
/// dependiente se reconstruye y la primera carga, ya descartada, falla con
/// [StateError] al usar su `ref`. Esa carga no es la que se ve en pantalla ni
/// un fallo del servidor: se vuelve a pedir el futuro vigente. Cualquier otro
/// error se propaga tal cual.
@visibleForTesting
Future<void> esperarLecturasVigentes(
  List<Future<Object?>> Function() pendientes, {
  int intentos = 3,
}) async {
  for (var intento = 1; ; intento++) {
    try {
      await Future.wait(pendientes());
      return;
    } on StateError {
      if (intento >= intentos) rethrow;
    }
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
/// [FutureProvider] y la UI pasaría por `loading`. Al volver a una conexión
/// estable sube la época (ver `orquestadorReconexionProvider`) y las lecturas
/// vuelven a pedir.
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
  ref.onDispose(() {
    vivo = false;
    cache.dejarDeMostrar(tabla, eventoId);
  });

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
