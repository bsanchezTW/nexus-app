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
      proximo: proximo,
    );

    expect(items.map((item) => item.id), ['fijado', 'proximo']);
    expect(items.first.kind, HomeFeaturedKind.eventoFijado);
  });

  test('si el próximo también está fijado no se duplica y manda el fijado', () {
    final fijado = _item(kind: HomeFeaturedKind.eventoFijado, id: 'mismo');
    final proximo = _item(kind: HomeFeaturedKind.proximoEvento, id: 'mismo');

    final items = ensamblarHomeFeaturedItems(
      fijados: [fijado],
      proximo: proximo,
    );

    expect(items, hasLength(1));
    expect(items.single.kind, HomeFeaturedKind.eventoFijado);
  });

  test('si la próxima actividad ya está fijada no se duplica', () {
    final fijada = _item(kind: HomeFeaturedKind.campanaFijada, id: 'a1');
    final proxima = _item(kind: HomeFeaturedKind.proximaActividad, id: 'a1');

    final items = ensamblarHomeFeaturedItems(
      fijados: [fijada],
      proximo: proxima,
    );

    expect(items, hasLength(1));
    expect(items.single.kind, HomeFeaturedKind.campanaFijada);
  });

  test('sin fijados solo queda el próximo evento', () {
    final proximo = _item(kind: HomeFeaturedKind.proximoEvento, id: 'proximo');

    final items = ensamblarHomeFeaturedItems(
      fijados: const [],
      proximo: proximo,
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
    expect(item.ctaLabel, 'Ver actividad');
    expect(item.ctaRoutePath, '/capturador/c1/usar');
    expect(item.secondaryCtaLabel, 'Capturar lead');
    expect(item.secondaryRoutePath, '/capturador/c1/capturar');
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

    final item = elegirProximoDestacado(actividad: actividad);

    expect(item, isNotNull);
    expect(item!.kind, HomeFeaturedKind.proximaActividad);
    expect(item.id, 'a1');
    expect(item.etiqueta, 'PRÓXIMA ACTIVIDAD');
    expect(item.ctaLabel, 'Ver actividad');
    expect(item.ctaRoutePath, '/capturador/a1/usar');
    expect(item.qrRoutePath, isNull);
  });

  test('si el evento es antes que la actividad manda el evento', () {
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

    final item = elegirProximoDestacado(evento: evento, actividad: actividad);

    expect(item!.kind, HomeFeaturedKind.proximoEvento);
    expect(item.id, 'e1');
  });

  test('si la actividad es antes que el evento manda la actividad', () {
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

    final item = elegirProximoDestacado(evento: evento, actividad: actividad);

    expect(item!.kind, HomeFeaturedKind.proximaActividad);
    expect(item.id, 'a1');
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

    final item = elegirProximoDestacado(evento: evento, actividad: actividad);

    expect(item!.kind, HomeFeaturedKind.proximoEvento);
    expect(item.id, 'e1');
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
}
