import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/env.dart';
import '../constants/supabase_tables.dart';
import 'politica_conexion.dart';
import 'sondeo_internet.dart';

final _dioSondeo = Dio(
  BaseOptions(
    connectTimeout: PoliticaConexion.esperaSondeo,
    receiveTimeout: PoliticaConexion.esperaSondeo,
  ),
);

/// `false` cuando la base todavía no tiene `rpe_ping()` (migración
/// 202610281200 sin aplicar). Desde ahí se sondea `/auth/v1/health` hasta que
/// la app se reinicie, para no pagar dos peticiones en cada sondeo.
bool _pingDisponible = true;

/// Un sondeo al backend de Supabase, con su latencia.
///
/// Llama a `rpe_ping()`, que recorre el mismo camino que los datos reales
/// (gateway → PostgREST → Postgres) sin leer tablas: si Postgres no responde,
/// PostgREST devuelve 503 y cuenta como base de datos caída. Si la función no
/// existe, cae a `/auth/v1/health`, que solo prueba el servicio de
/// autenticación.
///
/// Si el backend no contesta, pregunta a servicios neutrales ([hayInternet])
/// para separar "no hay Internet" de "hay Internet y la base de datos no
/// responde".
///
/// La URL es HTTPS, así que un portal cautivo no puede contestar en su
/// nombre: el TLS falla y cuenta como sin respuesta. Usa su propio cliente,
/// fuera del de Supabase, para que un sondeo fallido no se reporte además
/// como fallo de una petición real.
Future<LecturaSondeo> sondearBackend() async {
  final reloj = Stopwatch()..start();
  int? estado;
  if (_pingDisponible) {
    estado = await _estadoDe(_pedirPing);
    if (estado == 404) {
      _pingDisponible = false;
      reloj.reset();
    }
  }
  if (!_pingDisponible) estado = await _estadoDe(_pedirHealth);

  final lectura = interpretarRespuestaBackend(estado, reloj.elapsed);
  if (lectura != null) return lectura;
  return await hayInternet()
      ? const LecturaSondeo.backendCaido()
      : const LecturaSondeo.sinRespuesta();
}

/// Qué dice el código de estado de un sondeo. `null` si no hubo respuesta y
/// hay que averiguar si es Internet o el backend.
///
/// Cualquier código menor a 500 cuenta como respuesta, incluido un 401: lo
/// que se comprueba es que el tráfico llega y vuelve, no que la petición esté
/// autorizada. Un 5xx prueba que hay Internet y que falla el servidor.
@visibleForTesting
LecturaSondeo? interpretarRespuestaBackend(int? estado, Duration latencia) {
  if (estado == null) return null;
  if (estado >= 500) return const LecturaSondeo.backendCaido();
  return LecturaSondeo.respondio(latencia);
}

Future<int?> _estadoDe(Future<Response<String>> Function() pedir) async {
  try {
    final respuesta = await pedir().timeout(PoliticaConexion.esperaSondeo);
    return respuesta.statusCode;
  } catch (_) {
    return null;
  }
}

Options get _opciones => Options(
  headers: {'apikey': Env.supabasePublishableKey},
  responseType: ResponseType.plain,
  validateStatus: (_) => true,
);

Future<Response<String>> _pedirPing() => _dioSondeo.postUri<String>(
  Uri.parse('${Env.supabaseUrl}/rest/v1/rpc/${SupabaseRpc.ping}'),
  data: const <String, Object>{},
  options: _opciones..contentType = Headers.jsonContentType,
);

Future<Response<String>> _pedirHealth() => _dioSondeo.getUri<String>(
  Uri.parse('${Env.supabaseUrl}/auth/v1/health'),
  options: _opciones,
);
