import 'package:flutter/foundation.dart';

import '../router/route_paths.dart';

/// Qué puede hacer cada plataforma cuando no hay Internet.
///
/// La app es de feria: en el teléfono y en el notebook de la mesa de
/// acreditación tiene que seguir operando con la copia local. La web no tiene
/// dónde guardar fotos ni un snapshot completo, así que sin Internet se
/// bloquea con un aviso en vez de degradar. Linux no se usa y queda igual que
/// la web.
///
/// Las decisiones viven como funciones puras, igual que
/// `external_route_policy.dart` y `user_event_route_policy.dart`, para poder
/// probarlas sin montar la app ni simular una plataforma real.
class OfflinePolicy {
  const OfflinePolicy._();

  /// Plataformas que mantienen caché local y colas de escritura.
  static bool supportsOfflineCache(
    TargetPlatform platform, {
    required bool isWeb,
  }) {
    if (isWeb) return false;
    return switch (platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.windows ||
      TargetPlatform.macOS => true,
      TargetPlatform.linux || TargetPlatform.fuchsia => false,
    };
  }

  /// Plataformas que, sin red real, tapan la app con un aviso a pantalla
  /// completa.
  static bool blocksUiWhenOffline(
    TargetPlatform platform, {
    required bool isWeb,
  }) {
    return !supportsOfflineCache(platform, isWeb: isWeb);
  }

  /// Rutas que el overlay nunca puede cubrir.
  ///
  /// Sin red no se puede iniciar sesión, pero el usuario tiene que poder ver
  /// el formulario y el enlace de recuperación: taparlos deja la app sin
  /// ninguna pantalla utilizable y sin explicación.
  static bool isAuthGateRoute(String location) {
    return location == RoutePaths.login ||
        location == RoutePaths.recuperarPassword;
  }
}

/// Valores de la plataforma real en ejecución.
bool get supportsOfflineCacheAqui =>
    OfflinePolicy.supportsOfflineCache(defaultTargetPlatform, isWeb: kIsWeb);

bool get blocksUiWhenOfflineAqui =>
    OfflinePolicy.blocksUiWhenOffline(defaultTargetPlatform, isWeb: kIsWeb);
