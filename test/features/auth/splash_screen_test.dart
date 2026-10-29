import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:transworld_nexus/core/theme/app_theme.dart';
import 'package:transworld_nexus/features/auth/providers/splash_providers.dart';
import 'package:transworld_nexus/features/auth/screens/splash_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SplashScreen renders looping Lottie on brand background', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SplashScreen(armProfileTimeout: true)),
      ),
    );

    expect(find.byType(Scaffold), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppColors.background);
    expect(find.byType(Lottie), findsOneWidget);

    await tester.pump();
    await tester.pump(const Duration(seconds: 8));
  });

  testWidgets('el logo limpio y la animación comparten la caja del splash '
      'nativo', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SplashScreen())),
    );

    final logo = find.byWidgetPredicate(
      (w) =>
          w is Image &&
          w.image == const AssetImage('assets/images/splash/logo_inicio.png'),
    );
    expect(logo, findsOneWidget);
    expect(tester.getSize(logo), const Size.square(tamanoLogoInicio));
    expect(
      tester.getSize(find.byType(Lottie)),
      const Size.square(tamanoLogoInicio),
    );
    // Mismo centro que el splash nativo: el centro de la pantalla.
    expect(tester.getCenter(logo), tester.getCenter(find.byType(Scaffold)));

    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('splashReady is true on first frame, without waiting animation', (
    tester,
  ) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(
              home: SplashScreen(armProfileTimeout: true),
            );
          },
        ),
      ),
    );

    expect(container.read(splashReadyProvider), isTrue);
    expect(container.read(splashNavigationTimedOutProvider), isFalse);

    await tester.pump(const Duration(milliseconds: 2500));
    expect(container.read(splashReadyProvider), isTrue);
    expect(container.read(splashNavigationTimedOutProvider), isFalse);

    await tester.pump(const Duration(seconds: 8));
    expect(container.read(splashNavigationTimedOutProvider), isTrue);
  });
}
