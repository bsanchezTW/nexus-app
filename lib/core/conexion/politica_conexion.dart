import 'estado_conexion.dart';

/// Resultado de un sondeo al backend.
class LecturaSondeo {
  const LecturaSondeo.respondio(this.latencia) : respondio = true;

  const LecturaSondeo.sinRespuesta()
    : respondio = false,
      latencia = Duration.zero;

  final bool respondio;
  final Duration latencia;
}

/// Reglas que convierten señales de red en un [EstadoConexion].
///
/// Funciones puras, igual que `offline_policy.dart`, para poder probarlas sin
/// montar la app ni esperar sondeos reales.
///
/// El criterio es **degradar rápido y recuperar lento**: un sondeo fallido ya
/// pasa a modo sin conexión, pero volver a tiempo real exige varios sondeos
/// sanos seguidos y un mínimo de permanencia. Sin esa histéresis, una señal
/// intermitente haría saltar la app entre modos cada pocos segundos.
class PoliticaConexion {
  const PoliticaConexion._();

  /// Tope de cada sondeo. Un portal cautivo puede dejar la petición abierta.
  static const esperaSondeo = Duration(seconds: 4);

  /// Cada cuánto se sondea con la conexión estable.
  static const intervaloEstable = Duration(seconds: 15);

  /// Cada cuánto se sondea en modo degradado, para volver pronto.
  static const intervaloDegradado = Duration(seconds: 5);

  /// Un sondeo que tarda más que esto cuenta como lento.
  static const latenciaLenta = Duration(milliseconds: 2500);

  /// Para volver a estable cada sondeo tiene que tardar menos que esto.
  static const latenciaSana = Duration(milliseconds: 1500);

  /// Lentos entre los últimos [ventanaSondeos] que bastan para degradar.
  static const sondeosLentosParaDegradar = 2;

  /// Sondeos sin respuesta seguidos que significan "sin Internet".
  static const fallosParaSinInternet = 2;

  /// Sondeos sanos seguidos que exige volver a estable.
  static const sondeosParaRecuperar = 3;

  /// Historial que se conserva. Alcanza para todas las reglas de arriba.
  static const ventanaSondeos = 3;

  /// Tiempo mínimo en modo degradado antes de volver a estable.
  static const permanenciaMinimaDegradado = Duration(seconds: 30);

  /// Estado que corresponde a las señales actuales.
  ///
  /// [historial] va del más viejo al más reciente. [tiempoDegradado] es lo
  /// que lleva la app en modo degradado (cero si está estable).
  static EstadoConexion siguiente({
    required EstadoConexion actual,
    required bool hayInterfaz,
    required List<LecturaSondeo> historial,
    Duration tiempoDegradado = Duration.zero,
  }) {
    if (!hayInterfaz) return EstadoConexion.sinInternet;
    if (historial.isEmpty) return actual;

    if (!historial.last.respondio) {
      final fallosSeguidos = historial.reversed
          .takeWhile((l) => !l.respondio)
          .length;
      return fallosSeguidos >= fallosParaSinInternet
          ? EstadoConexion.sinInternet
          : EstadoConexion.inestable;
    }

    if (actual.degradado) {
      final recientes = historial.length >= sondeosParaRecuperar
          ? historial.sublist(historial.length - sondeosParaRecuperar)
          : const <LecturaSondeo>[];
      final sano =
          recientes.isNotEmpty &&
          recientes.every((l) => l.respondio && l.latencia <= latenciaSana);
      if (sano && tiempoDegradado >= permanenciaMinimaDegradado) {
        return EstadoConexion.estable;
      }
      // Responde, pero todavía no se ganó volver: sigue sin conexión.
      return EstadoConexion.inestable;
    }

    final lentos = historial
        .where((l) => l.respondio && l.latencia > latenciaLenta)
        .length;
    return lentos >= sondeosLentosParaDegradar
        ? EstadoConexion.inestable
        : EstadoConexion.estable;
  }

  /// `true` si la app debe hablar con el servidor en este [estado].
  ///
  /// Las plataformas sin copia local (web) no tienen a dónde degradar: con la
  /// conexión inestable siguen yendo al servidor y solo se detienen sin
  /// Internet.
  static bool usaServidor(
    EstadoConexion estado, {
    required bool soportaCopiaLocal,
  }) {
    if (!soportaCopiaLocal) return estado != EstadoConexion.sinInternet;
    return !estado.degradado;
  }
}
