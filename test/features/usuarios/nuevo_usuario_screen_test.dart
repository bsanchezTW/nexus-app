import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:transworld_nexus/core/constants/app_role.dart';
import 'package:transworld_nexus/core/network/connectivity_service.dart';
import 'package:transworld_nexus/core/router/route_paths.dart';
import 'package:transworld_nexus/data/models/evento.dart';
import 'package:transworld_nexus/data/models/perfil.dart';
import 'package:transworld_nexus/data/offline/sync_queue_service.dart';
import 'package:transworld_nexus/data/repositories/auth_repository.dart';
import 'package:transworld_nexus/features/auth/providers/auth_providers.dart';
import 'package:transworld_nexus/features/eventos/providers/eventos_providers.dart';
import 'package:transworld_nexus/features/usuarios/screens/nuevo_usuario_screen.dart';

class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository()
    : super(
        SupabaseClient(
          'http://localhost',
          'fake-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  @override
  Future<bool> verificarEmailRegistrado(String email) async => false;

  @override
  Future<CrearUsuarioResultado> crearUsuario({
    required String nombreCompleto,
    required String email,
    required String password,
    required String rol,
    String? eventoId,
    List<String>? eventoIds,
  }) async {
    return CrearUsuarioResultado(
      userId: 'nuevo-1',
      email: email,
      password: password,
      rol: rol,
    );
  }

  @override
  Future<List<Perfil>> obtenerTodosLosUsuarios() async => const [];
}

void main() {
  testWidgets('guardar un usuario nuevo vuelve a la lista', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final router = GoRouter(
      initialLocation: RoutePaths.nuevoUsuario,
      routes: [
        GoRoute(
          path: RoutePaths.usuarios,
          builder: (_, _) => const Scaffold(body: Text('lista-usuarios')),
        ),
        GoRoute(
          path: RoutePaths.nuevoUsuario,
          builder: (_, _) => const NuevoUsuarioScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          connectivityStreamProvider.overrideWith((ref) => Stream.value(true)),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          currentPerfilProvider.overrideWith(
            (ref) async => const Perfil(
              id: 'admin-1',
              nombreCompleto: 'Admin Demo',
              rol: AppRole.admin,
            ),
          ),
          eventosListProvider.overrideWith((ref) async => const <Evento>[]),
        ],
        child: MaterialApp.router(
          locale: const Locale('es'),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Nuevo Usuario');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'nuevo@transworld.cl',
    );

    await tester.ensureVisible(find.text('Administrador'));
    await tester.tap(find.text('Administrador'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Crear usuario'));
    await tester.pumpAndSettle();

    expect(find.text('lista-usuarios'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, RoutePaths.usuarios);
  });
}
