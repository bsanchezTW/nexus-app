import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/models/inscripcion_subevento.dart';
import 'package:transworld_nexus/data/models/registrado.dart';
import 'package:transworld_nexus/features/acreditacion/decidir_accion_escaneo.dart';

void main() {
  const persona = Registrado(
    id: 'r1',
    eventoId: 'e1',
    nombreCompleto: 'Ana Pérez',
    email: 'ana@x.cl',
  );
  const inscrita = InscripcionSubevento(
    id: 'i1',
    eventoId: 'e1',
    registradoId: 'r1',
    subeventoId: 's1',
    origen: 'app',
  );

  test('entrada acredita o reconoce si ya entró', () {
    expect(
      decidirAccionEscaneo(
        formatoAntiguo: false,
        invalido: false,
        registrado: persona,
        inscripcion: null,
        modoEntrada: true,
        esExterno: false,
        puedeCrear: false,
        hayRed: true,
      ).tipo,
      AccionEscaneoTipo.acreditar,
    );
    expect(
      decidirAccionEscaneo(
        formatoAntiguo: false,
        invalido: false,
        registrado: persona.copyWith(acreditado: true),
        inscripcion: null,
        modoEntrada: true,
        esExterno: false,
        puedeCrear: false,
        hayRed: true,
      ).tipo,
      AccionEscaneoTipo.yaAcreditado,
    );
  });

  test('taller marca, avisa o ofrece inscribir según rol y red', () {
    expect(
      decidirAccionEscaneo(
        formatoAntiguo: false,
        invalido: false,
        registrado: persona,
        inscripcion: inscrita,
        modoEntrada: false,
        esExterno: true,
        puedeCrear: false,
        hayRed: true,
      ).tipo,
      AccionEscaneoTipo.marcarAsistencia,
    );
    final externo = decidirAccionEscaneo(
      formatoAntiguo: false,
      invalido: false,
      registrado: persona,
      inscripcion: null,
      modoEntrada: false,
      esExterno: true,
      puedeCrear: false,
      hayRed: true,
    );
    expect(externo.tipo, AccionEscaneoTipo.soloAviso);
    final adminOffline = decidirAccionEscaneo(
      formatoAntiguo: false,
      invalido: false,
      registrado: persona,
      inscripcion: null,
      modoEntrada: false,
      esExterno: false,
      puedeCrear: true,
      hayRed: false,
    );
    expect(adminOffline.tipo, AccionEscaneoTipo.ofrecerInscribirYMarcar);
    expect(adminOffline.puedeForzar, isTrue);
  });

  test('formato antiguo e inválido no buscan persona', () {
    expect(
      decidirAccionEscaneo(
        formatoAntiguo: true,
        invalido: false,
        registrado: persona,
        inscripcion: null,
        modoEntrada: true,
        esExterno: false,
        puedeCrear: true,
        hayRed: true,
      ).tipo,
      AccionEscaneoTipo.formatoAntiguo,
    );
    expect(
      decidirAccionEscaneo(
        formatoAntiguo: false,
        invalido: true,
        registrado: null,
        inscripcion: null,
        modoEntrada: false,
        esExterno: false,
        puedeCrear: false,
        hayRed: false,
      ).tipo,
      AccionEscaneoTipo.invalido,
    );
  });
}
