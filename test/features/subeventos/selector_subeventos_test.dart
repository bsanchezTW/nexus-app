import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:transworld_nexus/data/models/ocupacion_evento.dart';
import 'package:transworld_nexus/data/models/subevento.dart';
import 'package:transworld_nexus/features/subeventos/widgets/selector_subeventos.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
  });

  final manana = DateTime.now().add(const Duration(days: 2));
  final dia = DateTime(manana.year, manana.month, manana.day);

  Subevento taller({
    required String id,
    required String nombre,
    required int inicio,
    required int fin,
  }) {
    return Subevento(
      id: id,
      eventoId: 'e',
      codigo: id,
      nombre: nombre,
      dia: dia,
      horaInicio: TimeOfDay(hour: inicio, minute: 0),
      horaFin: TimeOfDay(hour: fin, minute: 0),
    );
  }

  testWidgets('deshabilita el taller lleno y el que se solapa', (tester) async {
    final a = taller(id: 'a', nombre: 'IA', inicio: 10, fin: 11);
    final b = taller(id: 'b', nombre: 'Datos', inicio: 10, fin: 12);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectorSubeventos(
            subeventos: [a, b],
            seleccionados: const {'a'},
            ocupacion: const OcupacionEvento(
              evento: OcupacionItem(cupoMaximo: 10, inscritos: 1, asistentes: 0),
              subeventos: {
                'b': OcupacionItem(cupoMaximo: 1, inscritos: 1, asistentes: 0),
              },
            ),
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.textContaining('Choca con IA'), findsOneWidget);
    expect(find.textContaining('Sin cupo'), findsOneWidget);
    final datos = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Datos'),
    );
    expect(datos.onChanged, isNull);
  });
}
