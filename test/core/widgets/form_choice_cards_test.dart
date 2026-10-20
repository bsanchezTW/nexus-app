import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/core/widgets/form_sections.dart';

void main() {
  testWidgets('una opción deshabilitada no se puede elegir', (tester) async {
    var elegida = 'evento';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => FormChoiceCards<String>(
              value: elegida,
              onChanged: (value) => setState(() => elegida = value),
              choices: const [
                FormChoice(
                  value: 'evento',
                  icon: Icons.event,
                  title: 'Evento',
                  description: 'Agrupa talleres.',
                ),
                FormChoice(
                  value: 'taller',
                  icon: Icons.co_present,
                  title: 'Taller',
                  description: 'No disponible: este evento tiene 8 talleres.',
                  enabled: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Taller'));
    await tester.pump();
    expect(elegida, 'evento');
    expect(
      find.text('No disponible: este evento tiene 8 talleres.'),
      findsOneWidget,
    );
  });
}
