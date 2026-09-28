import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transworld_nexus/core/constants/app_role.dart';
import 'package:transworld_nexus/core/network/connectivity_service.dart';
import 'package:transworld_nexus/core/router/route_paths.dart';
import 'package:transworld_nexus/core/widgets/nexus_components.dart';
import 'package:transworld_nexus/data/models/evento.dart';
import 'package:transworld_nexus/data/models/inscripcion_subevento.dart';
import 'package:transworld_nexus/data/models/ocupacion_evento.dart';
import 'package:transworld_nexus/data/models/perfil.dart';
import 'package:transworld_nexus/data/models/registrado.dart';
import 'package:transworld_nexus/data/models/subevento.dart';
import 'package:transworld_nexus/data/offline/offline_read_cache.dart';
import 'package:transworld_nexus/data/offline/sync_queue_service.dart';
import 'package:transworld_nexus/data/repositories/inscripciones_subevento_repository.dart';
import 'package:transworld_nexus/data/repositories/registrados_repository.dart';
import 'package:transworld_nexus/features/auth/providers/auth_providers.dart';
import 'package:transworld_nexus/features/eventos/providers/eventos_providers.dart';
import 'package:transworld_nexus/features/registrados/screens/editar_registrado_screen.dart';
import 'package:transworld_nexus/features/subeventos/providers/inscripciones_providers.dart';
import 'package:transworld_nexus/features/subeventos/providers/subeventos_providers.dart';

class _FakeRegistradosRepository extends Fake implements RegistradosRepository {
  _FakeRegistradosRepository(this.registrado);

  Registrado registrado;

  @override
  Future<void> actualizar(String id, Map<String, dynamic> changes) async {
    registrado = registrado
        .conCambiosPendientes(changes)
        .copyWith(pendienteDeSincronizar: false);
  }
}

class _FakeInscripciones extends Fake
    implements InscripcionesSubeventoRepository {
  int inscribirLlamadas = 0;
  int quitarLlamadas = 0;

  @override
  Future<Map<String, dynamic>> inscribir({
    required String registradoId,
    required String subeventoId,
    bool forzarSobrecupo = false,
    bool marcarAsistencia = false,
    bool reemplazarSuperpuestos = false,
  }) async {
    inscribirLlamadas++;
    return const {'ok': true};
  }

  @override
  Future<void> quitar({
    required String registradoId,
    required String subeventoId,
  }) async {
    quitarLlamadas++;
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
  });

  testWidgets('los talleres inscritos aparecen y guardar no los reescribe', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cache = OfflineReadCache(prefs, ownerId: 'admin-1');
    const eventoId = 'evento-1';
    const original = Registrado(
      id: 'registrado-1',
      eventoId: eventoId,
      nombreCompleto: 'Ana Pérez',
      email: 'ana@empresa.cl',
      telefono: '+56912345678',
    );
    await cache.guardar('registrados', eventoId, [original.toCacheMap()]);
    final repo = _FakeRegistradosRepository(original);
    final inscripciones = _FakeInscripciones();
    final manana = DateTime.now().add(const Duration(days: 3));
    final taller = Subevento(
      id: 'taller-1',
      eventoId: eventoId,
      codigo: 'a7k2mq',
      nombre: 'Taller IA',
      dia: DateTime(manana.year, manana.month, manana.day),
      horaInicio: const TimeOfDay(hour: 10, minute: 0),
      horaFin: const TimeOfDay(hour: 11, minute: 0),
    );
    const inscripcion = InscripcionSubevento(
      id: 'ins-1',
      eventoId: eventoId,
      registradoId: 'registrado-1',
      subeventoId: 'taller-1',
      origen: 'app',
    );

    final router = GoRouter(
      initialLocation: RoutePaths.editarRegistrado(eventoId, 'registrado-1'),
      routes: [
        GoRoute(
          path: '/eventos/:id/registrados',
          builder: (_, _) => const SizedBox.shrink(),
        ),
        GoRoute(
          path: '/eventos/:eventoId/registrados/:registradoId/editar',
          builder: (_, _) => const EditarRegistradoScreen(
            eventoId: eventoId,
            registradoId: 'registrado-1',
          ),
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
          eventoByIdProvider.overrideWith(
            (ref, id) async => Evento(
              id: id,
              nombre: 'Evento',
              fecha: DateTime(2030),
              pais: 'Chile',
            ),
          ),
          registradosRepositoryProvider.overrideWithValue(repo),
          inscripcionesSubeventoRepositoryProvider.overrideWithValue(
            inscripciones,
          ),
          subeventosPorEventoProvider.overrideWith((ref, id) async => [taller]),
          ocupacionEventoProvider.overrideWith(
            (ref, id) async => const OcupacionEvento(
              evento: OcupacionItem(
                cupoMaximo: null,
                inscritos: 0,
                asistentes: 0,
              ),
              subeventos: {},
            ),
          ),
          inscripcionesPorEventoProvider.overrideWith((ref, id) async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return const [inscripcion];
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final fila = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Taller IA'),
    );
    expect(fila.value, isTrue);

    await tester.ensureVisible(find.byType(PrimaryGradientButton));
    tester
        .widget<PrimaryGradientButton>(find.byType(PrimaryGradientButton))
        .onPressed!();
    await tester.pumpAndSettle();

    expect(inscripciones.inscribirLlamadas, 0);
    expect(inscripciones.quitarLlamadas, 0);
  });
}
