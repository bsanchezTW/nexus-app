import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transworld_nexus/core/conexion/estado_conexion.dart';
import 'package:transworld_nexus/core/conexion/monitor_conexion.dart';
import 'package:transworld_nexus/core/network/connectivity_service.dart';
import 'package:transworld_nexus/core/theme/tw_tokens.dart';
import 'package:transworld_nexus/core/widgets/app_scaffold.dart';
import 'package:transworld_nexus/core/widgets/offline_banner.dart';
import 'package:transworld_nexus/core/widgets/tw_offline_notice_card.dart';
import 'package:transworld_nexus/data/offline/sync_queue_service.dart';

Future<void> _montarCard(WidgetTester tester, {required bool hayRed}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        connectivityStreamProvider.overrideWith((ref) => Stream.value(hayRed)),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [Text('Inicio'), TwOfflineNoticeCard(), Text('Resumen')],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('con red la card no ocupa sitio', (tester) async {
    await _montarCard(tester, hayRed: true);
    expect(find.text(kTwOfflineNoticeTitle), findsNothing);
  });

  testWidgets('sin red se pinta entre el contenido, no bajo el reloj', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 44);
    addTearDown(tester.view.reset);

    await _montarCard(tester, hayRed: false);

    expect(find.text(kTwOfflineNoticeTitle), findsOneWidget);
    expect(find.text(kTwOfflineNoticeSubtitle), findsOneWidget);

    final cardTop = tester.getRect(find.byType(TwOfflineNoticeCard)).top;
    expect(cardTop, greaterThan(tester.getRect(find.text('Inicio')).top));
    expect(cardTop, lessThan(tester.getRect(find.text('Resumen')).top));

    final fondo = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.color == TwColors.offlineNoticeBg);
    expect(fondo.color, TwColors.offlineNoticeBg);
  });

  testWidgets('con la conexión inestable avisa el modo sin conexión', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          estadoConexionProvider.overrideWithValue(EstadoConexion.inestable),
        ],
        child: const MaterialApp(home: Scaffold(body: TwOfflineNoticeCard())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(kTwUnstableNoticeTitle), findsOneWidget);
    expect(find.text(kTwUnstableNoticeSubtitle), findsOneWidget);
    expect(find.text(kTwOfflineNoticeTitle), findsNothing);
  });

  testWidgets('sin copia local (web), inestable avisa pero sigue en línea', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          estadoConexionProvider.overrideWithValue(EstadoConexion.inestable),
          isOnlineProvider.overrideWithValue(true),
        ],
        child: const MaterialApp(home: Scaffold(body: TwOfflineNoticeCard())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(kTwUnstableNoticeTitle), findsOneWidget);
    expect(find.text(kTwUnstableNoticeSubtitleOnline), findsOneWidget);
  });

  testWidgets('topGap deja aire entre el contenido y el cartel', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          connectivityStreamProvider.overrideWith((ref) => Stream.value(false)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(key: Key('hero'), height: 40, width: double.infinity),
                TwOfflineNoticeCard(topGap: 20),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final heroBottom = tester.getRect(find.byKey(const Key('hero'))).bottom;
    final tituloTop = tester.getRect(find.text(kTwOfflineNoticeTitle)).top;
    expect(tituloTop - heroBottom, greaterThanOrEqualTo(20));
  });

  testWidgets('AppScaffold no muestra el banner rojo de sin conexión', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              const AppScaffold(title: 'Editar algo', body: SizedBox.shrink()),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          connectivityStreamProvider.overrideWith((ref) => Stream.value(false)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OfflineBanner), findsNothing);
    expect(find.text('Sin conexión'), findsNothing);
  });
}
