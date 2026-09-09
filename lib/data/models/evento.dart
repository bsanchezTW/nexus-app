import '../../core/constants/duracion_actividad.dart';
import 'supabase_row_parsers.dart';

enum TipoRegistroEvento {
  comercial,
  cliente;

  static TipoRegistroEvento fromString(String? raw) {
    return TipoRegistroEvento.values.firstWhere(
      (t) => t.name == raw,
      orElse: () => TipoRegistroEvento.comercial,
    );
  }
}

class Evento {
  const Evento({
    required this.id,
    required this.nombre,
    required this.fecha,
    this.duracionDias = kDuracionActividadMinDias,
    this.pais,
    this.tematica,
    this.creadoPor,
    this.direccion,
    this.lugar,
    this.certificacionCapacitacion = false,
    this.imagenUrl,
    this.tipoRegistro = TipoRegistroEvento.comercial,
  });

  final String id;
  final String nombre;
  final DateTime fecha;
  final int duracionDias;
  final String? pais;
  final String? tematica;
  final String? creadoPor;
  final String? direccion;
  final String? lugar;
  final bool certificacionCapacitacion;
  final String? imagenUrl;
  final TipoRegistroEvento tipoRegistro;

  bool get esMultiDia => duracionDias > 1;

  DateTime get fechaFin => fechaTerminoActividad(fecha, duracionDias);

  String get etiquetaDuracion => etiquetaDuracionActividad(duracionDias);

  bool get yaOcurrio {
    final hoy = DateTime.now();
    final soloFecha = DateTime(hoy.year, hoy.month, hoy.day);
    return fechaFin.isBefore(soloFecha);
  }

  bool cubreDia(DateTime dia) => rangoCubreDia(fecha, duracionDias, dia);

  bool cubreMes(DateTime mes) => rangoCubreMes(fecha, duracionDias, mes);

  factory Evento.fromMap(Map<String, dynamic> map) {
    return Evento(
      id: map['id'] as String,
      nombre: map['nombre'] as String,
      fecha: DateTime.parse(map['fecha'] as String),
      duracionDias: acotarDuracionActividad(
        SupabaseRowParsers.asInt(map['duracion_dias'], fallback: 1),
      ),
      pais: map['pais'] as String?,
      tematica: map['tematica'] as String?,
      creadoPor: map['creado_por'] as String?,
      direccion: map['direccion'] as String?,
      lugar: map['lugar'] as String?,
      certificacionCapacitacion:
          (map['certificacion_capacitacion'] as bool?) ?? false,
      imagenUrl: map['imagen_url'] as String?,
      tipoRegistro: TipoRegistroEvento.fromString(
        map['tipo_registro'] as String?,
      ),
    );
  }

  /// Copia serializable para la caché offline. Usa las claves de
  /// [Evento.fromMap] para rehidratar por el mismo camino que la fila de
  /// `eventos` (a diferencia de [toInsertMap], que omite el id).
  Map<String, dynamic> toCacheMap() {
    return {
      'id': id,
      'nombre': nombre,
      'fecha': fecha.toIso8601String(),
      'duracion_dias': duracionDias,
      'pais': pais,
      'tematica': tematica,
      'creado_por': creadoPor,
      'direccion': direccion,
      'lugar': lugar,
      'certificacion_capacitacion': certificacionCapacitacion,
      'imagen_url': imagenUrl,
      'tipo_registro': tipoRegistro.name,
    };
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'nombre': nombre,
      'fecha': fecha.toIso8601String().split('T').first,
      'duracion_dias': duracionDias,
      'pais': pais,
      'tematica': tematica,
      'direccion': direccion,
      'lugar': lugar,
      'certificacion_capacitacion': certificacionCapacitacion,
      'imagen_url': imagenUrl,
      'tipo_registro': tipoRegistro.name,
    };
  }

  Evento copyWith({
    String? nombre,
    DateTime? fecha,
    int? duracionDias,
    String? pais,
    String? tematica,
    String? direccion,
    String? lugar,
    bool? certificacionCapacitacion,
    String? imagenUrl,
    TipoRegistroEvento? tipoRegistro,
  }) {
    return Evento(
      id: id,
      nombre: nombre ?? this.nombre,
      fecha: fecha ?? this.fecha,
      duracionDias: duracionDias ?? this.duracionDias,
      pais: pais ?? this.pais,
      tematica: tematica ?? this.tematica,
      creadoPor: creadoPor,
      direccion: direccion ?? this.direccion,
      lugar: lugar ?? this.lugar,
      certificacionCapacitacion:
          certificacionCapacitacion ?? this.certificacionCapacitacion,
      imagenUrl: imagenUrl ?? this.imagenUrl,
      tipoRegistro: tipoRegistro ?? this.tipoRegistro,
    );
  }
}
