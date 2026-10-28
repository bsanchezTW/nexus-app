import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transworld_nexus/data/offline/almacen/almacen_copia_local.dart';
import 'package:transworld_nexus/data/offline/almacen/migracion_preferencias.dart';

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

    expect(await migrarCopiaDesdePreferencias(prefs, almacen), 2);

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
    // La cola de pendientes no es parte de la copia: no se toca.
    expect(prefs.getString('sync_queue_v2_$_owner'), '[]');
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
