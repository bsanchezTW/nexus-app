import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/core/avisos/aviso_sistema.dart';
import 'package:transworld_nexus/core/conexion/estado_conexion.dart';

List<TipoAviso> _tipos(EntradaAvisos e) =>
    avisosDelSistema(e).map((a) => a.tipo).toList();

EntradaAvisos _entrada({
  EstadoConexion estado = EstadoConexion.estable,
  bool? enLinea,
  bool soportaCopiaLocal = true,
  int conflictos = 0,
  int pendientes = 0,
  bool subiendo = false,
  bool descargaEnCurso = false,
  bool descargaConErrores = false,
}) {
  return EntradaAvisos(
    estado: estado,
    enLinea: enLinea ?? !estado.degradado,
    soportaCopiaLocal: soportaCopiaLocal,
    conflictos: conflictos,
    pendientes: pendientes,
    subiendo: subiendo,
    descargaEnCurso: descargaEnCurso,
    descargaEtapa: descargaEnCurso ? 'Eventos' : null,
    descargaFraccion: descargaEnCurso ? 0.4 : 0,
    descargaConErrores: descargaConErrores,
  );
}

void main() {
  test('con la conexión estable y nada pendiente no hay avisos', () {
    expect(avisosDelSistema(_entrada()), isEmpty);
    expect(
      avisosDelSistema(_entrada(estado: EstadoConexion.verificando)),
      isEmpty,
    );
  });

  test('como mucho uno de conexión y uno de actividad, en ese orden', () {
    expect(
      _tipos(
        _entrada(
          estado: EstadoConexion.sinInternet,
          conflictos: 1,
          pendientes: 3,
          descargaConErrores: true,
        ),
      ),
      [TipoAviso.sinInternet, TipoAviso.conflictos],
    );
  });

  test('la actividad se elige por prioridad', () {
    expect(_tipos(_entrada(pendientes: 2, descargaEnCurso: true)), [
      TipoAviso.pendientes,
    ]);
    expect(_tipos(_entrada(pendientes: 2, subiendo: true)), [
      TipoAviso.subiendo,
    ]);
    expect(_tipos(_entrada(descargaEnCurso: true, descargaConErrores: true)), [
      TipoAviso.descargando,
    ]);
    expect(_tipos(_entrada(descargaConErrores: true)), [
      TipoAviso.descargaIncompleta,
    ]);
  });

  test('la descarga avisa que se puede seguir usando la app', () {
    final aviso = avisosDelSistema(_entrada(descargaEnCurso: true)).single;
    expect(aviso.titulo, 'Preparando el modo sin conexión');
    expect(
      aviso.detalle,
      'Puedes seguir usando la app con normalidad · Eventos 40 %',
    );
    expect(aviso.progreso, 0.4);
    expect(aviso.esProblema, isFalse);
  });

  test('inestable con copia local: ya opera sin conexión', () {
    final aviso = avisosDelSistema(
      _entrada(estado: EstadoConexion.inestable),
    ).single;
    expect(aviso.titulo, 'Conexión inestable');
    expect(aviso.detalle, startsWith('Pasamos a modo sin conexión'));
  });

  test('inestable en web: sigue en línea, solo más lenta', () {
    final aviso = avisosDelSistema(
      _entrada(
        estado: EstadoConexion.inestable,
        enLinea: true,
        soportaCopiaLocal: false,
      ),
    ).single;
    expect(aviso.detalle, 'Algunas acciones pueden tardar más de lo normal');
  });

  test('los pendientes solo ofrecen reintentar si hay con quién', () {
    final enLinea = avisosDelSistema(_entrada(pendientes: 1)).single;
    expect(enLinea.titulo, '1 cambio por subir');
    expect(enLinea.accion, AccionAviso.reintentar);

    final sinRed = avisosDelSistema(
      _entrada(estado: EstadoConexion.sinInternet, pendientes: 2),
    ).last;
    expect(sinRed.titulo, '2 cambios por subir');
    expect(sinRed.accion, AccionAviso.ninguna);
  });

  test('los conflictos llevan a revisarlos', () {
    final aviso = avisosDelSistema(_entrada(conflictos: 2)).single;
    expect(aviso.titulo, '2 cambios necesitan revisión');
    expect(aviso.accion, AccionAviso.revisarConflictos);
    expect(aviso.cantidad, 2);
  });
}
