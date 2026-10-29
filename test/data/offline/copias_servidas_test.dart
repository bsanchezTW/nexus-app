import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/offline/almacen/almacen_copia_local.dart';
import 'package:transworld_nexus/data/offline/offline_read_cache.dart';

const _tabla = 'registrados';
const _evento = 'evento-1';
const _clave = '$_tabla:$_evento';

Map<String, dynamic> _fila(String id) => {'id': id, 'nombre': 'Persona $id'};

/// Reloj fijo que se puede mover.
class _Reloj {
  DateTime ahora = DateTime(2026, 10, 29, 9);
  DateTime call() => ahora;
}

Future<List<Map<String, dynamic>>> _leer(
  OfflineReadCache cache, {
  required bool isOnline,
  required Future<List<Map<String, dynamic>>> Function() desdeServidor,
}) {
  return cache.leerCacheFirst<Map<String, dynamic>>(
    tabla: _tabla,
    eventoId: _evento,
    desdeServidor: desdeServidor,
    aFila: (f) => f,
    desdeFila: (f) => f,
    isOnline: isOnline,
    esperaMaximaServidor: const Duration(milliseconds: 30),
  );
}

/// Deja correr el microtask que publica los cambios.
Future<void> _publicar() => Future<void>.delayed(Duration.zero);

void main() {
  late _Reloj reloj;
  late AlmacenCopiaLocal almacen;
  late OfflineReadCache cache;

  setUp(() {
    reloj = _Reloj();
    almacen = AlmacenCopiaLocal.enMemoria();
    cache = OfflineReadCache(almacen, ownerId: 'u', reloj: reloj.call);
  });

  test('lo que entrega el servidor queda con su hora; un parche no', () async {
    await cache.guardar(_tabla, _evento, [_fila('1')]);
    expect(almacen.actualizadaEn('u', _tabla, _evento), reloj.ahora);

    final antes = reloj.ahora;
    reloj.ahora = antes.add(const Duration(hours: 1));
    await cache.parchearFila(
      tabla: _tabla,
      eventoId: _evento,
      id: '1',
      cambios: {'nombre': 'Otro'},
    );
    expect(almacen.actualizadaEn('u', _tabla, _evento), antes);

    // Una respuesta idéntica sigue siendo una confirmación.
    await cache.guardar(_tabla, _evento, [
      {'id': '1', 'nombre': 'Otro'},
    ]);
    expect(almacen.actualizadaEn('u', _tabla, _evento), reloj.ahora);
  });

  test('sin red, la lectura queda marcada como copia con su hora', () async {
    await cache.guardar(_tabla, _evento, [_fila('1')]);
    final confirmada = reloj.ahora;

    await _leer(
      cache,
      isOnline: false,
      desdeServidor: () async => throw StateError('no debería llamarse'),
    );
    await _publicar();

    expect(cache.copiasServidas.value, {_clave: confirmada});
  });

  test('el servidor lento la marca y su respuesta la desmarca', () async {
    await cache.guardar(_tabla, _evento, [_fila('1')]);
    final respuesta = Completer<List<Map<String, dynamic>>>();

    final servida = await _leer(
      cache,
      isOnline: true,
      desdeServidor: () => respuesta.future,
    );
    await _publicar();
    expect(servida.single['id'], '1');
    expect(cache.copiasServidas.value.keys, [_clave]);

    respuesta.complete([_fila('1'), _fila('2')]);
    await _publicar();
    await _publicar();
    expect(cache.copiasServidas.value, isEmpty);
  });

  test('cerrar la pantalla o recargar suelta la marca', () async {
    await cache.guardar(_tabla, _evento, [_fila('1')]);
    Future<void> sinRed() =>
        _leer(cache, isOnline: false, desdeServidor: () async => const []);

    await sinRed();
    cache.dejarDeMostrar(_tabla, _evento);
    await _publicar();
    expect(cache.copiasServidas.value, isEmpty);

    await sinRed();
    await _publicar();
    cache.olvidarCopiasServidas();
    await _publicar();
    expect(cache.copiasServidas.value, isEmpty);
  });

  test('una copia sin hora conocida igual se marca', () async {
    // Lo que vino de SharedPreferences no tenía hora.
    await almacen.guardar('u', _tabla, _evento, [_fila('1')]);

    await _leer(cache, isOnline: false, desdeServidor: () async => const []);
    await _publicar();

    expect(cache.copiasServidas.value, {_clave: null});
  });
}
