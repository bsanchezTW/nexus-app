import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/core/constants/duracion_actividad.dart';

void main() {
  test('un día de término igual al de inicio dura un día', () {
    final inicio = DateTime(2026, 9, 12);
    expect(duracionDesdeRango(inicio, inicio), 1);
    expect(fechaTerminoActividad(inicio, 1), DateTime(2026, 9, 12));
    expect(textoDuracionActividad(1), 'Esta actividad durará 1 día');
  });

  test('tres días de término caen dos días después', () {
    final inicio = DateTime(2026, 9, 12);
    final termino = DateTime(2026, 9, 14);
    expect(duracionDesdeRango(inicio, termino), 3);
    expect(fechaTerminoActividad(inicio, 3), DateTime(2026, 9, 14));
    expect(textoDuracionActividad(3), 'Esta actividad durará 3 días');
    expect(textoDuracionEvento(3), 'Este evento durará 3 días');
  });
}
