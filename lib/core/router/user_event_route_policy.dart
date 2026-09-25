/// Política de navegación del rol `user` dentro del módulo de eventos.
///
/// La autorización real vive en RLS. Esta allowlist evita que un enlace
/// profundo abra una pantalla de un evento que no está en `usuarios_eventos`
/// y ofrece una denegación predecible mientras esa lista se está cargando.
bool isUserEventRouteAllowed({
  required String location,
  required Set<String>? authorizedEventIds,
}) {
  if (location == '/eventos') return true;
  if (!location.startsWith('/eventos/')) return true;

  final segments = Uri(path: location).pathSegments;
  if (segments.length < 3 || segments.first != 'eventos') return false;

  final eventId = segments[1];
  if (eventId.isEmpty || eventId == 'crear') return false;
  if (authorizedEventIds == null || !authorizedEventIds.contains(eventId)) {
    return false;
  }

  final action = segments[2];
  if (segments.length == 3) {
    return const {
      'usar',
      'registrar',
      'registro-cliente',
      'acreditar',
      'acreditar-qr',
      'registrados',
      'kpi',
    }.contains(action);
  }

  return segments.length == 5 &&
      action == 'registrados' &&
      segments[3].isNotEmpty &&
      segments[4] == 'editar';
}

/// Gestión de acceso por evento. Solo administradores; el router redirige
/// al listado si el perfil no puede gestionar usuarios.
bool isEventAccessManagementRoute(String location) {
  final segments = Uri(path: location).pathSegments;
  return segments.length == 3 &&
      segments.first == 'eventos' &&
      segments[1].isNotEmpty &&
      segments[1] != 'crear' &&
      segments.last == 'acceso';
}

/// Exportaciones de datos sensibles. El router usa esta detección como una
/// segunda barrera además de ocultar la acción y proteger la propia pantalla.
bool isDataExportRoute(String location) {
  final segments = Uri(path: location).pathSegments;
  if (segments.length != 3 || segments.last != 'exportar') return false;
  return segments.first == 'eventos' || segments.first == 'capturador';
}
