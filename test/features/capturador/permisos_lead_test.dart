import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/core/constants/app_role.dart';
import 'package:transworld_nexus/data/models/evento_lead.dart';
import 'package:transworld_nexus/data/models/lead.dart';
import 'package:transworld_nexus/data/models/perfil.dart';
import 'package:transworld_nexus/data/offline/sync_queue_item.dart';
import 'package:transworld_nexus/features/capturador/permisos_lead.dart';
import 'package:transworld_nexus/features/capturador/providers/capturador_providers.dart';

Perfil _perfil(String id, AppRole rol) =>
    Perfil(id: id, nombreCompleto: id, rol: rol);

const _lead = Lead(
  id: 'lead-1',
  eventoId: 'act-1',
  nombreCompleto: 'Ana Pérez',
  perfilId: 'capturador',
);

/// Actividad de 3 días: 20, 21 y 22 de octubre. Cierra el 24 a las 00:00.
final _actividad = EventoLead(
  id: 'act-1',
  nombre: 'FOREDE',
  fecha: DateTime(2026, 10, 20),
  duracionDias: 3,
);

void main() {
  test('el cierre es el fin del último día más 24 horas', () {
    expect(cierreLeadsPropios(_actividad), DateTime(2026, 10, 24));
  });

  group('capturador con su propio lead', () {
    final yo = _perfil('capturador', AppRole.user);

    test('mientras la actividad está abierta lo ve completo y lo toca', () {
      final p = permisosLead(
        perfil: yo,
        lead: _lead,
        actividad: _actividad,
        ahora: DateTime(2026, 10, 23, 18),
      );
      expect(p.verContacto, isTrue);
      expect(p.editar, isTrue);
      expect(p.eliminar, isTrue);
    });

    test('tras el cierre vuelve a quedar enmascarado y de solo lectura', () {
      final p = permisosLead(
        perfil: yo,
        lead: _lead,
        actividad: _actividad,
        ahora: DateTime(2026, 10, 24, 0, 1),
      );
      expect(p.verContacto, isFalse);
      expect(p.editar, isFalse);
      expect(p.eliminar, isFalse);
    });

    test('sin la actividad resuelta no expone nada', () {
      final p = permisosLead(perfil: yo, lead: _lead, actividad: null);
      expect(p.verContacto, isFalse);
      expect(p.editar, isFalse);
    });
  });

  test('un lead ajeno nunca se ve completo ni se toca', () {
    final p = permisosLead(
      perfil: _perfil('otro', AppRole.user),
      lead: _lead,
      actividad: _actividad,
      ahora: DateTime(2026, 10, 21),
    );
    expect(p.verContacto, isFalse);
    expect(p.editar, isFalse);
    expect(p.eliminar, isFalse);
  });

  test('admin y organizador no dependen del cierre', () {
    final despues = DateTime(2027);
    final admin = permisosLead(
      perfil: _perfil('admin', AppRole.admin),
      lead: _lead,
      actividad: _actividad,
      ahora: despues,
    );
    final organizador = permisosLead(
      perfil: _perfil('org', AppRole.organizador),
      lead: _lead,
      actividad: _actividad,
      ahora: despues,
    );
    expect(admin.verContacto && admin.editar && admin.eliminar, isTrue);
    expect(organizador.verContacto && organizador.editar, isTrue);
    expect(organizador.eliminar, isFalse);
  });

  test('un borrado encolado sin red saca el lead de la lista', () {
    final borrado = SyncQueueItem(
      id: 'cola-1',
      operation: SyncOperation.update,
      table: 'leads',
      payload: {
        'id': 'lead-1',
        'changes': {campoLeadEliminadoAt: '2026-10-21T12:00:00Z'},
      },
      createdAt: DateTime(2026, 10, 21),
      updatedAt: DateTime(2026, 10, 21),
      ownerId: 'capturador',
    );

    final lista = fusionarLeadsConCola(
      servidor: const [
        _lead,
        Lead(id: 'lead-2', eventoId: 'act-1', nombreCompleto: 'Luis'),
      ],
      colaDeLeads: [borrado],
      eventoId: 'act-1',
    );

    expect(lista.map((lead) => lead.id), ['lead-2']);
  });
}
