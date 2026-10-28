import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/core/network/connectivity_service.dart';
import 'package:transworld_nexus/core/widgets/tw_sync_notice_card.dart';
import 'package:transworld_nexus/data/offline/snapshot_service.dart';
import 'package:transworld_nexus/data/offline/sync_queue_service.dart';

class _SnapshotFijo extends SnapshotService {
  _SnapshotFijo(super.ref, SnapshotEstado estado) {
    state = estado;
  }
}

Future<void> _montar(
  WidgetTester tester, {
  bool hayRed = true,
  int pendientes = 0,
  bool subiendo = false,
  SnapshotEstado snapshot = const SnapshotEstado(),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isOnlineProvider.overrideWith((ref) => hayRed),
        pendingSyncCountProvider.overrideWith((ref) => pendientes),
        syncEnCursoProvider.overrideWith((ref) => subiendo),
        syncConflictsProvider.overrideWith((ref) => const []),
        snapshotServiceProvider.overrideWith(
          (ref) => _SnapshotFijo(ref, snapshot),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: TwSyncNoticeCard())),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('sin pendientes ni descarga no ocupa sitio', (tester) async {
    await _montar(tester);
    expect(find.byKey(const Key('aviso_sync_pendientes')), findsNothing);
    expect(find.byKey(const Key('aviso_sync_descarga')), findsNothing);
  });

  testWidgets('sin red avisa lo guardado en el teléfono', (tester) async {
    await _montar(tester, hayRed: false, pendientes: 2);
    expect(find.text('2 cambios guardados en el teléfono'), findsOneWidget);
    expect(
      find.text('Se subirán solos cuando vuelva la conexión.'),
      findsOneWidget,
    );
  });

  testWidgets('con red y pendientes ofrece reintentar', (tester) async {
    await _montar(tester, pendientes: 1);
    expect(find.text('1 cambio sin subir'), findsOneWidget);
  });

  testWidgets('mientras sube muestra la barra', (tester) async {
    await _montar(tester, pendientes: 1, subiendo: true);
    expect(find.text('Subiendo cambios'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('la bajada de la copia local muestra etapa y porcentaje', (
    tester,
  ) async {
    await _montar(
      tester,
      snapshot: const SnapshotEstado(
        enCurso: true,
        progreso: SnapshotProgreso(
          etapa: SnapshotEtapa.listas,
          completados: 1,
          total: 2,
        ),
      ),
    );
    expect(
      find.text('Descargando copia para usar sin conexión'),
      findsOneWidget,
    );
    // Etapa 6 de 7 a medias: (5 + 0,5) / 7.
    expect(find.text('Asistentes y leads · 79 %'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('una bajada con errores lo dice', (tester) async {
    await _montar(
      tester,
      snapshot: const SnapshotEstado(errores: ['Imágenes: sin red']),
    );
    expect(find.text('Copia sin conexión incompleta'), findsOneWidget);
  });

  testWidgets('los pendientes tienen prioridad sobre la descarga', (
    tester,
  ) async {
    await _montar(
      tester,
      pendientes: 1,
      snapshot: const SnapshotEstado(
        enCurso: true,
        progreso: SnapshotProgreso(etapa: SnapshotEtapa.catalogo),
      ),
    );
    expect(find.text('1 cambio sin subir'), findsOneWidget);
    expect(find.byKey(const Key('aviso_sync_descarga')), findsNothing);
  });
}
