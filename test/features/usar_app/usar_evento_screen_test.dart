import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:transworld_nexus/core/constants/app_role.dart';
import 'package:transworld_nexus/core/network/connectivity_service.dart';
import 'package:transworld_nexus/core/router/page_transitions.dart';
import 'package:transworld_nexus/core/router/route_paths.dart';
import 'package:transworld_nexus/core/utils/registro_asistente.dart';
import 'package:transworld_nexus/core/widgets/app_widgets.dart';
import 'package:transworld_nexus/core/widgets/tw_toast.dart';
import 'package:transworld_nexus/data/models/evento.dart';
import 'package:transworld_nexus/data/models/perfil.dart';
import 'package:transworld_nexus/data/offline/sync_queue_service.dart';
import 'package:transworld_nexus/features/auth/providers/auth_providers.dart';
import 'package:transworld_nexus/features/capturador/providers/capturador_providers.dart';
import 'package:transworld_nexus/features/eventos/providers/eventos_providers.dart';
import 'package:transworld_nexus/features/registrados/providers/registrados_providers.dart';
import 'package:transworld_nexus/features/usar_app/screens/usar_evento_screen.dart';

void main() {
  final evento = Evento(
    id: 'evento-1',
    nombre: 'Evento de prueba',
    fecha: DateTime(2099, 8, 20),
    lugar: 'Santiago',
  );
  const perfil = Perfil(
    id: 'admin-1',
    nombreCompleto: 'Admin Demo',
    rol: AppRole.admin,
  );

  late SharedPreferences preferences;

  setUpAll(() async {
    await initializeDateFormatting('es');
    SharedPreferences.setMockInitialValues(const {});
    preferences = await SharedPreferences.getInstance();
  });

  testWidgets('al recargar el evento el menú de acciones sigue montado', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    var bloquearRecarga = false;
    final recarga = Completer<Evento>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          connectivityStreamProvider.overrideWith((ref) => Stream.value(true)),
          authStateChangesProvider.overrideWith(
            (ref) => const Stream<AuthState>.empty(),
          ),
          currentPerfilProvider.overrideWith((ref) async => perfil),
          registradosPorEventoProvider.overrideWith((ref, id) async => []),
          registradosResumenProvider.overrideWith(
            (ref, id) => const RegistradosResumen(
              total: 0,
              acreditados: 0,
              pendientes: 0,
            ),
          ),
          eventoByIdProvider.overrideWith((ref, id) async {
            if (bloquearRecarga) await recarga.future;
            return evento;
          }),
        ],
        child: const MaterialApp(
          locale: Locale('es'),
          home: UsarEventoScreen(eventoId: 'evento-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lista de asistentes registrados'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    bloquearRecarga = true;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(UsarEventoScreen)),
    );
    container.invalidate(eventoByIdProvider('evento-1'));
    await tester.pump();

    expect(find.text('Lista de asistentes registrados'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    recarga.complete(evento);
    await tester.pumpAndSettle();
    expect(find.text('Lista de asistentes registrados'), findsOneWidget);
  });

  testWidgets('el back nativo Android sale del evento real a la primera', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = previousPlatform);

    final router = GoRouter(
      initialLocation: RoutePaths.eventos,
      routes: [
        GoRoute(
          path: RoutePaths.eventos,
          builder: (_, _) => const Scaffold(body: Text('lista-eventos')),
        ),
        GoRoute(
          path: '/eventos/:id/usar',
          pageBuilder: (_, state) => sharedAxisPage(
            key: state.pageKey,
            child: UsarEventoScreen(eventoId: state.pathParameters['id']!),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          connectivityStreamProvider.overrideWith((ref) => Stream.value(true)),
          authStateChangesProvider.overrideWith(
            (ref) => const Stream<AuthState>.empty(),
          ),
          currentPerfilProvider.overrideWith((ref) async => perfil),
          registradosPorEventoProvider.overrideWith((ref, id) async => []),
          registradosResumenProvider.overrideWith(
            (ref, id) => const RegistradosResumen(
              total: 0,
              acreditados: 0,
              pendientes: 0,
            ),
          ),
          eventoByIdProvider.overrideWith((ref, id) async => evento),
          eventoLeadInternoProvider.overrideWith((ref, id) async => null),
        ],
        child: MaterialApp.router(
          locale: const Locale('es'),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    router.push(RoutePaths.usarEvento(evento.id));
    await tester.pumpAndSettle();

    expect(find.text('Evento de prueba'), findsWidgets);
    expect(find.byType(BackButtonListener), findsOneWidget);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();

    expect(find.text('lista-eventos'), findsOneWidget);
    expect(find.text('Evento de prueba'), findsNothing);

    debugDefaultTargetPlatformOverride = previousPlatform;
  });

  testWidgets(
    'el tile de la lista se reactiva al volver sin pop (atrás del navegador)',
    (tester) async {
      final router = GoRouter(
        initialLocation: RoutePaths.usarEvento('evento-1'),
        routes: [
          GoRoute(
            path: '/eventos/:id/usar',
            pageBuilder: (_, state) => sharedAxisPage(
              key: state.pageKey,
              child: UsarEventoScreen(eventoId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/eventos/:id/registrados',
            pageBuilder: (_, state) => sharedAxisPage(
              key: state.pageKey,
              child: const Scaffold(body: Text('registrados')),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            connectivityStreamProvider.overrideWith(
              (ref) => Stream.value(true),
            ),
            authStateChangesProvider.overrideWith(
              (ref) => const Stream<AuthState>.empty(),
            ),
            currentPerfilProvider.overrideWith((ref) async => perfil),
            registradosPorEventoProvider.overrideWith((ref, id) async => []),
            registradosResumenProvider.overrideWith(
              (ref, id) => const RegistradosResumen(
                total: 0,
                acreditados: 0,
                pendientes: 0,
              ),
            ),
            eventoByIdProvider.overrideWith((ref, id) async => evento),
            eventoLeadInternoProvider.overrideWith((ref, id) async => null),
          ],
          child: MaterialApp.router(
            locale: const Locale('es'),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lista de asistentes registrados'));
      await tester.pumpAndSettle();
      expect(find.text('registrados'), findsOneWidget);

      // El atrás del navegador saca la ruta de la pila sin pasar por `pop`:
      // el futuro de `context.push` queda huérfano y el spinner del tile no
      // se apagaba nunca, dejándolo además sin `onTap`.
      router.go(RoutePaths.usarEvento('evento-1'));
      await tester.pumpAndSettle();

      expect(find.text('Lista de asistentes registrados'), findsOneWidget);
      await tester.tap(find.text('Lista de asistentes registrados'));
      await tester.pumpAndSettle();

      expect(
        find.text('registrados'),
        findsOneWidget,
        reason: 'el tile quedó girando y sin onTap tras volver sin pop',
      );
    },
  );

  testWidgets(
    'un evento fuera de vigencia avisa al intentar registrar',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(TwToast.hide);

      final ayer = DateTime.now().subtract(const Duration(days: 1));
      final finalizado = Evento(
        id: 'evento-1',
        nombre: 'Evento cerrado',
        fecha: DateTime(ayer.year, ayer.month, ayer.day),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            connectivityStreamProvider.overrideWith(
              (ref) => Stream.value(true),
            ),
            authStateChangesProvider.overrideWith(
              (ref) => const Stream<AuthState>.empty(),
            ),
            currentPerfilProvider.overrideWith((ref) async => perfil),
            registradosPorEventoProvider.overrideWith((ref, id) async => []),
            registradosResumenProvider.overrideWith(
              (ref, id) => const RegistradosResumen(
                total: 0,
                acreditados: 0,
                pendientes: 0,
              ),
            ),
            eventoByIdProvider.overrideWith((ref, id) async => finalizado),
            eventoLeadInternoProvider.overrideWith((ref, id) async => null),
          ],
          child: const MaterialApp(
            locale: Locale('es'),
            home: UsarEventoScreen(eventoId: 'evento-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Registrar asistente'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      expect(find.text(kMensajeEventoFinalizado), findsOneWidget);
    },
  );
}
