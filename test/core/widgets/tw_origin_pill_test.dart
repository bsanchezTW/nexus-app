import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:transworld_nexus/core/theme/tw_tokens.dart';
import 'package:transworld_nexus/core/widgets/nexus_components.dart';
import 'package:transworld_nexus/core/widgets/tw_components.dart';

Color _fondoDelPill(WidgetTester tester) {
  final container = tester.widget<Container>(
    find
        .descendant(
          of: find.byType(TwOriginPill),
          matching: find.byType(Container),
        )
        .first,
  );
  return (container.decoration! as BoxDecoration).color!;
}

Future<void> _montar(WidgetTester tester, {required bool interno}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: TwOriginPill(interno: interno)),
      ),
    ),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('es', null));

  testWidgets('el interno se rotula en lima', (tester) async {
    await _montar(tester, interno: true);

    expect(find.text('INTERNO'), findsOneWidget);
    expect(find.text('EXTERNO'), findsNothing);
    expect(_fondoDelPill(tester), TwColors.originInternalBg);
  });

  testWidgets('el externo se rotula en naranjo', (tester) async {
    await _montar(tester, interno: false);

    expect(find.text('EXTERNO'), findsOneWidget);
    expect(find.text('INTERNO'), findsNothing);
    expect(_fondoDelPill(tester), TwColors.originExternalBg);
  });

  testWidgets('la fila de la lista muestra origen y estado a la vez', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        home: Scaffold(
          body: EventRow(
            date: DateTime(2020, 8, 10),
            title: 'Transworld Connect',
            place: 'Santiago',
            finalizado: true,
            chip: const TwOriginPill(interno: true),
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('INTERNO'), findsOneWidget);
    expect(find.text('FINALIZADO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
