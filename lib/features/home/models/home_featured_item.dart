import '../../../core/constants/duracion_actividad.dart';
import '../../../core/router/route_paths.dart';
import '../../../data/models/evento.dart';
import '../../../data/models/evento_lead.dart';

enum HomeFeaturedKind {
  proximoEvento,
  eventoFijado,
  campanaFijada,
  proximaActividad,
}

/// Botones de la card del home, en orden. Va relleno (blanco) Escanear QR si
/// está; si no, el primero.
enum HomeCardAccion { verEvento, verActividad, escanearQr, capturarLead }

/// Ítem mostrable en la card/slider del header del home.
///
/// Un evento interno es **una sola** card: su actividad de captura, si la
/// tiene, viaja dentro ([actividadId]) y suma sus leads y el botón Capturar
/// lead. Solo las actividades externas (sin evento detrás) tienen card propia.
class HomeFeaturedItem {
  const HomeFeaturedItem({
    required this.kind,
    required this.id,
    required this.nombre,
    required this.fecha,
    this.lugar = '',
    this.registrados = 0,
    this.acreditados = 0,
    this.leads = 0,
    this.empresas = 0,
    this.duracionDias = 1,
    this.imagenUrl,
    this.actividadId,
  });

  final HomeFeaturedKind kind;
  final String id;
  final String nombre;
  final DateTime fecha;
  final String lugar;
  final int registrados;
  final int acreditados;
  final int leads;

  /// Empresas distintas entre los leads. Solo actividades de captura.
  final int empresas;

  /// Días que dura el evento o la actividad.
  final int duracionDias;
  final String? imagenUrl;

  /// Actividad de captura interna del evento. Solo en cards de evento.
  final String? actividadId;

  bool get tieneImagen => imagenUrl != null && imagenUrl!.isNotEmpty;

  bool get esFijado =>
      kind == HomeFeaturedKind.eventoFijado ||
      kind == HomeFeaturedKind.campanaFijada;

  bool get esActividadCaptura =>
      kind == HomeFeaturedKind.campanaFijada ||
      kind == HomeFeaturedKind.proximaActividad;

  String get etiqueta => switch (kind) {
    HomeFeaturedKind.proximoEvento => 'PRÓXIMO EVENTO',
    HomeFeaturedKind.eventoFijado => 'EVENTO FIJADO',
    HomeFeaturedKind.campanaFijada => 'ACTIVIDAD FIJADA',
    HomeFeaturedKind.proximaActividad => 'PRÓXIMA ACTIVIDAD',
  };

  /// Ya pasó su último día, igual que [Evento.yaOcurrio].
  bool get finalizado {
    final hoy = DateTime.now();
    return fechaTerminoActividad(
      fecha,
      duracionDias,
    ).isBefore(DateTime(hoy.year, hoy.month, hoy.day));
  }

  /// Todo evento acredita con QR mientras no haya terminado.
  bool get puedeEscanearQr => !esActividadCaptura && !finalizado;

  String? get qrRoutePath =>
      puedeEscanearQr ? RoutePaths.acreditarQr(id) : null;

  /// Botones de la card. Un evento con actividad de captura cambia "Ver
  /// evento" por Capturar lead + Escanear QR (el título ya abre el evento);
  /// terminado el evento, Escanear QR deja su lugar a Ver evento. Escanear
  /// QR va siempre a la derecha.
  List<HomeCardAccion> get acciones {
    if (esActividadCaptura) {
      return const [HomeCardAccion.verActividad, HomeCardAccion.capturarLead];
    }
    if (actividadId != null) {
      return finalizado
          ? const [HomeCardAccion.verEvento, HomeCardAccion.capturarLead]
          : const [HomeCardAccion.capturarLead, HomeCardAccion.escanearQr];
    }
    return finalizado
        ? const [HomeCardAccion.verEvento]
        : const [HomeCardAccion.verEvento, HomeCardAccion.escanearQr];
  }

  /// Destino del título: el evento o el hub de la actividad.
  String get routePath => esActividadCaptura
      ? RoutePaths.usarEventoLead(id)
      : RoutePaths.usarEvento(id);

  /// Formulario manual de lead: el de la actividad externa, o el de la
  /// interna del evento. `null` si el evento no tiene actividad.
  String? get capturarLeadRoutePath {
    if (esActividadCaptura) return RoutePaths.capturarLead(id);
    final actividad = actividadId;
    if (actividad == null) return null;
    return RoutePaths.capturarLead(actividad, desdeEvento: id);
  }

  /// Lista de leads (número de leads). `null` sin actividad: el 0 no abre nada.
  String? get leadsRoutePath {
    if (esActividadCaptura) return RoutePaths.verLeads(id);
    final actividad = actividadId;
    if (actividad == null) return null;
    return RoutePaths.verLeads(actividad, desdeEvento: id);
  }

  /// Lista de registrados (número de registrados). Solo eventos.
  String? get registradosRoutePath =>
      esActividadCaptura ? null : RoutePaths.verRegistrados(id);

  /// KPI del evento (porcentaje de acreditados). Solo eventos.
  String? get kpiRoutePath => esActividadCaptura ? null : RoutePaths.kpi(id);

  String get porcentajeAcreditados {
    if (registrados <= 0) return '0%';
    return '${((acreditados / registrados) * 100).round()}%';
  }

  /// Copia serializable para la caché offline.
  ///
  /// Se guarda el ítem ya ensamblado —con sus métricas— y no sus fuentes: el
  /// slider nace de media docena de consultas encadenadas y rehacerlas sin red
  /// solo produce una pantalla de error.
  Map<String, dynamic> toCacheMap() => {
    'kind': kind.name,
    'id': id,
    'nombre': nombre,
    'fecha': fecha.toIso8601String(),
    'lugar': lugar,
    'registrados': registrados,
    'acreditados': acreditados,
    'leads': leads,
    'empresas': empresas,
    'duracion_dias': duracionDias,
    'imagen_url': imagenUrl,
    'actividad_id': actividadId,
  };

  factory HomeFeaturedItem.fromCacheMap(Map<String, dynamic> map) {
    return HomeFeaturedItem(
      kind: HomeFeaturedKind.values.firstWhere(
        (k) => k.name == map['kind'],
        orElse: () => HomeFeaturedKind.proximoEvento,
      ),
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      fecha: DateTime.parse(map['fecha'] as String),
      lugar: (map['lugar'] as String?) ?? '',
      registrados: (map['registrados'] as num?)?.toInt() ?? 0,
      acreditados: (map['acreditados'] as num?)?.toInt() ?? 0,
      leads: (map['leads'] as num?)?.toInt() ?? 0,
      empresas: (map['empresas'] as num?)?.toInt() ?? 0,
      duracionDias: (map['duracion_dias'] as num?)?.toInt() ?? 1,
      imagenUrl: map['imagen_url'] as String?,
      actividadId: map['actividad_id'] as String?,
    );
  }

  HomeFeaturedItem copyWith({
    int? registrados,
    int? acreditados,
    int? leads,
    int? empresas,
    String? actividadId,
  }) {
    return HomeFeaturedItem(
      kind: kind,
      id: id,
      nombre: nombre,
      fecha: fecha,
      lugar: lugar,
      registrados: registrados ?? this.registrados,
      acreditados: acreditados ?? this.acreditados,
      leads: leads ?? this.leads,
      empresas: empresas ?? this.empresas,
      duracionDias: duracionDias,
      imagenUrl: imagenUrl,
      actividadId: actividadId ?? this.actividadId,
    );
  }

  factory HomeFeaturedItem.proximoEvento(Evento evento) {
    return HomeFeaturedItem(
      kind: HomeFeaturedKind.proximoEvento,
      id: evento.id,
      nombre: evento.nombre,
      fecha: evento.fecha,
      lugar: evento.lugar ?? evento.pais ?? '',
      duracionDias: evento.duracionDias,
      imagenUrl: evento.imagenUrl,
    );
  }

  factory HomeFeaturedItem.eventoFijado(Evento evento) {
    return HomeFeaturedItem(
      kind: HomeFeaturedKind.eventoFijado,
      id: evento.id,
      nombre: evento.nombre,
      fecha: evento.fecha,
      lugar: evento.lugar ?? evento.pais ?? '',
      duracionDias: evento.duracionDias,
      imagenUrl: evento.imagenUrl,
    );
  }

  factory HomeFeaturedItem.campanaFijada(EventoLead campana) {
    return HomeFeaturedItem(
      kind: HomeFeaturedKind.campanaFijada,
      id: campana.id,
      nombre: campana.nombre,
      fecha: campana.fecha,
      lugar: campana.pais ?? '',
      duracionDias: campana.duracionDias,
      imagenUrl: campana.imagenUrl,
    );
  }

  factory HomeFeaturedItem.proximaActividad(EventoLead campana) {
    return HomeFeaturedItem(
      kind: HomeFeaturedKind.proximaActividad,
      id: campana.id,
      nombre: campana.nombre,
      fecha: campana.fecha,
      lugar: campana.pais ?? '',
      duracionDias: campana.duracionDias,
      imagenUrl: campana.imagenUrl,
    );
  }
}

/// Slider del home: fijados primero. Los próximos (evento y actividad) cierran
/// la lista, salvo los que ya están fijados (se muestran como fijados y no se
/// duplican). Un evento fijado dos veces —él mismo y su actividad interna—
/// queda una sola vez.
List<HomeFeaturedItem> ensamblarHomeFeaturedItems({
  required List<HomeFeaturedItem> fijados,
  List<HomeFeaturedItem> proximos = const [],
}) {
  final ids = <String>{};
  return [
    for (final item in [...fijados, ...proximos])
      if (ids.add(item.id)) item,
  ];
}

/// Actividad de captura **externa** vigente más cercana, o `null`. Las
/// internas no compiten: viajan dentro de la card de su evento.
EventoLead? proximaActividadVigente(Iterable<EventoLead> actividades) {
  final lista =
      actividades
          .where(
            (actividad) =>
                actividad.eventoOrigenId == null && !actividad.yaOcurrio,
          )
          .toList()
        ..sort((a, b) => a.fecha.compareTo(b.fecha));
  return lista.isEmpty ? null : lista.first;
}

/// Los slots de próximo del home: el próximo evento de registro y la próxima
/// actividad externa, el más cercano primero.
///
/// Antes solo se mostraba el más cercano de los dos: con una actividad en
/// curso (una feria de varios días), un evento recién creado nunca aparecía
/// en el inicio.
List<HomeFeaturedItem> elegirProximosDestacados({
  Evento? evento,
  EventoLead? actividad,
}) {
  if (evento == null && actividad == null) return const [];
  if (evento == null) return [HomeFeaturedItem.proximaActividad(actividad!)];
  final itemEvento = HomeFeaturedItem.proximoEvento(evento);
  if (actividad == null || actividad.eventoOrigenId == evento.id) {
    return [itemEvento];
  }
  final itemActividad = HomeFeaturedItem.proximaActividad(actividad);
  return actividad.fecha.isBefore(evento.fecha)
      ? [itemActividad, itemEvento]
      : [itemEvento, itemActividad];
}
