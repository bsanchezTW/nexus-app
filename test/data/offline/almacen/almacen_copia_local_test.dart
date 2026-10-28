import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/offline/almacen/almacen_copia_local.dart';
import 'package:transworld_nexus/data/offline/almacen/almacen_sqlite.dart';
import 'package:transworld_nexus/data/offline/almacen/copia_local_db.dart';

/// Registra lo que el almacén mandaría al disco.
class _AlmacenEspia extends AlmacenCopiaLocal {
  _AlmacenEspia() : super.enMemoria();

  final cambios = <CambioCopiaLocal>[];

  @override
  Future<void> persistir(CambioCopiaLocal cambio) async => cambios.add(cambio);
}

Map<String, dynamic> _persona(String id, {bool acreditado = false}) => {
  'id': id,
  'nombre_completo': 'Persona $id',
  'acreditado': acreditado,
};

void main() {
  group('AlmacenCopiaLocal', () {
    test(
      'lee lo guardado, en orden, y distingue vacío de nunca bajado',
      () async {
        final almacen = AlmacenCopiaLocal.enMemoria();
        await almacen.guardar('a', 'registrados', 'e1', [
          _persona('2'),
          _persona('1'),
        ]);
        await almacen.guardar('a', 'registrados', 'e2', const []);

        expect(almacen.leer('a', 'registrados', 'e1')!.map((f) => f['id']), [
          '2',
          '1',
        ]);
        expect(almacen.leer('a', 'registrados', 'e2'), isEmpty);
        expect(almacen.leer('a', 'registrados', 'e3'), isNull);
        expect(almacen.eventos('a', 'registrados'), {'e1', 'e2'});
        expect(almacen.leer('b', 'registrados', 'e1'), isNull);
      },
    );

    test('acreditar a una persona escribe solo esa fila', () async {
      final almacen = _AlmacenEspia();
      final filas = [for (var i = 0; i < 500; i++) _persona('$i')];
      await almacen.guardar('a', 'registrados', 'e1', filas);
      almacen.cambios.clear();

      final conUnaAcreditada = [...filas]
        ..[250] = _persona('250', acreditado: true);
      expect(
        await almacen.guardar('a', 'registrados', 'e1', conUnaAcreditada),
        isTrue,
      );

      final cambio = almacen.cambios.single;
      expect(cambio.filasNuevas.map((f) => f.id), ['250']);
      expect(cambio.idsBorrados, isEmpty);
    });

    test('un refresco idéntico no escribe nada', () async {
      final almacen = _AlmacenEspia();
      final filas = [_persona('1'), _persona('2')];
      await almacen.guardar('a', 'registrados', 'e1', filas);
      almacen.cambios.clear();

      expect(await almacen.guardar('a', 'registrados', 'e1', filas), isFalse);
      expect(almacen.cambios, isEmpty);
    });

    test('quitar y reordenar filas se refleja en el cambio', () async {
      final almacen = _AlmacenEspia();
      await almacen.guardar('a', 'registrados', 'e1', [
        _persona('1'),
        _persona('2'),
        _persona('3'),
      ]);
      almacen.cambios.clear();

      await almacen.guardar('a', 'registrados', 'e1', [
        _persona('3'),
        _persona('1'),
      ]);

      final cambio = almacen.cambios.single;
      expect(cambio.idsBorrados, ['2']);
      expect(
        {for (final f in cambio.filasNuevas) f.id: f.orden},
        {'3': 0, '1': 1},
      );
    });

    test('filas sin id o con id repetido se identifican por posición', () {
      final filas = AlmacenCopiaLocal.filasDe([
        {'total': 3},
        {'id': 'x'},
        {'id': 'x'},
      ]);
      expect(filas.map((f) => f.id), ['#0', 'x', '#2']);
    });

    test('borrar quita la entrada entera', () async {
      final almacen = _AlmacenEspia();
      await almacen.guardar('a', 'registrados', 'e1', [_persona('1')]);
      await almacen.borrar('a', 'registrados', 'e1');

      expect(almacen.leer('a', 'registrados', 'e1'), isNull);
      expect(almacen.cambios.last.borrarEntrada, isTrue);
    });
  });

  group('AlmacenSqlite', () {
    late CopiaLocalDb db;

    setUp(() {
      // Una sola conexión en memoria, compartida, para poder "reabrir".
      db = CopiaLocalDb(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
    });

    tearDown(() => db.close());

    test('lo guardado sobrevive a reabrir la base', () async {
      final almacen = await AlmacenSqlite.deBase(db);
      await almacen.guardar('a', 'registrados', 'e1', [
        _persona('2'),
        _persona('1', acreditado: true),
      ]);
      await almacen.guardar('a', 'registrados', 'vacio', const []);
      await almacen.esperarEscrituras();

      final reabierto = await AlmacenSqlite.deBase(db);
      final filas = reabierto.leer('a', 'registrados', 'e1')!;
      expect(filas.map((f) => f['id']), ['2', '1']);
      expect(filas.last['acreditado'], isTrue);
      expect(reabierto.leer('a', 'registrados', 'vacio'), isEmpty);
    });

    test('actualiza, quita filas y borra entradas en disco', () async {
      final almacen = await AlmacenSqlite.deBase(db);
      await almacen.guardar('a', 'registrados', 'e1', [
        _persona('1'),
        _persona('2'),
      ]);
      await almacen.guardar('a', 'leads', 'e1', [_persona('9')]);
      await almacen.guardar('a', 'registrados', 'e1', [
        _persona('2', acreditado: true),
      ]);
      await almacen.borrar('a', 'leads', 'e1');
      await almacen.esperarEscrituras();

      final reabierto = await AlmacenSqlite.deBase(db);
      expect(reabierto.leer('a', 'registrados', 'e1'), [
        _persona('2', acreditado: true),
      ]);
      expect(reabierto.leer('a', 'leads', 'e1'), isNull);
      expect(reabierto.eventos('a', 'leads'), isEmpty);
    });
  });
}
