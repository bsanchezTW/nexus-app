import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/models/evento.dart';
import 'package:transworld_nexus/data/models/subevento.dart';
import 'package:transworld_nexus/features/eventos/eventos_agrupados.dart';

Evento _evento(String id, {TipoEvento tipo = TipoEvento.evento}) => Evento(
  id: id,
  nombre: 'Evento $id',
  fecha: DateTime(2026, 10, 1),
  tipo: tipo,
  duracionDias: 2,
);

Subevento _taller(
  String id,
  String eventoId, {
  String? origen,
  int dia = 1,
  int hora = 10,
  int orden = 0,
  String? sala,
}) => Subevento(
  id: id,
  eventoId: eventoId,
  codigo: '',
  nombre: 'Taller $id',
  dia: DateTime(2026, 10, dia),
  horaInicio: TimeOfDay(hour: hora, minute: 0),
  horaFin: TimeOfDay(hour: hora + 1, minute: 0),
  orden: orden,
  sala: sala,
  eventoOrigenId: origen,
);

void main() {
  group('agruparEventos', () {
    test('cuelga los talleres de su principal y respeta el orden', () {
      final grupos = agruparEventos(
        [_evento('b'), _evento('a')],
        [
          _taller('t2', 'a', dia: 2, hora: 9),
          _taller('t1', 'a', dia: 1, hora: 15),
          _taller('t0', 'a', dia: 1, hora: 15, orden: -1),
        ],
      );

      expect(grupos.map((g) => g.evento.id), ['b', 'a']);
      expect(grupos.first.talleres, isEmpty);
      expect(grupos.last.talleres.map((t) => t.id), ['t0', 't1', 't2']);
    });

    test('un evento-taller sumado a un principal no se repite suelto', () {
      final grupos = agruparEventos(
        [
          _evento('principal'),
          _evento('taller-ev', tipo: TipoEvento.taller),
          _evento('suelto', tipo: TipoEvento.taller),
        ],
        [_taller('t1', 'principal', origen: 'taller-ev')],
      );

      expect(grupos.map((g) => g.evento.id), ['principal', 'suelto']);
      expect(grupos.first.talleres.single.eventoOrigenId, 'taller-ev');
    });

    test('si el principal no es visible, el taller sigue en la lista', () {
      final grupos = agruparEventos(
        [_evento('taller-ev', tipo: TipoEvento.taller)],
        [_taller('t1', 'principal-ajeno', origen: 'taller-ev')],
      );

      expect(grupos.map((g) => g.evento.id), ['taller-ev']);
      expect(grupos.single.talleres, isEmpty);
    });
  });

  group('filtrarGruposPorTexto', () {
    final grupos = agruparEventos(
      [_evento('a'), _evento('b')],
      [_taller('t1', 'a', sala: 'Salón Andes')],
    );

    test('sin texto devuelve todo y nada abierto', () {
      final r = filtrarGruposPorTexto(grupos, '  ');
      expect(r.grupos, hasLength(2));
      expect(r.abiertosPorBusqueda, isEmpty);
    });

    test('por nombre del evento no abre el grupo', () {
      final r = filtrarGruposPorTexto(grupos, 'evento b');
      expect(r.grupos.map((g) => g.evento.id), ['b']);
      expect(r.abiertosPorBusqueda, isEmpty);
    });

    test('por un taller muestra su principal abierto', () {
      final r = filtrarGruposPorTexto(grupos, 'andes');
      expect(r.grupos.map((g) => g.evento.id), ['a']);
      expect(r.abiertosPorBusqueda, {'a'});
    });
  });
}
