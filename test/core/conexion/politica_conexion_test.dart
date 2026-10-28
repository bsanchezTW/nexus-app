import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/core/conexion/estado_conexion.dart';
import 'package:transworld_nexus/core/conexion/politica_conexion.dart';

const _rapido = LecturaSondeo.respondio(Duration(milliseconds: 300));
const _lento = LecturaSondeo.respondio(Duration(seconds: 3));
const _regular = LecturaSondeo.respondio(Duration(seconds: 2));
const _caido = LecturaSondeo.sinRespuesta();
const _sinBase = LecturaSondeo.backendCaido();

EstadoConexion _siguiente(
  EstadoConexion actual,
  List<LecturaSondeo> historial, {
  bool hayInterfaz = true,
  Duration tiempoDegradado = Duration.zero,
}) {
  return PoliticaConexion.siguiente(
    actual: actual,
    hayInterfaz: hayInterfaz,
    historial: historial,
    tiempoDegradado: tiempoDegradado,
  );
}

void main() {
  group('PoliticaConexion.siguiente', () {
    test('sin interfaz es sin Internet, diga lo que diga el historial', () {
      expect(
        _siguiente(EstadoConexion.estable, [
          _rapido,
          _rapido,
        ], hayInterfaz: false),
        EstadoConexion.sinInternet,
      );
    });

    test('sin sondeos se queda donde está', () {
      expect(
        _siguiente(EstadoConexion.verificando, const []),
        EstadoConexion.verificando,
      );
    });

    test('el primer sondeo sano confirma la conexión', () {
      expect(
        _siguiente(EstadoConexion.verificando, [_rapido]),
        EstadoConexion.estable,
      );
    });

    test(
      'un sondeo sin respuesta degrada a inestable; dos, a sin Internet',
      () {
        expect(
          _siguiente(EstadoConexion.estable, [_rapido, _caido]),
          EstadoConexion.inestable,
        );
        expect(
          _siguiente(EstadoConexion.inestable, [_rapido, _caido, _caido]),
          EstadoConexion.sinInternet,
        );
      },
    );

    test('con Internet pero sin backend es un problema de base de datos', () {
      expect(
        _siguiente(EstadoConexion.estable, [_rapido, _sinBase]),
        EstadoConexion.inestable,
        reason: 'un solo sondeo todavía puede ser un parpadeo',
      );
      expect(
        _siguiente(EstadoConexion.inestable, [_rapido, _sinBase, _sinBase]),
        EstadoConexion.sinBackend,
      );
    });

    test('entre fallos mixtos manda el último sondeo', () {
      expect(
        _siguiente(EstadoConexion.inestable, [_rapido, _sinBase, _caido]),
        EstadoConexion.sinInternet,
      );
      expect(
        _siguiente(EstadoConexion.sinInternet, [_caido, _caido, _sinBase]),
        EstadoConexion.sinBackend,
      );
    });

    test('la base de datos que vuelve también debe ganarse estable', () {
      expect(
        _siguiente(EstadoConexion.sinBackend, [_sinBase, _sinBase, _rapido]),
        EstadoConexion.inestable,
      );
    });

    test('dos sondeos lentos de tres degradan; uno solo no', () {
      expect(
        _siguiente(EstadoConexion.estable, [_lento, _rapido, _lento]),
        EstadoConexion.inestable,
      );
      expect(
        _siguiente(EstadoConexion.estable, [_rapido, _rapido, _lento]),
        EstadoConexion.estable,
      );
    });

    test('degradado, la respuesta no basta: hay que ganarse volver', () {
      expect(
        _siguiente(EstadoConexion.sinInternet, [_caido, _caido, _rapido]),
        EstadoConexion.inestable,
      );
      expect(
        _siguiente(EstadoConexion.inestable, [
          _rapido,
          _rapido,
        ], tiempoDegradado: const Duration(minutes: 5)),
        EstadoConexion.inestable,
        reason: 'faltan sondeos sanos',
      );
    });

    test('vuelve a estable con tres sondeos sanos y la permanencia mínima', () {
      expect(
        _siguiente(EstadoConexion.inestable, [
          _rapido,
          _rapido,
          _rapido,
        ], tiempoDegradado: const Duration(seconds: 10)),
        EstadoConexion.inestable,
        reason: 'no cumplió la permanencia mínima',
      );
      expect(
        _siguiente(EstadoConexion.inestable, [
          _rapido,
          _rapido,
          _rapido,
        ], tiempoDegradado: PoliticaConexion.permanenciaMinimaDegradado),
        EstadoConexion.estable,
      );
    });

    test('para volver no alcanza con "no lento": tiene que ser rápido', () {
      expect(
        _siguiente(EstadoConexion.inestable, [
          _regular,
          _regular,
          _regular,
        ], tiempoDegradado: const Duration(minutes: 5)),
        EstadoConexion.inestable,
      );
    });
  });

  group('PoliticaConexion.usaServidor', () {
    test('con copia local, solo la conexión estable usa el servidor', () {
      expect(
        PoliticaConexion.usaServidor(
          EstadoConexion.estable,
          soportaCopiaLocal: true,
        ),
        isTrue,
      );
      expect(
        PoliticaConexion.usaServidor(
          EstadoConexion.verificando,
          soportaCopiaLocal: true,
        ),
        isTrue,
      );
      expect(
        PoliticaConexion.usaServidor(
          EstadoConexion.inestable,
          soportaCopiaLocal: true,
        ),
        isFalse,
      );
    });

    test('sin copia local (web) sigue en línea mientras haya respuesta', () {
      expect(
        PoliticaConexion.usaServidor(
          EstadoConexion.inestable,
          soportaCopiaLocal: false,
        ),
        isTrue,
      );
      expect(
        PoliticaConexion.usaServidor(
          EstadoConexion.sinInternet,
          soportaCopiaLocal: false,
        ),
        isFalse,
      );
      expect(
        PoliticaConexion.usaServidor(
          EstadoConexion.sinBackend,
          soportaCopiaLocal: false,
        ),
        isFalse,
      );
    });
  });
}
