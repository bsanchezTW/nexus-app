import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/core/widgets/app_widgets.dart';
import 'package:transworld_nexus/core/widgets/tw_toast.dart';

void main() {
  tearDown(TwToast.hide);

  testWidgets('la confirmación destructiva exige una decisión explícita', (
    tester,
  ) async {
    bool? resultado;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                resultado = await confirmDialog(
                  context,
                  title: 'Desinstalar RegisPro',
                  message: 'Esta acción no se puede deshacer.',
                  confirmLabel: 'Desinstalar',
                  destructive: true,
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.text('Desinstalar RegisPro'), findsOneWidget);
    expect(find.text('Esta acción no se puede deshacer.'), findsOneWidget);
    expect(resultado, isNull);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('Desinstalar RegisPro'), findsOneWidget);
    expect(resultado, isNull);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('Desinstalar RegisPro'), findsNothing);
    expect(resultado, isFalse);
  });

  for (final conBarra in [false, true]) {
    testWidgets('el toast aparece arriba, bajo la barra de estado '
        '(${conBarra ? 'con' : 'sin'} barra inferior)', (tester) async {
      Widget pantalla = Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showAppSnackBar(context, 'Evento creado correctamente'),
            child: const Text('Mostrar'),
          ),
        ),
      );
      if (conBarra) pantalla = ShellNavScope(child: pantalla);
      await tester.pumpWidget(MaterialApp(home: pantalla));

      await tester.tap(find.text('Mostrar'));
      await tester.pump();

      final toast = find.text('Evento creado correctamente');
      expect(toast, findsOneWidget);
      final positioned = tester.widget<Positioned>(
        find.ancestor(of: toast, matching: find.byType(Positioned)).first,
      );
      final safe = MediaQuery.paddingOf(tester.element(toast)).top;
      expect(positioned.top, safe + 10);
      expect(positioned.bottom, isNull);
    });
  }

  testWidgets('descartar creación: Cancelar se queda, Descartar confirma', (
    tester,
  ) async {
    bool? resultado;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                resultado = await confirmDiscardCreate(context);
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.text('¿Descartar?'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(resultado, isFalse);

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(resultado, isTrue);
  });

  testWidgets('confirmación admite etiquetas Sí y No', (tester) async {
    bool? resultado;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                resultado = await confirmDialog(
                  context,
                  title: 'Esta persona ya está capturada',
                  message: '¿Quiere agregar un comentario?',
                  confirmLabel: 'Sí',
                  cancelLabel: 'No',
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.text('Esta persona ya está capturada'), findsOneWidget);

    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(resultado, isFalse);

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí'));
    await tester.pumpAndSettle();
    expect(resultado, isTrue);
  });

  testWidgets('guardar cambios: tres acciones', (tester) async {
    FormExitAction? resultado;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                resultado = await confirmSaveEdits(context);
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.text('¿Guardar los cambios?'), findsOneWidget);

    await tester.tap(find.text('Seguir editando'));
    await tester.pumpAndSettle();
    expect(resultado, FormExitAction.stay);

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(resultado, FormExitAction.discard);

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(resultado, FormExitAction.save);
  });

  testWidgets('el vacío muestra Actualizar debajo del aviso', (tester) async {
    var refrescos = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: EmptyStateView(
          message: 'Aún no hay asistentes registrados.',
          onRefresh: () => refrescos++,
        ),
      ),
    );

    final aviso = find.text('Aún no hay asistentes registrados.');
    final actualizar = find.text('Actualizar');
    expect(aviso, findsOneWidget);
    expect(actualizar, findsOneWidget);
    expect(
      tester.getTopLeft(actualizar).dy,
      greaterThan(tester.getBottomLeft(aviso).dy),
    );

    await tester.tap(actualizar);
    expect(refrescos, 1);
  });

  testWidgets(
    'en Android e iOS el aviso vacío queda más arriba que en escritorio',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      Future<double> centroDelAviso(TargetPlatform platform) async {
        final previous = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = platform;
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: CustomScrollView(
                slivers: [
                  const SliverToBoxAdapter(child: SizedBox(height: 200)),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyStateView(
                      message: 'Aún no hay asistentes registrados.',
                      onRefresh: () {},
                    ),
                  ),
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();
          return tester
              .getCenter(find.text('Aún no hay asistentes registrados.'))
              .dy;
        } finally {
          debugDefaultTargetPlatformOverride = previous;
        }
      }

      final yAndroid = await centroDelAviso(TargetPlatform.android);
      final yIos = await centroDelAviso(TargetPlatform.iOS);
      final yWindows = await centroDelAviso(TargetPlatform.windows);

      expect(yAndroid, lessThan(yWindows));
      expect(yIos, lessThan(yWindows));
    },
  );
}
