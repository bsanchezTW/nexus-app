import 'package:flutter/material.dart';

import '../../core/constants/duracion_actividad.dart';
import 'supabase_row_parsers.dart';

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
    this.slug = '',
    this.accesoQr = false,
    this.cupoMaximo,
    this.descripcion,
    this.horaInicio,
    this.horaFin,
    this.inscripcionesCierre,
    this.mapaUrl,
    this.bannerUrl,
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
  final String slug;
  final bool accesoQr;
  final int? cupoMaximo;
  final String? descripcion;
  final TimeOfDay? horaInicio;
  final TimeOfDay? horaFin;
  final DateTime? inscripcionesCierre;
  final String? mapaUrl;
  final String? bannerUrl;

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
    final accesoExplicito = map['acceso_qr'];
    final accesoQr = accesoExplicito is bool
        ? accesoExplicito
        : map['tipo_registro'] == 'cliente';
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
      slug: map['slug'] as String? ?? '',
      accesoQr: accesoQr,
      cupoMaximo: map['cupo_maximo'] as int?,
      descripcion: map['descripcion'] as String?,
      horaInicio: horaDesdeTexto(map['hora_inicio'] as String?),
      horaFin: horaDesdeTexto(map['hora_fin'] as String?),
      inscripcionesCierre: fechaLocalDesdeTexto(
        map['inscripciones_cierre'] as String?,
      ),
      mapaUrl: map['mapa_url'] as String?,
      bannerUrl: map['banner_url'] as String?,
    );
  }

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
      'slug': slug,
      'acceso_qr': accesoQr,
      'cupo_maximo': cupoMaximo,
      'descripcion': descripcion,
      'hora_inicio': horaATexto(horaInicio),
      'hora_fin': horaATexto(horaFin),
      'inscripciones_cierre': fechaLocalATexto(inscripcionesCierre),
      'mapa_url': mapaUrl,
      'banner_url': bannerUrl,
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
      'acceso_qr': accesoQr,
      'cupo_maximo': cupoMaximo,
      'descripcion': descripcion,
      'hora_inicio': horaATexto(horaInicio),
      'hora_fin': horaATexto(horaFin),
      'inscripciones_cierre': fechaLocalATexto(inscripcionesCierre),
      'mapa_url': mapaUrl,
      'banner_url': bannerUrl,
      if (slug.isNotEmpty) 'slug': slug,
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
    bool? accesoQr,
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
      slug: slug,
      accesoQr: accesoQr ?? this.accesoQr,
      cupoMaximo: cupoMaximo,
      descripcion: descripcion,
      horaInicio: horaInicio,
      horaFin: horaFin,
      inscripcionesCierre: inscripcionesCierre,
      mapaUrl: mapaUrl,
      bannerUrl: bannerUrl,
    );
  }
}

TimeOfDay? horaDesdeTexto(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final partes = raw.split(':');
  if (partes.length < 2) return null;
  final hora = int.tryParse(partes[0]);
  final minuto = int.tryParse(partes[1]);
  if (hora == null || minuto == null) return null;
  return TimeOfDay(hour: hora, minute: minuto);
}

String? horaATexto(TimeOfDay? hora) {
  if (hora == null) return null;
  final h = hora.hour.toString().padLeft(2, '0');
  final m = hora.minute.toString().padLeft(2, '0');
  return '$h:$m:00';
}

DateTime? fechaLocalDesdeTexto(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return DateTime.parse(raw.replaceFirst(RegExp(r'Z$'), ''));
}

String? fechaLocalATexto(DateTime? fecha) {
  if (fecha == null) return null;
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${fecha.year}-${dos(fecha.month)}-${dos(fecha.day)}T${dos(fecha.hour)}:${dos(fecha.minute)}:${dos(fecha.second)}';
}
