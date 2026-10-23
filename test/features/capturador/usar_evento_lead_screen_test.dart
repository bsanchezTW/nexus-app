import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:transworld_nexus/core/constants/app_role.dart';
import 'package:transworld_nexus/core/network/connectivity_service.dart';
import 'package:transworld_nexus/core/widgets/evento_hero_banner.dart';
import 'package:transworld_nexus/core/widgets/tw_components.dart';
import 'package:transworld_nexus/data/models/evento_lead.dart';
import 'package:transworld_nexus/data/models/perfil.dart';
import 'package:transworld_nexus/data/offline/sync_queue_service.dart';
import 'package:transworld_nexus/features/auth/providers/auth_providers.dart';
import 'package:transworld_nexus/features/capturador/providers/capturador_providers.dart';
import 'package:transworld_nexus/features/capturador/screens/usar_evento_lead_screen.dart';

void main() {
  final evento = EventoLead(
    id: 'campana-1',
    nombre: 'Campaña de prueba',
    fecha: DateTime(2099, 8, 20),
    pais: 'Chile',
  );
  const perfilUser = Perfil(
    id: 'user-1',
    nombreCompleto: 'Usuario Interno',
    rol: AppRole.user,
  );

  late SharedPreferences preferences;

  setUpAll(() async {
    await initializeDateFormatting('es');
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
          eventoLeadByIdProvider.overrideWith((ref, id) async => evento),
          leadsResumenLocalProvider.overrideWith(
            (ref, id) => const LeadsResumen(total: 12, empresas: 5),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('es'),
          home: UsarEventoLeadScreen(eventoId: 'campana-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'el usuario interno ve el resumen de la campaña, no solo sus leads',
    (tester) async {
      await montar(tester, perfil: perfilUser);

      // El hero del rediseño (§9) muestra 2 métricas, rotuladas en mayúsculas.
      final stats = tester.widget<TwStatsRow>(find.byType(TwStatsRow));
      expect(stats.stats, hasLength(2));
      expect(find.text('LEADS CAPTURADOS'), findsOneWidget);
      expect(find.text('EMPRESAS'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('DETALLE DE LA ACTIVIDAD'), findsOneWidget);
      expect(find.byType(EventoHeroFoto), findsNothing);
      expect(find.text('Mis leads'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('el hero de una actividad con foto monta la portada', (
    tester,
  ) async {
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
          currentPerfilProvider.overrideWith((ref) async => perfilUser),
          eventoLeadByIdProvider.overrideWith(
            (ref, id) async => EventoLead(
              id: 'campana-1',
              nombre: 'Campaña de prueba',
              fecha: DateTime(2099, 8, 20),
              pais: 'Chile',
              imagenUrl: 'https://example.com/actividad.jpg',
            ),
          ),
          leadsResumenLocalProvider.overrideWith(
            (ref, id) => const LeadsResumen(total: 12, empresas: 5),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('es'),
          home: UsarEventoLeadScreen(eventoId: 'campana-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(EventoHeroFoto), findsOneWidget);
    expect(
      tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .any(
            (box) =>
                box.decoration is BoxDecoration &&
                (box.decoration as BoxDecoration).gradient ==
                    TwEventHero.veloFoto,
          ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin foto el hero no lleva velo', (tester) async {
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
          currentPerfilProvider.overrideWith((ref) async => perfilUser),
          eventoLeadByIdProvider.overrideWith(
            (ref, id) async => EventoLead(
              id: 'campana-1',
              nombre: 'Campaña de prueba',
              fecha: DateTime(2099, 8, 20),
              pais: 'Chile',
            ),
          ),
          leadsResumenLocalProvider.overrideWith(
            (ref, id) => const LeadsResumen(total: 12, empresas: 5),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('es'),
          home: UsarEventoLeadScreen(eventoId: 'campana-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(EventoHeroFoto), findsNothing);
    expect(
      tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .any(
            (box) =>
                box.decoration is BoxDecoration &&
                (box.decoration as BoxDecoration).gradient ==
                    TwEventHero.veloFoto,
          ),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('al recargar la campaña el menú de acciones sigue montado', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    var bloquearRecarga = false;
    final recarga = Completer<EventoLead>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          connectivityStreamProvider.overrideWith((ref) => Stream.value(true)),
          authStateChangesProvider.overrideWith(
            (ref) => const Stream<AuthState>.empty(),
          ),
          currentPerfilProvider.overrideWith((ref) async => perfilUser),
          leadsResumenLocalProvider.overrideWith(
            (ref, id) => const LeadsResumen(total: 12, empresas: 5),
          ),
          eventoLeadByIdProvider.overrideWith((ref, id) async {
            if (bloquearRecarga) await recarga.future;
            return evento;
          }),
        ],
        child: const MaterialApp(
          locale: Locale('es'),
          home: UsarEventoLeadScreen(eventoId: 'campana-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ver leads'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    bloquearRecarga = true;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(UsarEventoLeadScreen)),
    );
    container.invalidate(eventoLeadByIdProvider('campana-1'));
    await tester.pump();

    expect(find.text('Ver leads'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    recarga.complete(evento);
    await tester.pumpAndSettle();
    expect(find.text('Ver leads'), findsOneWidget);
  });

  testWidgets(
    'una actividad interna muestra el tile al evento de registro',
    (tester) async {
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
            currentPerfilProvider.overrideWith((ref) async => perfilUser),
            eventoLeadByIdProvider.overrideWith(
              (ref, id) async => EventoLead(
                id: 'campana-1',
                nombre: 'Campaña de prueba',
                fecha: DateTime(2099, 8, 20),
                pais: 'Chile',
                tipo: TipoEventoLead.interno,
                eventoOrigenId: 'evt-madre',
              ),
            ),
            leadsResumenLocalProvider.overrideWith(
              (ref, id) => const LeadsResumen(total: 12, empresas: 5),
            ),
          ],
          child: const MaterialApp(
            locale: Locale('es'),
            home: UsarEventoLeadScreen(eventoId: 'campana-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Ver evento de registro'),
        80,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Ver evento de registro'), findsOneWidget);
    },
  );

  testWidgets('una actividad externa no muestra el tile al evento madre', (
    tester,
  ) async {
    await montar(tester, perfil: perfilUser);
    expect(find.text('Ver evento de registro'), findsNothing);
  });
}
