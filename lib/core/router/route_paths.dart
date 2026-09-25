import '../config/env.dart';

/// Rutas centralizadas de la app (usadas por `go_router`).
///
/// Mantener esto en un solo archivo evita el problema de rutas "sueltas"
/// como el alias accidental `/RecuperarPassword` detectado en el proyecto
/// legado (documentacion_zips_registro_pro.md, Sección 17.9).
class RoutePaths {
  RoutePaths._();

  static const splash = '/splash';
  static const login = '/login';
  static const recuperarPassword = '/recuperar-password';
  static const recrearPass = '/recrear-pass';
  static const eventoFinalizado = '/evento-finalizado';

  static const home = '/';
  static const perfil = '/perfil';
  static const misAcreditados = '/perfil/acreditados';
  static const actualizaciones = '/actualizaciones';
  static const sincronizacion = '/sincronizacion';
  static const notificaciones = '/notificaciones';

  static const eventos = '/eventos';
  static const crearEvento = '/eventos/crear';
  static String editarEvento(String id) => '/eventos/$id/editar';
  static String accesoEvento(String id) => '/eventos/$id/acceso';
  static String usarEvento(String id) => '/eventos/$id/usar';
  static String subeventos(String eventoId) => '/eventos/$eventoId/subeventos';
  static String crearSubevento(String eventoId) =>
      '/eventos/$eventoId/subeventos/crear';
  static String editarSubevento(String eventoId, String subeventoId) =>
      '/eventos/$eventoId/subeventos/$subeventoId/editar';
  static String registrar(String id) => '/eventos/$id/registrar';
  static String registroPorCliente(String id) =>
      '/eventos/$id/registro-cliente';
  static String acreditarConfirmado(String id) => '/eventos/$id/acreditar';
  static String acreditarQr(String id) => '/eventos/$id/acreditar-qr';
  static String verRegistrados(String id) => '/eventos/$id/registrados';
  static String editarRegistrado(String eventoId, String registradoId) =>
      '/eventos/$eventoId/registrados/$registradoId/editar';
  static String kpi(String id) => '/eventos/$id/kpi';
  static String exportar(String id) => '/eventos/$id/exportar';

  static String externoEvento(String id) => '/externo/eventos/$id';

  static const usuarios = '/usuarios';
  static const nuevoUsuario = '/usuarios/nuevo';
  static String editarUsuario(String id) => '/usuarios/$id/editar';

  /// Módulo Capturador de leads (`eventos_leads` / `leads`).
  static const capturador = '/capturador';
  static const crearEventoLead = '/capturador/crear';
  static String editarEventoLead(String id) => '/capturador/$id/editar';
  static String usarEventoLead(String id) => '/capturador/$id/usar';
  static String capturarLead(String id, {String? desdeEvento}) {
    final base = '/capturador/$id/capturar';
    if (desdeEvento == null || desdeEvento.isEmpty) return base;
    return '$base?desdeEvento=${Uri.encodeQueryComponent(desdeEvento)}';
  }

  static String verLeads(String id, {String? desdeEvento}) {
    final base = '/capturador/$id/leads';
    return _conDesdeEvento(base, desdeEvento);
  }

  static String detalleLead(
    String eventoId,
    String leadId, {
    String? desdeEvento,
  }) {
    return _conDesdeEvento('/capturador/$eventoId/leads/$leadId', desdeEvento);
  }

  static String comentariosLead(
    String eventoId,
    String leadId, {
    String? desdeEvento,
  }) {
    return _conDesdeEvento(
      '/capturador/$eventoId/leads/$leadId/comentarios',
      desdeEvento,
    );
  }

  static String exportarLeads(String id) => '/capturador/$id/exportar';

  static String _conDesdeEvento(String base, String? desdeEvento) {
    if (desdeEvento == null || desdeEvento.isEmpty) return base;
    return '$base?desdeEvento=${Uri.encodeQueryComponent(desdeEvento)}';
  }

  static String urlPublicaEvento(String slug) {
    final base = Env.publicWebBaseUrl.replaceAll(RegExp(r'/$'), '');
    return '$base/eventos/$slug';
  }
}
