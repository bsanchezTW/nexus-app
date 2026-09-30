/// Nombres de las "tablas" de [OfflineReadCache] que no son un espejo directo
/// de una tabla de Supabase.
///
/// Los registrados y los leads se guardan bajo su nombre real
/// (`SupabaseTables.registrados`, `leads__all` / `leads__own`) porque la copia
/// es fila a fila. El resto del catálogo son listas derivadas —resúmenes,
/// fijados, destacados del home— y necesitan un nombre propio para no
/// pisarse entre sí.
class OfflineCacheTables {
  OfflineCacheTables._();

  /// Catálogo de eventos visible para el perfil (RLS ya lo recorta).
  static const eventos = 'catalogo_eventos';

  /// Talleres de todos los eventos visibles, para agruparlos en la lista.
  static const catalogoSubeventos = 'catalogo_subeventos';

  /// Un evento por clave, para poder abrir su detalle sin red.
  static const eventoDetalle = 'evento_detalle';

  /// Catálogo de actividades de captura.
  static const eventosLeads = 'catalogo_eventos_leads';

  static const eventoLeadDetalle = 'evento_lead_detalle';

  /// Vínculo `evento de registro → actividad de captura interna`.
  ///
  /// Es lo que permite capturar un lead desde un evento sin red: la actividad
  /// no se puede crear offline, así que tiene que estar ya cacheada.
  static const eventoLeadPorOrigen = 'evento_lead_por_origen';

  /// Perfiles visibles (gestión de usuarios y nombres de vendedor).
  static const usuarios = 'catalogo_usuarios';

  static const eventosFijados = 'fijados_eventos';
  static const campanasFijadas = 'fijados_campanas';

  /// Conteos globales del home.
  static const homeResumen = 'home_resumen';

  /// Slider del home ya ensamblado, con sus métricas.
  static const homeDestacados = 'home_destacados';

  /// Contadores de "Mi perfil".
  static const perfilStats = 'perfil_stats';

  /// Leads propios que muestra "Mi perfil".
  static const misLeads = 'mis_leads';

  /// Asistentes que acreditó el usuario en sesión, con su evento.
  static const misAcreditados = 'mis_acreditados';

  /// Total remoto de leads del externo.
  static const externoResumen = 'externo_resumen';

  /// Eventos que el rol interno `user` tiene asignados. El router decide con
  /// esto, así que sin red debe sobrevivir en vez de fallar cerrado y dejar al
  /// usuario sin ningún evento.
  static const usuarioEventosAutorizados = 'usuario_eventos_autorizados';

  /// Eventos autorizados del externo, ya resueltos a objetos.
  static const externoEventosAutorizados = 'externo_eventos_autorizados';

  /// Metadatos del último snapshot (fecha y alcance).
  static const syncMeta = 'sync_meta';
}
