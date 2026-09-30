import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transworld_nexus/core/widgets/form_sections.dart';
import 'package:transworld_nexus/core/constants/app_role.dart';
import 'package:transworld_nexus/core/network/connectivity_service.dart';
import 'package:transworld_nexus/core/router/refresh_on_visible.dart';
import 'package:transworld_nexus/core/router/route_paths.dart';
import 'package:transworld_nexus/data/models/ocupacion_evento.dart';
import 'package:transworld_nexus/data/models/evento.dart';
import 'package:transworld_nexus/data/models/perfil.dart';
import 'package:transworld_nexus/data/models/registrado.dart';
import 'package:transworld_nexus/data/offline/offline_read_cache.dart';
import 'package:transworld_nexus/data/offline/sync_queue_service.dart';
import 'package:transworld_nexus/data/repositories/registrados_repository.dart';
import 'package:transworld_nexus/features/auth/providers/auth_providers.dart';
import 'package:transworld_nexus/features/eventos/providers/eventos_providers.dart';
import 'package:transworld_nexus/features/subeventos/providers/inscripciones_providers.dart';
import 'package:transworld_nexus/features/subeventos/providers/subeventos_providers.dart';
import 'package:transworld_nexus/features/registrados/screens/editar_registrado_screen.dart';
import 'package:transworld_nexus/features/registrados/screens/ver_registrados_screen.dart';

class _FakeRegistradosRepository extends Fake implements RegistradosRepository {
  _FakeRegistradosRepository(this.registrado);

  Registrado registrado;

  @override
  Future<List<Registrado>> listarPorEvento(String eventoId) async => [
    registrado,
  ];

  @override
  Future<void> actualizar(String id, Map<String, dynamic> changes) async {
    registrado = registrado
        .conCambiosPendientes(changes)
        .copyWith(pendienteDeSincronizar: false);
  }
}

void main() {
  testWidgets('al guardar un registrado la lista muestra el cambio al volver', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cache = OfflineReadCache(prefs, ownerId: 'admin-1');
    const eventoId = 'evento-1';
    const original = Registrado(
      id: 'registrado-1',
      eventoId: eventoId,
      nombreCompleto: 'Nombre anterior',
      email: 'persona@empresa.cl',
      telefono: '+56912345678',
    );
    await cache.guardar('registrados', eventoId, [original.toCacheMap()]);
    final repo = _FakeRegistradosRepository(original);

    final router = GoRouter(
      initialLocation: RoutePaths.verRegistrados(eventoId),
      routes: [
        GoRoute(
          path: '/eventos/:id/registrados',
          builder: (_, _) => const VerRegistradosScreen(eventoId: eventoId),
        ),
        GoRoute(
          path: '/eventos/:eventoId/registrados/:registradoId/editar',
          builder: (_, _) => const EditarRegistradoScreen(
            eventoId: eventoId,
            registradoId: 'registrado-1',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          offlineReadCacheProvider.overrideWithValue(cache),
          syncQueueActiveOwnerIdProvider.overrideWithValue('admin-1'),
          isOnlineProvider.overrideWith((ref) => true),
          currentPerfilProvider.overrideWith(
            (ref) async => const Perfil(
              id: 'admin-1',
              nombreCompleto: 'Admin',
              rol: AppRole.admin,
            ),
          ),
          eventoByIdProvider.overrideWith(
            (ref, id) async => Evento(
              id: id,
              nombre: 'Evento',
              fecha: DateTime(2030),
              pais: 'Chile',
            ),
          ),
          registradosRepositoryProvider.overrideWithValue(repo),
          subeventosPorEventoProvider.overrideWith((ref, id) async => const []),
          ocupacionEventoProvider.overrideWith(
            (ref, id) async => const OcupacionEvento(
              evento: OcupacionItem(cupoMaximo: null, inscritos: 0, asistentes: 0),
              subeventos: {},
            ),
          ),
          inscripcionesPorEventoProvider.overrideWith((ref, id) async => const []),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nombre anterior'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'Nombre actualizado',
    );
    await tester.ensureVisible(find.byType(FormActionBar));
    await tester.pumpAndSettle();
    final guardar = tester.widget<FormActionBar>(
      find.byType(FormActionBar),
    );
    expect(guardar.onPressed, isNotNull);
    guardar.onPressed!();
    await tester.pumpAndSettle();

    expect(repo.registrado.nombreCompleto, 'Nombre actualizado');
    expect(locationOfRouter(router), RoutePaths.verRegistrados(eventoId));
    expect(find.byType(VerRegistradosScreen), findsOneWidget);
    expect(find.text('Nombre actualizado'), findsOneWidget);
    expect(find.text('Nombre anterior'), findsNothing);
  });
}
