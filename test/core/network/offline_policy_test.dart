import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/core/network/offline_policy.dart';
import 'package:transworld_nexus/core/router/route_paths.dart';

void main() {
  group('OfflinePolicy.supportsOfflineCache', () {
    test('móvil, Windows y macOS operan con caché local', () {
      for (final plataforma in const [
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.windows,
        TargetPlatform.macOS,
      ]) {
        expect(
          OfflinePolicy.supportsOfflineCache(plataforma, isWeb: false),
          isTrue,
          reason: '$plataforma es una plataforma de feria',
        );
      }
    });

    test('Linux no tiene modo offline', () {
      for (final plataforma in const [TargetPlatform.linux]) {
        expect(
          OfflinePolicy.supportsOfflineCache(plataforma, isWeb: false),
          isFalse,
        );
      }
    });

    test('web nunca, ni siquiera si el motor reporta un móvil', () {
      // Chrome en un teléfono reporta `TargetPlatform.android`, pero sigue
      // siendo web: no hay sistema de archivos para las fotos ni snapshot.
      expect(
        OfflinePolicy.supportsOfflineCache(TargetPlatform.android, isWeb: true),
        isFalse,
      );
    });
  });

  group('OfflinePolicy.blocksUiWhenOffline', () {
    test('es el complemento exacto de soportar caché', () {
      for (final plataforma in TargetPlatform.values) {
        for (final web in const [true, false]) {
          expect(
            OfflinePolicy.blocksUiWhenOffline(plataforma, isWeb: web),
            !OfflinePolicy.supportsOfflineCache(plataforma, isWeb: web),
          );
        }
      }
    });
  });

  group('OfflinePolicy.isAuthGateRoute', () {
    test('login y recuperar contraseña quedan siempre visibles', () {
      expect(OfflinePolicy.isAuthGateRoute(RoutePaths.login), isTrue);
      expect(
        OfflinePolicy.isAuthGateRoute(RoutePaths.recuperarPassword),
        isTrue,
      );
    });

    test('el resto de la app sí se puede tapar', () {
      for (final ruta in [
        RoutePaths.home,
        RoutePaths.eventos,
        RoutePaths.perfil,
        RoutePaths.splash,
        RoutePaths.recrearPass,
        RoutePaths.usarEvento('evento-1'),
      ]) {
        expect(
          OfflinePolicy.isAuthGateRoute(ruta),
          isFalse,
          reason: '$ruta no es una puerta de autenticación',
        );
      }
    });
  });
}
