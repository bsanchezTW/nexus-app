import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:transworld_nexus/core/network/connectivity_service.dart';
import 'package:transworld_nexus/data/models/evento.dart';
import 'package:transworld_nexus/data/models/evento_lead.dart';
import 'package:transworld_nexus/data/repositories/eventos_leads_repository.dart';
import 'package:transworld_nexus/features/capturador/services/evento_lead_interno_service.dart';

/// Registra por qué vía se resolvió el evento de leads, para distinguir el
/// vínculo por id del viejo match por nombre.
class FakeEventosLeadsRepository extends EventosLeadsRepository {
  FakeEventosLeadsRepository({this.existente})
    : super(
        SupabaseClient(
          'http://localhost',
          'fake-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final EventoLead? existente;

  final List<String> origenesBuscados = [];
  final List<String> nombresBuscados = [];
  final List<EventoLead> creados = [];

  @override
  Future<EventoLead?> buscarPorEventoOrigen(String eventoOrigenId) async {
    origenesBuscados.add(eventoOrigenId);
    return existente;
  }

  @override
  Future<EventoLead?> buscarPorNombre(String nombre) async {
    nombresBuscados.add(nombre);
    return null;
  }

  @override
  Future<EventoLead> crear(EventoLead evento) async {
    creados.add(evento);
    return EventoLead(
      id: 'evento-lead-nuevo',
      nombre: evento.nombre,
      fecha: evento.fecha,
      duracionDias: evento.duracionDias,
      pais: evento.pais,
      tematica: evento.tematica,
      eventoOrigenId: evento.eventoOrigenId,
      tipo: evento.tipo,
      imagenUrl: evento.imagenUrl,
    );
  }
}

Future<EventoLead> _resolver(
  WidgetTester tester, {
  required FakeEventosLeadsRepository repo,
  required Evento evento,
}) async {
  late WidgetRef capturado;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eventosLeadsRepositoryProvider.overrideWithValue(repo),
        connectivityStreamProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          capturado = ref;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pump();

  return obtenerOCrearEventoLeadInterno(capturado, evento);
}

void main() {
  final evento = Evento(
    id: 'evento-1',
    nombre: 'Transworld Connect',
    fecha: DateTime(2026, 9, 12),
    pais: 'Chile',
    tematica: 'Telecomunicaciones',
    imagenUrl: 'https://cdn.example/connect.jpg',
    duracionDias: 3,
  );

  testWidgets('el primer lead crea el evento de leads interno vinculado', (
    tester,
  ) async {
    final repo = FakeEventosLeadsRepository();

    final resuelto = await _resolver(tester, repo: repo, evento: evento);

    expect(repo.creados, hasLength(1));
    expect(repo.creados.single.eventoOrigenId, 'evento-1');
    expect(repo.creados.single.tipo, TipoEventoLead.interno);
    expect(repo.creados.single.pais, 'Chile');
    expect(repo.creados.single.imagenUrl, 'https://cdn.example/connect.jpg');
    expect(repo.creados.single.duracionDias, 3);
    expect(resuelto.id, 'evento-lead-nuevo');
  });

  testWidgets('el segundo lead reutiliza el mismo evento de leads', (
    tester,
  ) async {
    final repo = FakeEventosLeadsRepository(
      existente: EventoLead.internoDesdeEvento(
        eventoOrigenId: 'evento-1',
        nombre: 'Transworld Connect',
        fecha: DateTime(2026, 9, 12),
      ).copyWith(),
    );

    final resuelto = await _resolver(tester, repo: repo, evento: evento);

    expect(repo.creados, isEmpty);
    expect(repo.origenesBuscados, ['evento-1']);
    expect(resuelto.eventoOrigenId, 'evento-1');
  });

  testWidgets('un homónimo suelto ya no se adopta como interno', (
    tester,
  ) async {
    final repo = FakeEventosLeadsRepository();

    await _resolver(tester, repo: repo, evento: evento);

    // Antes bastaba con el nombre para reusar una campaña ajena al evento.
    expect(repo.nombresBuscados, isEmpty);
    expect(repo.creados, hasLength(1));
  });
}
