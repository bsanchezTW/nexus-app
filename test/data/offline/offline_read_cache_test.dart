import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transworld_nexus/data/models/lead.dart';
import 'package:transworld_nexus/data/offline/offline_read_cache.dart';

void main() {
  const tabla = 'leads';
  const eventoId = 'evento-1';

  final lead = Lead(
    id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    eventoId: eventoId,
    nombreCompleto: 'María González',
    empresa: 'Transworld',
    cargo: 'Gerente comercial',
    email: 'maria@transworld.cl',
    descripcion: 'Interesada en el plan anual.',
    createdAt: DateTime.utc(2026, 3, 14, 9, 30),
    vendedorNombre: 'Pedro Soto',
  );

  Future<OfflineReadCache> nuevaCache() async {
    SharedPreferences.setMockInitialValues({});
    return OfflineReadCache(
      await SharedPreferences.getInstance(),
      ownerId: 'usuario-a',
    );
  }

  Future<List<Lead>> leer(
    OfflineReadCache cache, {
    required Future<List<Lead>> Function() desdeServidor,
    String evento = eventoId,
    bool isOnline = true,
  }) {
    return cache.leerConRespaldo<Lead>(
      tabla: tabla,
      eventoId: evento,
      desdeServidor: desdeServidor,
      aFila: (l) => l.toCacheMap(),
      desdeFila: Lead.fromMap,
      isOnline: isOnline,
    );
  }

  group('OfflineReadCache.leerConRespaldo', () {
    test(
      'con servidor disponible devuelve lo fresco y guarda la copia',
      () async {
        final cache = await nuevaCache();

        final frescos = await leer(cache, desdeServidor: () async => [lead]);

        expect(frescos.single.nombreCompleto, 'María González');

        // La segunda lectura, ya offline, no toca el servidor.
        final desdeCache = await leer(
          cache,
          isOnline: false,
          desdeServidor: () async => throw Exception('Failed host lookup'),
        );
        expect(desdeCache.single.nombreCompleto, 'María González');
      },
    );

    test(
      'cuando el servidor falla sirve la última copia sin perder campos',
      () async {
        final cache = await nuevaCache();
        await leer(cache, desdeServidor: () async => [lead]);

        final desdeCache = await leer(
          cache,
          isOnline: false,
          desdeServidor: () async => throw Exception('Failed host lookup'),
        );

        final revivido = desdeCache.single;
        expect(revivido.id, lead.id);
        expect(revivido.empresa, lead.empresa);
        expect(revivido.cargo, lead.cargo);
        expect(revivido.email, lead.email);
        expect(revivido.descripcion, lead.descripcion);
        expect(revivido.createdAt, lead.createdAt);
        expect(revivido.vendedorNombre, lead.vendedorNombre);
      },
    );

    test(
      'sin copia previa propaga el error en vez de mentir con una lista vacía',
      () async {
        final cache = await nuevaCache();

        var llamado = false;
        expect(
          () => leer(
            cache,
            isOnline: false,
            desdeServidor: () async {
              llamado = true;
              throw Exception('Failed host lookup');
            },
          ),
          throwsA(isA<Exception>()),
        );
        expect(llamado, isFalse);
      },
    );

    test('la copia de un evento no responde por otro', () async {
      final cache = await nuevaCache();
      await leer(cache, desdeServidor: () async => [lead]);

      expect(
        () => leer(
          cache,
          evento: 'otro-evento',
          isOnline: false,
          desdeServidor: () async => throw Exception('Failed host lookup'),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('una carga posterior reemplaza la copia anterior', () async {
      final cache = await nuevaCache();
      await leer(cache, desdeServidor: () async => [lead]);

      final renombrado = lead.conCambiosPendientes({
        'nombre_completo': 'María González Pérez',
      });
      await leer(cache, desdeServidor: () async => [renombrado]);

      final desdeCache = await leer(
        cache,
        isOnline: false,
        desdeServidor: () async => throw Exception('Failed host lookup'),
      );
      expect(desdeCache.single.nombreCompleto, 'María González Pérez');
    });

    test(
      'un 403 jamás revive la copia aunque el dispositivo figure offline',
      () async {
        final cache = await nuevaCache();
        await leer(cache, desdeServidor: () async => [lead]);

        expect(
          () => leer(
            cache,
            desdeServidor: () async => throw Exception('403 permission denied'),
          ),
          throwsA(isA<Exception>()),
        );

        // La denegación purga la copia: una desconexión posterior no puede
        // volver a mostrar el evento revocado.
        expect(
          () => leer(
            cache,
            desdeServidor: () async => throw Exception('Failed host lookup'),
          ),
          throwsA(isA<Exception>()),
        );
      },
    );

    test(
      'una lista de autorizaciones resuelta purga eventos revocados',
      () async {
        final cache = await nuevaCache();
        await leer(cache, desdeServidor: () async => [lead]);
        await cache.retenerEventos(tabla, const {'otro-evento'});

        expect(
          () => leer(
            cache,
            desdeServidor: () async => throw Exception('Failed host lookup'),
          ),
          throwsA(isA<Exception>()),
        );
      },
    );

    test('un rol privado purga filas cacheadas de otros perfiles', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cache = OfflineReadCache(prefs, ownerId: 'usuario-a');
      await cache.guardar(tabla, eventoId, [
        {...lead.toCacheMap(), 'perfil_id': 'usuario-a'},
        {...lead.toCacheMap(), 'id': 'lead-ajeno', 'perfil_id': 'usuario-b'},
      ]);

      await cache.retenerFilasPropias(tabla, 'usuario-a');
      final visibles = await leer(
        cache,
        desdeServidor: () async => throw Exception('Failed host lookup'),
      );
      expect(visibles.map((item) => item.id), [lead.id]);
    });

    test('cada usuario lee únicamente su namespace', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final cacheA = OfflineReadCache(prefs, ownerId: 'usuario-a');
      final cacheB = OfflineReadCache(prefs, ownerId: 'usuario-b');
      await leer(cacheA, desdeServidor: () async => [lead]);

      expect(
        () => cacheB.leerConRespaldo<Lead>(
          tabla: tabla,
          eventoId: eventoId,
          desdeServidor: () async => throw Exception('Failed host lookup'),
          aFila: (l) => l.toCacheMap(),
          desdeFila: Lead.fromMap,
          isOnline: false,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('leerLocal devuelve la copia guardada sin ir al servidor', () async {
      final cache = await nuevaCache();
      await cache.guardar(tabla, eventoId, [lead.toCacheMap()]);

      final local = cache.leerLocal(
        tabla: tabla,
        eventoId: eventoId,
        desdeFila: Lead.fromMap,
      );
      expect(local, isNotNull);
      expect(local!.single.nombreCompleto, 'María González');
      expect(
        cache.leerLocal(
          tabla: tabla,
          eventoId: 'otro',
          desdeFila: Lead.fromMap,
        ),
        isNull,
      );
    });
  });

  group('OfflineReadCache ámbito global', () {
    test('guarda y lee tablas que no se particionan por evento', () async {
      final cache = await nuevaCache();
      await cache.guardarGlobal('perfil', [lead.toCacheMap()]);

      final local = cache.leerGlobal(tabla: 'perfil', desdeFila: Lead.fromMap);
      expect(local?.single.id, lead.id);
    });

    test('una purga de eventos revocados no toca el ámbito global', () async {
      final cache = await nuevaCache();
      await cache.guardarGlobal('perfil', [lead.toCacheMap()]);
      await cache.guardar('perfil', eventoId, [lead.toCacheMap()]);

      // El catálogo global no representa un evento y no está sujeto a la
      // lista de autorizaciones: sobrevive aunque no quede ninguno.
      await cache.retenerEventos('perfil', const {});

      expect(
        cache.leerGlobal(tabla: 'perfil', desdeFila: Lead.fromMap),
        isNotNull,
      );
      expect(
        cache.leerLocal(
          tabla: 'perfil',
          eventoId: eventoId,
          desdeFila: Lead.fromMap,
        ),
        isNull,
      );
    });
  });

  group('OfflineReadCache espera acotada al servidor', () {
    test('un servidor que nunca responde cae a la copia local', () async {
      final cache = await nuevaCache();
      await cache.guardar(tabla, eventoId, [lead.toCacheMap()]);

      // Wifi cautivo: la petición no falla, simplemente no vuelve. Sin el
      // timeout la pantalla se quedaría en `loading` con la copia buena
      // esperando en disco.
      final servido = await cache.leerConRespaldo<Lead>(
        tabla: tabla,
        eventoId: eventoId,
        desdeServidor: () => Completer<List<Lead>>().future,
        aFila: (l) => l.toCacheMap(),
        desdeFila: Lead.fromMap,
        isOnline: true,
        esperaMaximaServidor: const Duration(milliseconds: 50),
      );

      expect(servido.single.id, lead.id);
    });
  });

  group('OfflineReadCache credenciales', () {
    Future<List<Lead>> leerConJwtVencido(
      OfflineReadCache cache, {
      required bool isOnline,
    }) {
      return cache.leerConRespaldo<Lead>(
        tabla: tabla,
        eventoId: eventoId,
        desdeServidor: () async => throw Exception('JWT expired'),
        aFila: (l) => l.toCacheMap(),
        desdeFila: Lead.fromMap,
        isOnline: isOnline,
      );
    }

    test('un token vencido sin red conserva la copia de la feria', () async {
      final cache = await nuevaCache();
      await cache.guardar(tabla, eventoId, [lead.toCacheMap()]);

      // Sin red, un fallo de credencial lo levanta el propio SDK y no prueba
      // que el acceso haya sido revocado. Borrar aquí destruiría los datos
      // justo cuando no hay red para volver a bajarlos.
      final servido = await leerConJwtVencido(cache, isOnline: false);
      expect(servido.single.id, lead.id);

      expect(
        cache.leerLocal(
          tabla: tabla,
          eventoId: eventoId,
          desdeFila: Lead.fromMap,
        ),
        isNotNull,
      );
    });

    test('con red, un token rechazado sí purga la copia', () async {
      final cache = await nuevaCache();
      await cache.guardar(tabla, eventoId, [lead.toCacheMap()]);

      await expectLater(
        leerConJwtVencido(cache, isOnline: true),
        throwsA(isA<Exception>()),
      );
      expect(
        cache.leerLocal(
          tabla: tabla,
          eventoId: eventoId,
          desdeFila: Lead.fromMap,
        ),
        isNull,
      );
    });
  });

  group('OfflineReadCache migración v2', () {
    test('el blob por tabla se reparte en una clave por evento', () async {
      SharedPreferences.setMockInitialValues({
        'offline_read_cache_v2_usuario-a_$tabla': jsonEncode({
          eventoId: [lead.toCacheMap()],
          'evento-2': [
            {...lead.toCacheMap(), 'id': 'lead-2'},
          ],
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final cache = OfflineReadCache(prefs, ownerId: 'usuario-a');

      expect(
        cache
            .leerLocal(
              tabla: tabla,
              eventoId: eventoId,
              desdeFila: Lead.fromMap,
            )
            ?.single
            .id,
        lead.id,
      );
      expect(
        cache
            .leerLocal(
              tabla: tabla,
              eventoId: 'evento-2',
              desdeFila: Lead.fromMap,
            )
            ?.single
            .id,
        'lead-2',
      );

      // El índice queda poblado, así que la purga por revocación sigue
      // alcanzando a lo migrado.
      await cache.retenerEventos(tabla, {eventoId});
      expect(
        cache.leerLocal(
          tabla: tabla,
          eventoId: 'evento-2',
          desdeFila: Lead.fromMap,
        ),
        isNull,
      );
    });
  });

  group('OfflineReadCache.leerCacheFirst', () {
    Future<List<Lead>> leerFirst(
      OfflineReadCache cache, {
      required Future<List<Lead>> Function() desdeServidor,
      required bool isOnline,
      void Function()? onActualizado,
      int revision = 0,
      int epoca = 0,
      Duration esperaMaximaServidor = const Duration(milliseconds: 50),
    }) {
      return cache.leerCacheFirst<Lead>(
        tabla: tabla,
        eventoId: eventoId,
        desdeServidor: desdeServidor,
        aFila: (l) => l.toCacheMap(),
        desdeFila: Lead.fromMap,
        isOnline: isOnline,
        esperaMaximaServidor: esperaMaximaServidor,
        revision: revision,
        epoca: epoca,
        onActualizado: onActualizado,
      );
    }

    final renombrado = lead.conCambiosPendientes({
      'nombre_completo': 'María González Pérez',
    });

    String? nombreEnDisco(OfflineReadCache cache) => cache
        .leerLocal(tabla: tabla, eventoId: eventoId, desdeFila: Lead.fromMap)
        ?.single
        .nombreCompleto;

    /// Deja la época 0 confirmada sin cambiar el disco.
    Future<void> confirmarEpoca(OfflineReadCache cache) async {
      await leerFirst(cache, isOnline: true, desdeServidor: () async => [lead]);
    }

    test(
      'con copia local y servidor que no contesta cae al disco tras el tope',
      () async {
        final cache = await nuevaCache();
        await cache.guardar(tabla, eventoId, [lead.toCacheMap()]);

        final servido = await leerFirst(
          cache,
          isOnline: true,
          desdeServidor: () => Completer<List<Lead>>().future,
        );
        expect(servido.single.id, lead.id);
      },
    );

    test(
      'época sin confirmar: espera al servidor y entrega lo fresco sin avisar',
      () async {
        final cache = await nuevaCache();
        await cache.guardar(tabla, eventoId, [lead.toCacheMap()]);

        var avisos = 0;
        final servido = await leerFirst(
          cache,
          isOnline: true,
          onActualizado: () => avisos++,
          desdeServidor: () async => [renombrado],
        );

        expect(servido.single.nombreCompleto, 'María González Pérez');
        expect(nombreEnDisco(cache), 'María González Pérez');
        await Future<void>.delayed(Duration.zero);
        expect(avisos, 0);
      },
    );

    test(
      'época confirmada: sirve el disco y avisa cuando el servidor trae algo',
      () async {
        final cache = await nuevaCache();
        await cache.guardar(tabla, eventoId, [lead.toCacheMap()]);
        await confirmarEpoca(cache);

        final actualizado = Completer<void>();
        final servido = await leerFirst(
          cache,
          isOnline: true,
          onActualizado: actualizado.complete,
          desdeServidor: () async => [renombrado],
        );
        expect(servido.single.nombreCompleto, 'María González');

        await actualizado.future.timeout(const Duration(seconds: 2));
        expect(nombreEnDisco(cache), 'María González Pérez');
      },
    );

    test('una época nueva vuelve a exigir el servidor', () async {
      final cache = await nuevaCache();
      await cache.guardar(tabla, eventoId, [lead.toCacheMap()]);
      await confirmarEpoca(cache);

      final servido = await leerFirst(
        cache,
        isOnline: true,
        epoca: 1,
        desdeServidor: () async => [renombrado],
      );
      expect(servido.single.nombreCompleto, 'María González Pérez');
    });

    test(
      'servidor lento: tras el tope sirve disco y avisa al llegar la respuesta',
      () async {
        final cache = await nuevaCache();
        await cache.guardar(tabla, eventoId, [lead.toCacheMap()]);

        final respuesta = Completer<List<Lead>>();
        final actualizado = Completer<void>();
        final servido = await leerFirst(
          cache,
          isOnline: true,
          onActualizado: actualizado.complete,
          desdeServidor: () => respuesta.future,
        );
        expect(servido.single.nombreCompleto, 'María González');

        respuesta.complete([renombrado]);
        await actualizado.future.timeout(const Duration(seconds: 2));
        expect(nombreEnDisco(cache), 'María González Pérez');
      },
    );

    test(
      'si el provider se reconstruye con la consulta en vuelo, el aviso le '
      'llega al lector nuevo y no al destruido',
      () async {
        final cache = await nuevaCache();
        await cache.guardar(tabla, eventoId, [lead.toCacheMap()]);
        await confirmarEpoca(cache);

        final respuesta = Completer<List<Lead>>();
        var consultas = 0;
        Future<List<Lead>> servidor() {
          consultas++;
          return respuesta.future;
        }

        var avisosViejo = 0;
        final avisoNuevo = Completer<void>();
        await leerFirst(
          cache,
          isOnline: true,
          onActualizado: () => avisosViejo++,
          desdeServidor: servidor,
        );
        // Reconstrucción mientras la primera consulta sigue en el aire.
        await leerFirst(
          cache,
          isOnline: true,
          onActualizado: avisoNuevo.complete,
          desdeServidor: servidor,
        );

        respuesta.complete([renombrado]);
        await avisoNuevo.future.timeout(const Duration(seconds: 2));
        expect(avisosViejo, 0);
        expect(consultas, 1, reason: 'la consulta en vuelo se comparte');
      },
    );

    test('un parche durante la consulta en vuelo no se pisa', () async {
      final cache = await nuevaCache();
      await cache.guardar(tabla, eventoId, [lead.toCacheMap()]);
      await confirmarEpoca(cache);

      final respuestaVieja = Completer<List<Lead>>();
      await leerFirst(
        cache,
        isOnline: true,
        desdeServidor: () => respuestaVieja.future,
      );

      await cache.parchearFila(
        tabla: tabla,
        eventoId: eventoId,
        id: lead.id,
        cambios: {'nombre_completo': 'Editado en este teléfono'},
      );
      respuestaVieja.complete([lead]);
      await cache.esperarRevalidaciones();

      expect(nombreEnDisco(cache), 'Editado en este teléfono');
    });

    test('los fallos de red quedan registrados para avisar', () async {
      final cache = await nuevaCache();
      await cache.guardar(tabla, eventoId, [lead.toCacheMap()]);
      await confirmarEpoca(cache);

      await leerFirst(
        cache,
        isOnline: true,
        desdeServidor: () async => throw const SocketException('sin red'),
      );
      await cache.esperarRevalidaciones();

      expect(cache.consumirFallos(), 1);
      expect(cache.consumirFallos(), 0);
    });

    test('offline con copia no llama al servidor', () async {
      final cache = await nuevaCache();
      await cache.guardar(tabla, eventoId, [lead.toCacheMap()]);

      var llamado = false;
      final servido = await leerFirst(
        cache,
        isOnline: false,
        desdeServidor: () async {
          llamado = true;
          return [lead];
        },
      );
      expect(servido.single.id, lead.id);
      expect(llamado, isFalse);
    });

  });

  group('OfflineReadCache.parchearFila', () {
    test('actualiza una fila existente y deja las demás', () async {
      final cache = await nuevaCache();
      await cache.guardar('registrados', eventoId, [
        {'id': 'ana', 'acreditado': true, 'nombre': 'Ana'},
        {'id': 'bruno', 'acreditado': false, 'nombre': 'Bruno'},
      ]);

      final cambio = await cache.parchearFila(
        tabla: 'registrados',
        eventoId: eventoId,
        id: 'ana',
        cambios: {'acreditado': false},
      );

      expect(cambio, isTrue);
      final local = cache.leerLocal(
        tabla: 'registrados',
        eventoId: eventoId,
        desdeFila: (fila) => fila,
      );
      expect(
        local!.firstWhere((fila) => fila['id'] == 'ana')['acreditado'],
        isFalse,
      );
      expect(
        local.firstWhere((fila) => fila['id'] == 'bruno')['nombre'],
        'Bruno',
      );
    });

    test('no inventa una copia si el evento no está en disco', () async {
      final cache = await nuevaCache();
      final cambio = await cache.parchearFila(
        tabla: 'registrados',
        eventoId: eventoId,
        id: 'ana',
        cambios: {'acreditado': false},
      );
      expect(cambio, isFalse);
      expect(
        cache.leerLocal(
          tabla: 'registrados',
          eventoId: eventoId,
          desdeFila: (fila) => fila,
        ),
        isNull,
      );
    });

    test('omitir la revalidación no deja que un GET viejo pise el parche', () async {
      final cache = await nuevaCache();
      await cache.guardar('registrados', eventoId, [
        {'id': 'ana', 'acreditado': false},
      ]);
      await cache.parchearFila(
        tabla: 'registrados',
        eventoId: eventoId,
        id: 'ana',
        cambios: {'acreditado': true},
      );
      cache.omitirProximaRevalidacion('registrados', eventoId, 1);

      var servidor = 0;
      final local = await cache.leerCacheFirst<Map<String, dynamic>>(
        tabla: 'registrados',
        eventoId: eventoId,
        revision: 1,
        isOnline: true,
        desdeServidor: () async {
          servidor++;
          return [
            {'id': 'ana', 'acreditado': false},
          ];
        },
        aFila: (fila) => fila,
        desdeFila: (fila) => fila,
      );

      expect(servidor, 0);
      expect(local.single['acreditado'], isTrue);
    });
  });

  group('tieneEvento', () {
    test('responde por el índice, sin leer los datos', () async {
      final cache = await nuevaCache();
      await cache.guardar('registrados', 'evento-vigente', [
        {'id': 'ana'},
      ]);

      expect(cache.tieneEvento('registrados', 'evento-vigente'), isTrue);
      expect(cache.tieneEvento('registrados', 'evento-purgado'), isFalse);
    });

    test('una lista vacía sí cuenta como copia local', () async {
      // Un evento activo sin inscritos igual está descargado: sin esto la UI
      // lo marcaría como no disponible sin conexión.
      final cache = await nuevaCache();
      await cache.guardar('registrados', 'evento-sin-gente', []);

      expect(cache.tieneEvento('registrados', 'evento-sin-gente'), isTrue);
    });

    test('tras retenerEventos lo purgado deja de figurar', () async {
      final cache = await nuevaCache();
      await cache.guardar('registrados', 'vigente', [
        {'id': 'ana'},
      ]);
      await cache.guardar('registrados', 'vencido', [
        {'id': 'luis'},
      ]);

      await cache.retenerEventos('registrados', {'vigente'});

      expect(cache.tieneEvento('registrados', 'vigente'), isTrue);
      expect(cache.tieneEvento('registrados', 'vencido'), isFalse);
    });
  });
}
