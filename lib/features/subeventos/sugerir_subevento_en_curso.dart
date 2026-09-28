import '../../../data/models/subevento.dart';

Subevento? sugerirSubeventoEnCurso(List<Subevento> talleres, DateTime ahora) {
  final enCurso = [
    for (final taller in talleres)
      if (taller.enCurso(ahora)) taller,
  ];
  if (enCurso.isEmpty) return null;
  enCurso.sort((a, b) {
    final inicioA = DateTime(
      a.dia.year,
      a.dia.month,
      a.dia.day,
      a.horaInicio.hour,
      a.horaInicio.minute,
    );
    final inicioB = DateTime(
      b.dia.year,
      b.dia.month,
      b.dia.day,
      b.horaInicio.hour,
      b.horaInicio.minute,
    );
    return inicioB.compareTo(inicioA);
  });
  return enCurso.first;
}
