import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/models/inscripcion_subevento.dart';
import 'package:transworld_nexus/data/models/subevento.dart';
import 'package:transworld_nexus/features/kpi/providers/kpi_providers.dart';

Subevento _taller({
  required String id,
  required String nombre,
  required DateTime dia,
  required int hora,
  int orden = 0,
  int? cupo,
}) {
  return Subevento(
    id: id,
    eventoId: 'evento-1',
    codigo: id,
    nombre: nombre,
    dia: dia,
    horaInicio: TimeOfDay(hour: hora, minute: 0),
    horaFin: TimeOfDay(hour: hora + 1, minute: 0),
    cupoMaximo: cupo,
    orden: orden,
  );
}

void main() {
  test('cuenta inscritos, asistencia, cupo y sobrecupo desde la caché', () {
    final tarde = _taller(
      id: 'tarde',
      nombre: 'Cierre',
      dia: DateTime(2026, 12, 1),
      hora: 15,
      cupo: 10,
    );
    final manana = _taller(
      id: 'manana',
      nombre: 'Apertura',
      dia: DateTime(2026, 12, 1),
      hora: 9,
      cupo: 2,
    );
    final kpis = calcularKpisTalleres(
      subeventos: [tarde, manana],
      inscripciones: const [
        InscripcionSubevento(
          id: 'i1',
          eventoId: 'evento-1',
          registradoId: 'ana',
          subeventoId: 'manana',
          origen: 'app',
          asistio: true,
        ),
        InscripcionSubevento(
          id: 'i2',
          eventoId: 'evento-1',
          registradoId: 'luis',
          subeventoId: 'manana',
          origen: 'app',
          sobrecupo: true,
        ),
        InscripcionSubevento(
          id: 'i3',
          eventoId: 'evento-1',
          registradoId: 'ana',
          subeventoId: 'tarde',
          origen: 'app',
        ),
      ],
    );

    expect(kpis.map((k) => k.subevento.nombre), ['Apertura', 'Cierre']);
    expect(kpis.first.inscritos, 2);
    expect(kpis.first.asistentes, 1);
    expect(kpis.first.cupo, 2);
    expect(kpis.first.sobrecupo, 1);
    expect(kpis.first.porcentajeAsistencia, 0.5);
    expect(kpis.last.asistentes, 0);
    expect(kpis.last.porcentajeAsistencia, 0);
  });
}
