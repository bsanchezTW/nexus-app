/// Duración de un evento o actividad de captura, en días calendario.
///
/// [fecha] es el primer día; el último es `fecha + (duracionDias - 1)`.
/// Al elegir la fecha de inicio, el término parte igual (1 día) hasta que
/// el usuario lo mueva.
const int kDuracionActividadMinDias = 1;
const int kDuracionActividadMaxDias = 366;

int acotarDuracionActividad(int dias) {
  if (dias < kDuracionActividadMinDias) return kDuracionActividadMinDias;
  if (dias > kDuracionActividadMaxDias) return kDuracionActividadMaxDias;
  return dias;
}

DateTime fechaCalendario(DateTime fecha) =>
    DateTime(fecha.year, fecha.month, fecha.day);

DateTime fechaTerminoActividad(DateTime inicio, int duracionDias) {
  return fechaCalendario(
    inicio,
  ).add(Duration(days: acotarDuracionActividad(duracionDias) - 1));
}

int duracionDesdeRango(DateTime inicio, DateTime termino) {
  final dias =
      fechaCalendario(termino).difference(fechaCalendario(inicio)).inDays + 1;
  return acotarDuracionActividad(dias);
}

bool rangoCubreDia(DateTime inicio, int duracionDias, DateTime dia) {
  final d = fechaCalendario(dia);
  final a = fechaCalendario(inicio);
  final b = fechaTerminoActividad(inicio, duracionDias);
  return !d.isBefore(a) && !d.isAfter(b);
}

bool rangoCubreMes(DateTime inicio, int duracionDias, DateTime mes) {
  final mesIni = DateTime(mes.year, mes.month, 1);
  final mesFin = DateTime(mes.year, mes.month + 1, 0);
  final a = fechaCalendario(inicio);
  final b = fechaTerminoActividad(inicio, duracionDias);
  return !b.isBefore(mesIni) && !a.isAfter(mesFin);
}

String etiquetaDuracionActividad(int dias) {
  return dias == 1 ? '1 día' : '$dias días';
}

String textoDuracionActividad(int dias) {
  return 'Esta actividad durará ${etiquetaDuracionActividad(dias)}';
}

String textoDuracionEvento(int dias) {
  return 'Este evento durará ${etiquetaDuracionActividad(dias)}';
}
