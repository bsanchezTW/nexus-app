import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/models/subevento.dart';
import 'package:transworld_nexus/features/subeventos/sugerir_subevento_en_curso.dart';

void main() {
  test('si hay varios en curso, gana el que empezó más tarde', () {
    final dia = DateTime(2026, 12, 1);
    final ahora = DateTime(2026, 12, 1, 10, 30);
    final temprano = Subevento(
      id: 'temprano',
      eventoId: 'e',
      codigo: 'aaaaaa',
      nombre: 'Apertura',
      dia: dia,
      horaInicio: const TimeOfDay(hour: 9, minute: 0),
      horaFin: const TimeOfDay(hour: 12, minute: 0),
    );
    final reciente = Subevento(
      id: 'reciente',
      eventoId: 'e',
      codigo: 'bbbbbb',
      nombre: 'IA',
      dia: dia,
      horaInicio: const TimeOfDay(hour: 10, minute: 0),
      horaFin: const TimeOfDay(hour: 12, minute: 0),
    );
    final pasado = Subevento(
      id: 'pasado',
      eventoId: 'e',
      codigo: 'cccccc',
      nombre: 'Cierre',
      dia: dia,
      horaInicio: const TimeOfDay(hour: 8, minute: 0),
      horaFin: const TimeOfDay(hour: 9, minute: 0),
    );

    expect(
      sugerirSubeventoEnCurso([temprano, pasado, reciente], ahora)?.id,
      'reciente',
    );
    expect(
      sugerirSubeventoEnCurso([pasado], DateTime(2026, 12, 1, 15)),
      isNull,
    );
  });
}
