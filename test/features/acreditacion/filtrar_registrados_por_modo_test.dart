import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/models/inscripcion_subevento.dart';
import 'package:transworld_nexus/data/models/registrado.dart';
import 'package:transworld_nexus/features/acreditacion/screens/acreditar_confirmado_screen.dart';
import 'package:transworld_nexus/features/subeventos/providers/inscripciones_providers.dart';

void main() {
  const ana = Registrado(
    id: 'ana',
    eventoId: 'evento-1',
    nombreCompleto: 'Ana',
    email: 'ana@x.cl',
  );
  const luis = Registrado(
    id: 'luis',
    eventoId: 'evento-1',
    nombreCompleto: 'Luis',
    email: 'luis@x.cl',
  );
  const inscripcion = InscripcionSubevento(
    id: 'i1',
    eventoId: 'evento-1',
    registradoId: 'ana',
    subeventoId: 'taller-1',
    origen: 'app',
  );

  test('en entrada muestra a todos y en un taller solo a los inscritos', () {
    expect(
      filtrarRegistradosPorModo(
        registrados: const [ana, luis],
        inscripciones: const [inscripcion],
        subeventoId: null,
      ),
      const [ana, luis],
    );
    expect(
      filtrarRegistradosPorModo(
        registrados: const [ana, luis],
        inscripciones: const [inscripcion],
        subeventoId: 'taller-1',
      ),
      const [ana],
    );
  });

  test('los conflictos del taller llegan como ids', () {
    expect(idsDeConflictos(['taller-a', 'taller-b']), ['taller-a', 'taller-b']);
    expect(idsDeConflictos(null), isEmpty);
  });
}
