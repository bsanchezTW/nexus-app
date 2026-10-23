import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/models/evento.dart';
import 'package:transworld_nexus/data/models/subevento.dart';
import 'package:transworld_nexus/features/subeventos/agrupar_talleres.dart';

Evento _evento(String id, DateTime fecha) =>
    Evento(id: id, nombre: id, fecha: fecha, pais: 'Chile');

Subevento _enlace(String eventoId, String tallerId) => Subevento(
  id: '$eventoId-$tallerId',
  eventoId: eventoId,
  codigo: 'c',
  nombre: tallerId,
  dia: DateTime(2026, 10, 1),
  horaInicio: const TimeOfDay(hour: 10, minute: 0),
  horaFin: const TimeOfDay(hour: 11, minute: 0),
  eventoOrigenId: tallerId,
);

void main() {
  final connect = _evento('connect', DateTime(2026, 8, 25));
  final foro = _evento('foro', DateTime(2026, 11, 5));
  final radwin = _evento('radwin', DateTime(2026, 8, 25));
  final altai = _evento('altai', DateTime(2026, 8, 24));
  final suelto = _evento('suelto', DateTime(2026, 12, 1));
  final compartido = _evento('compartido', DateTime(2026, 11, 5));

  test('agrupa por evento, con "sin evento" primero y eventos recientes '
      'antes', () {
    final grupos = agruparTalleresPorEvento(
      talleres: [radwin, suelto, altai, compartido],
      eventos: [connect, foro, radwin, altai, suelto, compartido],
      subeventos: [
        _enlace('connect', 'radwin'),
        _enlace('connect', 'altai'),
        _enlace('foro', 'compartido'),
        // Subevento propio, sin taller de origen: no agrupa nada.
        Subevento(
          id: 'propio',
          eventoId: 'foro',
          codigo: 'p',
          nombre: 'propio',
          dia: DateTime(2026, 11, 5),
          horaInicio: const TimeOfDay(hour: 9, minute: 0),
          horaFin: const TimeOfDay(hour: 10, minute: 0),
        ),
      ],
    );

    expect(grupos.map((g) => g.evento?.id), [null, 'foro', 'connect']);
    expect(grupos[0].talleres.map((t) => t.id), ['suelto']);
    expect(grupos[1].talleres.map((t) => t.id), ['compartido']);
    // Dentro de la sección, por fecha.
    expect(grupos[2].talleres.map((t) => t.id), ['altai', 'radwin']);
  });

  test('un taller agregado a dos eventos aparece en ambas secciones', () {
    final grupos = agruparTalleresPorEvento(
      talleres: [radwin],
      eventos: [connect, foro, radwin],
      subeventos: [_enlace('connect', 'radwin'), _enlace('foro', 'radwin')],
    );

    expect(grupos.map((g) => g.evento?.id), ['foro', 'connect']);
    expect(grupos.every((g) => g.talleres.single.id == 'radwin'), isTrue);
  });

  test('si el evento al que está agregado no es visible, queda sin evento', () {
    final grupos = agruparTalleresPorEvento(
      talleres: [radwin],
      eventos: [radwin],
      subeventos: [_enlace('connect', 'radwin')],
    );

    expect(grupos.single.evento, isNull);
  });
}
