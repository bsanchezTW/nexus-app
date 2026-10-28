import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/core/avisos/aviso_sistema.dart';
import 'package:transworld_nexus/features/sincronizacion/providers/avisos_sistema_provider.dart';
import 'package:transworld_nexus/features/sincronizacion/widgets/tw_avisos_sistema.dart';
import 'package:transworld_nexus/features/updates/providers/update_providers.dart';
import 'package:transworld_nexus/features/updates/services/update_service.dart';
import 'package:transworld_nexus/features/updates/widgets/update_notice_card.dart';

class _ActualizacionAlDia extends UpdateController {
  _ActualizacionAlDia(super.ref) {
    state = const UpdateState(status: UpdateStatus.upToDate);
  }
}

const _sinInternet = AvisoSistema(
  tipo: TipoAviso.sinInternet,
  titulo: 'Sin conexión a internet',
  detalle: 'Trabajas con la copia local',
);

const _pendientes = AvisoSistema(
  tipo: TipoAviso.pendientes,
  titulo: '3 cambios por subir',
  detalle: 'Están guardados en este dispositivo y se subirán solos',
  cantidad: 3,
);

const _descargando = AvisoSistema(
  tipo: TipoAviso.descargando,
  titulo: 'Preparando el modo sin conexión',
  detalle: 'Puedes seguir usando la app con normalidad · Eventos 40 %',
  progreso: 0.4,
);

Future<void> _montar(
  WidgetTester tester,
  List<AvisoSistema> avisos,
  Widget hijo,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        avisosSistemaProvider.overrideWithValue(avisos),
        updateControllerProvider.overrideWith(_ActualizacionAlDia.new),
      ],
      child: MaterialApp(
        home: Scaffold(body: Column(children: [hijo])),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('TwAvisosSistema', () {
    testWidgets('sin avisos no ocupa sitio', (tester) async {
      await _montar(tester, const [], const TwAvisosSistema(topGap: 20));
      expect(find.byType(TarjetaAvisoSistema), findsNothing);
    });

    testWidgets('pinta la conexión arriba y la actividad debajo', (
      tester,
    ) async {
      await _montar(tester, const [
        _sinInternet,
        _pendientes,
      ], const TwAvisosSistema());

      final conexion = tester.getRect(find.text('Sin conexión a internet'));
      final actividad = tester.getRect(find.text('3 cambios por subir'));
      expect(conexion.top, lessThan(actividad.top));
    });

    testWidgets('la descarga se ve con su barra de progreso', (tester) async {
      await _montar(tester, const [_descargando], const TwAvisosSistema());

      expect(find.text('Preparando el modo sin conexión'), findsOneWidget);
      expect(
        find.text('Puedes seguir usando la app con normalidad · Eventos 40 %'),
        findsOneWidget,
      );
      final barra = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(barra.value, 0.4);
    });

    testWidgets('la actualización solo ocupa el lugar si está libre', (
      tester,
    ) async {
      await _montar(tester, const [_sinInternet], const TwAvisosSistema());
      expect(find.byType(UpdateNoticeCard), findsOneWidget);

      await _montar(tester, const [_pendientes], const TwAvisosSistema());
      expect(find.byType(UpdateNoticeCard), findsNothing);

      await _montar(
        tester,
        const [],
        const TwAvisosSistema(incluirActualizacion: false),
      );
      expect(find.byType(UpdateNoticeCard), findsNothing);
    });

    testWidgets('topGap deja aire sobre la tarjeta', (tester) async {
      await _montar(tester, const [
        _sinInternet,
      ], const TwAvisosSistema(topGap: 20));
      final tarjeta = tester.getRect(find.byType(TarjetaAvisoSistema));
      expect(tarjeta.top, greaterThanOrEqualTo(20));
    });
  });

  group('TwIndicadorConexion', () {
    testWidgets('no aparece si no hay nada que avisar', (tester) async {
      await _montar(tester, const [], const TwIndicadorConexion());
      expect(find.byKey(const Key('indicador_conexion')), findsNothing);
    });

    testWidgets('muestra la cantidad por subir y abre los avisos', (
      tester,
    ) async {
      await _montar(tester, const [
        _sinInternet,
        _pendientes,
      ], const TwIndicadorConexion());

      expect(find.byKey(const Key('indicador_conexion')), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('indicador_conexion')));
      await tester.pumpAndSettle();

      expect(find.text('Conexión y datos'), findsOneWidget);
      expect(find.text('Sin conexión a internet'), findsOneWidget);
      expect(find.text('3 cambios por subir'), findsOneWidget);
    });

    testWidgets('sobre la cámara muestra el título del aviso', (tester) async {
      await _montar(tester, const [
        _descargando,
      ], const TwIndicadorConexion(sobreOscuro: true));

      expect(find.text('Preparando el modo sin conexión'), findsOneWidget);
    });
  });
}
