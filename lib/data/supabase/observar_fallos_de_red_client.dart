import 'package:http/http.dart';

import '../../core/conexion/senal_fallos_red.dart';
import '../../core/network/connectivity_service.dart';

/// Avisa a `MonitorConexion` cuando una petición a Supabase no llega.
///
/// Envuelve el cliente HTTP del SDK, así que cubre todas las peticiones —
/// lecturas, escrituras, RPC, la cola y el Storage— sin que cada repositorio
/// tenga que acordarse. Solo los fallos de transporte cuentan: un 4xx/5xx es
/// una respuesta, y prueba que la red funciona.
class ObservarFallosDeRedClient extends BaseClient {
  ObservarFallosDeRedClient(this._inner);

  final Client _inner;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    try {
      return await _inner.send(request);
    } catch (error) {
      if (isNetworkTransportError(error)) reportarFalloDeRed();
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}
