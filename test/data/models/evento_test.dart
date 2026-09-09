import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/models/evento.dart';

void main() {
  test('sin duración en la fila se asume un día', () {
    final evento = Evento.fromMap({
      'id': 'e-1',
      'nombre': 'Taller',
      'fecha': '2026-09-12',
    });

    expect(evento.duracionDias, 1);
    expect(evento.esMultiDia, isFalse);
    expect(evento.toInsertMap()['duracion_dias'], 1);
    expect(evento.toInsertMap().containsKey('activo'), isFalse);
  });

  test('un evento de 3 días cubre el rango y no el día siguiente', () {
    final evento = Evento(
      id: 'e-1',
      nombre: 'Feria',
      fecha: DateTime(2026, 9, 12),
      duracionDias: 3,
    );

    expect(evento.cubreDia(DateTime(2026, 9, 12)), isTrue);
    expect(evento.cubreDia(DateTime(2026, 9, 14)), isTrue);
    expect(evento.cubreDia(DateTime(2026, 9, 15)), isFalse);
    expect(evento.cubreMes(DateTime(2026, 9, 1)), isTrue);
    expect(evento.cubreMes(DateTime(2026, 10, 1)), isFalse);
    expect(evento.toInsertMap()['duracion_dias'], 3);
    expect(evento.toCacheMap()['duracion_dias'], 3);
    expect(evento.toInsertMap().containsKey('activo'), isFalse);
    expect(evento.toCacheMap().containsKey('activo'), isFalse);
  });

  test('un flag activo residual en la fila no cambia la vigencia', () {
    final evento = Evento.fromMap({
      'id': 'e-1',
      'nombre': 'Taller',
      'fecha': '2099-01-01',
      'activo': false,
    });

    expect(evento.yaOcurrio, isFalse);
    expect(evento.toInsertMap().containsKey('activo'), isFalse);
  });

  test('yaOcurrio usa el último día del rango, no el de inicio', () {
    final ayer = DateTime.now().subtract(const Duration(days: 1));
    final inicio = DateTime(ayer.year, ayer.month, ayer.day);

    expect(
      Evento(id: 'e-1', nombre: 'Corto', fecha: inicio).yaOcurrio,
      isTrue,
    );
    expect(
      Evento(
        id: 'e-2',
        nombre: 'Largo',
        fecha: inicio,
        duracionDias: 3,
      ).yaOcurrio,
      isFalse,
    );
  });
}
