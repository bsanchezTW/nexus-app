import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/models/evento.dart';
import 'package:transworld_nexus/data/models/evento_lead.dart';
import 'package:transworld_nexus/features/home/providers/home_dashboard_providers.dart';

DateTime _hoy() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

Evento _evento({
  required String id,
  required DateTime fecha,
  int duracionDias = 1,
}) {
  return Evento(id: id, nombre: id, fecha: fecha, duracionDias: duracionDias);
}

EventoLead _actividad({
  required String id,
  required DateTime fecha,
  int duracionDias = 1,
}) {
  return EventoLead(
    id: id,
    nombre: id,
    fecha: fecha,
    duracionDias: duracionDias,
  );
}

void main() {
  test('Activos son los no finalizados, no el flag del registro', () {
    final hoy = _hoy();
    final data = HomeDashboardData(
      eventos: [
        _evento(id: 'pasado-1', fecha: hoy.subtract(const Duration(days: 2))),
        _evento(id: 'pasado-2', fecha: hoy.subtract(const Duration(days: 10))),
        _evento(id: 'hoy', fecha: hoy),
      ],
      totalRegistrados: 0,
      totalAcreditados: 0,
    );

    expect(data.eventosActivos, 1);
  });

  test(
    'Activos suma la actividad vigente cuando los eventos ya terminaron',
    () {
      final hoy = _hoy();
      final data = HomeDashboardData(
        eventos: [
          _evento(id: 'pasado', fecha: hoy.subtract(const Duration(days: 3))),
        ],
        actividades: [
          _actividad(id: 'vigente', fecha: hoy, duracionDias: 4),
          _actividad(
            id: 'terminada',
            fecha: hoy.subtract(const Duration(days: 20)),
          ),
        ],
        totalRegistrados: 0,
        totalAcreditados: 0,
      );

      expect(data.eventosActivos, 1);
    },
  );

  test(
    'una actividad en curso cuenta como activa aunque haya empezado antes',
    () {
      final hoy = _hoy();
      final data = HomeDashboardData(
        eventos: const [],
        actividades: [
          _actividad(
            id: 'curso',
            fecha: hoy.subtract(const Duration(days: 2)),
            duracionDias: 10,
          ),
        ],
        totalRegistrados: 0,
        totalAcreditados: 0,
      );

      expect(data.eventosActivos, 1);
    },
  );

  test('un evento de varios días sigue activo aunque haya empezado ayer', () {
    final hoy = _hoy();
    final data = HomeDashboardData(
      eventos: [
        _evento(
          id: 'curso',
          fecha: hoy.subtract(const Duration(days: 1)),
          duracionDias: 3,
        ),
      ],
      totalRegistrados: 0,
      totalAcreditados: 0,
    );

    expect(data.eventosActivos, 1);
    expect(data.eventosEnDia(hoy), hasLength(1));
  });
}
