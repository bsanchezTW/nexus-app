import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/models/evento.dart';
import 'package:transworld_nexus/data/models/evento_lead.dart';
import 'package:transworld_nexus/data/offline/snapshot_service.dart';
import 'package:transworld_nexus/data/offline/sync_queue_item.dart';

void main() {
  final hoy = DateTime.now();
  final ayer = hoy.subtract(const Duration(days: 1));
  final manana = hoy.add(const Duration(days: 1));

  Evento evento(
    String id, {
    required DateTime fecha,
    String? nombre,
    int duracionDias = 1,
  }) {
    return Evento(
      id: id,
      nombre: nombre ?? id,
      fecha: fecha,
      duracionDias: duracionDias,
    );
  }

  EventoLead actividad(
    String id, {
    required DateTime fecha,
    String? origenId,
    int duracionDias = 1,
  }) {
    return EventoLead(
      id: id,
      nombre: id,
      fecha: fecha,
      duracionDias: duracionDias,
      eventoOrigenId: origenId,
    );
  }

  group('SnapshotService.eventosDelSnapshot', () {
    test('baja los que aún no han ocurrido', () {
      final elegidos = SnapshotService.eventosDelSnapshot([
        evento('hoy', fecha: hoy),
        evento('futuro', fecha: manana),
      ]);

      expect(elegidos.map((e) => e.id), ['hoy', 'futuro']);
    });

    test('lo ya finalizado deja de bajarse', () {
      final elegidos = SnapshotService.eventosDelSnapshot([
        evento('pasado', fecha: ayer),
        evento('vigente', fecha: hoy),
      ]);

      expect(elegidos.map((e) => e.id), ['vigente']);
    });

    test(
      'un evento de varios días sigue bajándose aunque haya empezado ayer',
      () {
        final elegidos = SnapshotService.eventosDelSnapshot([
          evento('corta', fecha: ayer),
          evento('larga', fecha: ayer, duracionDias: 3),
        ]);

        expect(elegidos.map((e) => e.id), ['larga']);
      },
    );
  });

  group('SnapshotService.actividadesDelSnapshot', () {
    test('se refrescan las que siguen vigentes', () {
      final elegidas = SnapshotService.actividadesDelSnapshot([
        actividad('vieja', fecha: ayer),
        actividad('viva', fecha: hoy),
      ]);

      expect(elegidas.map((e) => e.id), ['viva']);
    });

    test('una de varios días sigue vigente aunque haya empezado ayer', () {
      final elegidas = SnapshotService.actividadesDelSnapshot([
        actividad('corta', fecha: ayer),
        actividad('larga', fecha: ayer, duracionDias: 3),
      ]);

      expect(elegidas.map((e) => e.id), ['larga']);
    });
  });

  group('SnapshotService.campanasDelSnapshot', () {
    test('el interno baja todas las actividades vigentes', () {
      final elegidas = SnapshotService.campanasDelSnapshot(
        actividades: [
          actividad('ajena', fecha: manana),
          actividad('propia', fecha: manana, origenId: 'evento-1'),
        ],
        eventosVisibles: [evento('evento-1', fecha: manana)],
        esExterno: false,
      );

      expect(elegidas.map((e) => e.id), ['ajena', 'propia']);
    });

    test('el externo solo baja las ligadas a sus eventos', () {
      final elegidas = SnapshotService.campanasDelSnapshot(
        actividades: [
          actividad('ajena', fecha: manana),
          actividad('por-id', fecha: manana, origenId: 'evento-1'),
          actividad('Expo', fecha: manana),
          actividad('pasada', fecha: ayer, origenId: 'evento-1'),
        ],
        eventosVisibles: [evento('evento-1', fecha: manana, nombre: 'Expo')],
        esExterno: true,
      );

      expect(elegidas.map((e) => e.id), ['por-id', 'Expo']);
    });
  });

  group('SnapshotService.esErrorSinAccesoResumen', () {
    test('reconoce el 42501 del RPC de conteos', () {
      const crudo =
          'PostgrestException(message: Sin acceso al resumen de la campaña, '
          'code: 42501, details: Forbidden, hint: null)';

      expect(SnapshotService.esErrorSinAccesoResumen(crudo), isTrue);
      expect(SnapshotService.esErrorSinAccesoResumen('timeout'), isFalse);
    });
  });

  group('SnapshotService.eventosAConservar', () {
    // Fecha fija: la política compara días y un test anclado a `now()` fallaría
    // al correr justo en un cambio de día.
    final ahora = DateTime(2026, 8, 21, 22, 0);

    test('conserva lo vigente y suelta lo caducado', () {
      final conservados = SnapshotService.eventosAConservar([
        evento('futuro', fecha: DateTime(2026, 9, 5)),
        evento('hoy', fecha: DateTime(2026, 8, 21)),
        evento('en-margen', fecha: DateTime(2026, 8, 20)),
        evento('viejo', fecha: DateTime(2026, 6, 1)),
      ], ahora: ahora);

      expect(conservados, {'futuro', 'hoy', 'en-margen'});
    });

    test('mira el último día, no el de inicio', () {
      final conservados = SnapshotService.eventosAConservar([
        evento('un-dia-vieja', fecha: DateTime(2026, 6, 1)),
        evento('multi-dia', fecha: DateTime(2026, 8, 18), duracionDias: 5),
      ], ahora: ahora);

      expect(conservados, {'multi-dia'});
    });

    test('lo caducado con escrituras pendientes no se toca', () {
      final conservados = SnapshotService.eventosAConservar(
        [evento('viejo', fecha: DateTime(2026, 6, 1))],
        protegidos: {'viejo'},
        ahora: ahora,
      );

      expect(conservados, {
        'viejo',
      }, reason: 'su caché es lo único que sostiene lo capturado sin red');
    });
  });

  group('SnapshotService.actividadesAConservar', () {
    final ahora = DateTime(2026, 8, 21, 22, 0);

    test('mira el último día, no el de inicio', () {
      final conservados = SnapshotService.actividadesAConservar([
        actividad('un-dia-vieja', fecha: DateTime(2026, 6, 1)),
        actividad('multi-dia', fecha: DateTime(2026, 8, 18), duracionDias: 5),
      ], ahora: ahora);

      expect(conservados, {'multi-dia'});
    });
  });

  group('SnapshotService.origenesAConservar', () {
    test('se indexa por el evento de origen, no por la actividad', () {
      final origenes = SnapshotService.origenesAConservar(
        [
          actividad('c1', fecha: DateTime(2026, 9, 1), origenId: 'evento-1'),
          actividad('c2', fecha: DateTime(2026, 9, 1), origenId: 'evento-2'),
        ],
        {'c1'},
      );

      expect(origenes, {'evento-1'});
    });

    test('una actividad externa sin origen no deja clave', () {
      final origenes = SnapshotService.origenesAConservar(
        [actividad('c1', fecha: DateTime(2026, 9, 1))],
        {'c1'},
      );

      expect(origenes, isEmpty);
    });
  });

  group('SnapshotService.idsConEscriturasPendientes', () {
    SyncQueueItem item(String id, String eventoId, SyncStatus status) {
      return SyncQueueItem(
        id: id,
        operation: SyncOperation.insert,
        table: 'registrados',
        payload: {'evento_id': eventoId},
        createdAt: DateTime(2026, 8, 21),
        updatedAt: DateTime(2026, 8, 21),
        status: status,
      );
    }

    test('protege los eventos con cola sin subir', () {
      final protegidos = SnapshotService.idsConEscriturasPendientes([
        item('1', 'evento-pendiente', SyncStatus.pending),
        item('2', 'evento-en-conflicto', SyncStatus.conflict),
        item('3', 'evento-ya-subido', SyncStatus.synced),
      ]);

      expect(protegidos, {'evento-pendiente', 'evento-en-conflicto'});
    });

    test('un payload sin evento no aporta nada', () {
      final protegidos = SnapshotService.idsConEscriturasPendientes([
        SyncQueueItem(
          id: '1',
          operation: SyncOperation.insert,
          table: 'registrados',
          payload: const {},
          createdAt: DateTime(2026, 8, 21),
          updatedAt: DateTime(2026, 8, 21),
          status: SyncStatus.pending,
        ),
      ]);

      expect(protegidos, isEmpty);
    });
  });
}
