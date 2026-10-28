import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../conexion/monitor_conexion.dart';
import '../conexion/politica_conexion.dart';
import 'offline_policy.dart';

export '../conexion/interfaz_red.dart' show connectivityStreamProvider;

/// `connectivity_plus` informa disponibilidad de interfaz, no acceso real a
/// Internet. Esta comprobación permite convertir fallos de transporte en una
/// escritura offline sin ocultar errores de validación, permisos o RLS.
bool isNetworkTransportError(Object error) {
  final type = error.runtimeType.toString().toLowerCase();
  final message = error.toString().toLowerCase();
  return type.contains('socketexception') ||
      type.contains('clientexception') ||
      type.contains('timeoutexception') ||
      message.contains('socketexception') ||
      message.contains('failed host lookup') ||
      message.contains('network is unreachable') ||
      message.contains('connection refused') ||
      message.contains('connection reset') ||
      message.contains('connection closed') ||
      message.contains('timed out') ||
      message.contains('timeout') ||
      message.contains('xmlhttprequest error') ||
      message.contains('failed to fetch');
}

/// Tope de una escritura directa al servidor antes de pasarla a la cola.
///
/// Con el wifi de un recinto que no deja salir, `connectivity_plus` sigue
/// diciendo "conectado" y la petición no falla: simplemente no vuelve. Sin
/// tope, acreditar se quedaba esperando lo que tarde el sistema en cortar la
/// conexión. Solo vale para escrituras idempotentes —repetirlas desde la cola
/// no duplica nada si la primera sí había llegado.
const Duration esperaMaximaEscrituraDirecta = Duration(seconds: 10);

/// `true` si la app debe hablar con el servidor ahora mismo.
///
/// Sale de `estadoConexionProvider` —sondeos reales al backend—, no de si el
/// wifi está encendido: con una conexión inestable las plataformas con copia
/// local pasan a operar sin conexión. Mientras se hace el primer sondeo vale
/// `true`; las lecturas tienen su propio tope y caen a la copia local si el
/// servidor no contesta.
final isOnlineProvider = Provider<bool>((ref) {
  return PoliticaConexion.usaServidor(
    ref.watch(estadoConexionProvider),
    soportaCopiaLocal: supportsOfflineCacheAqui,
  );
});
