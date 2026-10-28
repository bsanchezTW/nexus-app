import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// `true` si [url] contesta.
///
/// En el navegador un servicio ajeno no manda cabeceras CORS, así que una
/// petición normal fallaría aunque haya Internet. Con `no-cors` la respuesta
/// llega opaca —no se puede leer—, pero la promesa solo se rechaza si la red
/// falla, que es justo lo que interesa saber.
Future<bool> responde(Uri url) async {
  try {
    await web.window
        .fetch(
          url.toString().toJS,
          web.RequestInit(mode: 'no-cors', cache: 'no-store'),
        )
        .toDart;
    return true;
  } catch (_) {
    return false;
  }
}
