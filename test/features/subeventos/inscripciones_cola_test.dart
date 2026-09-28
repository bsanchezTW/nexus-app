import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transworld_nexus/core/constants/supabase_tables.dart';
import 'package:transworld_nexus/core/network/connectivity_service.dart';
import 'package:transworld_nexus/data/models/inscripcion_subevento.dart';
import 'package:transworld_nexus/data/offline/offline_read_cache.dart';
import 'package:transworld_nexus/data/offline/sync_queue_item.dart';
import 'package:transworld_nexus/data/repositories/inscripciones_subevento_repository.dart';
import 'package:transworld_nexus/features/subeventos/providers/inscripciones_providers.dart';

class _CacheEspia extends OfflineReadCache {
  _CacheEspia(super.prefs) : super(ownerId: 'admin-1');

  int parches = 0;

  @override
  Future<bool> parchearFila({
    required String tabla,
    required String eventoId,
    required String id,
    required Map<String, dynamic> cambios,
  }) async {
    parches++;
    return false;
  }
}

class _RepoRechaza extends Fake implements InscripcionesSubeventoRepository {
  @override
  Future<Map<String, dynamic>> marcarAsistencia({
    required String registradoId,
    required String subeventoId,
    bool asistio = true,
  }) async {
    return const {'ok': false, 'motivo': 'no_inscrito'};
  }
}

SyncQueueItem _item({
  required String id,
  required String registradoId,
  required String subeventoId,
}) {
  final ahora = DateTime.utc(2026, 12, 1);
  return SyncQueueItem(
    id: id,
    operation: SyncOperation.insert,
    table: SupabaseTables.inscripcionesSubevento,
    payload: {
      'accion': 'marcar_asistencia',
      'evento_id': 'evento-1',
      'registrado_id': registradoId,
      'subevento_id': subeventoId,
    },
    createdAt: ahora,
    updatedAt: ahora,
  );
}

void main() {
  test('la cola marca la fila existente y agrega la que no está', () {
    const existente = InscripcionSubevento(
      id: 'ins-1',
      eventoId: 'evento-1',
      registradoId: 'ana',
      subeventoId: 'taller-1',
      origen: 'app',
    );
    final fusion = fusionarInscripcionesConCola(
      servidor: const [existente],
      cola: [
        _item(id: 'cola-1', registradoId: 'ana', subeventoId: 'taller-1'),
        _item(id: 'cola-2', registradoId: 'luis', subeventoId: 'taller-1'),
      ],
      eventoId: 'evento-1',
    );

    expect(fusion, hasLength(2));
    expect(fusion.first.id, 'ins-1');
    expect(fusion.first.asistio, isTrue);
    expect(fusion.first.pendienteDeSincronizar, isTrue);
    expect(fusion.last.registradoId, 'luis');
    expect(fusion.last.asistio, isTrue);
    expect(fusion.last.pendienteDeSincronizar, isTrue);
  });

  testWidgets('un rechazo online no parchea la caché', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cache = _CacheEspia(prefs);
    Object? error;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isOnlineProvider.overrideWith((ref) => true),
          offlineReadCacheProvider.overrideWithValue(cache),
          inscripcionesSubeventoRepositoryProvider.overrideWithValue(
            _RepoRechaza(),
          ),
        ],
        child: MaterialApp(
          home: Consumer(
          builder: (context, ref, _) {
            return TextButton(
              onPressed: () async {
                try {
                  await persistirAsistenciaSubevento(
                    ref,
                    eventoId: 'evento-1',
                    registradoId: '11111111-1111-1111-1111-111111111111',
                    subeventoId: 'taller-1',
                    accion: 'marcar_asistencia',
                  );
                } catch (e) {
                  error = e;
                }
              },
              child: const Text('marcar'),
            );
          },
        ),
        ),
      ),
    );

    await tester.tap(find.text('marcar'));
    await tester.pumpAndSettle();

    expect(error, isA<AsistenciaRechazada>());
    expect((error! as AsistenciaRechazada).motivo, 'no_inscrito');
    expect(cache.parches, 0);
  });
}
