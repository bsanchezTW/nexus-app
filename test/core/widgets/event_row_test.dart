import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:transworld_nexus/core/theme/tw_tokens.dart';
import 'package:transworld_nexus/core/widgets/nexus_components.dart';
import 'package:transworld_nexus/core/widgets/tw_components.dart';

Future<void> _montar(WidgetTester tester, Widget fila, {double ancho = 360}) {
  tester.view.physicalSize = Size(ancho, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('es'),
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(20), child: fila),
      ),
    ),
  );
}

Color _fondoDelBloque(WidgetTester tester) {
  final bloque = tester.widget<Container>(
    find
        .descendant(of: find.byType(DateTile), matching: find.byType(Container))
        .first,
  );
  return (bloque.decoration! as BoxDecoration).color!;
}

void main() {
  setUpAll(() => initializeDateFormatting('es', null));

  group('lineasBloqueFecha', () {
    test('un día muestra día y mes', () {
      final dia = DateTime(2026, 11, 25);
      expect(lineasBloqueFecha(dia, dia), ('25', 'NOV'));
    });

    test('varios días del mismo mes comparten el mes', () {
      expect(
        lineasBloqueFecha(DateTime(2026, 10, 20), DateTime(2026, 10, 24)),
        ('20–24', 'OCT'),
      );
    });

    test('entre dos meses cada línea lleva su mes', () {
      expect(lineasBloqueFecha(DateTime(2026, 10, 30), DateTime(2026, 11, 2)), (
        '30 OCT',
        '2 NOV',
      ));
    });

    test('entre dos años se lee igual que entre meses', () {
      expect(lineasBloqueFecha(DateTime(2026, 12, 30), DateTime(2027, 1, 2)), (
        '30 DIC',
        '2 ENE',
      ));
    });

    test('todos los meses van en 3 letras, septiembre incluido', () {
      expect(lineasBloqueFecha(DateTime(2026, 9, 9), DateTime(2026, 9, 11)), (
        '9–11',
        'SEP',
      ));
      expect(formatearDiaMesCorto(DateTime(2026, 9, 9)), '9 SEP');
      for (var mes = 1; mes <= 12; mes++) {
        expect(mesCortoMayus(DateTime(2026, mes)), hasLength(3));
      }
    });

    test('la hora no cuenta como otro día', () {
      expect(
        lineasBloqueFecha(DateTime(2026, 3, 10, 9), DateTime(2026, 3, 10, 18)),
        ('10', 'MAR'),
      );
    });
  });

  group('EventRow', () {
    testWidgets('el rango va en el bloque y no hay píldora de duración', (
      tester,
    ) async {
      await _montar(
        tester,
        EventRow(
          date: DateTime(2026, 10, 20),
          endDate: DateTime(2026, 10, 24),
          title: 'Feria Transworld',
          place: 'Santiago',
          chip: const TwOriginPill(interno: true),
          onTap: () {},
        ),
      );

      expect(find.text('20–24'), findsOneWidget);
      expect(find.text('OCT'), findsOneWidget);
      expect(find.text('Santiago'), findsOneWidget);
      expect(find.text('INTERNO'), findsOneWidget);
      expect(find.textContaining('días'), findsNothing);
    });

    testWidgets('un día y varios días usan el mismo ancho de bloque', (
      tester,
    ) async {
      await _montar(
        tester,
        Column(
          children: [
            EventRow(
              key: const Key('uno'),
              date: DateTime(2026, 11, 25),
              title: 'Un día',
              place: 'Lima',
              onTap: () {},
            ),
            EventRow(
              key: const Key('varios'),
              date: DateTime(2026, 10, 30),
              endDate: DateTime(2026, 11, 2),
              title: 'Varios días',
              place: 'Lima',
              onTap: () {},
            ),
          ],
        ),
      );

      double ancho(String clave) => tester
          .getSize(
            find.descendant(
              of: find.byKey(Key(clave)),
              matching: find.byType(DateTile),
            ),
          )
          .width;
      expect(ancho('uno'), 54);
      expect(ancho('varios'), 54);
      expect(find.text('30 OCT'), findsOneWidget);
      expect(find.text('2 NOV'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('finalizado lleva píldora y el bloque queda gris', (
      tester,
    ) async {
      await _montar(
        tester,
        EventRow(
          date: DateTime(2020, 8, 10),
          title: 'Transworld Connect',
          place: 'Santiago',
          chip: const TwOriginPill(interno: false),
          finalizado: true,
          onTap: () {},
        ),
      );

      expect(find.text('EXTERNO'), findsOneWidget);
      expect(find.text('FINALIZADO'), findsOneWidget);
      expect(_fondoDelBloque(tester), TwColors.surfaceTint);
    });

    testWidgets('una actividad de hoy dice en curso; una próxima no lleva', (
      tester,
    ) async {
      final hoy = DateTime.now();
      await _montar(
        tester,
        Column(
          children: [
            EventRow(
              date: hoy.subtract(const Duration(days: 1)),
              endDate: hoy.add(const Duration(days: 1)),
              title: 'En curso',
              place: 'Santiago',
              onTap: () {},
            ),
            EventRow(
              date: hoy.add(const Duration(days: 10)),
              title: 'Próxima',
              place: 'Santiago',
              onTap: () {},
            ),
          ],
        ),
      );

      expect(find.text('EN CURSO'), findsOneWidget);
      expect(find.text('FINALIZADO'), findsNothing);
    });

    testWidgets('sin conexión reemplaza al estado', (tester) async {
      await _montar(
        tester,
        EventRow(
          date: DateTime(2020, 8, 10),
          title: 'Actividad sin país',
          place: '',
          chip: const TwOriginPill(interno: false),
          finalizado: true,
          sinCache: true,
          onTap: () {},
        ),
      );

      expect(find.text('SIN CONEXIÓN'), findsOneWidget);
      expect(find.text('FINALIZADO'), findsNothing);
    });

    testWidgets('las píldoras nunca se apilan, aunque el texto sea grande', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _montar(
        tester,
        EventRow(
          date: DateTime(2020, 8, 10),
          title: 'Congreso',
          place:
              'Centro de Convenciones Espacio Riesco, Avenida El Salto 5000, Huechuraba',
          chip: const TwOriginPill(interno: true),
          finalizado: true,
          onTap: () {},
        ),
        ancho: 320,
      );

      final origen = tester.getTopLeft(find.text('INTERNO'));
      final estado = tester.getTopLeft(find.text('FINALIZADO'));
      expect(origen.dy, closeTo(estado.dy, 1));
      expect(tester.takeException(), isNull);
    });
  });
}
