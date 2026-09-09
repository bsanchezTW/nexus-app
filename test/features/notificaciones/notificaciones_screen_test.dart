import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:transworld_nexus/core/network/connectivity_service.dart';
import 'package:transworld_nexus/data/models/notificacion.dart';
import 'package:transworld_nexus/data/offline/sync_queue_service.dart';
import 'package:transworld_nexus/data/repositories/notificaciones_repository.dart';
import 'package:transworld_nexus/features/notificaciones/providers/notificaciones_providers.dart';
import 'package:transworld_nexus/features/notificaciones/screens/notificaciones_screen.dart';

class FakeNotificacionesRepository extends NotificacionesRepository {
  FakeNotificacionesRepository({this.fakeList = const []})
    : super(
        SupabaseClient(
          'http://localhost',
          'fake-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final List<NotificacionInbox> fakeList;
  List<String>? ultimasOcultadas;
  var ocultarTodasLlamado = false;

  @override
  Future<List<NotificacionInbox>> listar({int limite = 100}) async => fakeList;

  @override
  Future<void> marcarTodasLeidas(List<String> notificacionIds) async {}

  @override
  Future<void> ocultarNotificaciones(List<String> notificacionIds) async {
    ultimasOcultadas = notificacionIds;
  }

  @override
  Future<void> ocultarTodasNotificaciones() async {
    ocultarTodasLlamado = true;
  }
}

NotificacionInbox _notificacion({
  required String id,
  required String cuerpo,
  bool leida = true,
}) {
  return NotificacionInbox(
    id: id,
    tipo: TipoNotificacion.registro,
    titulo: 'Nuevo registro',
    cuerpo: cuerpo,
    nombreRegistrado: 'Demo',
    nombreEvento: 'Evento demo',
    createdAt: DateTime(2026, 8, 4, 12),
    leida: leida,
  );
}

Future<void> _montar(
  WidgetTester tester, {
  required FakeNotificacionesRepository repo,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  final router = GoRouter(
    initialLocation: '/notificaciones',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const SizedBox.shrink(),
        routes: [
          GoRoute(
            path: 'notificaciones',
            builder: (_, _) => const NotificacionesScreen(),
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
        notificacionesRepositoryProvider.overrideWithValue(repo),
        notificacionesInboxProvider.overrideWith((ref) async => repo.fakeList),
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
  setUpAll(() async {
    await initializeDateFormatting('es', null);
  });

  testWidgets('muestra botón eliminar cuando hay notificaciones', (
    tester,
  ) async {
    final repo = FakeNotificacionesRepository(
      fakeList: [_notificacion(id: '1', cuerpo: 'Ana se registró a Summit')],
    );

    await _montar(tester, repo: repo);

    expect(find.byIcon(Symbols.delete_outline_rounded), findsOneWidget);
  });

  testWidgets('sin selección confirma eliminar todas', (tester) async {
    final repo = FakeNotificacionesRepository(
      fakeList: [
        _notificacion(id: '1', cuerpo: 'Ana se registró a Summit'),
        _notificacion(id: '2', cuerpo: 'Luis se registró a Expo'),
      ],
    );

    await _montar(tester, repo: repo);

    await tester.tap(find.byIcon(Symbols.delete_outline_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Eliminar todas'), findsOneWidget);
    expect(
      find.text('¿Deseas eliminar todas las notificaciones?'),
      findsOneWidget,
    );

    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();

    expect(repo.ocultarTodasLlamado, isTrue);
    expect(repo.ultimasOcultadas, isNull);
  });

  testWidgets('pulsación larga activa selección y tap alterna filas', (
    tester,
  ) async {
    final repo = FakeNotificacionesRepository(
      fakeList: [
        _notificacion(id: '1', cuerpo: 'Ana se registró a Summit'),
        _notificacion(id: '2', cuerpo: 'Luis se registró a Expo'),
      ],
    );

    await _montar(tester, repo: repo);
    final textoAntes = tester
        .getTopLeft(find.text('Ana se registró a Summit'))
        .dx;

    await tester.longPress(find.text('Ana se registró a Summit'));
    await tester.pumpAndSettle();

    expect(find.text('1 seleccionada(s)'), findsOneWidget);
    expect(find.byIcon(Symbols.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Symbols.radio_button_unchecked_rounded), findsOneWidget);
    expect(find.byIcon(Symbols.person_add_rounded), findsNothing);
    expect(
      tester.getTopLeft(find.text('Ana se registró a Summit')).dx,
      textoAntes,
    );

    await tester.tap(find.text('Luis se registró a Expo'));
    await tester.pumpAndSettle();

    expect(find.text('2 seleccionada(s)'), findsOneWidget);

    await tester.tap(find.text('Ana se registró a Summit'));
    await tester.pumpAndSettle();

    expect(find.text('1 seleccionada(s)'), findsOneWidget);
  });

  testWidgets('con selección confirma eliminar solo las seleccionadas', (
    tester,
  ) async {
    final repo = FakeNotificacionesRepository(
      fakeList: [
        _notificacion(id: '1', cuerpo: 'Ana se registró a Summit'),
        _notificacion(id: '2', cuerpo: 'Luis se registró a Expo'),
      ],
    );

    await _montar(tester, repo: repo);

    await tester.longPress(find.text('Ana se registró a Summit'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Symbols.delete_outline_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Eliminar seleccionadas'), findsOneWidget);
    expect(
      find.text('¿Deseas eliminar 1 notificación(es) seleccionada(s)?'),
      findsOneWidget,
    );

    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();

    expect(repo.ultimasOcultadas, ['1']);
    expect(repo.ocultarTodasLlamado, isFalse);
  });

  testWidgets('al deseleccionar la última fila vuelve al título normal', (
    tester,
  ) async {
    final repo = FakeNotificacionesRepository(
      fakeList: [_notificacion(id: '1', cuerpo: 'Ana se registró a Summit')],
    );

    await _montar(tester, repo: repo);

    await tester.longPress(find.text('Ana se registró a Summit'));
    await tester.pumpAndSettle();
    expect(find.text('1 seleccionada(s)'), findsOneWidget);

    await tester.tap(find.text('Ana se registró a Summit'));
    await tester.pumpAndSettle();

    expect(find.text('Notificaciones'), findsOneWidget);
    expect(find.text('1 seleccionada(s)'), findsNothing);
  });

  testWidgets('deslizar a la izquierda descarta la notificación', (
    tester,
  ) async {
    final repo = FakeNotificacionesRepository(
      fakeList: [
        _notificacion(id: '1', cuerpo: 'Ana se registró a Summit'),
        _notificacion(id: '2', cuerpo: 'Luis se registró a Expo'),
      ],
    );

    await _montar(tester, repo: repo);

    expect(find.byType(Dismissible), findsNWidgets(2));

    await tester.drag(
      find.text('Ana se registró a Summit'),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ana se registró a Summit'), findsNothing);
    expect(find.text('Luis se registró a Expo'), findsOneWidget);
    expect(repo.ultimasOcultadas, ['1']);
    expect(repo.ocultarTodasLlamado, isFalse);
  });

  testWidgets('deslizar a la derecha descarta la notificación', (tester) async {
    final repo = FakeNotificacionesRepository(
      fakeList: [
        _notificacion(id: '1', cuerpo: 'Ana se registró a Summit'),
        _notificacion(id: '2', cuerpo: 'Luis se registró a Expo'),
      ],
    );

    await _montar(tester, repo: repo);

    await tester.drag(
      find.text('Luis se registró a Expo'),
      const Offset(500, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('Luis se registró a Expo'), findsNothing);
    expect(find.text('Ana se registró a Summit'), findsOneWidget);
    expect(repo.ultimasOcultadas, ['2']);
  });
}
