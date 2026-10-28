import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `true` si hay alguna interfaz de red encendida (wifi, datos, cable).
///
/// Solo sirve para saber al instante que **no** hay red: una interfaz
/// encendida no prueba que se llegue al backend. Esa respuesta la da
/// `estadoConexionProvider`, que usa esta señal como una de sus entradas.
final connectivityStreamProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();

  bool hayInterfaz(List<ConnectivityResult> results) =>
      results.isNotEmpty && !results.contains(ConnectivityResult.none);

  yield hayInterfaz(await connectivity.checkConnectivity());

  yield* connectivity.onConnectivityChanged.map(hayInterfaz).distinct();
});
