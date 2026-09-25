import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/models/evento.dart';
import 'package:transworld_nexus/features/usuarios/widgets/selector_eventos_multiples.dart';

Evento _evento(String id, String nombre) {
  return Evento(id: id, nombre: nombre, fecha: DateTime(2026, 12, 1));
}

void main() {
  testWidgets('muestra la lista sin chips de seleccionados', (tester) async {
    final seleccionados = <String>{'e1'};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectorEventosMultiples(
            eventos: [
              _evento('e1', 'Summit 2026'),
              _evento('e2', 'Taller ALTAI'),
            ],
            seleccionados: seleccionados,
            onChanged: (ids) => seleccionados
              ..clear()
              ..addAll(ids),
          ),
        ),
      ),
    );

    expect(find.text('Summit 2026'), findsOneWidget);
    expect(find.text('Taller ALTAI'), findsOneWidget);
    expect(find.byType(InputChip), findsNothing);
    expect(find.text('1 evento autorizado.'), findsOneWidget);
  });

  testWidgets('el checkbox agrega y quita eventos de la selección', (
    tester,
  ) async {
    var seleccionados = <String>{};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SelectorEventosMultiples(
                eventos: [_evento('e1', 'Summit 2026')],
                seleccionados: seleccionados,
                onChanged: (ids) => setState(() => seleccionados = ids),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();

    expect(find.text('1 evento autorizado.'), findsOneWidget);
    expect(find.byType(InputChip), findsNothing);
  });
}
