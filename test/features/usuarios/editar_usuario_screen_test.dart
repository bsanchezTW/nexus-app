import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
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
import 'package:transworld_nexus/features/usuarios/providers/usuarios_providers.dart';
import 'package:transworld_nexus/features/usuarios/screens/editar_usuario_screen.dart';

class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository({this.sessionUserId, this.eliminarError})
    : super(
        SupabaseClient(
          'http://localhost',
          'fake-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final String? sessionUserId;
  final Object? eliminarError;

  @override
  String? get currentUserId => sessionUserId;

  @override
  String? get emailSesionActual => 'admin@transworld.cl';

  @override
  Future<String?> obtenerEmailUsuario(String usuarioId) async =>
      'usuario@transworld.cl';

  @override
  Future<List<String>> listarEventosAutorizadosUsuario(
    String usuarioId,
  ) async => const [];

  @override
  Future<void> actualizarNombre(String id, String nuevoNombre) async {}

  @override
  Future<void> configurarAccesoUsuario({
    required String usuarioId,
    required String nuevoRol,
    required List<String> eventoIds,
  }) async {}

  @override
  Future<void> establecerActivo(String id, bool activo) async {}

  @override
  Future<List<Perfil>> obtenerTodosLosUsuarios() async => const [];

  @override
  Future<bool> eliminarUsuario(String usuarioId) async {
    if (eliminarError != null) throw eliminarError!;
    return true;
  }
}

const _adminId = 'admin-1';
const _otroId = 'user-2';

const _adminPerfil = Perfil(
  id: _adminId,
  nombreCompleto: 'Admin Demo',
  rol: AppRole.admin,
);

const _otroPerfil = Perfil(
  id: _otroId,
  nombreCompleto: 'Usuario Demo',
  rol: AppRole.organizador,
);

Future<void> _montar(
  WidgetTester tester, {
  required String usuarioId,
  required Perfil editado,
  String? sessionUserId,
  Object? eliminarError,
}) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final repo = FakeAuthRepository(
    sessionUserId: sessionUserId ?? _adminId,
    eliminarError: eliminarError,
  );

  final router = GoRouter(
    initialLocation: '/editar',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const SizedBox.shrink(),
        routes: [
          GoRoute(
            path: 'editar',
            builder: (_, _) => EditarUsuarioScreen(usuarioId: usuarioId),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        connectivityStreamProvider.overrideWith((ref) => Stream.value(true)),
        authRepositoryProvider.overrideWithValue(repo),
        currentPerfilProvider.overrideWith((ref) async => _adminPerfil),
        usuarioPorIdProvider(usuarioId).overrideWith((ref) async => editado),
      ],
      child: MaterialApp.router(
        locale: const Locale('es'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('oculta regenerar contraseña al editar la cuenta propia', (
    tester,
  ) async {
    await _montar(
      tester,
      usuarioId: _adminId,
      editado: _adminPerfil,
      sessionUserId: _adminId,
    );

    expect(
      find.text('Para cambiar tu contraseña usa Mi perfil.'),
      findsOneWidget,
    );
    expect(find.byIcon(Symbols.refresh_rounded), findsNothing);
  });

  testWidgets('muestra regenerar contraseña al editar otro usuario', (
    tester,
  ) async {
    await _montar(
      tester,
      usuarioId: _otroId,
      editado: _otroPerfil,
      sessionUserId: _adminId,
    );

    expect(
      find.text('Para cambiar tu contraseña usa Mi perfil.'),
      findsNothing,
    );
    expect(find.byIcon(Symbols.refresh_rounded), findsOneWidget);
  });

  testWidgets('guardar un usuario vuelve a la lista', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = FakeAuthRepository(sessionUserId: _adminId);

    final router = GoRouter(
      initialLocation: RoutePaths.editarUsuario(_otroId),
      routes: [
        GoRoute(
          path: RoutePaths.usuarios,
          builder: (_, _) => const Scaffold(body: Text('lista-usuarios')),
        ),
        GoRoute(
          path: '/usuarios/:id/editar',
          builder: (_, state) =>
              EditarUsuarioScreen(usuarioId: state.pathParameters['id']!),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          connectivityStreamProvider.overrideWith((ref) => Stream.value(true)),
          authRepositoryProvider.overrideWithValue(repo),
          currentPerfilProvider.overrideWith((ref) async => _adminPerfil),
          usuarioPorIdProvider(
            _otroId,
          ).overrideWith((ref) async => _otroPerfil),
          eventosListProvider.overrideWith((ref) async => const <Evento>[]),
        ],
        child: MaterialApp.router(
          locale: const Locale('es'),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Guardar cambios'));
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    expect(find.text('lista-usuarios'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, RoutePaths.usuarios);
  });

  testWidgets('controla el error al eliminar un usuario con leads', (
    tester,
  ) async {
    await _montar(
      tester,
      usuarioId: _otroId,
      editado: _otroPerfil,
      eliminarError: Exception('foreign key violation: leads_perfil_id_fkey'),
    );

    await tester.tap(find.byTooltip('Eliminar usuario'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();

    expect(find.text('No se puede eliminar este usuario'), findsOneWidget);
    expect(find.textContaining('foreign key'), findsNothing);
  });
}
