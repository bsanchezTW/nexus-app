import 'package:dio/dio.dart';

import '../config/env.dart';
import 'politica_conexion.dart';
import 'sondeo_internet.dart';

final _dioSondeo = Dio(
  BaseOptions(
    connectTimeout: PoliticaConexion.esperaSondeo,
    receiveTimeout: PoliticaConexion.esperaSondeo,
  ),
);

/// Un sondeo al backend de Supabase, con su latencia.
///
/// Cuenta como respuesta cualquier código menor a 500, incluido un 401: lo
/// que se comprueba es que el tráfico llega al backend y vuelve, no que la
/// petición esté autorizada. La URL es HTTPS, así que un portal cautivo no
/// puede contestar en su nombre: el TLS falla y cuenta como sin respuesta.
///
/// Si el backend no contesta, pregunta a servicios neutrales ([hayInternet])
/// para separar "no hay Internet" de "hay Internet y la base de datos no
/// responde". Un 5xx ya prueba que hay Internet: es el backend el que falla.
///
/// Usa su propio cliente, fuera del de Supabase, para que un sondeo fallido no
/// se reporte además como fallo de una petición real.
Future<LecturaSondeo> sondearBackend() async {
  final reloj = Stopwatch()..start();
  try {
    final respuesta = await _dioSondeo
        .getUri(
          Uri.parse('${Env.supabaseUrl}/auth/v1/health'),
          options: Options(
            headers: {'apikey': Env.supabasePublishableKey},
            responseType: ResponseType.plain,
            validateStatus: (_) => true,
          ),
        )
        .timeout(PoliticaConexion.esperaSondeo);
    final estado = respuesta.statusCode;
    if (estado != null && estado >= 500) {
      return const LecturaSondeo.backendCaido();
    }
    if (estado != null) return LecturaSondeo.respondio(reloj.elapsed);
  } catch (_) {
    // Sin respuesta: se averigua abajo si es Internet o el backend.
  }
  return await hayInternet()
      ? const LecturaSondeo.backendCaido()
      : const LecturaSondeo.sinRespuesta();
}
