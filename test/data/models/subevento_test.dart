import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/models/subevento.dart';

void main() {
  Subevento taller(int inicioHora, int inicioMin, int finHora, int finMin) {
    return Subevento(
      id: '$inicioHora$finHora',
      eventoId: 'e',
      codigo: 'abcdef',
      nombre: 'Taller',
      dia: DateTime(2026, 11, 12),
      horaInicio: TimeOfDay(hour: inicioHora, minute: inicioMin),
      horaFin: TimeOfDay(hour: finHora, minute: finMin),
    );
  }

  test('los horarios contiguos no se solapan', () {
    final primero = taller(10, 0, 11, 0);
    final segundo = taller(11, 0, 12, 0);
    expect(primero.seSuperponeCon(segundo), isFalse);
  });

  test('enCurso incluye la media hora previa', () {
    final actual = taller(10, 0, 11, 0);
    expect(
      actual.enCurso(DateTime(2026, 11, 12, 9, 40)),
      isTrue,
    );
    expect(actual.yaTermino(DateTime(2026, 11, 12, 11, 0)), isTrue);
  });
}
