import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transworld_nexus/core/conexion/estado_conexion.dart';
import 'package:transworld_nexus/core/conexion/monitor_conexion.dart';
import 'package:transworld_nexus/core/network/connectivity_service.dart';
import 'package:transworld_nexus/core/network/offline_guard.dart';
import 'package:transworld_nexus/core/widgets/tw_toast.dart';
import 'package:transworld_nexus/data/offline/sync_queue_service.dart';

void main() {
  tearDown(TwToast.hide);

  testWidgets('sin red requireOnline muestra el toast único y corta', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var siguio = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          connectivityStreamProvider.overrideWith((ref) => Stream.value(false)),
          usaServidorProvider.overrideWith((ref) => false),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () {
                  if (!requireOnline(context, ref)) return;
                  siguio = true;
                },
                child: const Text('Escribir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Escribir'));
    await tester.pump();

    expect(find.text(kMensajeSinConexion), findsOneWidget);
    expect(siguio, isFalse);
  });

  testWidgets('con red requireOnline deja seguir', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var siguio = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          connectivityStreamProvider.overrideWith((ref) => Stream.value(true)),
          usaServidorProvider.overrideWith((ref) => true),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () {
                  if (!requireOnline(context, ref)) return;
                  siguio = true;
                },
                child: const Text('Escribir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Escribir'));
    await tester.pump();

    expect(find.text(kMensajeSinConexion), findsNothing);
    expect(siguio, isTrue);
  });

  testWidgets('con la base de datos caída el toast lo dice', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          estadoConexionProvider.overrideWithValue(EstadoConexion.sinBackend),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => requireOnline(context, ref),
                child: const Text('Escribir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Escribir'));
    await tester.pump();

    expect(find.text(kMensajeSinBaseDeDatos), findsOneWidget);
    expect(find.text(kMensajeSinConexion), findsNothing);
  });
}
