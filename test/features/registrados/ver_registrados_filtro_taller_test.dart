import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:transworld_nexus/core/constants/app_role.dart';
import 'package:transworld_nexus/core/network/connectivity_service.dart';
import 'package:transworld_nexus/core/router/route_paths.dart';
import 'package:transworld_nexus/data/models/inscripcion_subevento.dart';
import 'package:transworld_nexus/data/models/perfil.dart';
import 'package:transworld_nexus/data/models/registrado.dart';
import 'package:transworld_nexus/data/models/subevento.dart';
import 'package:transworld_nexus/data/offline/sync_queue_service.dart';
import 'package:transworld_nexus/features/auth/providers/auth_providers.dart';
import 'package:transworld_nexus/features/registrados/providers/registrados_providers.dart';
import 'package:transworld_nexus/features/registrados/screens/ver_registrados_screen.dart';
import 'package:transworld_nexus/features/subeventos/providers/inscripciones_providers.dart';
import 'package:transworld_nexus/features/subeventos/providers/subeventos_providers.dart';

void main() {
  testWidgets('filtrar por taller muestra solo al inscrito', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const eventoId = 'evento-1';
    const ana = Registrado(
      id: 'ana',
      eventoId: eventoId,
      nombreCompleto: 'Ana Pérez',
      email: 'ana@empresa.cl',
    );
    const luis = Registrado(
      id: 'luis',
      eventoId: eventoId,
      nombreCompleto: 'Luis Soto',
      email: 'luis@empresa.cl',
    );
    final manana = DateTime.now().add(const Duration(days: 3));
    final taller = Subevento(
      id: 'taller-1',
      eventoId: eventoId,
      codigo: 'a7k2mq',
      nombre: 'Taller IA',
      dia: DateTime(manana.year, manana.month, manana.day),
      horaInicio: const TimeOfDay(hour: 10, minute: 0),
      horaFin: const TimeOfDay(hour: 11, minute: 0),
    );
    const inscripcion = InscripcionSubevento(
      id: 'ins-1',
      eventoId: eventoId,
      registradoId: 'ana',
      subeventoId: 'taller-1',
      origen: 'app',
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
    addTearDown(router.dispose);

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
          registradosPorEventoProvider.overrideWith(
            (ref, id) async => const [ana, luis],
          ),
          subeventosPorEventoProvider.overrideWith((ref, id) async => [taller]),
          inscripcionesPorEventoProvider.overrideWith((ref, id) async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return const [inscripcion];
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.text('Luis Soto'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ActionChip, 'Taller IA'));
    await tester.tap(find.widgetWithText(ActionChip, 'Taller IA'));
    await tester.pumpAndSettle();

    expect(find.text('Ana Pérez'), findsOneWidget);
    expect(find.text('Luis Soto'), findsNothing);
  });
}
