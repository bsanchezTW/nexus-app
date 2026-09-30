import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transworld_nexus/core/constants/app_role.dart';
import 'package:transworld_nexus/core/network/connectivity_service.dart';
import 'package:transworld_nexus/core/router/route_paths.dart';
import 'package:transworld_nexus/core/widgets/form_sections.dart';
import 'package:transworld_nexus/data/models/evento_lead.dart';
import 'package:transworld_nexus/data/models/lead.dart';
import 'package:transworld_nexus/data/models/lead_write_result.dart';
import 'package:transworld_nexus/data/models/perfil.dart';
import 'package:transworld_nexus/data/offline/offline_read_cache.dart';
import 'package:transworld_nexus/data/offline/sync_queue_service.dart';
import 'package:transworld_nexus/data/repositories/leads_repository.dart';
import 'package:transworld_nexus/features/auth/providers/auth_providers.dart';
import 'package:transworld_nexus/features/capturador/providers/capturador_providers.dart';
import 'package:transworld_nexus/features/capturador/screens/lista_leads_screen.dart';

class _FakeLeadsRepository extends Fake implements LeadsRepository {
  _FakeLeadsRepository(this.lead);

  Lead lead;

  @override
  Future<List<Lead>> listarPorEvento(String eventoId) async => [lead];

  @override
  Future<LeadWriteResult> actualizar(
    String id,
    Map<String, dynamic> changes,
  ) async {
    lead = lead
        .conCambiosPendientes(changes)
        .copyWith(pendienteDeSincronizar: false);
    return LeadWriteResult(outcome: LeadWriteOutcome.actualizado, leadId: id);
  }
}

void main() {
  testWidgets('al guardar un lead la lista muestra el cambio al volver', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cache = OfflineReadCache(prefs, ownerId: 'admin-1');
    const eventoId = 'campana-1';
    const original = Lead(
      id: 'lead-1',
      eventoId: eventoId,
      nombreCompleto: 'Lead anterior',
      email: 'lead@empresa.cl',
      perfilId: 'admin-1',
    );
    await cache.guardar(leadsCacheTabla(true), eventoId, [
      original.toCacheMap(),
    ]);
    final repo = _FakeLeadsRepository(original);

    final router = GoRouter(
      initialLocation: RoutePaths.verLeads(eventoId),
      routes: [
        GoRoute(
          path: '/capturador/:id/leads',
          builder: (_, _) => const ListaLeadsScreen(eventoId: eventoId),
        ),
        GoRoute(
          path: '/capturador/:eventoId/leads/:leadId',
          builder: (_, _) =>
              const DetalleLeadScreen(eventoId: eventoId, leadId: 'lead-1'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          offlineReadCacheProvider.overrideWithValue(cache),
          syncQueueActiveOwnerIdProvider.overrideWithValue('admin-1'),
          isOnlineProvider.overrideWith((ref) => true),
          currentPerfilProvider.overrideWith(
            (ref) async => const Perfil(
              id: 'admin-1',
              nombreCompleto: 'Admin',
              rol: AppRole.admin,
            ),
          ),
          eventoLeadByIdProvider.overrideWith(
            (ref, id) async => EventoLead(
              id: id,
              nombre: 'Campaña',
              fecha: DateTime(2030),
              pais: 'Chile',
            ),
          ),
          leadsRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lead anterior'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'Lead actualizado',
    );
    await tester.ensureVisible(find.byType(FormActionBar));
    await tester.pumpAndSettle();
    final guardar = tester.widget<FormActionBar>(
      find.byType(FormActionBar),
    );
    expect(guardar.onPressed, isNotNull);
    guardar.onPressed!();
    await tester.pumpAndSettle();

    expect(find.byType(ListaLeadsScreen), findsOneWidget);
    expect(find.text('Lead actualizado'), findsOneWidget);
    expect(find.text('Lead anterior'), findsNothing);
  });
}
