import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:transworld_nexus/core/constants/app_role.dart';
import 'package:transworld_nexus/core/network/connectivity_service.dart';
import 'package:transworld_nexus/core/network/offline_guard.dart';
import 'package:transworld_nexus/core/widgets/tw_toast.dart';
import 'package:transworld_nexus/data/models/lead_comentario.dart';
import 'package:transworld_nexus/data/models/perfil.dart';
import 'package:transworld_nexus/data/repositories/lead_comentarios_repository.dart';
import 'package:transworld_nexus/features/auth/providers/auth_providers.dart';
import 'package:transworld_nexus/features/capturador/lead_comentario_flujo.dart';
import 'package:transworld_nexus/features/capturador/screens/comentarios_lead_screen.dart';

class _FakeComentarios extends LeadComentariosRepository {
  _FakeComentarios(this.items)
    : super(
        SupabaseClient(
          'http://localhost',
          'fake-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final List<LeadComentario> items;

  @override
  Future<List<LeadComentario>> listar(String leadId) async {
    return items.where((c) => c.leadId == leadId).toList();
  }

  @override
  Future<LeadComentario> crear({
    required String leadId,
    required String cuerpo,
  }) async {
    final comentario = LeadComentario(
      id: 'nuevo-${items.length}',
      leadId: leadId,
      cuerpo: cuerpo.trim(),
      autorId: 'user-1',
      autorNombre: 'Bastian Abarca',
      createdAt: DateTime(2026, 8, 20, 13, 15),
    );
    items.add(comentario);
    return comentario;
  }

  @override
  Future<void> borrar(String comentarioId) async {
    items.removeWhere((c) => c.id == comentarioId);
  }

  @override
  Future<LeadComentario> editar({
    required String comentarioId,
    required String cuerpo,
  }) async {
    final i = items.indexWhere((c) => c.id == comentarioId);
    final actual = items[i];
    final editado = LeadComentario(
      id: actual.id,
      leadId: actual.leadId,
      cuerpo: cuerpo.trim(),
      autorId: actual.autorId,
      autorNombre: actual.autorNombre,
      autorRol: actual.autorRol,
      createdAt: actual.createdAt,
      updatedAt: DateTime(2026, 8, 20, 14, 0),
    );
    items[i] = editado;
    return editado;
  }
}

void main() {
  tearDown(TwToast.hide);

  const perfil = Perfil(
    id: 'user-1',
    nombreCompleto: 'Bastian Abarca',
    rol: AppRole.user,
  );

  final propio = LeadComentario(
    id: 'c-propio',
    leadId: 'lead-1',
    cuerpo: 'Lo vi en el stand 4',
    autorId: 'user-1',
    autorNombre: 'Bastian Abarca',
    autorRol: 'user',
    createdAt: DateTime(2026, 8, 20, 12, 0),
  );
  final ajeno = LeadComentario(
    id: 'c-ajeno',
    leadId: 'lead-1',
    cuerpo: 'Pidió brochure',
    autorId: 'user-2',
    autorNombre: 'Andres Freire',
    autorRol: 'externo',
    createdAt: DateTime(2026, 8, 20, 12, 5),
  );

  Future<void> montar(
    WidgetTester tester, {
    required List<LeadComentario> iniciales,
    bool online = true,
    Perfil? perfilOverride,
    Size size = const Size(390, 844),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final repo = _FakeComentarios(List.of(iniciales));
    final router = GoRouter(
      initialLocation: '/comentarios',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
        GoRoute(
          path: '/comentarios',
          builder: (_, _) => const ComentariosLeadScreen(
            eventoId: 'campana-1',
            leadId: 'lead-1',
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityStreamProvider.overrideWith(
            (ref) => Stream.value(online),
          ),
          usaServidorProvider.overrideWith((ref) => online),
          currentPerfilProvider.overrideWith(
            (ref) async => perfilOverride ?? perfil,
          ),
          leadComentariosRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lista comentarios propios y ajenos', (tester) async {
    await montar(tester, iniciales: [propio, ajeno]);

    expect(find.text('Lo vi en el stand 4'), findsOneWidget);
    expect(find.text('Pidió brochure'), findsOneWidget);
    expect(find.text('Andres Freire'), findsOneWidget);
    expect(find.text('Usuario'), findsWidgets);
    expect(find.text('Usuario Externo'), findsOneWidget);
    expect(find.textContaining('20/08/2026'), findsWidgets);
    expect(find.text('Sé el primero en comentar'), findsNothing);
  });

  testWidgets('publica un comentario propio', (tester) async {
    await montar(tester, iniciales: const []);

    expect(find.text('Sé el primero en comentar'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('comentarios_lead_composer')),
      'Interesado en capacitación',
    );
    await tester.tap(find.byKey(const Key('comentarios_lead_enviar')));
    await tester.pumpAndSettle();

    expect(find.text('Interesado en capacitación'), findsOneWidget);
    expect(find.text('Sé el primero en comentar'), findsNothing);
  });

  testWidgets('el compositor flota redondeado y centrado en web fullscreen', (
    tester,
  ) async {
    await montar(tester, iniciales: [propio], size: const Size(1440, 900));

    final composer = find.byKey(
      const Key('comentarios_lead_composer_floating'),
    );
    expect(composer, findsOneWidget);
    final rect = tester.getRect(composer);
    expect(rect.width, lessThanOrEqualTo(680));
    expect(rect.left, greaterThan(0));
    expect(rect.right, lessThan(1440));
    expect(rect.bottom, lessThan(900));

    final material = tester.widget<Material>(composer);
    final shape = material.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(26));
  });

  testWidgets('el autor puede borrar el suyo y no el ajeno', (tester) async {
    await montar(tester, iniciales: [propio, ajeno]);

    await tester.longPress(find.byKey(const Key('comentario_burbuja_c-ajeno')));
    await tester.pumpAndSettle();
    expect(find.text('Editar'), findsNothing);
    expect(find.text('Borrar'), findsNothing);

    await tester.longPress(
      find.byKey(const Key('comentario_burbuja_c-propio')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Editar'), findsOneWidget);
    expect(find.text('Borrar'), findsOneWidget);

    await tester.tap(find.text('Borrar'));
    await tester.pumpAndSettle();
    expect(find.text('¿Borrar comentario?'), findsOneWidget);

    await tester.tap(find.text('Borrar').last);
    await tester.pumpAndSettle();

    expect(find.text('Lo vi en el stand 4'), findsNothing);
    expect(find.text('Pidió brochure'), findsOneWidget);
  });

  testWidgets('un admin borra un comentario ajeno sin poder editarlo', (
    tester,
  ) async {
    const admin = Perfil(
      id: 'admin-1',
      nombreCompleto: 'Admin Demo',
      rol: AppRole.admin,
    );
    await montar(tester, iniciales: [propio, ajeno], perfilOverride: admin);

    await tester.longPress(find.byKey(const Key('comentario_burbuja_c-ajeno')));
    await tester.pumpAndSettle();
    expect(find.text('Editar'), findsNothing);
    expect(find.text('Borrar'), findsOneWidget);
  });

  testWidgets('un comentario editado muestra la marca junto a la hora', (
    tester,
  ) async {
    final editado = LeadComentario(
      id: 'c-editado',
      leadId: 'lead-1',
      cuerpo: 'Texto actualizado',
      autorId: 'user-1',
      autorNombre: 'Bastian Abarca',
      autorRol: 'user',
      createdAt: DateTime(2026, 8, 20, 12, 0),
      updatedAt: DateTime(2026, 8, 20, 14, 0),
    );
    await montar(tester, iniciales: [editado]);
    expect(find.textContaining('editado'), findsOneWidget);
  });

  testWidgets('el autor edita el comentario en un segundo sheet', (
    tester,
  ) async {
    await montar(tester, iniciales: [propio]);

    await tester.longPress(
      find.byKey(const Key('comentario_burbuja_c-propio')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();

    expect(find.text('Editar comentario'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Lo vi en el stand 4'),
      'Lo vi en el stand 7',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Lo vi en el stand 7'), findsOneWidget);
    expect(find.text('Lo vi en el stand 4'), findsNothing);
    expect(find.textContaining('editado'), findsOneWidget);
  });

  testWidgets('sin red no navega al hilo de comentarios', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityStreamProvider.overrideWith((ref) => Stream.value(false)),
          usaServidorProvider.overrideWith((ref) => false),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () {
                  irAComentariosLead(
                    context,
                    ref,
                    eventoId: 'campana-1',
                    leadId: 'lead-1',
                  );
                },
                child: const Text('Abrir hilo'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir hilo'));
    await tester.pump();

    expect(find.text('Abrir hilo'), findsOneWidget);
    expect(find.text(kMensajeSinConexion), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
