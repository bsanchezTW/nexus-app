import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/models/evento.dart';
import 'package:transworld_nexus/features/subeventos/subevento_desde_evento.dart';

void main() {
  Evento evento({
    required String id,
    required String nombre,
    required DateTime fecha,
    int duracionDias = 1,
    TimeOfDay? horaInicio,
    TimeOfDay? horaFin,
    String? descripcion,
    String? tematica,
    String? lugar,
    String? imagenUrl,
    int? cupoMaximo,
  }) {
    return Evento(
      id: id,
      nombre: nombre,
      fecha: fecha,
      duracionDias: duracionDias,
      horaInicio: horaInicio,
      horaFin: horaFin,
      descripcion: descripcion,
      tematica: tematica,
      lugar: lugar,
      imagenUrl: imagenUrl,
      cupoMaximo: cupoMaximo,
    );
  }

  test('copia los datos y conserva el día dentro del evento principal', () {
    final taller = subeventoDesdeEvento(
      principal: evento(
        id: 'principal',
        nombre: 'Feria',
        fecha: DateTime(2026, 9, 10),
        duracionDias: 3,
      ),
      origen: evento(
        id: 'origen',
        nombre: 'Taller de redes',
        fecha: DateTime(2026, 9, 11),
        horaInicio: const TimeOfDay(hour: 15, minute: 0),
        horaFin: const TimeOfDay(hour: 16, minute: 30),
        descripcion: 'Contenido',
        lugar: 'Sala 2',
        imagenUrl: 'https://img.example/taller.jpg',
        cupoMaximo: 20,
      ),
      orden: 4,
    );

    expect(taller.eventoId, 'principal');
    expect(taller.codigo, isEmpty);
    expect(taller.nombre, 'Taller de redes');
    expect(taller.dia, DateTime(2026, 9, 11));
    expect(taller.horaInicio, const TimeOfDay(hour: 15, minute: 0));
    expect(taller.horaFin, const TimeOfDay(hour: 16, minute: 30));
    expect(taller.descripcion, 'Contenido');
    expect(taller.sala, 'Sala 2');
    expect(taller.imagenUrl, 'https://img.example/taller.jpg');
    expect(taller.cupoMaximo, 20);
    expect(taller.orden, 4);
    expect(taller.visiblePublico, isTrue);
    expect(taller.eventoOrigenId, 'origen');
  });

  test('un día fuera del principal pasa al primer día del evento', () {
    final taller = subeventoDesdeEvento(
      principal: evento(
        id: 'principal',
        nombre: 'Feria',
        fecha: DateTime(2026, 9, 10),
        duracionDias: 2,
      ),
      origen: evento(
        id: 'origen',
        nombre: 'Charla',
        fecha: DateTime(2026, 8, 1),
      ),
      orden: 0,
    );

    expect(taller.dia, DateTime(2026, 9, 10));
  });

  test(
    'sin horario usa 10:00 a 11:00 y corrige un fin que no es posterior',
    () {
      final sinHorario = subeventoDesdeEvento(
        principal: evento(
          id: 'principal',
          nombre: 'Feria',
          fecha: DateTime(2026, 9, 10),
        ),
        origen: evento(
          id: 'origen',
          nombre: 'Charla',
          fecha: DateTime(2026, 9, 10),
        ),
        orden: 0,
      );
      final finIgual = subeventoDesdeEvento(
        principal: evento(
          id: 'principal',
          nombre: 'Feria',
          fecha: DateTime(2026, 9, 10),
        ),
        origen: evento(
          id: 'origen',
          nombre: 'Charla',
          fecha: DateTime(2026, 9, 10),
          horaInicio: const TimeOfDay(hour: 18, minute: 15),
          horaFin: const TimeOfDay(hour: 18, minute: 15),
        ),
        orden: 1,
      );

      expect(sinHorario.horaInicio, const TimeOfDay(hour: 10, minute: 0));
      expect(sinHorario.horaFin, const TimeOfDay(hour: 11, minute: 0));
      expect(finIgual.horaInicio, const TimeOfDay(hour: 18, minute: 15));
      expect(finIgual.horaFin, const TimeOfDay(hour: 19, minute: 15));
    },
  );

  test('sin descripción usa la temática', () {
    final taller = subeventoDesdeEvento(
      principal: evento(
        id: 'principal',
        nombre: 'Feria',
        fecha: DateTime(2026, 9, 10),
      ),
      origen: evento(
        id: 'origen',
        nombre: 'Charla',
        fecha: DateTime(2026, 9, 10),
        descripcion: '   ',
        tematica: 'Logística',
      ),
      orden: 0,
    );

    expect(taller.descripcion, 'Logística');
  });
}
