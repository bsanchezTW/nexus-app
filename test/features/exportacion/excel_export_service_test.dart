import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xls;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/models/inscripcion_subevento.dart';
import 'package:transworld_nexus/data/models/registrado.dart';
import 'package:transworld_nexus/data/models/subevento.dart';
import 'package:transworld_nexus/features/exportacion/services/excel_export_service.dart';

void main() {
  const personaId = '11111111-1111-1111-1111-111111111111';
  const tallerId = '22222222-2222-2222-2222-222222222222';
  const codigoQr = 'TW1-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

  test('el Excel lleva talleres y no la credencial ni los UUID', () {
    const service = ExcelExportService();
    final bytes = service.generar(
      [
        Registrado(
          id: personaId,
          eventoId: '33333333-3333-3333-3333-333333333333',
          nombreCompleto: 'Ana Díaz',
          email: 'ana@empresa.cl',
          codigoQr: codigoQr,
          acreditado: true,
          sobrecupo: true,
          acreditadoEn: DateTime.utc(2026, 12, 1, 15, 30),
        ),
      ],
      tituloHoja: 'Registrados',
      subeventos: [
        Subevento(
          id: tallerId,
          eventoId: '33333333-3333-3333-3333-333333333333',
          codigo: 'a7k2mq',
          nombre: 'Taller IA',
          dia: DateTime(2026, 12, 1),
          horaInicio: const TimeOfDay(hour: 10, minute: 0),
          horaFin: const TimeOfDay(hour: 11, minute: 30),
          cupoMaximo: 1,
        ),
      ],
      inscripciones: const [
        InscripcionSubevento(
          id: '44444444-4444-4444-4444-444444444444',
          eventoId: '33333333-3333-3333-3333-333333333333',
          registradoId: personaId,
          subeventoId: tallerId,
          origen: 'app',
          asistio: true,
        ),
      ],
    );

    final libro = xls.Excel.decodeBytes(bytes);
    expect(libro.tables.keys, containsAll(['Registrados', 'Talleres']));
    final hoja = libro['Registrados'];
    final cabeceras = [
      for (final celda in hoja.row(0)) _texto(celda),
    ];
    expect(cabeceras, contains('Acreditado en'));
    expect(cabeceras, contains('Sobrecupo'));
    expect(cabeceras, contains('Taller IA'));
    expect(cabeceras, isNot(contains('Bloque')));
    expect(cabeceras.join(' '), isNot(contains('codigo')));

    final fila = [for (final celda in hoja.row(1)) _texto(celda)];
    expect(fila, contains('Asistió'));
    expect(fila, contains('Sí'));

    final resumen = [
      for (final celda in libro['Talleres'].row(1)) _texto(celda),
    ];
    expect(resumen, contains('Taller IA'));
    expect(resumen, contains('a7k2mq'));
    expect(resumen, contains('1'));

    final xml = utf8.decode(
      ZipDecoder()
          .decodeBytes(bytes)
          .files
          .where((archivo) => archivo.name.endsWith('.xml'))
          .expand((archivo) => archivo.content as List<int>)
          .toList(),
    );
    expect(xml, isNot(contains(codigoQr)));
    expect(xml, isNot(contains(personaId)));
    expect(xml, isNot(contains(tallerId)));
  });

  test('mil registrados se arman en una pasada', () {
    const service = ExcelExportService();
    final talleres = [
      for (var i = 0; i < 8; i++)
        Subevento(
          id: 'taller-$i',
          eventoId: 'evento',
          codigo: 'c$i',
          nombre: 'Taller $i',
          dia: DateTime(2026, 12, 1),
          horaInicio: TimeOfDay(hour: 9, minute: i),
          horaFin: TimeOfDay(hour: 10, minute: i),
        ),
    ];
    final registrados = [
      for (var i = 0; i < 1000; i++)
        Registrado(
          id: 'persona-$i',
          eventoId: 'evento',
          nombreCompleto: 'Persona $i',
          email: 'p$i@x.cl',
          codigoQr: 'TW1-${i.toString().padLeft(32, 'A')}',
        ),
    ];
    final inscripciones = [
      for (var i = 0; i < 1000; i++)
        InscripcionSubevento(
          id: 'ins-$i',
          eventoId: 'evento',
          registradoId: 'persona-$i',
          subeventoId: 'taller-${i % 8}',
          origen: 'app',
          asistio: i.isEven,
        ),
    ];

    final bytes = service.generar(
      registrados,
      tituloHoja: 'Registrados',
      subeventos: talleres,
      inscripciones: inscripciones,
    );
    final hoja = xls.Excel.decodeBytes(bytes)['Registrados'];
    expect(hoja.maxRows, 1001);
    expect(_texto(hoja.row(1)[11]), 'Asistió');
    expect(_texto(hoja.row(2)[12]), 'Inscrito');
  });
}

String _texto(xls.Data? celda) {
  final valor = celda?.value;
  if (valor is xls.TextCellValue) return valor.value.text ?? '';
  return '';
}
