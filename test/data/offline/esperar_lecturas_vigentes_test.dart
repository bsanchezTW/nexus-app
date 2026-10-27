import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/offline/offline_read_cache.dart';

void main() {
  test(
    'una carga reemplazada se espera de nuevo y no cuenta como fallo',
    () async {
      var llamadas = 0;

      await esperarLecturasVigentes(() {
        llamadas++;
        // La primera vez una de las cargas ya fue descartada y falla al usar
        // su ref; la segunda vez se piden los futuros vigentes.
        return [
          Future.value(1),
          if (llamadas == 1)
            Future<Object?>.error(
              StateError('Cannot call onDispose after a provider was disposed'),
            )
          else
            Future.value(2),
        ];
      });

      expect(llamadas, 2);
    },
  );

  test('un error del servidor se propaga sin reintentar', () async {
    var llamadas = 0;

    await expectLater(
      esperarLecturasVigentes(() {
        llamadas++;
        return [Future<Object?>.error(Exception('500'))];
      }),
      throwsA(isA<Exception>()),
    );
    expect(llamadas, 1);
  });

  test('si la carga sigue descartándose, se rinde tras los intentos', () async {
    var llamadas = 0;

    await expectLater(
      esperarLecturasVigentes(() {
        llamadas++;
        return [Future<Object?>.error(StateError('descartada'))];
      }),
      throwsA(isA<StateError>()),
    );
    expect(llamadas, 3);
  });
}
