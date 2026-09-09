import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:transworld_nexus/core/theme/app_theme.dart';
import 'package:transworld_nexus/core/theme/tw_tokens.dart';
import 'package:transworld_nexus/core/widgets/evento_hero_banner.dart';
import 'package:transworld_nexus/features/home/models/home_featured_item.dart';
import 'package:transworld_nexus/features/home/widgets/proximo_evento_card.dart';

final _items = [
  HomeFeaturedItem(
    kind: HomeFeaturedKind.eventoFijado,
    id: 'evento-1',
    nombre: 'Evento destacado con un nombre suficientemente extenso',
    fecha: DateTime(2026, 8, 10),
    lugar: 'Santiago de Chile',
  ),
  HomeFeaturedItem(
    kind: HomeFeaturedKind.campanaFijada,
    id: 'campana-1',
    nombre: 'Campaña destacada',
    fecha: DateTime(2026, 9, 12),
  ),
];

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  test('el inset centrado coincide con el gutter del home', () {
    expect(homeFeaturedSettledInset(320), TwSpacing.screenH);
    expect(homeFeaturedSettledInset(400), TwSpacing.screenH);
    expect(homeFeaturedSettledInset(1200), (1200 - AppSpacing.contentMax) / 2);
  });

  testWidgets('sin eventos la card permanece con el mensaje de calma', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ProximoEventoCard(items: []),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ProximoEventoCard), findsOneWidget);
    expect(find.byKey(const Key('proximo_evento_vacio')), findsOneWidget);
    expect(find.text('PRÓXIMO EVENTO'), findsOneWidget);
    expect(find.text('Todo tranquilo por aquí'), findsOneWidget);
    expect(
      find.text('No hay próximos eventos programados por ahora'),
      findsOneWidget,
    );
    expect(tester.getSize(find.byType(ProximoEventoCard)).height, greaterThan(0));
    expect(find.text('Ver evento'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'métricas y CTA quedan anclados abajo aunque el título ocupe dos líneas',
    (tester) async {
      final items = [
        HomeFeaturedItem(
          kind: HomeFeaturedKind.eventoFijado,
          id: 'evento-largo',
          nombre:
              'Evento destacado con un nombre suficientemente extenso para dos líneas',
          fecha: DateTime(2026, 8, 10),
          lugar: 'Santiago de Chile',
        ),
        HomeFeaturedItem(
          kind: HomeFeaturedKind.eventoFijado,
          id: 'evento-corto',
          nombre: 'Expo',
          fecha: DateTime(2026, 9, 12),
          lugar: 'Santiago de Chile',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: ProximoEventoCard(items: items),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      double visibleTop(String text) {
        final viewport = tester.getRect(find.byType(PageView));
        for (final element in find.text(text).evaluate()) {
          final rect = tester.getRect(find.byWidget(element.widget));
          if (viewport.overlaps(rect)) return rect.top;
        }
        fail('No hay "$text" visible en el carrusel');
      }

      final statsLargo = visibleTop('REGISTRADOS');
      final ctaLargo = visibleTop('Ver evento');
      final tituloLargo = visibleTop(
        'Evento destacado con un nombre suficientemente extenso para dos líneas',
      );

      await tester.tap(find.byKey(const Key('proximo_evento_punto_1')));
      await tester.pumpAndSettle();

      expect(visibleTop('REGISTRADOS'), statsLargo);
      expect(visibleTop('Ver evento'), ctaLargo);
      expect(visibleTop('Expo'), closeTo(tituloLargo, 1));
    },
  );

  testWidgets('desliza las cards sin cambiar la altura máxima', (tester) async {
    final items = _items;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(1.6),
            ),
            child: Center(
              child: SizedBox(
                width: 320,
                child: ProximoEventoCard(items: items),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(PageView), findsOneWidget);
    expect(find.byType(AnimatedSwitcher), findsNothing);
    final alturaInicial = tester.getSize(find.byType(ProximoEventoCard)).height;
    expect(alturaInicial, greaterThan(96));
    expect(find.text('Ver evento'), findsOneWidget);
    expect(find.text('Escanear QR'), findsOneWidget);
    expect(find.text('REGISTRADOS'), findsWidgets);

    await tester.fling(
      find.text('Evento destacado con un nombre suficientemente extenso'),
      const Offset(-250, 0),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.text('Campaña destacada'), findsOneWidget);
    expect(
      tester.getSize(find.byType(ProximoEventoCard)).height,
      alturaInicial,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('la card ocupa todo el ancho: sin flechas laterales', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ProximoEventoCard(items: _items),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('proximo_evento_siguiente')), findsNothing);
    expect(find.byKey(const Key('proximo_evento_anterior')), findsNothing);
    expect(tester.getSize(find.byType(PageView)).width, 320);
  });

  testWidgets('los puntos cambian de card sin depender del swipe', (
    tester,
  ) async {
    // El binding exige devolver la variable de debug antes de terminar el
    // cuerpo del test, así que no sirve un addTearDown.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 420,
                child: ProximoEventoCard(items: _items),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Campaña destacada'), findsNothing);

      await tester.tap(find.byKey(const Key('proximo_evento_punto_1')));
      await tester.pumpAndSettle();
      expect(find.text('Campaña destacada'), findsOneWidget);

      await tester.tap(find.byKey(const Key('proximo_evento_punto_0')));
      await tester.pumpAndSettle();
      expect(
        find.text('Evento destacado con un nombre suficientemente extenso'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('la card de próximo evento muestra métricas y CTA', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ProximoEventoCard(
                items: [
                  HomeFeaturedItem(
                    kind: HomeFeaturedKind.proximoEvento,
                    id: 'evento-1',
                    nombre: 'Taller ALTAI: Título por confirmar',
                    fecha: DateTime(2026, 8, 25),
                    lugar: 'Hotel Intercontinental · Santiago',
                    registrados: 64,
                    acreditados: 26,
                    leads: 23,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('PRÓXIMO EVENTO'), findsOneWidget);
    expect(find.text('25 AGO'), findsOneWidget);
    expect(find.text('Taller ALTAI: Título por confirmar'), findsOneWidget);
    expect(find.text('Hotel Intercontinental · Santiago'), findsOneWidget);
    expect(find.text('64'), findsOneWidget);
    expect(find.text('41%'), findsOneWidget);
    expect(find.text('23'), findsOneWidget);
    expect(find.text('Ver evento'), findsOneWidget);
    expect(find.text('Escanear QR'), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    expect(find.byType(EventoHeroFoto), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('con imagen de portada la card monta la foto del evento', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ProximoEventoCard(
                items: [
                  HomeFeaturedItem(
                    kind: HomeFeaturedKind.proximoEvento,
                    id: 'evento-1',
                    nombre: 'Taller ALTAI: Título por confirmar',
                    fecha: DateTime(2026, 8, 25),
                    imagenUrl: 'https://example.com/evento.jpg',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Taller ALTAI: Título por confirmar'), findsOneWidget);
    expect(find.byType(EventoHeroFoto), findsOneWidget);
    expect(
      tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .any(
            (box) =>
                box.decoration is BoxDecoration &&
                (box.decoration as BoxDecoration).gradient ==
                    TwGradients.heroScrim,
          ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('deslizar el carrusel sigue mostrando la foto de cada card', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ProximoEventoCard(
                items: [
                  HomeFeaturedItem(
                    kind: HomeFeaturedKind.eventoFijado,
                    id: 'evento-1',
                    nombre: 'Evento con foto',
                    fecha: DateTime(2026, 8, 10),
                    imagenUrl: 'https://example.com/evento.jpg',
                  ),
                  HomeFeaturedItem(
                    kind: HomeFeaturedKind.campanaFijada,
                    id: 'campana-1',
                    nombre: 'Actividad con foto',
                    fecha: DateTime(2026, 9, 12),
                    imagenUrl: 'https://example.com/actividad.jpg',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(EventoHeroFoto), findsWidgets);

    await tester.tap(find.byKey(const Key('proximo_evento_punto_1')));
    await tester.pumpAndSettle();
    expect(find.text('Actividad con foto'), findsOneWidget);
    expect(find.byType(EventoHeroFoto), findsWidgets);

    await tester.tap(find.byKey(const Key('proximo_evento_punto_0')));
    await tester.pumpAndSettle();
    expect(find.text('Evento con foto'), findsOneWidget);
    expect(find.byType(EventoHeroFoto), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la actividad fijada ofrece capturar lead y no escanear QR', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ProximoEventoCard(
                items: [
                  HomeFeaturedItem(
                    kind: HomeFeaturedKind.campanaFijada,
                    id: 'evento-lead-1',
                    nombre: 'Actividad de captura destacada',
                    fecha: DateTime(2026, 9, 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('ACTIVIDAD FIJADA'), findsOneWidget);
    expect(find.text('Capturar lead'), findsOneWidget);
    expect(find.text('Ver actividad'), findsOneWidget);
    expect(find.byIcon(Symbols.person_add_rounded), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Ver actividad')).dy,
      lessThan(tester.getTopLeft(find.text('Capturar lead')).dy),
    );
    expect(find.text('Escanear QR'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la próxima actividad ofrece capturar lead y no escanear QR', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ProximoEventoCard(
                items: [
                  HomeFeaturedItem(
                    kind: HomeFeaturedKind.proximaActividad,
                    id: 'evento-lead-1',
                    nombre: 'Feria retail',
                    fecha: DateTime(2026, 9, 20),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('proximo_evento_vacio')), findsNothing);
    expect(find.text('PRÓXIMA ACTIVIDAD'), findsOneWidget);
    expect(find.text('Feria retail'), findsOneWidget);
    expect(find.text('Capturar lead'), findsOneWidget);
    expect(find.text('Ver actividad'), findsOneWidget);
    expect(find.text('Escanear QR'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('los puntos inactivos se distinguen del activo', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ProximoEventoCard(items: _items),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('proximo_evento_punto_0')), findsOneWidget);
    expect(find.byKey(const Key('proximo_evento_punto_1')), findsOneWidget);

    BoxDecoration decoDe(Key key) {
      final container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(AnimatedContainer),
        ),
      );
      return container.decoration! as BoxDecoration;
    }

    final activo = decoDe(const Key('proximo_evento_punto_0'));
    final inactivo = decoDe(const Key('proximo_evento_punto_1'));
    expect(activo.color, TwColors.hero700);
    expect(inactivo.color, isNot(TwColors.border07));
    expect(inactivo.color, isNot(activo.color));
    expect(inactivo.color!.a, greaterThan(0.2));
  });

  testWidgets('las cards centradas respetan el gutter del home', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ProximoEventoCard(items: _items),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pageWidth = tester.getSize(find.byType(PageView)).width;
    expect(pageWidth, 320);
    final card = find
        .descendant(
          of: find.byType(PageView),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.decoration is BoxDecoration &&
                (widget.decoration! as BoxDecoration).gradient ==
                    TwGradients.hero,
          ),
        )
        .first;
    expect(tester.getSize(card).width, pageWidth - TwSpacing.screenH * 2);
  });

  testWidgets('el CTA Capturar lead de la actividad fijada abre el alta', (
    tester,
  ) async {
    String? location;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: ProximoEventoCard(
                  items: [
                    HomeFeaturedItem(
                      kind: HomeFeaturedKind.campanaFijada,
                      id: 'campana-1',
                      nombre: 'Feria retail',
                      fecha: DateTime(2026, 9, 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/capturador/:id/capturar',
          builder: (_, state) {
            location = state.uri.path;
            return const SizedBox.shrink();
          },
        ),
        GoRoute(
          path: '/capturador/:id/usar',
          builder: (_, state) {
            location = state.uri.path;
            return const SizedBox.shrink();
          },
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    await tester.tap(find.text('Capturar lead'));
    await tester.pump();
    expect(location, '/capturador/campana-1/capturar');

    location = null;
    router.go('/');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ver actividad'));
    await tester.pump();
    expect(location, '/capturador/campana-1/usar');
    expect(tester.takeException(), isNull);
  });

  testWidgets('solo el botón Ver evento navega al evento', (tester) async {
    String? location;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: ProximoEventoCard(
                  items: [
                    HomeFeaturedItem(
                      kind: HomeFeaturedKind.proximoEvento,
                      id: 'evento-1',
                      nombre: 'Taller ALTAI: Título por confirmar',
                      fecha: DateTime(2026, 8, 25),
                      lugar: 'Hotel Intercontinental · Santiago',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/eventos/:id/usar',
          builder: (_, state) {
            location = state.uri.path;
            return const SizedBox.shrink();
          },
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    await tester.tap(find.text('Taller ALTAI: Título por confirmar'));
    await tester.pump();
    expect(location, isNull);

    await tester.tap(find.text('Hotel Intercontinental · Santiago'));
    await tester.pump();
    expect(location, isNull);

    await tester.tap(find.text('Ver evento'));
    await tester.pump();
    expect(location, '/eventos/evento-1/usar');
    expect(tester.takeException(), isNull);
  });
}
