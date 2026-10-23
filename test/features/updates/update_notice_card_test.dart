import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:transworld_nexus/data/models/github_release.dart';
import 'package:transworld_nexus/features/updates/providers/update_providers.dart';
import 'package:transworld_nexus/features/updates/services/update_service.dart';
import 'package:transworld_nexus/features/updates/widgets/update_notice_card.dart';

const _info = AppUpdateInfo(
  installedVersion: '1.9.0',
  remoteVersion: '1.10.0',
  releaseName: 'RegisPro v1.10.0',
  notes: 'Novedades',
  asset: GitHubReleaseAsset(
    name: 'android-regispro-v1.10.0.apk',
    size: 1024,
    browserDownloadUrl: 'https://example.com/a.apk',
  ),
  tagName: 'v1.10.0',
);

/// Controlador con un estado fijo: el aviso solo lee el estado.
class _ControladorFijo extends UpdateController {
  _ControladorFijo(super.ref, UpdateState inicial) {
    state = inicial;
  }
}

Widget _app(UpdateState estado) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) =>
            const Scaffold(body: Center(child: UpdateNoticeCard())),
      ),
      GoRoute(
        path: '/actualizaciones',
        builder: (_, _) => const Scaffold(body: Text('Pantalla de updates')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      updateControllerProvider.overrideWith(
        (ref) => _ControladorFijo(ref, estado),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('sin versión nueva no hay aviso', (tester) async {
    await tester.pumpWidget(
      _app(const UpdateState(status: UpdateStatus.upToDate)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('aviso_actualizacion')), findsNothing);
  });

  testWidgets('con versión nueva avisa sin modal y abre Actualizaciones', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const UpdateState(status: UpdateStatus.available, info: _info)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nueva versión disponible'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);

    await tester.tap(find.byKey(const Key('aviso_actualizacion')));
    await tester.pumpAndSettle();

    expect(find.text('Pantalla de updates'), findsOneWidget);
  });

  testWidgets('durante la descarga muestra el avance', (tester) async {
    await tester.pumpWidget(
      _app(
        const UpdateState(
          status: UpdateStatus.downloading,
          info: _info,
          progress: 0.45,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Descargando actualización'), findsOneWidget);
    expect(find.textContaining('45 %'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}
