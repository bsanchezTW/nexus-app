import 'package:flutter/material.dart';

import 'evento.dart';

class Subevento {
  const Subevento({
    required this.id,
    required this.eventoId,
    required this.codigo,
    required this.nombre,
    required this.dia,
    required this.horaInicio,
    required this.horaFin,
    this.descripcion,
    this.sala,
    this.expositor,
    this.imagenUrl,
    this.cupoMaximo,
    this.orden = 0,
    this.visiblePublico = true,
  });

  final String id;
  final String eventoId;
  final String codigo;
  final String nombre;
  final String? descripcion;
  final DateTime dia;
  final TimeOfDay horaInicio;
  final TimeOfDay horaFin;
  final String? sala;
  final String? expositor;
  final String? imagenUrl;
  final int? cupoMaximo;
  final int orden;
  final bool visiblePublico;

  bool seSuperponeCon(Subevento otro) {
    if (dia.year != otro.dia.year ||
        dia.month != otro.dia.month ||
        dia.day != otro.dia.day) {
      return false;
    }
    final inicio = _minutos(horaInicio);
    final fin = _minutos(horaFin);
    final otroInicio = _minutos(otro.horaInicio);
    final otroFin = _minutos(otro.horaFin);
    return inicio < otroFin && otroInicio < fin;
  }

  bool enCurso(DateTime ahora, {Duration antes = const Duration(minutes: 30)}) {
    final inicio = DateTime(dia.year, dia.month, dia.day, horaInicio.hour, horaInicio.minute);
    final fin = DateTime(dia.year, dia.month, dia.day, horaFin.hour, horaFin.minute);
    return !ahora.isBefore(inicio.subtract(antes)) && ahora.isBefore(fin);
  }

  bool yaTermino(DateTime ahora) {
    final fin = DateTime(dia.year, dia.month, dia.day, horaFin.hour, horaFin.minute);
    return !ahora.isBefore(fin);
  }

  factory Subevento.fromMap(Map<String, dynamic> map) {
    return Subevento(
      id: map['id'] as String,
      eventoId: map['evento_id'] as String,
      codigo: map['codigo'] as String? ?? '',
      nombre: map['nombre'] as String,
      descripcion: map['descripcion'] as String?,
      dia: DateTime.parse(map['dia'] as String),
      horaInicio: horaDesdeTexto(map['hora_inicio'] as String?) ??
          const TimeOfDay(hour: 0, minute: 0),
      horaFin: horaDesdeTexto(map['hora_fin'] as String?) ??
          const TimeOfDay(hour: 0, minute: 0),
      sala: map['sala'] as String?,
      expositor: map['expositor'] as String?,
      imagenUrl: map['imagen_url'] as String?,
      cupoMaximo: map['cupo_maximo'] as int?,
      orden: (map['orden'] as num?)?.toInt() ?? 0,
      visiblePublico: (map['visible_publico'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toCacheMap() => {
    'id': id,
    'evento_id': eventoId,
    'codigo': codigo,
    'nombre': nombre,
    'descripcion': descripcion,
    'dia': dia.toIso8601String().split('T').first,
    'hora_inicio': horaATexto(horaInicio),
    'hora_fin': horaATexto(horaFin),
    'sala': sala,
    'expositor': expositor,
    'imagen_url': imagenUrl,
    'cupo_maximo': cupoMaximo,
    'orden': orden,
    'visible_publico': visiblePublico,
  };

  Map<String, dynamic> toInsertMap() => {
    'evento_id': eventoId,
    'codigo': codigo,
    'nombre': nombre,
    'descripcion': descripcion,
    'dia': dia.toIso8601String().split('T').first,
    'hora_inicio': horaATexto(horaInicio),
    'hora_fin': horaATexto(horaFin),
    'sala': sala,
    'expositor': expositor,
    'imagen_url': imagenUrl,
    'cupo_maximo': cupoMaximo,
    'orden': orden,
    'visible_publico': visiblePublico,
  };

  Subevento copyWith({
    String? nombre,
    String? codigo,
    DateTime? dia,
    TimeOfDay? horaInicio,
    TimeOfDay? horaFin,
    int? orden,
    bool? visiblePublico,
  }) {
    return Subevento(
      id: id,
      eventoId: eventoId,
      codigo: codigo ?? this.codigo,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion,
      dia: dia ?? this.dia,
      horaInicio: horaInicio ?? this.horaInicio,
      horaFin: horaFin ?? this.horaFin,
      sala: sala,
      expositor: expositor,
      imagenUrl: imagenUrl,
      cupoMaximo: cupoMaximo,
      orden: orden ?? this.orden,
      visiblePublico: visiblePublico ?? this.visiblePublico,
    );
  }
}

int _minutos(TimeOfDay hora) => hora.hour * 60 + hora.minute;
