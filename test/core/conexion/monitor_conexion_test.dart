import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/core/conexion/estado_conexion.dart';
import 'package:transworld_nexus/core/conexion/monitor_conexion.dart';
import 'package:transworld_nexus/core/conexion/politica_conexion.dart';

const _rapido = LecturaSondeo.respondio(Duration(milliseconds: 200));
const _caido = LecturaSondeo.sinRespuesta();

/// Sondeo guionado: entrega las lecturas en orden y repite la última.
class _Guion {
  _Guion(Iterable<LecturaSondeo> lecturas) : _cola = Queue.of(lecturas);

  final Queue<LecturaSondeo> _cola;
  LecturaSondeo? _ultima;
  int llamadas = 0;

  Future<LecturaSondeo> call() async {
    llamadas++;
    if (_cola.isNotEmpty) _ultima = _cola.removeFirst();
    return _ultima ?? _rapido;
  }

  void despues(Iterable<LecturaSondeo> lecturas) => _cola.addAll(lecturas);
}

/// Reloj que avanza junto con el tiempo falso del test.
class _Reloj {
  DateTime ahora = DateTime(2026, 10, 28, 9);

  DateTime call() => ahora;
}

Future<void> _avanzar(WidgetTester tester, _Reloj reloj, Duration d) async {
  reloj.ahora = reloj.ahora.add(d);
  await tester.pump(d);
}

void main() {
  testWidgets('sin iniciar no sondea y solo refleja la interfaz', (
    tester,
  ) async {
    final guion = _Guion(const [_rapido]);
    final monitor = MonitorConexion(guion.call, hayInterfaz: false);
    addTearDown(monitor.dispose);

    expect(monitor.state, EstadoConexion.sinInternet);
    monitor.interfazCambio(true);
    expect(monitor.state, EstadoConexion.verificando);

    await tester.pump(const Duration(minutes: 1));
    expect(guion.llamadas, 0);
  });

  testWidgets('el primer sondeo sano confirma estable', (tester) async {
    final guion = _Guion(const [_rapido]);
    final monitor = MonitorConexion(guion.call);
    addTearDown(monitor.dispose);

    monitor.iniciar();
    await tester.pump();

    expect(monitor.state, EstadoConexion.estable);
    monitor.pausar();
  });

  testWidgets('un fallo real degrada al instante y volver exige histéresis', (
    tester,
  ) async {
    final reloj = _Reloj();
    final guion = _Guion(const [_rapido]);
    final monitor = MonitorConexion(guion.call, reloj: reloj.call);
    addTearDown(monitor.dispose);

    monitor.iniciar();
    await tester.pump();
    expect(monitor.state, EstadoConexion.estable);

    monitor.reportarFallo();
    expect(monitor.state, EstadoConexion.inestable);

    // Tres sondeos sanos (cada 5 s) todavía no cumplen los 30 s.
    for (var i = 0; i < 3; i++) {
      await _avanzar(tester, reloj, PoliticaConexion.intervaloDegradado);
    }
    expect(monitor.state, EstadoConexion.inestable);

    // Al cumplir la permanencia mínima vuelve con el siguiente sondeo sano.
    while (monitor.state != EstadoConexion.estable) {
      await _avanzar(tester, reloj, PoliticaConexion.intervaloDegradado);
      expect(
        reloj.ahora.difference(DateTime(2026, 10, 28, 9)),
        lessThanOrEqualTo(const Duration(seconds: 40)),
      );
    }
    monitor.pausar();
  });

  testWidgets('sondeos sin respuesta llevan a sin Internet', (tester) async {
    final reloj = _Reloj();
    final guion = _Guion(const [_rapido]);
    final monitor = MonitorConexion(guion.call, reloj: reloj.call);
    addTearDown(monitor.dispose);

    monitor.iniciar();
    await tester.pump();
    guion.despues(const [_caido]);

    await _avanzar(tester, reloj, PoliticaConexion.intervaloEstable);
    expect(monitor.state, EstadoConexion.inestable);
    await _avanzar(tester, reloj, PoliticaConexion.intervaloDegradado);
    expect(monitor.state, EstadoConexion.sinInternet);
    monitor.pausar();
  });

  testWidgets('perder la interfaz es sin Internet de inmediato', (
    tester,
  ) async {
    final guion = _Guion(const [_rapido]);
    final monitor = MonitorConexion(guion.call, hayInterfaz: true);
    addTearDown(monitor.dispose);

    monitor.iniciar();
    await tester.pump();
    expect(monitor.state, EstadoConexion.estable);

    monitor.interfazCambio(false);
    expect(monitor.state, EstadoConexion.sinInternet);
    monitor.pausar();
  });

  testWidgets('en pausa no sondea y al volver confirma al tiro', (
    tester,
  ) async {
    final guion = _Guion(const [_rapido]);
    final monitor = MonitorConexion(guion.call);
    addTearDown(monitor.dispose);

    monitor.iniciar();
    await tester.pump();
    final antes = guion.llamadas;

    monitor.pausar();
    await tester.pump(const Duration(minutes: 2));
    expect(guion.llamadas, antes);

    monitor.reanudar();
    await tester.pump();
    expect(guion.llamadas, antes + 1);
    monitor.pausar();
  });
}
