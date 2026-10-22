import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/core/widgets/tw_toast.dart';

Future<void> _montar(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => TwToast.info(context, 'Listo'),
              child: const Text('Mostrar'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  tearDown(TwToast.hide);

  testWidgets('el toast cae desde arriba y al irse sube', (tester) async {
    await _montar(tester);

    await tester.tap(find.text('Mostrar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.text('Listo'), findsOneWidget);
    final slide = find.byKey(const Key('tw-toast-slide'));
    final fade = find.byKey(const Key('tw-toast-fade'));
    expect(
      tester.widget<SlideTransition>(slide).position.value.dy,
      lessThan(0),
    );

    await tester.pumpAndSettle();
    expect(tester.widget<SlideTransition>(slide).position.value.dy, 0);
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);

    TwToast.hide();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.text('Listo'), findsOneWidget);
    expect(
      tester.widget<SlideTransition>(slide).position.value.dy,
      lessThan(0),
    );
    expect(tester.widget<FadeTransition>(fade).opacity.value, lessThan(1));

    await tester.pumpAndSettle();
    expect(find.text('Listo'), findsNothing);
  });

  testWidgets('deslizarlo hacia arriba lo descarta', (tester) async {
    await _montar(tester);
    await tester.tap(find.text('Mostrar'));
    await tester.pumpAndSettle();

    await tester.drag(find.text('Listo'), const Offset(0, -80));
    await tester.pumpAndSettle();

    expect(find.text('Listo'), findsNothing);
  });
}
