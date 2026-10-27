import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/models/evento.dart';

void main() {
  test('sin duración en la fila se asume un día', () {
    final evento = Evento.fromMap({
      'id': 'e-1',
      'nombre': 'Taller',
      'fecha': '2026-09-12',
    });

    expect(evento.duracionDias, 1);
    expect(evento.esMultiDia, isFalse);
    expect(evento.toInsertMap()['duracion_dias'], 1);
    expect(evento.toInsertMap().containsKey('activo'), isFalse);
  });

  test('un evento de 3 días cubre el rango y no el día siguiente', () {
    final evento = Evento(
      id: 'e-1',
      nombre: 'Feria',
      fecha: DateTime(2026, 9, 12),
      duracionDias: 3,
    );

    expect(evento.cubreDia(DateTime(2026, 9, 12)), isTrue);
    expect(evento.cubreDia(DateTime(2026, 9, 14)), isTrue);
    expect(evento.cubreDia(DateTime(2026, 9, 15)), isFalse);
    expect(evento.cubreMes(DateTime(2026, 9, 1)), isTrue);
    expect(evento.cubreMes(DateTime(2026, 10, 1)), isFalse);
    expect(evento.toInsertMap()['duracion_dias'], 3);
    expect(evento.toCacheMap()['duracion_dias'], 3);
    expect(evento.toInsertMap().containsKey('activo'), isFalse);
    expect(evento.toCacheMap().containsKey('activo'), isFalse);
  });

  test('un flag activo residual en la fila no cambia la vigencia', () {
    final evento = Evento.fromMap({
      'id': 'e-1',
      'nombre': 'Taller',
      'fecha': '2099-01-01',
      'activo': false,
    });

    expect(evento.yaOcurrio, isFalse);
    expect(evento.toInsertMap().containsKey('activo'), isFalse);
  });

  test('yaOcurrio usa el último día del rango, no el de inicio', () {
    final ayer = DateTime.now().subtract(const Duration(days: 1));
    final inicio = DateTime(ayer.year, ayer.month, ayer.day);

    expect(Evento(id: 'e-1', nombre: 'Corto', fecha: inicio).yaOcurrio, isTrue);
    expect(
      Evento(
        id: 'e-2',
        nombre: 'Largo',
        fecha: inicio,
        duracionDias: 3,
      ).yaOcurrio,
      isFalse,
    );
  });

  test('una caché vieja con tipo_registro cliente marca acceso QR', () {
    final evento = Evento.fromMap({
      'id': 'e-1',
      'nombre': 'Taller',
      'fecha': '2026-11-12',
      'tipo_registro': 'cliente',
      'hora_inicio': '09:00:00',
      'inscripciones_cierre': '2026-11-11T23:59:00',
    });

    expect(evento.accesoQr, isTrue);
    expect(evento.slug, isEmpty);
    expect(evento.horaInicio?.hour, 9);
    expect(evento.inscripcionesCierre?.hour, 23);
    expect(evento.toInsertMap().containsKey('tipo_registro'), isFalse);
    expect(evento.toInsertMap()['acceso_qr'], isTrue);
    expect(evento.tipo, TipoEvento.evento);
    expect(evento.toInsertMap()['tipo'], 'evento');
  });

  test('tipo taller se conserva al leer y al guardar', () {
    final evento = Evento.fromMap({
      'id': 'e-1',
      'nombre': 'Charla',
      'fecha': '2026-11-12',
      'tipo': 'taller',
    });

    expect(evento.esTaller, isTrue);
    expect(evento.toInsertMap()['tipo'], 'taller');
    expect(evento.toCacheMap()['tipo'], 'taller');
  });

  test('descripción, cierre y mapa sobreviven guardar → caché → leer', () {
    final original = Evento.fromMap({
      'id': 'e-1',
      'nombre': 'Connect',
      'fecha': '2026-11-12',
      'descripcion': 'Demos y talleres',
      'inscripciones_cierre': '2026-11-11T23:59:00',
      'mapa_url': 'https://www.google.com/maps/embed?pb=abc',
      'banner_url': 'https://x/banner.jpg',
    });
    final releido = Evento.fromMap(original.toCacheMap());

    expect(releido.descripcion, 'Demos y talleres');
    expect(releido.inscripcionesCierre, DateTime(2026, 11, 11, 23, 59));
    expect(releido.mapaUrl, 'https://www.google.com/maps/embed?pb=abc');
    expect(
      original.toInsertMap()['inscripciones_cierre'],
      '2026-11-11T23:59:00',
    );
    // El banner ya no se usa: editar no lo toca.
    expect(original.toInsertMap().containsKey('banner_url'), isFalse);
  });

  test('urlGoogleMaps acepta el enlace de Compartir tal como se copia', () {
    // Mismos casos que googleMapsLink en eventos-web (domain/maps.js).
    expect(
      urlGoogleMaps('Casa Piedra\nhttps://maps.app.goo.gl/AbC123?g_st=iw'),
      'https://maps.app.goo.gl/AbC123?g_st=iw',
    );
    expect(urlGoogleMaps('https://goo.gl/maps/xyz'), 'https://goo.gl/maps/xyz');
    const lugar =
        'https://www.google.com/maps/place/Casa+Piedra/@-33.39,-70.59,17z';
    expect(urlGoogleMaps(lugar), lugar);
    expect(
      urlGoogleMaps('https://www.google.cl/maps/@-33.4,-70.6,15z'),
      isNotNull,
    );
    expect(
      urlGoogleMaps('https://maps.google.com/?q=-12.09,-77.02'),
      isNotNull,
    );
  });

  test('urlGoogleMaps sigue aceptando Insertar un mapa', () {
    const embed = 'https://www.google.com/maps/embed?pb=!1m18!2sHotel';
    expect(urlGoogleMaps(embed), embed);
    expect(
      urlGoogleMaps(
        '<iframe src="https://www.google.com/maps/embed?pb=!1m1&amp;x=1" '
        'width="600" height="450" loading="lazy"></iframe>',
      ),
      'https://www.google.com/maps/embed?pb=!1m1&x=1',
    );
    expect(
      urlGoogleMaps('http://www.google.com/maps/embed?pb=1'),
      'https://www.google.com/maps/embed?pb=1',
    );
  });

  test('urlGoogleMaps rechaza lo que no es Google Maps', () {
    expect(urlGoogleMaps('  '), isNull);
    expect(urlGoogleMaps('Calle Nueva 1890, Huechuraba'), isNull);
    expect(
      urlGoogleMaps('https://www.google.com/search?q=casa+piedra'),
      isNull,
    );
    expect(urlGoogleMaps('https://goo.gl/otra-cosa'), isNull);
    expect(urlGoogleMaps('https://evil.example/maps/embed?pb=1'), isNull);
  });
}
