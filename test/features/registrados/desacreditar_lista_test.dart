import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:transworld_nexus/core/constants/app_role.dart';
import 'package:transworld_nexus/core/network/connectivity_service.dart';
import 'package:transworld_nexus/core/router/route_paths.dart';
import 'package:transworld_nexus/data/models/perfil.dart';
import 'package:transworld_nexus/data/models/registrado.dart';
import 'package:transworld_nexus/data/offline/sync_queue_service.dart';
import 'package:transworld_nexus/data/repositories/registrados_repository.dart';
import 'package:transworld_nexus/features/auth/providers/auth_providers.dart';
import 'package:transworld_nexus/features/registrados/providers/registrados_providers.dart';
import 'package:transworld_nexus/features/registrados/screens/ver_registrados_screen.dart';
import 'package:transworld_nexus/features/subeventos/providers/inscripciones_providers.dart';
import 'package:transworld_nexus/features/subeventos/providers/subeventos_providers.dart';

class _FakeRegistradosRepository extends Fake implements RegistradosRepository {
  String? desacreditadoId;

  @override
  Future<void> desacreditar(String id) async {
    desacreditadoId = id;
  }
}

void main() {
  testWidgets('un acreditado pide confirmación para quitar la acreditación', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = _FakeRegistradosRepository();
    const eventoId = 'evento-1';
    const asistente = Registrado(
      id: 'asistente-1',
      eventoId: eventoId,
      nombreCompleto: 'Ana Pérez',
      email: 'ana@empresa.com',
      acreditado: true,
    );

    final router = GoRouter(
      initialLocation: RoutePaths.verRegistrados(eventoId),
      routes: [
        GoRoute(
          path: '/eventos/:id/registrados',
          builder: (_, _) => const VerRegistradosScreen(eventoId: eventoId),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          connectivityStreamProvider.overrideWith((ref) => Stream.value(true)),
          isOnlineProvider.overrideWith((ref) => true),
          syncQueueActiveOwnerIdProvider.overrideWithValue('owner-1'),
          authStateChangesProvider.overrideWith(
            (ref) => const Stream<AuthState>.empty(),
          ),
          currentPerfilProvider.overrideWith(
            (ref) async => const Perfil(
              id: 'admin-1',
              nombreCompleto: 'Admin',
              rol: AppRole.admin,
            ),
          ),
          registradosRepositoryProvider.overrideWithValue(repo),
          registradosPorEventoProvider.overrideWith(
            (ref, id) async => [asistente],
          ),
          subeventosPorEventoProvider.overrideWith((ref, id) async => const []),
          inscripcionesPorEventoProvider.overrideWith((ref, id) async => const []),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('registrado_acreditar_asistente-1')));
    await tester.pumpAndSettle();

    expect(
      find.text('¿Deseas quitar la acreditación de Ana Pérez?'),
      findsOneWidget,
    );
    expect(find.text('Quitar'), findsOneWidget);

    await tester.tap(find.text('Quitar'));
    await tester.pumpAndSettle();

    expect(repo.desacreditadoId, 'asistente-1');
    expect(tester.takeException(), isNull);
  });
}
