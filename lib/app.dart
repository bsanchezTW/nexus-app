import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/conexion/monitor_conexion.dart';
import 'core/config/app_bootstrap.dart';
import 'core/desktop/desktop_window.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_scroll_behavior.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/browser_theme_color.dart';
import 'core/widgets/action_lock.dart';
import 'core/widgets/app_widgets.dart';
import 'core/widgets/offline_blocking_overlay.dart';
import 'core/widgets/sync_conflict_listener.dart';
import 'core/widgets/windows_mouse_gestures.dart';
import 'data/offline/orquestador_reconexion.dart';
import 'data/offline/snapshot_service.dart';
import 'data/offline/sync_coordinator.dart';
import 'features/auth/providers/auth_providers.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/notificaciones/providers/notificaciones_providers.dart';
import 'features/notificaciones/services/push_notification_service.dart';
import 'features/sincronizacion/providers/sincronizacion_en_vivo_provider.dart';
import 'features/updates/widgets/windows_update_gate.dart';

/// Router mínimo del splash de bootstrap.
///
/// Tiene que ser [MaterialApp.router] (no un [MaterialApp] con `home`): en web
/// el `MaterialApp` suelto pone el motor en historial de una sola entrada y el
/// botón atrás de Chrome deja de recorrer las pantallas de la app.
final _bootRouter = GoRouter(
  routes: [GoRoute(path: '/', builder: (context, state) => const _BootGate())],
  errorBuilder: (context, state) => const _BootGate(),
);

class TransworldNexusApp extends ConsumerWidget {
  const TransworldNexusApp({super.key});

  static String get publicAppName =>
      kIsWeb ? 'Transworld | RegisPro' : 'RegisPro';

  static const _localizationsDelegates = [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(appBootstrapProvider);

    if (boot.hasValue) {
      ref.watch(currentPerfilProvider);
      return const _ReadyApp();
    }

    return BrowserThemeColor(
      color: AppColors.background,
      child: MaterialApp.router(
        title: publicAppName,
        debugShowCheckedModeBanner: false,
        // Tema liviano: [AppTheme.light] baja Plus Jakarta (google_fonts) y
        // retrasaría el primer frame que Android usa para soltar el splash.
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            surface: AppColors.background,
          ),
          scaffoldBackgroundColor: AppColors.background,
        ),
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: _localizationsDelegates,
        scrollBehavior: const AppScrollBehavior(),
        routerConfig: _bootRouter,
      ),
    );
  }
}

class _BootGate extends ConsumerWidget {
  const _BootGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(appBootstrapProvider);
    if (boot.hasError) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: ErrorView(
          message: 'No se pudo iniciar la app.\n${boot.error}',
          onRetry: () => ref.invalidate(appBootstrapProvider),
        ),
      );
    }
    return const SplashScreen();
  }
}

class _ReadyApp extends ConsumerWidget {
  const _ReadyApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Sondeos al backend: deciden si la app opera en línea o con su copia
    // local (ver core/conexion/monitor_conexion.dart).
    ref.watch(monitorConexionInitializerProvider);
    // Al volver a una conexión estable: subir la cola, recargar y respaldar.
    ref.watch(orquestadorReconexionProvider);
    ref.watch(syncCoordinatorInitializerProvider);
    ref.watch(snapshotAutoStartProvider);
    ref.watch(notificacionesRealtimeSubscriptionProvider);
    ref.watch(sincronizacionEnVivoProvider);
    ref.watch(pushNotificationsBootstrapProvider);

    final router = ref.watch(appRouterProvider);
    ref.read(pushNotificationServiceProvider).attachRouter(router);

    return BrowserThemeColor(
      color: AppColors.background,
      child: MaterialApp.router(
        title: TransworldNexusApp.publicAppName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: TransworldNexusApp._localizationsDelegates,
        scrollBehavior: const AppScrollBehavior(),
        routerConfig: router,
        builder: (context, child) => DesktopWindowFrame(
          child: WindowsMouseGestures(
            router: router,
            child: ActionLockBarrier(
              child: OfflineBlockingOverlay(
                router: router,
                child: SyncConflictListener(
                  child: WindowsUpdateGate(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
