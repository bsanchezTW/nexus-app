import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';

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

/// Único punto de verdad sobre el estado de conexión.
///
/// El proyecto legado tenía la detección de red repetida y ligeramente
/// distinta en cada pantalla (`NetInfo.addEventListener` en móvil,
/// `window.addEventListener('online', ...)` en web). Acá se centraliza en
/// un `StreamProvider` que ambas plataformas comparten sin código extra.
final connectivityStreamProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();

  bool isOnline(List<ConnectivityResult> results) =>
      results.isNotEmpty && !results.contains(ConnectivityResult.none);

  yield isOnline(await connectivity.checkConnectivity());

  yield* connectivity.onConnectivityChanged.map(isOnline).distinct();
});

/// Snapshot síncrono (con valor por defecto optimista `true`) para lugares
/// donde no conviene reconstruir todo el árbol de widgets por un `AsyncValue`.
final isOnlineProvider = Provider<bool>((ref) {
  return ref.watch(connectivityStreamProvider).valueOrNull ?? true;
});

/// Espera de cada intento de alcance. Corta antes de que un portal cautivo
/// mantenga la petición abierta indefinidamente.
const Duration _esperaPing = Duration(seconds: 4);

/// Un parpadeo de red no debe congelar la app: el cambio de estado se confirma
/// con un segundo intento antes de propagarse.
const Duration _debounceCambio = Duration(seconds: 2);

const Duration _intervaloConRed = Duration(seconds: 30);
const Duration _intervaloSinRed = Duration(seconds: 5);

final _dioPing = Dio(
  BaseOptions(connectTimeout: _esperaPing, receiveTimeout: _esperaPing),
);

/// `true` si el backend contesta cualquier cosa.
///
/// Sirve cualquier código de estado, incluido un 401: lo que se comprueba es
/// que el tráfico sale, no que la petición esté autorizada.
Future<bool> _backendResponde() async {
  try {
    final respuesta = await _dioPing.getUri(
      Uri.parse('${Env.supabaseUrl}/auth/v1/health'),
      options: Options(
        headers: {'apikey': Env.supabasePublishableKey},
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    return respuesta.statusCode != null;
  } catch (_) {
    return false;
  }
}

/// Salida real a Internet, no solo interfaz levantada.
///
/// `connectivity_plus` responde "conectado" con el wifi de un recinto o de un
/// hotel que no deja pasar tráfico. Para el banner de móvil esa diferencia es
/// tolerable, pero el overlay de escritorio congela toda la app: bloquearla
/// —o no bloquearla— por una interfaz que miente es justo el error que hay que
/// evitar, así que aquí se confirma con una petición real al backend.
final conexionRealProvider = StreamProvider<bool>((ref) async* {
  var vivo = true;
  ref.onDispose(() => vivo = false);

  bool hayInterfaz() =>
      ref.read(connectivityStreamProvider).valueOrNull ?? true;

  // La interfaz caída ya es evidencia suficiente y ahorra el intento.
  Future<bool> alcanzable() async => hayInterfaz() && await _backendResponde();

  // Optimista al arrancar: el overlay no debe parpadear mientras se resuelve
  // el primer intento.
  var ultimo = true;
  yield true;

  while (vivo) {
    final estado = await alcanzable();
    if (vivo && estado != ultimo) {
      await Future<void>.delayed(_debounceCambio);
      if (!vivo) break;
      if (await alcanzable() == estado) {
        ultimo = estado;
        yield estado;
      }
    }
    if (!vivo) break;
    await Future<void>.delayed(ultimo ? _intervaloConRed : _intervaloSinRed);
  }
});
