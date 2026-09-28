/// Nombres de tablas, columnas y RPCs de Supabase, en un solo lugar.
///
/// Evita repetir strings mágicos (`'registrados'`, `'evento_id'`, etc.) por
/// todas las pantallas, como ocurría en el proyecto legado. Todas las
/// tablas viven en el esquema `public` (ver supabase/schema.sql).
class SupabaseTables {
  SupabaseTables._();

  static const perfiles = 'perfiles';
  static const eventos = 'eventos';
  static const registrados = 'registrados';
  static const subeventos = 'subeventos';
  static const inscripcionesSubevento = 'inscripciones_subevento';
  static const enviosQr = 'envios_qr';

  static const usuariosEventos = 'usuarios_eventos';

  /// Eventos del módulo Capturador de leads (tabla independiente de [eventos]).
  static const eventosLeads = 'eventos_leads';
  static const leads = 'leads';
  static const leadComentarios = 'lead_comentarios';

  static const notificaciones = 'notificaciones';
  static const notificacionesLeidas = 'notificaciones_leidas';
  static const notificacionesOcultas = 'notificaciones_ocultas';
  static const deviceTokens = 'device_tokens';

  /// Fijados personales por usuario (eventos y eventos de leads, por separado).
  static const usuariosEventosFijados = 'usuarios_eventos_fijados';
  static const usuariosEventosLeadsFijados = 'usuarios_eventos_leads_fijados';

  /// Perfil sistema al que se reasignan las FKs históricas
  /// (`acreditado_por`, `ingresado_por`, `creado_por`, `perfil_id` de
  /// leads) al eliminar un usuario. No debe listarse en la UI de gestión.
  static const perfilUsuarioEliminadoId =
      '00000000-0000-0000-0000-000000000001';
}

class SupabaseRpc {
  SupabaseRpc._();

  static const marcarRecuperacionPass = 'marcar_recuperacion_pass';
  static const verificarUsuarioRegistrado = 'verificar_usuario_registrado';
  static const actualizarRolUsuario = 'rpe_actualizar_rol_usuario';
  static const configurarAccesoUsuario = 'rpe_configurar_acceso_usuario';
  static const configurarAccesoEvento = 'rpe_configurar_acceso_evento';
  static const eliminarUsuario = 'rpe_eliminar_usuario';
  static const obtenerEmailUsuario = 'rpe_obtener_email_usuario';
  static const sincronizarEventosUsuario = 'rpe_sincronizar_eventos_usuario';
  static const sincronizarEventosExterno = 'rpe_sincronizar_eventos_externo';
  static const ocultarTodasNotificaciones = 'rpe_ocultar_todas_notificaciones';
  static const resumenCampana = 'cl_resumen_campana';
  static const guardarLead = 'cl_guardar_lead';
  static const buscarLeadPorEmail = 'cl_buscar_lead_por_email';
  static const existeEmailRegistrado = 'rpe_existe_email_registrado';
  static const registrarAsistente = 'rpe_registrar_asistente';
  static const importarRegistrados = 'rpe_importar_registrados';
  static const regenerarCodigoQr = 'rpe_regenerar_codigo_qr';
  static const ocupacionEvento = 'rpe_ocupacion_evento';
  static const inscribirSubevento = 'rpe_inscribir_subevento';
  static const quitarInscripcionSubevento = 'rpe_quitar_inscripcion_subevento';
  static const marcarAsistenciaSubevento = 'rpe_marcar_asistencia_subevento';
  static const misAcreditados = 'rpe_mis_acreditados';
}

class SupabaseFunctions {
  SupabaseFunctions._();

  static const resetPassword = 'reset-password';
  static const enviarQr = 'enviar-qr';
  static const qrImagen = 'qr-imagen';
  static const crearUsuario = 'crear-usuario';
  static const regenerarPasswordUsuario = 'regenerar-password-usuario';
  static const enviarPush = 'enviar-push';
  static const limpiarStorage = 'limpiar-storage';
}
