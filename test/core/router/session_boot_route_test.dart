import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/core/router/route_paths.dart';
import 'package:transworld_nexus/core/router/session_boot_route.dart';

void main() {
  String? hold({
    required String location,
    bool esPublica = false,
    bool perfilFallido = false,
  }) {
    return rutaMientrasCargaPerfil(
      location: location,
      esPublica: esPublica,
      perfilFallido: perfilFallido,
    );
  }

  test('con perfil fallido siempre vuelve a login', () {
    expect(
      hold(location: RoutePaths.home, perfilFallido: true),
      RoutePaths.login,
    );
    expect(
      hold(location: RoutePaths.splash, perfilFallido: true),
      RoutePaths.login,
    );
    expect(
      hold(location: RoutePaths.login, esPublica: true, perfilFallido: true),
      RoutePaths.login,
    );
  });

  test('en splash o login se queda esperando, sin abrir el formulario', () {
    expect(hold(location: RoutePaths.splash), isNull);
    expect(hold(location: RoutePaths.login, esPublica: true), isNull);
  });

  test('en ruta protegida espera en splash, no en login', () {
    expect(hold(location: RoutePaths.home), RoutePaths.splash);
    expect(hold(location: RoutePaths.eventos), RoutePaths.splash);
  });

  test('en otras rutas públicas no interrumpe', () {
    expect(
      hold(location: RoutePaths.recuperarPassword, esPublica: true),
      isNull,
    );
    expect(hold(location: RoutePaths.eventoFinalizado, esPublica: true), isNull);
  });
}
