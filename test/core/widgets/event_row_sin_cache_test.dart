import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:transworld_nexus/core/widgets/nexus_components.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  Future<void> montar(
    WidgetTester tester, {
    required bool sinCache,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        home: Scaffold(
          body: EventRow(
            date: DateTime(2026, 3, 10),
            title: 'Transworld Connect',
            place: 'Santiago',
            sinCache: sinCache,
            onTap: onTap,
            onLongPress: onLongPress,
          ),
        ),
      ),
    );
  }

  testWidgets('sin caché la fila se marca y no navega', (tester) async {
    var toques = 0;
    var mantenidos = 0;
    await montar(
      tester,
      sinCache: true,
      onTap: () => toques++,
      onLongPress: () => mantenidos++,
    );

    expect(find.text('SIN CONEXIÓN'), findsOneWidget);
    expect(find.byIcon(Symbols.lock_rounded), findsOneWidget);
    expect(find.byIcon(Symbols.chevron_right_rounded), findsNothing);

    // El aviso lo pone la pantalla en `onTap`; la fila sigue siendo pulsable
    // para poder mostrarlo, pero el menú contextual queda apagado.
    await tester.tap(find.text('Transworld Connect'));
    await tester.pumpAndSettle();
    expect(toques, 1);

    await tester.longPress(find.text('Transworld Connect'));
    await tester.pumpAndSettle();
    expect(mantenidos, 0, reason: 'fijar/editar/eliminar exigen red');
  });

  testWidgets('con caché la fila se comporta como siempre', (tester) async {
    var mantenidos = 0;
    await montar(
      tester,
      sinCache: false,
      onTap: () {},
      onLongPress: () => mantenidos++,
    );

    expect(find.text('SIN CONEXIÓN'), findsNothing);
    expect(find.byIcon(Symbols.lock_rounded), findsNothing);
    expect(find.byIcon(Symbols.chevron_right_rounded), findsOneWidget);

    await tester.longPress(find.text('Transworld Connect'));
    await tester.pumpAndSettle();
    expect(mantenidos, 1);
  });
}
