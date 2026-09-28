import '../../../data/models/inscripcion_subevento.dart';
import '../../../data/models/registrado.dart';

enum AccionEscaneoTipo {
  acreditar,
  yaAcreditado,
  marcarAsistencia,
  yaMarcado,
  ofrecerInscribirYMarcar,
  soloAviso,
  noPertenece,
  formatoAntiguo,
  invalido,
}

class AccionEscaneo {
  const AccionEscaneo(this.tipo, {this.puedeForzar = false});

  final AccionEscaneoTipo tipo;
  final bool puedeForzar;
}

AccionEscaneo decidirAccionEscaneo({
  required bool formatoAntiguo,
  required bool invalido,
  Registrado? registrado,
  InscripcionSubevento? inscripcion,
  required bool modoEntrada,
  required bool esExterno,
  required bool puedeCrear,
  required bool hayRed,
}) {
  if (formatoAntiguo) return const AccionEscaneo(AccionEscaneoTipo.formatoAntiguo);
  if (invalido) return const AccionEscaneo(AccionEscaneoTipo.invalido);
  if (registrado == null) return const AccionEscaneo(AccionEscaneoTipo.noPertenece);
  if (modoEntrada) {
    return AccionEscaneo(
      registrado.acreditado
          ? AccionEscaneoTipo.yaAcreditado
          : AccionEscaneoTipo.acreditar,
    );
  }
  if (inscripcion?.asistio == true) {
    return const AccionEscaneo(AccionEscaneoTipo.yaMarcado);
  }
  if (inscripcion != null) {
    return const AccionEscaneo(AccionEscaneoTipo.marcarAsistencia);
  }
  if (esExterno || (!hayRed && !puedeCrear)) {
    return const AccionEscaneo(AccionEscaneoTipo.soloAviso);
  }
  return AccionEscaneo(
    AccionEscaneoTipo.ofrecerInscribirYMarcar,
    puedeForzar: puedeCrear,
  );
}
