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
      imagenUrl: map['imagen_url'] as String?,
    );
  }

  HomeFeaturedItem copyWith({int? registrados, int? acreditados, int? leads}) {
    return HomeFeaturedItem(
      kind: kind,
      id: id,
      nombre: nombre,
      fecha: fecha,
      lugar: lugar,
      registrados: registrados ?? this.registrados,
      acreditados: acreditados ?? this.acreditados,
      leads: leads ?? this.leads,
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
      imagenUrl: campana.imagenUrl,
    );
  }
}

/// Slider del home: fijados primero. El próximo (evento o actividad) cierra
/// la lista si no está ya fijado (si lo está, se muestra como fijado y no se
/// duplica).
List<HomeFeaturedItem> ensamblarHomeFeaturedItems({
  required List<HomeFeaturedItem> fijados,
  HomeFeaturedItem? proximo,
}) {
  if (proximo == null) return List<HomeFeaturedItem>.of(fijados);
  if (fijados.any((item) => item.id == proximo.id)) {
    return List<HomeFeaturedItem>.of(fijados);
  }
  return [...fijados, proximo];
}

/// Actividad de captura vigente más cercana, o `null` si todas ya terminaron.
EventoLead? proximaActividadVigente(Iterable<EventoLead> actividades) {
  final lista = actividades.where((actividad) => !actividad.yaOcurrio).toList()
    ..sort((a, b) => a.fecha.compareTo(b.fecha));
  return lista.isEmpty ? null : lista.first;
}

/// El slot de próximo del home: el más cercano entre evento de registro y
/// actividad de captura. Si la actividad es la interna de ese evento, manda
/// el evento (misma pieza, sin duplicar el hero).
HomeFeaturedItem? elegirProximoDestacado({
  Evento? evento,
  EventoLead? actividad,
}) {
  if (evento == null && actividad == null) return null;
  if (evento == null) return HomeFeaturedItem.proximaActividad(actividad!);
  if (actividad == null) return HomeFeaturedItem.proximoEvento(evento);
  if (actividad.eventoOrigenId == evento.id) {
    return HomeFeaturedItem.proximoEvento(evento);
  }
  if (actividad.fecha.isBefore(evento.fecha)) {
    return HomeFeaturedItem.proximaActividad(actividad);
  }
  return HomeFeaturedItem.proximoEvento(evento);
}
