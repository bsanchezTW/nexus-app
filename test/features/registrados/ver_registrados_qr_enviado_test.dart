import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:transworld_nexus/core/constants/app_role.dart';
import 'package:transworld_nexus/core/network/connectivity_service.dart';
import 'package:transworld_nexus/core/router/route_paths.dart';
import 'package:transworld_nexus/data/models/evento.dart';
import 'package:transworld_nexus/data/models/perfil.dart';
import 'package:transworld_nexus/data/models/registrado.dart';
import 'package:transworld_nexus/data/offline/sync_queue_service.dart';
import 'package:transworld_nexus/features/auth/providers/auth_providers.dart';
import 'package:transworld_nexus/features/eventos/providers/eventos_providers.dart';
import 'package:transworld_nexus/features/registrados/providers/registrados_providers.dart';
import 'package:transworld_nexus/features/registrados/screens/ver_registrados_screen.dart';
import 'package:transworld_nexus/features/subeventos/providers/inscripciones_providers.dart';
import 'package:transworld_nexus/features/subeventos/providers/subeventos_providers.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  testWidgets(
    'QR enviado: ícono en la misma línea del estado, sin agrandar la tarjeta',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const eventoId = 'evento-1';
      const maria = Registrado(
        id: 'maria',
        eventoId: eventoId,
        nombreCompleto: 'Maria Castro',
        email: 'maria@empresa.cl',
        acreditado: true,
        emailConfirmacionEnviado: true,
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
            connectivityStreamProvider.overrideWith(
              (ref) => Stream.value(true),
            ),
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
            eventoByIdProvider.overrideWith(
              (ref, id) async => Evento(
                id: id,
                nombre: 'Evento',
                fecha: DateTime(2030),
                pais: 'Chile',
              ),
            ),
            registradosPorEventoProvider.overrideWith(
              (ref, id) async => const [maria],
            ),
            subeventosPorEventoProvider.overrideWith(
              (ref, id) async => const [],
            ),
            inscripcionesPorEventoProvider.overrideWith(
              (ref, id) async => const [],
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // En la tarjeta el envío es solo un ícono junto al estado, sin texto
      // que la haga crecer.
      expect(find.byKey(const Key('chip_qr_enviado')), findsOneWidget);
      expect(find.text('QR enviado'), findsNothing);
      final estado = tester.getCenter(find.text('Acreditado'));
      final chip = tester.getCenter(find.byKey(const Key('chip_qr_enviado')));
      expect(chip.dy, moreOrLessEquals(estado.dy, epsilon: 1));
    },
  );
}
