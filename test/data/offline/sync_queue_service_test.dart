import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:transworld_nexus/data/offline/almacen/almacen_copia_local.dart';
import 'package:transworld_nexus/data/offline/almacen/almacen_sqlite.dart';
import 'package:transworld_nexus/data/offline/almacen/copia_local_db.dart';
import 'package:transworld_nexus/data/offline/sync_queue_item.dart';
import 'package:transworld_nexus/data/offline/sync_queue_service.dart';

class _ConflictExecutor implements SyncExecutor {
  int calls = 0;

  @override
  String get table => 'leads';

  @override
  Future<void> onInsert(Map<String, dynamic> payload) async {
    calls++;
    throw const TerminalSyncConflictException(
      SyncConflict(
        code: 'lead_duplicate_other',
        message: 'Este lead ya fue registrado por Ana Pérez',
        primerCapturadorNombre: 'Ana Pérez',
      ),
    );
  }

  @override
  Future<void> onUpdate(Map<String, dynamic> payload) => onInsert(payload);
}

class _BlockingExecutor implements SyncExecutor {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  String get table => 'leads';

  @override
  Future<void> onInsert(Map<String, dynamic> payload) async {
    started.complete();
    await release.future;
  }

  @override
  Future<void> onUpdate(Map<String, dynamic> payload) => onInsert(payload);
}

/// Rechaza como duplicado el primer ítem y acepta el resto.
class _DuplicadoLuegoExitoExecutor implements SyncExecutor {
  final procesados = <String>[];

  @override
  String get table => 'leads';

  @override
  Future<void> onInsert(Map<String, dynamic> payload) async {
    final nombre = payload['nombre_completo'] as String;
    procesados.add(nombre);
    if (nombre == 'Duplicada') {
      throw const SyncDiscardedException(
        'Este lead ya fue registrado por Ana Pérez',
      );
    }
  }

  @override
  Future<void> onUpdate(Map<String, dynamic> payload) => onInsert(payload);
}

void main() {
  group('esIdSoloLocal', () {
    test('reconoce el id temporal de un insert encolado', () {
      expect(esIdSoloLocal('${syncLocalIdPrefix}abc-123'), isTrue);
    });

    test('un uuid del servidor no es local', () {
      expect(esIdSoloLocal('a1b2c3d4-e5f6-7890-abcd-ef1234567890'), isFalse);
    });

    test('no confunde un uuid que contenga "local" más adelante', () {
      expect(esIdSoloLocal('abc-local_123'), isFalse);
    });
  });

  group('SyncQueueService por usuario', () {
    test('cambiar de cuenta no expone ni procesa la cola anterior', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final almacen = AlmacenCopiaLocal.enMemoria();
      final queueA = SyncQueueService(prefs, almacen, 'usuario-a');
      await queueA.enqueueInsert(
        table: 'leads',
        payload: {'perfil_id': 'usuario-a'},
      );

      final queueB = SyncQueueService(prefs, almacen, 'usuario-b');
      expect(queueB.state, isEmpty);
      final restoredA = SyncQueueService(prefs, almacen, 'usuario-a');
      expect(restoredA.state, hasLength(1));
    });

    test('un conflicto es terminal y conserva datos estructurados', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final almacen = AlmacenCopiaLocal.enMemoria();
      final queue = SyncQueueService(prefs, almacen, 'usuario-a');
      await queue.enqueueInsert(
        table: 'leads',
        payload: {'perfil_id': 'usuario-a'},
      );
      final executor = _ConflictExecutor();

      await queue.processPending({'leads': executor});
      expect(queue.state.single.status, SyncStatus.conflict);
      expect(queue.state.single.conflict?.primerCapturadorNombre, 'Ana Pérez');
      expect(queue.pendingFor('leads'), isEmpty);

      await queue.processPending({'leads': executor});
      expect(executor.calls, 1, reason: 'no debe reintentar conflictos');

      final discarded = await queue.discardConflict(queue.state.single.id);
      expect(discarded?.conflict?.primerCapturadorNombre, 'Ana Pérez');
      expect(queue.state, isEmpty);
    });

    test(
      'no pierde una edición mientras el insert está sincronizando',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final almacen = AlmacenCopiaLocal.enMemoria();
        final queue = SyncQueueService(prefs, almacen, 'usuario-a');
        final localId = await queue.enqueueInsert(
          table: 'leads',
          payload: {'perfil_id': 'usuario-a', 'nombre_completo': 'Original'},
        );
        final executor = _BlockingExecutor();

        final processing = queue.processPending({'leads': executor});
        await executor.started.future;

        await expectLater(
          queue.enqueueUpdate(
            table: 'leads',
            entityId: localId,
            changes: {'nombre_completo': 'Editado'},
          ),
          throwsA(isA<SyncItemInFlightException>()),
        );

        executor.release.complete();
        expect(await processing, 1);
        expect(queue.state, isEmpty);
      },
    );

    test(
      'legacy inequívoco se adopta y el resto queda en cuarentena',
      () async {
        final now = DateTime.utc(2026, 8, 12);
        final propio = SyncQueueItem(
          id: 'propio',
          operation: SyncOperation.insert,
          table: 'leads',
          payload: const {'perfil_id': 'usuario-a'},
          createdAt: now,
          updatedAt: now,
        );
        final ambiguo = SyncQueueItem(
          id: 'ambiguo',
          operation: SyncOperation.insert,
          table: 'registrados',
          payload: const {},
          createdAt: now,
          updatedAt: now,
        );
        SharedPreferences.setMockInitialValues({
          'sync_queue_v1': jsonEncode([propio.toJson(), ambiguo.toJson()]),
        });
        final prefs = await SharedPreferences.getInstance();
        final almacen = AlmacenCopiaLocal.enMemoria();
        final queue = SyncQueueService(prefs, almacen, 'usuario-a');

        expect(await queue.migrateLegacyIfUnambiguous(), 1);
        expect(queue.state.single.id, 'propio');
        expect(
          prefs.getString('sync_queue_v2_quarantine'),
          contains('ambiguo'),
        );
        expect(prefs.getString('sync_queue_v1'), isNull);
      },
    );
  });

  group('duplicados del servidor', () {
    Future<SyncQueueService> colaCon(List<String> nombres) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final almacen = AlmacenCopiaLocal.enMemoria();
      final cola = SyncQueueService(prefs, almacen, 'usuario-a');
      for (final nombre in nombres) {
        await cola.enqueueInsert(
          table: 'leads',
          payload: {'nombre_completo': nombre},
        );
      }
      return cola;
    }

    test('un duplicado se omite y la cola sigue con el resto', () async {
      final cola = await colaCon(['Duplicada', 'Nueva']);
      final executor = _DuplicadoLuegoExitoExecutor();

      final sincronizados = await cola.processPending({'leads': executor});

      // El duplicado no cuenta como sincronizado, pero tampoco frena la fila:
      // en feria una hoja modal por cada repetido detiene la entrada.
      expect(sincronizados, 1);
      expect(executor.procesados, ['Duplicada', 'Nueva']);
      expect(cola.state, isEmpty);
      expect(cola.pendingCount, 0);
      expect(cola.conflicts, isEmpty);
    });

    test(
      'el insert offline conserva foto local y los datos del lead',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final almacen = AlmacenCopiaLocal.enMemoria();
        final cola = SyncQueueService(prefs, almacen, 'usuario-a');
        await cola.enqueueInsert(
          table: 'leads',
          payload: {
            'nombre_completo': 'María González',
            'empresa': 'Transworld',
            'email': 'maria@transworld.cl',
            'fotos_urls': ['local_foto:///datos/leads_pendientes/a.jpg'],
          },
        );

        expect(cola.state.single.payload['fotos_urls'], [
          'local_foto:///datos/leads_pendientes/a.jpg',
        ]);
        expect(cola.state.single.payload['nombre_completo'], 'María González');
        expect(cola.state.single.payload['empresa'], 'Transworld');
        expect(cola.state.single.payload['email'], 'maria@transworld.cl');
      },
    );

    test('el motivo queda disponible para avisar una sola vez', () async {
      final cola = await colaCon(['Duplicada']);
      await cola.processPending({'leads': _DuplicadoLuegoExitoExecutor()});

      expect(cola.descartes, ['Este lead ya fue registrado por Ana Pérez']);
      cola.limpiarDescartes();
      expect(cola.descartes, isEmpty);
    });
  });

  group('SyncQueueService en SQLite', () {
    test('lo encolado sobrevive a reabrir la base', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = CopiaLocalDb(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      addTearDown(db.close);

      final cola = SyncQueueService(
        prefs,
        await AlmacenSqlite.deBase(db),
        'usuario-a',
      );
      final id = await cola.enqueueInsert(
        table: 'leads',
        payload: {'nombre_completo': 'Ana'},
      );
      await cola.enqueueUpdate(
        table: 'registrados',
        entityId: 'persona-1',
        changes: {'acreditado': true},
      );

      final reabierta = SyncQueueService(
        prefs,
        await AlmacenSqlite.deBase(db),
        'usuario-a',
      );
      expect(reabierta.state.map((i) => i.table), ['leads', 'registrados']);
      expect(reabierta.state.first.id, id);
      expect(reabierta.state.last.payload['changes'], {'acreditado': true});
    });

    test('sincronizar un ítem lo saca también del disco', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = CopiaLocalDb(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );
      addTearDown(db.close);

      final cola = SyncQueueService(
        prefs,
        await AlmacenSqlite.deBase(db),
        'usuario-a',
      );
      await cola.enqueueInsert(
        table: 'leads',
        payload: {'nombre_completo': 'Ok'},
      );
      await cola.processPending({'leads': _DuplicadoLuegoExitoExecutor()});

      final reabierta = SyncQueueService(
        prefs,
        await AlmacenSqlite.deBase(db),
        'usuario-a',
      );
      expect(reabierta.state, isEmpty);
    });
  });
}
