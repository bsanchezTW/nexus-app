import 'package:dio/dio.dart';

import 'politica_conexion.dart';

final _dio = Dio(
  BaseOptions(
    connectTimeout: PoliticaConexion.esperaSondeo,
    receiveTimeout: PoliticaConexion.esperaSondeo,
  ),
);

/// `true` si [url] devuelve cualquier respuesta HTTP.
Future<bool> responde(Uri url) async {
  try {
    final respuesta = await _dio.getUri(
      url,
      options: Options(
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    return respuesta.statusCode != null;
  } catch (_) {
    return false;
  }
}
