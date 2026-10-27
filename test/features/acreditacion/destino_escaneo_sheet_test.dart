import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:transworld_nexus/data/models/subevento.dart';
import 'package:transworld_nexus/features/acreditacion/destino_escaneo_sheet.dart';

final _ahora = DateTime(2099, 5, 10, 10, 15);

Subevento _taller(String id, String nombre, int hora) => Subevento(
  id: id,
  eventoId: 'e1',
  codigo: id,
  nombre: nombre,
  dia: DateTime(2099, 5, 10),
  horaInicio: TimeOfDay(hour: hora, minute: 0),
  horaFin: TimeOfDay(hour: hora + 1, minute: 0),
);

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  Future<DestinoEscaneo?> abrir(
    WidgetTester tester,
    Future<void> Function() elegir,
  ) async {
    DestinoEscaneo? elegido;
    var cerrada = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                elegido = await showDestinoEscaneoSheet(
                  context,
                  // Desordenados a propósito: la hoja los ordena por hora.
                  talleres: [
                    _taller('t2', 'Taller de redes', 12),
                    _taller('t1', 'Taller de cámaras', 10),
                  ],
                  ahora: _ahora,
                );
                cerrada = true;
              },
              child: const Text('Escanear QR'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Escanear QR'));
    await tester.pumpAndSettle();
    await elegir();
    await tester.pumpAndSettle();
    expect(cerrada, isTrue);
    return elegido;
  }

  testWidgets('pregunta dónde acreditar: entrada arriba y talleres por hora', (
    tester,
  ) async {
    final destino = await abrir(tester, () async {
      expect(find.text('¿Dónde vas a acreditar?'), findsOneWidget);
      expect(find.text('Entrada del evento principal'), findsOneWidget);
      // El taller en curso (10:00, ahora 10:15) lleva la marca.
      expect(find.text('EN CURSO'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Taller de cámaras')).dy,
        lessThan(tester.getTopLeft(find.text('Taller de redes')).dy),
      );
      await tester.tap(find.byKey(const Key('destino_entrada')));
    });

    expect(destino, isNotNull);
    expect(destino!.taller, isNull);
  });

  testWidgets('elegir un taller lo devuelve', (tester) async {
    final destino = await abrir(tester, () async {
      await tester.tap(find.byKey(const Key('destino_taller_t2')));
    });

    expect(destino?.taller?.id, 't2');
  });
}
