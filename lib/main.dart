import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';
import 'core/desktop/desktop_window.dart';
import 'core/widgets/espera_bloqueante.dart';
import 'features/auth/screens/splash_screen.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!DefaultFirebaseOptions.isConfigured) return;
  // Background handler registrado; Firebase se inicializa en primer plano.
}

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // El splash nativo se va con el primer cuadro: que ese cuadro ya traiga el
  // logo del inicio, para que el traspaso no parpadee.
  retenerPrimerCuadroHastaElLogo(binding);
  // Antes que el router: así el "atrás" se ignora mientras se guarda.
  EsperaBloqueante.instalar();
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
