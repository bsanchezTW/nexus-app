import '../../../core/router/route_paths.dart';
import '../../../data/models/evento.dart';
import '../../../data/models/evento_lead.dart';

enum HomeFeaturedKind {
  proximoEvento,
  eventoFijado,
  campanaFijada,
  proximaActividad,
}

/// Ítem mostrable en la card/slider del header del home.
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

  /// Días que dura la actividad. Solo actividades de captura.
  final int duracionDias;
  final String? imagenUrl;

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

  /// Primario (blanco): hub de la actividad fijada; abrir el evento en el resto.
  String get ctaLabel => esActividadCaptura ? 'Ver actividad' : 'Ver evento';

  String get ctaRoutePath => esActividadCaptura
      ? RoutePaths.usarEventoLead(id)
      : RoutePaths.usarEvento(id);

  /// Capturar lead (ghost). Null en eventos de registro.
  String? get secondaryCtaLabel => esActividadCaptura ? 'Capturar lead' : null;

  String? get secondaryRoutePath =>
      esActividadCaptura ? RoutePaths.capturarLead(id) : null;

  bool get puedeEscanearQr => !esActividadCaptura;

  String? get qrRoutePath =>
      puedeEscanearQr ? RoutePaths.acreditarQr(id) : null;

  String get porcentajeAcreditados {
    if (registrados <= 0) return '0%';
    return '${((acreditados / registrados) * 100).round()}%';
  }

  /// Destino del detalle (evento o hub de actividad), no el CTA primario.
  String get routePath => switch (kind) {
    HomeFeaturedKind.proximoEvento ||
    HomeFeaturedKind.eventoFijado => RoutePaths.usarEvento(id),
    HomeFeaturedKind.campanaFijada ||
    HomeFeaturedKind.proximaActividad => RoutePaths.usarEventoLead(id),
  };

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
    );
  }

  HomeFeaturedItem copyWith({
    int? registrados,
    int? acreditados,
    int? leads,
    int? empresas,
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
    );
  }

  factory HomeFeaturedItem.proximoEvento(Evento evento) {
    return HomeFeaturedItem(
      kind: HomeFeaturedKind.proximoEvento,
      id: evento.id,
      nombre: evento.nombre,
      fecha: evento.fecha,
      lugar: evento.lugar ?? evento.pais ?? '',
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
/// duplican).
List<HomeFeaturedItem> ensamblarHomeFeaturedItems({
  required List<HomeFeaturedItem> fijados,
  List<HomeFeaturedItem> proximos = const [],
}) {
  final ids = fijados.map((item) => item.id).toSet();
  return [
    ...fijados,
    for (final proximo in proximos)
      if (!ids.contains(proximo.id)) proximo,
  ];
}

/// Actividad de captura vigente más cercana, o `null` si todas ya terminaron.
EventoLead? proximaActividadVigente(Iterable<EventoLead> actividades) {
  final lista = actividades.where((actividad) => !actividad.yaOcurrio).toList()
    ..sort((a, b) => a.fecha.compareTo(b.fecha));
  return lista.isEmpty ? null : lista.first;
}

/// Los slots de próximo del home: el próximo evento de registro y la próxima
/// actividad de captura, el más cercano primero.
///
/// Antes solo se mostraba el más cercano de los dos: con una actividad en
/// curso (una feria de varios días), un evento recién creado nunca aparecía
/// en el inicio. Si la actividad es la interna de ese evento, queda solo el
/// evento (misma pieza, sin duplicar el hero).
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
