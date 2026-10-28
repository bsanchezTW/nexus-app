import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/core/conexion/sondeo_backend.dart';

const _latencia = Duration(milliseconds: 250);

void main() {
  group('interpretarRespuestaBackend', () {
    test('sin respuesta no decide: hay que preguntar por Internet', () {
      expect(interpretarRespuestaBackend(null, _latencia), isNull);
    });

    test('2xx y 4xx prueban que el backend contesta', () {
      for (final estado in const [200, 204, 401, 403]) {
        final lectura = interpretarRespuestaBackend(estado, _latencia)!;
        expect(lectura.respondio, isTrue, reason: '$estado');
        expect(lectura.latencia, _latencia);
      }
    });

    test('un 5xx es la base de datos caída, no falta de Internet', () {
      // PostgREST responde 503 cuando no alcanza a Postgres.
      for (final estado in const [500, 502, 503, 540]) {
        final lectura = interpretarRespuestaBackend(estado, _latencia)!;
        expect(lectura.respondio, isFalse, reason: '$estado');
        expect(lectura.backendCaido, isTrue, reason: '$estado');
      }
    });
  });
}
