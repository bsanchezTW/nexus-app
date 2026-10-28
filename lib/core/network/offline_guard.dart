import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../conexion/estado_conexion.dart';
import '../conexion/monitor_conexion.dart';
import '../widgets/app_widgets.dart';
import 'connectivity_service.dart';

/// Texto único para cualquier operación que exige red.
const kMensajeSinConexion = 'No disponible sin conexión a Internet';

/// Mismo bloqueo con la conexión inestable: hay red, pero la app ya pasó a
/// modo sin conexión y la acción necesita al servidor.
const kMensajeConexionInestable =
    'No disponible con la conexión inestable. Inténtalo cuando se estabilice';

/// `true` si la app opera en línea. Si no, muestra el toast unificado y no
/// sigue.
bool requireOnline(BuildContext context, WidgetRef ref) {
  if (ref.read(isOnlineProvider)) return true;
  showOfflineUnavailableToast(context, ref: ref);
  return false;
}

/// Toast de "no disponible sin conexión". Con [ref] distingue la conexión
/// inestable de la falta de Internet.
void showOfflineUnavailableToast(BuildContext context, {WidgetRef? ref}) {
  final inestable =
      ref?.read(estadoConexionProvider) == EstadoConexion.inestable;
  showAppSnackBar(
    context,
    inestable ? kMensajeConexionInestable : kMensajeSinConexion,
    isError: true,
  );
}
