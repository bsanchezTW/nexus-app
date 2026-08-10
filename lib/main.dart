import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/theme/app_theme.dart';
import 'data/offline/sync_queue_service.dart';
import 'data/supabase/supabase_client_provider.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!DefaultFirebaseOptions.isConfigured) return;
  // Background handler registrado; Firebase se inicializa en primer plano.
}

const _webInitTimeout = Duration(seconds: 20);

Future<T> _awaitInit<T>(Future<T> future, String label) {
  if (!kIsWeb) return future;
  return future.timeout(
    _webInitTimeout,
    onTimeout: () => throw TimeoutException(
      'La inicialización de "$label" superó ${_webInitTimeout.inSeconds}s.',
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) usePathUrlStrategy();

  final isMobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (isMobile && DefaultFirebaseOptions.isConfigured) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  try {
    await _awaitInit(Env.load(), 'env');
    await _awaitInit(initializeDateFormatting('es'), 'locale');
    await _awaitInit(initSupabase(), 'supabase');
    final sharedPreferences =
        await _awaitInit(SharedPreferences.getInstance(), 'prefs');

    runApp(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        ],
        child: const TransworldNexusApp(),
      ),
    );
  } catch (e, st) {
    debugPrint('Arranque falló: $e\n$st');
    runApp(_BootFailureApp(error: e));
  }
}

/// Pantalla mínima si el arranque web falla (timeout / .env / Supabase).
class _BootFailureApp extends StatelessWidget {
  const _BootFailureApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        backgroundColor: AppColors.primaryDeep,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined,
                      color: Colors.white70, size: 40),
                  const SizedBox(height: 16),
                  const Text(
                    'No se pudo iniciar RegisPro',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    kIsWeb
                        ? 'Recarga la página. Si el problema continúa, limpia la caché del sitio.'
                        : 'Reinicia la aplicación e inténtalo de nuevo.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, height: 1.4),
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 16),
                    Text(
                      '$error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
