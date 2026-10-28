import 'politica_conexion.dart';
import 'sondeo_internet_io.dart'
    if (dart.library.js_interop) 'sondeo_internet_web.dart'
    as impl;

/// Servicios neutrales que solo sirven para saber si hay salida a Internet.
///
/// Son dos de proveedores distintos: basta con que conteste uno. Se usan solo
/// cuando Supabase no respondió, para distinguir "no hay Internet" de "hay
/// Internet pero la base de datos no responde".
const urlsSondeoInternet = [
  'https://www.gstatic.com/generate_204',
  'https://cloudflare.com/cdn-cgi/trace',
];

/// `true` si alguno de [urlsSondeoInternet] contesta dentro del tope.
Future<bool> hayInternet() async {
  final intentos = [
    for (final url in urlsSondeoInternet)
      impl
          .responde(Uri.parse(url))
          .timeout(PoliticaConexion.esperaSondeo, onTimeout: () => false)
          .catchError((Object _) => false),
  ];
  // Corren en paralelo: basta con que uno diga que sí.
  for (final intento in intentos) {
    if (await intento) return true;
  }
  return false;
}
