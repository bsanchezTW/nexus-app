import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/core/widgets/app_widgets.dart';
import 'package:transworld_nexus/core/widgets/espera_bloqueante.dart';

Future<void> _montar(WidgetTester tester, void Function(BuildContext) alTocar) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () => alTocar(context),
                child: const Text('Abrir'),
              ),
              TextButton(onPressed: () {}, child: const Text('Otra cosa')),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('el modal no se cierra hasta que termina y muestra spinner', (
    tester,
  ) async {
    final tarea = Completer<void>();
    bool? resultado;
    await _montar(tester, (context) async {
      resultado = await confirmarYEjecutar(
        context,
        title: 'Eliminar evento',
        message: '¿Seguro?',
        confirmLabel: 'Eliminar',
        destructive: true,
        accion: () => tarea.future,
      );
    });

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pump();

    // Sigue abierto, con spinner en lugar del texto y sin poder cancelar.
    expect(find.text('Eliminar evento'), findsOneWidget);
    expect(find.text('Eliminar'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('confirmar_y_ejecutar')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    final cancelar = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Cancelar'),
    );
    expect(cancelar.onPressed, isNull);
    expect(find.byKey(const Key('espera_bloqueante')), findsOneWidget);
    expect(resultado, isNull);

    tarea.complete();
    await tester.pumpAndSettle();

    expect(find.text('Eliminar evento'), findsNothing);
    expect(find.byKey(const Key('espera_bloqueante')), findsNothing);
    expect(resultado, isTrue);
  });

  testWidgets('si la acción falla el modal se cierra y el error sube', (
    tester,
  ) async {
    Object? error;
    await _montar(tester, (context) async {
      try {
        await confirmarYEjecutar(
          context,
          title: 'Eliminar',
          message: '¿Seguro?',
          confirmLabel: 'Sí',
          accion: () async => throw Exception('RLS'),
        );
      } catch (e) {
        error = e;
      }
    });

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí'));
    await tester.pumpAndSettle();

    expect(find.text('¿Seguro?'), findsNothing);
    expect(error, isA<Exception>());
    expect(EsperaBloqueante.activa, isFalse);
  });

  testWidgets('cancelar no ejecuta nada', (tester) async {
    var ejecutado = false;
    bool? resultado;
    await _montar(tester, (context) async {
      resultado = await confirmarYEjecutar(
        context,
        title: 'Eliminar',
        message: '¿Seguro?',
        accion: () async => ejecutado = true,
      );
    });

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(ejecutado, isFalse);
    expect(resultado, isFalse);
  });

  testWidgets('mientras guarda, el resto de la app no recibe toques', (
    tester,
  ) async {
    final tarea = Completer<void>();
    var otros = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => conEspera(context, () => tarea.future),
                  child: const Text('Guardar'),
                ),
                TextButton(
                  onPressed: () => otros++,
                  child: const Text('Otra cosa'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Guardar'));
    await tester.pump();
    await tester.tap(find.text('Otra cosa'), warnIfMissed: false);
    expect(otros, 0);

    tarea.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Otra cosa'));
    expect(otros, 1);
  });

  testWidgets('un diálogo abierto a mitad de la espera sí se puede tocar', (
    tester,
  ) async {
    bool? respuesta;
    await _montar(tester, (context) {
      conEspera(context, () async {
        respuesta = await confirmDialog(
          context,
          title: 'Correo ya registrado',
          message: 'Esa persona ya está en el evento.',
          confirmLabel: 'Abrir',
        );
      });
    });

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('espera_bloqueante')), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Abrir'));
    await tester.pumpAndSettle();

    expect(respuesta, isTrue);
    expect(EsperaBloqueante.activa, isFalse);
  });
}
