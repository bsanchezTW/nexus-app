import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/models/evento_lead.dart';

void main() {
  test('el evento de leads sin origen es externo', () {
    final evento = EventoLead.fromMap({
      'id': 'el-1',
      'nombre': 'Feria retail',
      'fecha': '2026-09-12',
      'tipo_evento_lead': 'externo',
    });

    expect(evento.esInterno, isFalse);
    expect(evento.eventoOrigenId, isNull);
  });

  test('el interno conserva el id del evento del que nació', () {
    final evento = EventoLead.fromMap({
      'id': 'el-1',
      'nombre': 'Transworld Connect',
      'fecha': '2026-09-12',
      'tipo_evento_lead': 'interno',
      'evento_origen_id': 'evento-1',
    });

    expect(evento.esInterno, isTrue);
    expect(evento.eventoOrigenId, 'evento-1');
  });

  test('una fila anterior a la columna de tipo se lee como externa', () {
    final evento = EventoLead.fromMap({
      'id': 'el-legacy',
      'nombre': 'Campaña histórica',
      'fecha': '2025-03-01',
    });

    expect(evento.esInterno, isFalse);
  });

  test('internoDesdeEvento copia los metadatos y fija el vínculo', () {
    final evento = EventoLead.internoDesdeEvento(
      eventoOrigenId: 'evento-1',
      nombre: '  Transworld Connect  ',
      fecha: DateTime(2026, 9, 12),
      pais: 'Chile',
      tematica: 'Telecomunicaciones',
    );

    expect(evento.nombre, 'Transworld Connect');
    expect(evento.tipo, TipoEventoLead.interno);

    final insert = evento.toInsertMap();
    expect(insert['tipo_evento_lead'], 'interno');
    expect(insert['evento_origen_id'], 'evento-1');
    expect(insert['pais'], 'Chile');
    expect(insert['imagen_url'], isNull);
  });

  test('internoDesdeEvento copia la imagen del evento de origen', () {
    final evento = EventoLead.internoDesdeEvento(
      eventoOrigenId: 'evento-1',
      nombre: 'Transworld Connect',
      fecha: DateTime(2026, 9, 12),
      imagenUrl: 'https://cdn.example/evento.jpg',
    );

    expect(evento.tieneImagen, isTrue);
    expect(
      evento.toInsertMap()['imagen_url'],
      'https://cdn.example/evento.jpg',
    );
  });

  test('el alta manual viaja como externa y sin evento de origen', () {
    final insert = EventoLead(
      id: '',
      nombre: 'Feria retail',
      fecha: DateTime(2026, 9, 12),
      imagenUrl: 'https://cdn.example/feria.jpg',
    ).toInsertMap();

    expect(insert['tipo_evento_lead'], 'externo');
    expect(insert['evento_origen_id'], isNull);
    expect(insert['imagen_url'], 'https://cdn.example/feria.jpg');
    expect(insert['duracion_dias'], 1);
  });

  test('editar un interno no lo puede convertir en externo', () {
    final interno = EventoLead.internoDesdeEvento(
      eventoOrigenId: 'evento-1',
      nombre: 'Transworld Connect',
      fecha: DateTime(2026, 9, 12),
    );

    // El formulario reconstruye el modelo desde sus campos, así que sin este
    // recorte el update arrastraría el tipo por defecto (externo).
    final update = interno.copyWith(nombre: 'Otro nombre').toUpdateMap();

    expect(update.containsKey('tipo_evento_lead'), isFalse);
    expect(update.containsKey('evento_origen_id'), isFalse);
    expect(update.containsKey('nombre'), isFalse);
    expect(update, isEmpty);
  });

  test('fromMap lee la imagen de portada', () {
    final evento = EventoLead.fromMap({
      'id': 'el-1',
      'nombre': 'Feria retail',
      'fecha': '2026-09-12',
      'imagen_url': 'https://cdn.example/feria.jpg',
    });

    expect(evento.imagenUrl, 'https://cdn.example/feria.jpg');
    expect(evento.tieneImagen, isTrue);
  });

  test('copyWith conserva el vínculo con el evento de origen', () {
    final interno = EventoLead.internoDesdeEvento(
      eventoOrigenId: 'evento-1',
      nombre: 'Transworld Connect',
      fecha: DateTime(2026, 9, 12),
    );

    final editado = interno.copyWith(pais: 'Perú');

    expect(editado.esInterno, isTrue);
    expect(editado.eventoOrigenId, 'evento-1');
  });

  test('una actividad externa sí persiste los campos del formulario', () {
    final update = EventoLead(
      id: 'el-1',
      nombre: 'Feria retail',
      fecha: DateTime(2026, 9, 12),
      pais: 'Chile',
      tematica: 'Retail',
      imagenUrl: 'https://cdn.example/feria.jpg',
    ).toUpdateMap();

    expect(update['nombre'], 'Feria retail');
    expect(update['pais'], 'Chile');
    expect(update['imagen_url'], 'https://cdn.example/feria.jpg');
    expect(update['duracion_dias'], 1);
    expect(update.containsKey('tipo_evento_lead'), isFalse);
  });

  test('editar un interno no persiste la imagen desde el cliente', () {
    final interno = EventoLead.internoDesdeEvento(
      eventoOrigenId: 'evento-1',
      nombre: 'Transworld Connect',
      fecha: DateTime(2026, 9, 12),
      imagenUrl: 'https://cdn.example/evento.jpg',
    );

    expect(interno.copyWith().toUpdateMap(), isEmpty);
  });

  test('sin duración en la fila se asume un día', () {
    final evento = EventoLead.fromMap({
      'id': 'el-1',
      'nombre': 'Feria retail',
      'fecha': '2026-09-12',
    });

    expect(evento.duracionDias, 1);
    expect(evento.esMultiDia, isFalse);
    expect(
      evento.fechaFin,
      DateTime(evento.fecha.year, evento.fecha.month, evento.fecha.day),
    );
    expect(evento.etiquetaDuracion, '1 día');
  });

  test('una actividad de 3 días termina el segundo día siguiente', () {
    final evento = EventoLead.fromMap({
      'id': 'el-1',
      'nombre': 'Feria retail',
      'fecha': '2026-09-12',
      'duracion_dias': 3,
    });

    expect(evento.duracionDias, 3);
    expect(evento.esMultiDia, isTrue);
    expect(
      evento.fechaFin
          .difference(
            DateTime(evento.fecha.year, evento.fecha.month, evento.fecha.day),
          )
          .inDays,
      2,
    );
    expect(evento.etiquetaDuracion, '3 días');
    expect(evento.toInsertMap()['duracion_dias'], 3);
    expect(evento.toUpdateMap()['duracion_dias'], 3);
    expect(evento.toCacheMap()['duracion_dias'], 3);
  });

  test('el interno no persiste la duración: la hereda del evento', () {
    final update = EventoLead.internoDesdeEvento(
      eventoOrigenId: 'evento-1',
      nombre: 'Transworld Connect',
      fecha: DateTime(2026, 9, 12),
      duracionDias: 5,
    ).toUpdateMap();

    expect(update, isEmpty);
    expect(
      EventoLead.internoDesdeEvento(
        eventoOrigenId: 'evento-1',
        nombre: 'Transworld Connect',
        fecha: DateTime(2026, 9, 12),
        duracionDias: 5,
      ).duracionDias,
      5,
    );
  });
}
