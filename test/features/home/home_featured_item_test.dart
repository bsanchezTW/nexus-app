import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/models/evento.dart';
import 'package:transworld_nexus/data/models/evento_lead.dart';
import 'package:transworld_nexus/features/home/models/home_featured_item.dart';

HomeFeaturedItem _item({required HomeFeaturedKind kind, required String id}) {
  return HomeFeaturedItem(
    kind: kind,
    id: id,
    nombre: id,
    fecha: DateTime(2026, 8, 14),
  );
}

void main() {
  test('el evento fijado queda primero y el próximo al final', () {
    final fijado = _item(kind: HomeFeaturedKind.eventoFijado, id: 'fijado');
    final proximo = _item(kind: HomeFeaturedKind.proximoEvento, id: 'proximo');

    final items = ensamblarHomeFeaturedItems(
      fijados: [fijado],
      proximos: [proximo],
    );

    expect(items.map((item) => item.id), ['fijado', 'proximo']);
    expect(items.first.kind, HomeFeaturedKind.eventoFijado);
  });

  test('si el próximo también está fijado no se duplica y manda el fijado', () {
    final fijado = _item(kind: HomeFeaturedKind.eventoFijado, id: 'mismo');
    final proximo = _item(kind: HomeFeaturedKind.proximoEvento, id: 'mismo');

    final items = ensamblarHomeFeaturedItems(
      fijados: [fijado],
      proximos: [proximo],
    );

    expect(items, hasLength(1));
    expect(items.single.kind, HomeFeaturedKind.eventoFijado);
  });

  test('si la próxima actividad ya está fijada no se duplica', () {
    final fijada = _item(kind: HomeFeaturedKind.campanaFijada, id: 'a1');
    final proxima = _item(kind: HomeFeaturedKind.proximaActividad, id: 'a1');

    final items = ensamblarHomeFeaturedItems(
      fijados: [fijada],
      proximos: [proxima],
    );

    expect(items, hasLength(1));
    expect(items.single.kind, HomeFeaturedKind.campanaFijada);
  });

  test('sin fijados solo queda el próximo evento', () {
    final proximo = _item(kind: HomeFeaturedKind.proximoEvento, id: 'proximo');

    final items = ensamblarHomeFeaturedItems(
      fijados: const [],
      proximos: [proximo],
    );

    expect(items, hasLength(1));
    expect(items.single.kind, HomeFeaturedKind.proximoEvento);
  });

  test('copia la imagen de portada del evento', () {
    const url = 'https://cdn.example/evento.jpg';
    final evento = Evento(
      id: 'e1',
      nombre: 'Taller',
      fecha: DateTime(2026, 8, 14),
      imagenUrl: url,
    );

    expect(HomeFeaturedItem.proximoEvento(evento).imagenUrl, url);
    expect(HomeFeaturedItem.eventoFijado(evento).tieneImagen, isTrue);
    expect(
      HomeFeaturedItem.proximoEvento(evento).copyWith(registrados: 3).imagenUrl,
      url,
    );
  });

  test('la actividad fijada copia la imagen y ofrece capturar lead', () {
    final campana = EventoLead(
      id: 'c1',
      nombre: 'Feria',
      fecha: DateTime(2026, 9, 12),
      imagenUrl: 'https://cdn.example/feria.jpg',
    );
    final item = HomeFeaturedItem.campanaFijada(campana);

    expect(item.etiqueta, 'ACTIVIDAD FIJADA');
    expect(item.acciones, [
      HomeCardAccion.verActividad,
      HomeCardAccion.capturarLead,
    ]);
    expect(item.routePath, '/capturador/c1/usar');
    expect(item.capturarLeadRoutePath, '/capturador/c1/capturar');
    expect(item.leadsRoutePath, '/capturador/c1/leads');
    expect(item.registradosRoutePath, isNull);
    expect(item.qrRoutePath, isNull);
    expect(item.tieneImagen, isTrue);
    expect(item.imagenUrl, 'https://cdn.example/feria.jpg');
  });

  test('sin eventos de registro manda la próxima actividad de captura', () {
    final actividad = EventoLead(
      id: 'a1',
      nombre: 'Feria retail',
      fecha: DateTime(2026, 9, 20),
    );

    final item = elegirProximosDestacados(actividad: actividad).single;

    expect(item.kind, HomeFeaturedKind.proximaActividad);
    expect(item.id, 'a1');
    expect(item.etiqueta, 'PRÓXIMA ACTIVIDAD');
    expect(item.routePath, '/capturador/a1/usar');
    expect(item.qrRoutePath, isNull);
  });

  test('evento y actividad aparecen ambos, el evento primero si es antes', () {
    final evento = Evento(
      id: 'e1',
      nombre: 'Taller',
      fecha: DateTime(2026, 9, 10),
    );
    final actividad = EventoLead(
      id: 'a1',
      nombre: 'Feria',
      fecha: DateTime(2026, 9, 20),
    );

    final items = elegirProximosDestacados(
      evento: evento,
      actividad: actividad,
    );

    expect(items.map((item) => item.kind), [
      HomeFeaturedKind.proximoEvento,
      HomeFeaturedKind.proximaActividad,
    ]);
    expect(items.map((item) => item.id), ['e1', 'a1']);
  });

  test('una actividad anterior no esconde el evento recién creado', () {
    final evento = Evento(
      id: 'e1',
      nombre: 'Taller',
      fecha: DateTime(2026, 10, 1),
    );
    final actividad = EventoLead(
      id: 'a1',
      nombre: 'Feria',
      fecha: DateTime(2026, 9, 20),
    );

    final items = elegirProximosDestacados(
      evento: evento,
      actividad: actividad,
    );

    expect(items.map((item) => item.id), ['a1', 'e1']);
    expect(items.last.etiqueta, 'PRÓXIMO EVENTO');
  });

  test('la interna del próximo evento no duplica el hero', () {
    final evento = Evento(
      id: 'e1',
      nombre: 'Connect',
      fecha: DateTime(2026, 9, 20),
    );
    final actividad = EventoLead(
      id: 'a1',
      nombre: 'Connect',
      fecha: DateTime(2026, 9, 20),
      eventoOrigenId: 'e1',
      tipo: TipoEventoLead.interno,
    );

    final items = elegirProximosDestacados(
      evento: evento,
      actividad: actividad,
    );

    expect(items.single.kind, HomeFeaturedKind.proximoEvento);
    expect(items.single.id, 'e1');
  });

  test('elige la actividad vigente más cercana y descarta las terminadas', () {
    final hoy = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final terminada = EventoLead(
      id: 'pasada',
      nombre: 'Pasada',
      fecha: hoy.subtract(const Duration(days: 10)),
    );
    final cercana = EventoLead(
      id: 'cerca',
      nombre: 'Cerca',
      fecha: hoy.add(const Duration(days: 5)),
    );
    final lejana = EventoLead(
      id: 'lejos',
      nombre: 'Lejos',
      fecha: hoy.add(const Duration(days: 40)),
    );

    final proxima = proximaActividadVigente([lejana, terminada, cercana]);

    expect(proxima?.id, 'cerca');
  });

  test('una actividad en curso gana aunque haya empezado antes', () {
    final hoy = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final enCurso = EventoLead(
      id: 'curso',
      nombre: 'En curso',
      fecha: hoy.subtract(const Duration(days: 2)),
      duracionDias: 10,
    );
    final futura = EventoLead(
      id: 'futura',
      nombre: 'Futura',
      fecha: hoy.add(const Duration(days: 20)),
    );

    expect(enCurso.yaOcurrio, isFalse);
    expect(proximaActividadVigente([futura, enCurso])?.id, 'curso');
  });

  group('Escanear QR', () {
    final hoy = DateTime.now();
    final hoySolo = DateTime(hoy.year, hoy.month, hoy.day);

    Evento evento(DateTime fecha, {int dias = 1}) =>
        Evento(id: 'e1', nombre: 'Evento', fecha: fecha, duracionDias: dias);

    test('se ofrece en un evento que todavía no termina', () {
      final item = HomeFeaturedItem.eventoFijado(
        evento(hoySolo.add(const Duration(days: 10))),
      );

      expect(item.puedeEscanearQr, isTrue);
      expect(item.qrRoutePath, '/eventos/e1/acreditar-qr');
    });

    test('desaparece cuando el evento ya finalizó', () {
      final item = HomeFeaturedItem.eventoFijado(
        evento(hoySolo.subtract(const Duration(days: 2))),
      );

      expect(item.finalizado, isTrue);
      expect(item.puedeEscanearQr, isFalse);
    });

    test('sigue en el último día de un evento de varios días', () {
      final item = HomeFeaturedItem.eventoFijado(
        evento(hoySolo.subtract(const Duration(days: 2)), dias: 3),
      );

      expect(item.finalizado, isFalse);
      expect(item.puedeEscanearQr, isTrue);
    });
  });

  group('Card de evento con actividad incluida', () {
    final hoy = DateTime.now();
    final hoySolo = DateTime(hoy.year, hoy.month, hoy.day);

    HomeFeaturedItem evento({String? actividadId, int diasDesdeHoy = 5}) =>
        HomeFeaturedItem.proximoEvento(
          Evento(
            id: 'e1',
            nombre: 'Jornada',
            fecha: hoySolo.add(Duration(days: diasDesdeHoy)),
          ),
        ).copyWith(actividadId: actividadId);

    test('una actividad interna no compite como próxima actividad', () {
      final interna = EventoLead(
        id: 'interna',
        nombre: 'Jornada',
        fecha: hoySolo.add(const Duration(days: 2)),
        eventoOrigenId: 'e1',
        tipo: TipoEventoLead.interno,
      );
      final externa = EventoLead(
        id: 'externa',
        nombre: 'Feria',
        fecha: hoySolo.add(const Duration(days: 9)),
      );

      expect(proximaActividadVigente([interna, externa])?.id, 'externa');
      expect(proximaActividadVigente([interna]), isNull);
    });

    test('sin actividad: Ver evento + Escanear QR y Leads no se abre', () {
      final item = evento();

      expect(item.acciones, [
        HomeCardAccion.verEvento,
        HomeCardAccion.escanearQr,
      ]);
      expect(item.leadsRoutePath, isNull);
      expect(item.capturarLeadRoutePath, isNull);
      expect(item.registradosRoutePath, '/eventos/e1/registrados');
      expect(item.kpiRoutePath, '/eventos/e1/kpi');
    });

    test(
      'con actividad: Escanear QR + Capturar lead, y Leads abre su lista',
      () {
        final item = evento(actividadId: 'a1');

        expect(item.acciones, [
          HomeCardAccion.escanearQr,
          HomeCardAccion.capturarLead,
        ]);
        expect(
          item.capturarLeadRoutePath,
          startsWith('/capturador/a1/capturar'),
        );
        expect(item.leadsRoutePath, startsWith('/capturador/a1/leads'));
        expect(item.routePath, '/eventos/e1/usar');
      },
    );

    test('finalizado con actividad: Ver evento + Capturar lead', () {
      final item = evento(actividadId: 'a1', diasDesdeHoy: -3);

      expect(item.acciones, [
        HomeCardAccion.verEvento,
        HomeCardAccion.capturarLead,
      ]);
    });

    test('un evento fijado dos veces queda una sola vez', () {
      final fijado = HomeFeaturedItem.eventoFijado(
        Evento(id: 'e1', nombre: 'Jornada', fecha: hoySolo),
      );

      final items = ensamblarHomeFeaturedItems(fijados: [fijado, fijado]);

      expect(items.single.id, 'e1');
    });

    test('la caché conserva la actividad del evento', () {
      final item = evento(actividadId: 'a1');

      final copia = HomeFeaturedItem.fromCacheMap(item.toCacheMap());

      expect(copia.actividadId, 'a1');
    });
  });
}
