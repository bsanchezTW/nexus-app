import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../conexion/estado_conexion.dart';
import '../conexion/monitor_conexion.dart';
import '../network/offline_policy.dart';
import '../theme/tw_tokens.dart';

/// Tapa la app cuando no hay Internet en las plataformas que no tienen modo
/// offline (web y Linux).
///
/// Ahí no se baja el snapshot ni existe caché operativa: dejar navegar produce
/// listas vacías y formularios cuyas escrituras se pierden. En móvil, Windows y
/// macOS no aparece nunca —esas sí operan con disco— y tampoco cubre login ni
/// recuperar contraseña, que deben seguir visibles.
///
/// Solo bloquea cuando no hay forma de llegar al servidor —sin Internet o con
/// la base de datos sin responder—, y dice cuál de los dos es: con la base de
/// datos caída, revisar el wifi no sirve de nada. Con la conexión inestable la
/// web sigue funcionando, más lenta, y lo avisa `TwAvisosSistema`.
class OfflineBlockingOverlay extends ConsumerWidget {
  const OfflineBlockingOverlay({
    super.key,
    required this.router,
    required this.child,
  });

  final GoRouter router;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!blocksUiWhenOfflineAqui) return child;

    // `verificando` no bloquea: si no, el overlay parpadea en cada arranque.
    final estado = ref.watch(estadoConexionProvider);
    if (!estado.servidorInalcanzable) return child;
    final sinBackend = estado == EstadoConexion.sinBackend;

    return ListenableBuilder(
      listenable: router.routerDelegate,
      builder: (context, _) {
        final location = router.routerDelegate.currentConfiguration.uri.path;
        if (OfflinePolicy.isAuthGateRoute(location)) return child;
        return Stack(
          children: [
            child,
            Positioned.fill(child: _AvisoSinConexion(sinBackend: sinBackend)),
          ],
        );
      },
    );
  }
}

class _AvisoSinConexion extends StatelessWidget {
  const _AvisoSinConexion({required this.sinBackend});

  /// Hay Internet, pero la base de datos no responde.
  final bool sinBackend;

  @override
  Widget build(BuildContext context) {
    // `AbsorbPointer` deja la app de abajo intacta pero inalcanzable: no se
    // navega ni se pulsa nada mientras dure el corte.
    return AbsorbPointer(
      child: Material(
        color: TwColors.bg,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  sinBackend
                      ? Symbols.database_off_rounded
                      : Symbols.wifi_off_rounded,
                  size: 56,
                  color: TwColors.danger,
                ),
                const SizedBox(height: 18),
                Text(
                  sinBackend
                      ? 'Problemas con la conexión a la base de datos'
                      : 'Sin conexión',
                  style: TwText.heroTitle.copyWith(color: TwColors.ink),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  sinBackend
                      ? 'Hay Internet, pero el servidor de RegisPro no '
                            'responde. Inténtalo en unos minutos.'
                      : 'Revisa tu conexión a Internet para seguir usando '
                            'RegisPro.',
                  style: TwText.tileSubtitle,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
