import '../conexion/estado_conexion.dart';

/// Qué se le avisa al usuario sobre la conexión y la copia local.
enum TipoAviso {
  sinInternet,
  sinBackend,
  inestable,
  copiaLocal,
  conflictos,
  subiendo,
  pendientes,
  descargando,
  descargaIncompleta,
}

/// Lugar del aviso. Se muestra como mucho uno de cada ranura a la vez: el
/// estado de la conexión y, debajo, lo que la app está haciendo con los
/// datos. Más de dos tarjetas seguidas tapan el contenido de la pantalla.
enum RanuraAviso { conexion, actividad }

/// Qué pasa al tocar el aviso.
enum AccionAviso {
  ninguna,
  revisarConflictos,
  reintentar,
  abrirSincronizacion,

  /// Volver a pedir al servidor lo que la pantalla muestra desde la copia.
  recargar,
}

class AvisoSistema {
  const AvisoSistema({
    required this.tipo,
    required this.titulo,
    required this.detalle,
    this.accion = AccionAviso.ninguna,
    this.progreso,
    this.cantidad = 0,
  });

  final TipoAviso tipo;
  final String titulo;
  final String detalle;
  final AccionAviso accion;

  /// 0…1 para una barra; 0 pinta la barra indeterminada; `null`, sin barra.
  final double? progreso;

  /// Cambios o conflictos a los que se refiere, para el indicador compacto.
  final int cantidad;

  RanuraAviso get ranura => switch (tipo) {
    TipoAviso.sinInternet ||
    TipoAviso.sinBackend ||
    TipoAviso.inestable ||
    TipoAviso.copiaLocal => RanuraAviso.conexion,
    _ => RanuraAviso.actividad,
  };

  /// Es un problema que el usuario debería mirar, no solo información.
  bool get esProblema => switch (tipo) {
    TipoAviso.subiendo || TipoAviso.descargando => false,
    _ => true,
  };
}

/// Todo lo que decide los avisos, sin depender de Riverpod ni de la UI.
class EntradaAvisos {
  const EntradaAvisos({
    required this.estado,
    required this.enLinea,
    required this.soportaCopiaLocal,
    this.conflictos = 0,
    this.pendientes = 0,
    this.subiendo = false,
    this.descargaEnCurso = false,
    this.descargaEtapa,
    this.descargaFraccion = 0,
    this.descargaConErrores = false,
    this.mostrandoCopia = false,
    this.copiaActualizadaEn,
    this.ahora,
  });

  final EstadoConexion estado;

  /// La app está usando el servidor (ver `usaServidorProvider`).
  final bool enLinea;
  final bool soportaCopiaLocal;
  final int conflictos;
  final int pendientes;
  final bool subiendo;
  final bool descargaEnCurso;
  final String? descargaEtapa;
  final double descargaFraccion;
  final bool descargaConErrores;

  /// Alguna pantalla muestra datos de la copia local, no del servidor.
  final bool mostrandoCopia;

  /// Confirmación más vieja entre las copias que se muestran. `null` si no se
  /// sabe.
  final DateTime? copiaActualizadaEn;

  /// Reloj para "hace X". Por defecto, ahora.
  final DateTime? ahora;
}

/// "hace 5 min", "hace 2 h", "hace 3 días".
String haceCuanto(DateTime desde, DateTime ahora) {
  final d = ahora.difference(desde);
  if (d.inMinutes < 1) return 'hace un momento';
  if (d.inHours < 1) return 'hace ${d.inMinutes} min';
  if (d.inDays < 1) return 'hace ${d.inHours} h';
  return d.inDays == 1 ? 'hace 1 día' : 'hace ${d.inDays} días';
}

/// "hace X" de la copia que se muestra, o `null` si no se sabe.
String? _edadCopia(EntradaAvisos e) {
  final desde = e.copiaActualizadaEn;
  if (!e.mostrandoCopia || desde == null) return null;
  return haceCuanto(desde, e.ahora ?? DateTime.now());
}

/// Agrega la edad de la copia al detalle de un aviso de conexión degradada.
String _conEdad(String detalle, EntradaAvisos e) {
  final edad = _edadCopia(e);
  return edad == null ? detalle : '$detalle · Copia de $edad';
}

String _cambios(int n) => n == 1 ? '1 cambio' : '$n cambios';

/// Avisos vigentes, del más urgente al menos.
///
/// Como mucho uno por [RanuraAviso]: el de conexión primero y luego el de
/// actividad, que se elige por prioridad (conflictos, subida, pendientes,
/// descarga). Función pura, igual que `PoliticaConexion`, para probar los
/// textos y el orden sin montar pantallas.
List<AvisoSistema> avisosDelSistema(EntradaAvisos e) {
  return [?_avisoConexion(e), ?_avisoActividad(e)];
}

AvisoSistema? _avisoConexion(EntradaAvisos e) {
  return switch (e.estado) {
    EstadoConexion.sinInternet => AvisoSistema(
      tipo: TipoAviso.sinInternet,
      titulo: 'Sin conexión a internet',
      detalle: e.soportaCopiaLocal
          ? _conEdad(
              'Trabajas con la copia local. Lo que registres se subirá al '
              'volver la conexión',
              e,
            )
          : 'Revisa tu conexión para seguir usando RegisPro',
    ),
    EstadoConexion.sinBackend => AvisoSistema(
      tipo: TipoAviso.sinBackend,
      titulo: 'Problemas con la conexión a la base de datos',
      detalle: e.soportaCopiaLocal
          ? _conEdad(
              'Hay internet, pero el servidor no responde. Trabajas con la '
              'copia local y lo que registres se subirá cuando vuelva',
              e,
            )
          : 'Hay internet, pero el servidor no responde. Inténtalo en unos '
                'minutos',
    ),
    EstadoConexion.inestable => AvisoSistema(
      tipo: TipoAviso.inestable,
      titulo: 'Conexión inestable',
      detalle: e.enLinea
          ? 'Algunas acciones pueden tardar más de lo normal'
          : _conEdad(
              'Pasamos a modo sin conexión para que no esperes. Lo que '
              'registres se subirá cuando se estabilice',
              e,
            ),
    ),
    EstadoConexion.verificando || EstadoConexion.estable => _avisoCopiaLocal(e),
  };
}

/// Con la conexión en buen estado, una pantalla igual puede estar mostrando
/// la copia: el servidor no respondió a tiempo o falló esa consulta. Sin este
/// aviso la lista vieja parecía la verdadera.
AvisoSistema? _avisoCopiaLocal(EntradaAvisos e) {
  if (!e.mostrandoCopia) return null;
  final edad = _edadCopia(e);
  return AvisoSistema(
    tipo: TipoAviso.copiaLocal,
    titulo: 'Mostrando copia local',
    detalle: edad == null
        ? 'El servidor no respondió a tiempo. Toca para reintentar'
        : 'El servidor no respondió a tiempo. Actualizada $edad · Toca para '
              'reintentar',
    accion: AccionAviso.recargar,
  );
}

AvisoSistema? _avisoActividad(EntradaAvisos e) {
  if (e.conflictos > 0) {
    return AvisoSistema(
      tipo: TipoAviso.conflictos,
      titulo: e.conflictos == 1
          ? 'Un cambio necesita revisión'
          : '${e.conflictos} cambios necesitan revisión',
      detalle: e.conflictos == 1
          ? 'El servidor no lo aceptó. Toca para revisarlo'
          : 'El servidor no los aceptó. Toca para revisarlos',
      accion: AccionAviso.revisarConflictos,
      cantidad: e.conflictos,
    );
  }

  if (e.pendientes > 0) {
    if (e.subiendo) {
      return AvisoSistema(
        tipo: TipoAviso.subiendo,
        titulo: 'Subiendo cambios',
        detalle: '${_cambios(e.pendientes)} por enviar al servidor',
        progreso: 0,
        cantidad: e.pendientes,
      );
    }
    return AvisoSistema(
      tipo: TipoAviso.pendientes,
      titulo: '${_cambios(e.pendientes)} por subir',
      detalle: e.enLinea
          ? 'No se pudieron enviar al servidor. Toca para reintentar'
          : 'Están guardados en este dispositivo y se subirán solos',
      accion: e.enLinea ? AccionAviso.reintentar : AccionAviso.ninguna,
      cantidad: e.pendientes,
    );
  }

  if (e.descargaEnCurso) {
    final pct = (e.descargaFraccion * 100).clamp(0, 100).toStringAsFixed(0);
    final etapa = e.descargaEtapa;
    return AvisoSistema(
      tipo: TipoAviso.descargando,
      titulo: 'Preparando el modo sin conexión',
      detalle:
          'Puedes seguir usando la app con normalidad'
          '${etapa == null ? '' : ' · $etapa $pct %'}',
      accion: AccionAviso.abrirSincronizacion,
      progreso: e.descargaFraccion,
    );
  }

  if (e.descargaConErrores) {
    return const AvisoSistema(
      tipo: TipoAviso.descargaIncompleta,
      titulo: 'Copia sin conexión incompleta',
      detalle: 'Parte de los datos no se descargó. Toca para ver el detalle',
      accion: AccionAviso.abrirSincronizacion,
    );
  }

  return null;
}
