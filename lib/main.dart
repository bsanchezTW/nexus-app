import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';
import 'core/desktop/desktop_window.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!DefaultFirebaseOptions.isConfigured) return;
  // Background handler registrado; Firebase se inicializa en primer plano.
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) usePathUrlStrategy();
  await bootstrapDesktopWindow();

  // La app está diseñada solo en vertical. El manifiesto de Android y el
  // Info.plist ya lo fijan; esto cubre el resto de los casos móviles.
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  if (!kIsWeb && Platform.isAndroid && DefaultFirebaseOptions.isConfigured) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  // Env / fechas / Supabase / prefs: en [appBootstrapProvider], después del
  // primer frame, para que Android suelte el splash nativo de inmediato.
  runApp(const ProviderScope(child: TransworldNexusApp()));
}
