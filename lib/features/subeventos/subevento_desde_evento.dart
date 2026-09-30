import 'package:flutter/material.dart';

import '../../../data/models/evento.dart';
import '../../../data/models/subevento.dart';

/// Arma un taller a partir de un evento suelto.
///
/// Si el día del evento queda fuera del principal, se usa el primer día del
/// principal: el servidor rechaza talleres fuera de ese rango.
Subevento subeventoDesdeEvento({
  required Evento principal,
  required Evento origen,
  required int orden,
}) {
  final inicioRango = DateTime(
    principal.fecha.year,
    principal.fecha.month,
    principal.fecha.day,
  );
  final fin = principal.fechaFin;
  final finRango = DateTime(fin.year, fin.month, fin.day);
  var dia = DateTime(origen.fecha.year, origen.fecha.month, origen.fecha.day);
  if (dia.isBefore(inicioRango) || dia.isAfter(finRango)) {
    dia = inicioRango;
  }

  var horaInicio = origen.horaInicio ?? const TimeOfDay(hour: 10, minute: 0);
  var horaFin = origen.horaFin ?? const TimeOfDay(hour: 11, minute: 0);
  if (_minutos(horaFin) <= _minutos(horaInicio)) {
    final siguiente = _minutos(horaInicio) + 60;
    if (siguiente >= 24 * 60) {
      horaInicio = const TimeOfDay(hour: 10, minute: 0);
      horaFin = const TimeOfDay(hour: 11, minute: 0);
    } else {
      horaFin = TimeOfDay(hour: siguiente ~/ 60, minute: siguiente % 60);
    }
  }

  final descripcion = (origen.descripcion ?? '').trim().isNotEmpty
      ? origen.descripcion
      : origen.tematica;

  return Subevento(
    id: '',
    eventoId: principal.id,
    codigo: '',
    nombre: origen.nombre,
    descripcion: descripcion,
    dia: dia,
    horaInicio: horaInicio,
    horaFin: horaFin,
    sala: origen.lugar,
    imagenUrl: origen.imagenUrl,
    cupoMaximo: origen.cupoMaximo,
    orden: orden,
    eventoOrigenId: origen.id,
  );
}

int _minutos(TimeOfDay hora) => hora.hour * 60 + hora.minute;
