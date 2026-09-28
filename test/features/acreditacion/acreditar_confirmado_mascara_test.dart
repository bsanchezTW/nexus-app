import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:transworld_nexus/core/constants/app_role.dart';
import 'package:transworld_nexus/core/network/connectivity_service.dart';
import 'package:transworld_nexus/data/models/perfil.dart';
import 'package:transworld_nexus/data/models/registrado.dart';
import 'package:transworld_nexus/data/offline/sync_queue_service.dart';
import 'package:transworld_nexus/features/acreditacion/screens/acreditar_confirmado_screen.dart';
import 'package:transworld_nexus/features/auth/providers/auth_providers.dart';
import 'package:transworld_nexus/features/registrados/providers/registrados_providers.dart';
import 'package:transworld_nexus/features/subeventos/providers/inscripciones_providers.dart';
import 'package:transworld_nexus/features/subeventos/providers/subeventos_providers.dart';

void main() {
  const eventoId = 'evento-1';
  const registrados = [
    Registrado(
      id: 'reg-1',
      eventoId: eventoId,
      nombreCompleto: 'María González',
      email: 'maria.gonzalez@transworld.com',
    ),
  ];

  const perfilUser = Perfil(
    id: 'user-1',
    nombreCompleto: 'Usuario Interno',
    rol: AppRole.user,
  );
  const perfilOrganizador = Perfil(
    id: 'org-1',
    nombreCompleto: 'Organizador',
    rol: AppRole.organizador,
  );

  late SharedPreferences preferences;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const {});
    preferences = await SharedPreferences.getInstance();
  });

  Future<void> montar(WidgetTester tester, {required Perfil perfil}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          connectivityStreamProvider.overrideWith((ref) => Stream.value(true)),
          authStateChangesProvider.overrideWith(
            (ref) => const Stream<AuthState>.empty(),
          ),
          currentPerfilProvider.overrideWith((ref) async => perfil),
          registradosPorEventoProvider.overrideWith(
            (ref, id) async => registrados,
          ),
          subeventosPorEventoProvider.overrideWith((ref, id) async => const []),
          inscripcionesPorEventoProvider.overrideWith((ref, id) async => const []),
        ],
        child: const MaterialApp(
          home: AcreditarConfirmadoScreen(eventoId: eventoId),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('el usuario interno ve el correo tapado, dominio incluido', (
    tester,
  ) async {
    await montar(tester, perfil: perfilUser);

    expect(find.text('María González'), findsOneWidget);
    expect(find.text('ma****@tr****.com'), findsOneWidget);
    expect(find.text('maria.gonzalez@transworld.com'), findsNothing);
  });

  testWidgets('el organizador sigue viendo el correo completo', (tester) async {
    await montar(tester, perfil: perfilOrganizador);

    expect(find.text('maria.gonzalez@transworld.com'), findsOneWidget);
  });

  testWidgets('sin permiso, buscar por correo no lo delata', (tester) async {
    await montar(tester, perfil: perfilUser);

    await tester.enterText(find.byType(TextField), 'maria.gonzalez');
    await tester.pumpAndSettle();

    expect(find.text('María González'), findsNothing);
    expect(find.text('No se encontraron resultados.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'gonzález');
    await tester.pumpAndSettle();

    expect(find.text('María González'), findsOneWidget);
  });
}
