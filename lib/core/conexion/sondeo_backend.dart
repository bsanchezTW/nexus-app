import 'package:dio/dio.dart';

import '../config/env.dart';
import 'politica_conexion.dart';

final _dioSondeo = Dio(
  BaseOptions(
    connectTimeout: PoliticaConexion.esperaSondeo,
    receiveTimeout: PoliticaConexion.esperaSondeo,
  ),
);

/// Un sondeo al backend de Supabase, con su latencia.
///
/// Cuenta cualquier código de estado, incluido un 401: lo que se comprueba es
/// que el tráfico llega al backend y vuelve, no que la petición esté
/// autorizada. La URL es HTTPS, así que un portal cautivo no puede contestar
/// en su nombre: el TLS falla y cuenta como sin respuesta.
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
    if (respuesta.statusCode == null) return const LecturaSondeo.sinRespuesta();
    return LecturaSondeo.respondio(reloj.elapsed);
  } catch (_) {
    return const LecturaSondeo.sinRespuesta();
  }
}
