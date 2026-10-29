import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transworld_nexus/data/offline/almacen/almacen_copia_local.dart';
import 'package:transworld_nexus/data/offline/almacen/migracion_preferencias.dart';
import 'package:transworld_nexus/data/offline/sync_queue_service.dart';

const _owner = '11111111-2222-3333-4444-555555555555';

void main() {
  test('la copia v3 pasa al almacén y sale de SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({
      'offline_read_cache_v3_${_owner}_registrados:evento-1': jsonEncode([
        {'id': 'p1', 'nombre_completo': 'Ana'},
      ]),
      'offline_read_cache_v3_${_owner}_catalogo_eventos:__global__': jsonEncode(
        [
          {'id': 'evento-1'},
        ],
      ),
      'offline_read_cache_v3_${_owner}_registrados__idx': jsonEncode([
        'evento-1',
      ]),
      'sync_queue_v2_$_owner': '[]',
    });
    final prefs = await SharedPreferences.getInstance();
    final almacen = AlmacenCopiaLocal.enMemoria();

    // Dos entradas de la copia y la cola (vacía).
    expect(await migrarCopiaDesdePreferencias(prefs, almacen), 3);

    expect(almacen.leer(_owner, 'registrados', 'evento-1'), [
      {'id': 'p1', 'nombre_completo': 'Ana'},
    ]);
    expect(almacen.leer(_owner, 'catalogo_eventos', '__global__'), [
      {'id': 'evento-1'},
    ]);
    expect(
      prefs.getKeys().where((k) => k.startsWith('offline_read_cache')),
      isEmpty,
    );
    expect(prefs.getString('sync_queue_v2_$_owner'), isNull);
    expect(
      almacen.leer(_owner, tablaColaPendientes, entradaColaPendientes),
      isEmpty,
    );
  });

  test('si un evento quedó en v2 y v3, gana la v3', () async {
    SharedPreferences.setMockInitialValues({
      'offline_read_cache_v2_${_owner}_registrados': jsonEncode({
        'evento-1': [
          {'id': 'p1', 'acreditado': false},
        ],
        'evento-2': [
          {'id': 'p2'},
        ],
      }),
      'offline_read_cache_v3_${_owner}_registrados:evento-1': jsonEncode([
        {'id': 'p1', 'acreditado': true},
      ]),
    });
    final prefs = await SharedPreferences.getInstance();
    final almacen = AlmacenCopiaLocal.enMemoria();

    await migrarCopiaDesdePreferencias(prefs, almacen);

    expect(almacen.leer(_owner, 'registrados', 'evento-1'), [
      {'id': 'p1', 'acreditado': true},
    ]);
    expect(almacen.leer(_owner, 'registrados', 'evento-2'), [
      {'id': 'p2'},
    ]);
  });

  test('la v1 mezclaba cuentas: va a cuarentena y no se adopta', () async {
    SharedPreferences.setMockInitialValues({
      'offline_read_cache_v1_registrados': '[{"id":"x"}]',
      'offline_read_cache_v3_quarantine_viejo': '[]',
    });
    final prefs = await SharedPreferences.getInstance();
    final almacen = AlmacenCopiaLocal.enMemoria();

    expect(await migrarCopiaDesdePreferencias(prefs, almacen), 0);

    expect(prefs.getString('offline_read_cache_v1_registrados'), isNull);
    expect(
      prefs.getString('offline_read_cache_v3_quarantine_registrados'),
      '[{"id":"x"}]',
    );
    expect(prefs.getString('offline_read_cache_v3_quarantine_viejo'), '[]');
  });

  test('una entrada ilegible se descarta sin frenar al resto', () async {
    SharedPreferences.setMockInitialValues({
      'offline_read_cache_v3_${_owner}_registrados:roto': '{no es json',
      'offline_read_cache_v3_${_owner}_registrados:bien': '[{"id":"ok"}]',
    });
    final prefs = await SharedPreferences.getInstance();
    final almacen = AlmacenCopiaLocal.enMemoria();

    expect(await migrarCopiaDesdePreferencias(prefs, almacen), 1);
    expect(almacen.leer(_owner, 'registrados', 'bien'), [
      {'id': 'ok'},
    ]);
    expect(almacen.leer(_owner, 'registrados', 'roto'), isNull);
    expect(prefs.getKeys(), isEmpty);
  });

  group('cola de pendientes', () {
    Map<String, dynamic> item(String id) => {
      'id': id,
      'operation': 'insert',
      'table': 'leads',
      'payload': {'id': id},
      'status': 'pending',
    };

    test('pasa al almacén en orden y sale de SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'sync_queue_v2_$_owner': jsonEncode([item('local_1'), item('local_2')]),
        'sync_queue_v2_quarantine': '[]',
        'sync_queue_v2_quarantine_raw': 'x',
        'sync_queue_v1': '[]',
      });
      final prefs = await SharedPreferences.getInstance();
      final almacen = AlmacenCopiaLocal.enMemoria();

      await migrarCopiaDesdePreferencias(prefs, almacen);

      expect(
        almacen
            .leer(_owner, tablaColaPendientes, entradaColaPendientes)!
            .map((i) => i['id']),
        ['local_1', 'local_2'],
      );
      expect(prefs.getString('sync_queue_v2_$_owner'), isNull);
      // La cuarentena y la cola v1 sin dueño las maneja SyncQueueService.
      expect(prefs.getString('sync_queue_v2_quarantine'), '[]');
      expect(prefs.getString('sync_queue_v2_quarantine_raw'), 'x');
      expect(prefs.getString('sync_queue_v1'), '[]');
    });

    test(
      'fusiona sin perder pendientes que ya estaban en el almacén',
      () async {
        SharedPreferences.setMockInitialValues({
          'sync_queue_v2_$_owner': jsonEncode([
            item('local_1'),
            item('local_2'),
          ]),
        });
        final prefs = await SharedPreferences.getInstance();
        final almacen = AlmacenCopiaLocal.enMemoria();
        // Una migración anterior copió local_1 y la app encoló local_3 después.
        await almacen.guardar(
          _owner,
          tablaColaPendientes,
          entradaColaPendientes,
          [
            {...item('local_1'), 'status': 'failed'},
            item('local_3'),
          ],
        );

        await migrarCopiaDesdePreferencias(prefs, almacen);

        final cola = almacen.leer(
          _owner,
          tablaColaPendientes,
          entradaColaPendientes,
        )!;
        expect(cola.map((i) => i['id']), ['local_2', 'local_1', 'local_3']);
        expect(
          cola.firstWhere((i) => i['id'] == 'local_1')['status'],
          'failed',
          reason: 'ante el mismo id gana el del almacén',
        );
      },
    );

    test('una cola ilegible se queda en SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'sync_queue_v2_$_owner': '{roto',
      });
      final prefs = await SharedPreferences.getInstance();

      await migrarCopiaDesdePreferencias(prefs, AlmacenCopiaLocal.enMemoria());

      expect(prefs.getString('sync_queue_v2_$_owner'), '{roto');
    });
  });

  test('sin nada que migrar no toca nada', () async {
    SharedPreferences.setMockInitialValues({'otra_cosa': 'x'});
    final prefs = await SharedPreferences.getInstance();

    expect(
      await migrarCopiaDesdePreferencias(prefs, AlmacenCopiaLocal.enMemoria()),
      0,
    );
    expect(prefs.getString('otra_cosa'), 'x');
  });
}
