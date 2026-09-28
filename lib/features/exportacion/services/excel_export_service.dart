import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;

import '../../../core/utils/excel_sheet_styler.dart';
import '../../../data/models/evento.dart';
import '../../../data/models/inscripcion_subevento.dart';
import '../../../data/models/registrado.dart';
import '../../../data/models/subevento.dart';

/// Genera el `.xlsx` de descarga (registrados o acreditados) a partir de
/// una lista de [Registrado]. Reemplaza a `xlsx.utils.json_to_sheet` /
/// `XLSX.writeFile` del proyecto legado, sin depender de Electron
/// (`window.ipcRenderer`, ver Sección 4.13/17.4 de la auditoría): la
/// entrega del archivo la resuelve `export_file_delivery` (guardar en
/// Windows; guardar o compartir en móvil; compartir en el resto).
class ExcelExportService {
  const ExcelExportService();

  static const _cabecerasBase = [
    'Nombre y Apellido',
    'Email',
    'Empresa',
    'Cargo',
    'Teléfono',
    'RUT / RUC',
    'Patente',
    'Acreditado',
    'Acreditado en',
    'Sobrecupo',
    'Fecha de registro',
  ];

  static const _cabecerasTalleres = [
    'Taller',
    'Código',
    'Día',
    'Inicio',
    'Fin',
    'Cupo',
    'Inscritos',
    'Asistentes',
    'Sobrecupo',
    'Asistencia',
  ];

  Uint8List generar(
    List<Registrado> registrados, {
    required String tituloHoja,
    List<Subevento> subeventos = const [],
    List<InscripcionSubevento> inscripciones = const [],
  }) {
    final excel = xls.Excel.createExcel();
    final nombreHojaOriginal = excel.getDefaultSheet()!;
    excel.rename(nombreHojaOriginal, tituloHoja);
    final sheet = excel[tituloHoja];
    final talleres = _ordenar(subeventos);
    final columnasTaller = _columnasTaller(talleres);
    final cabeceras = [
      ..._cabecerasBase,
      for (final columna in columnasTaller) columna.titulo,
    ];
    final estado = _estadoPorPersona(inscripciones, registrados);
    final conteos = _conteoPorTaller(inscripciones, registrados);

    sheet.appendRow([for (final h in cabeceras) xls.TextCellValue(h)]);

    for (final r in registrados) {
      sheet.appendRow([
        xls.TextCellValue(r.nombreCompleto),
        xls.TextCellValue(r.email),
        xls.TextCellValue(r.empresa ?? ''),
        xls.TextCellValue(r.cargo ?? ''),
        xls.TextCellValue(r.telefono ?? ''),
        xls.TextCellValue(r.rut ?? ''),
        xls.TextCellValue(r.patente ?? ''),
        xls.TextCellValue(r.acreditado ? 'Sí' : 'No'),
        xls.TextCellValue(
          r.acreditadoEn != null ? _fechaHora(r.acreditadoEn!) : '',
        ),
        xls.TextCellValue(r.sobrecupo ? 'Sí' : 'No'),
        xls.TextCellValue(r.createdAt != null ? _fechaHora(r.createdAt!) : ''),
        for (final columna in columnasTaller)
          xls.TextCellValue(estado['${r.id}|${columna.id}'] ?? ''),
      ]);
    }

    ExcelSheetStyler.aplicar(
      sheet: sheet,
      cabeceras: cabeceras,
      filasDatos: registrados.length,
    );

    final resumen = excel['Talleres'];
    resumen.appendRow([
      for (final h in _cabecerasTalleres) xls.TextCellValue(h),
    ]);
    for (final taller in talleres) {
      final conteo = conteos[taller.id];
      final inscritos = conteo?.inscritos ?? 0;
      final asistentes = conteo?.asistentes ?? 0;
      resumen.appendRow([
        xls.TextCellValue(taller.nombre),
        xls.TextCellValue(taller.codigo),
        xls.TextCellValue(_fecha(taller.dia)),
        xls.TextCellValue(horaATexto(taller.horaInicio)?.substring(0, 5) ?? ''),
        xls.TextCellValue(horaATexto(taller.horaFin)?.substring(0, 5) ?? ''),
        xls.TextCellValue(taller.cupoMaximo?.toString() ?? ''),
        xls.TextCellValue('$inscritos'),
        xls.TextCellValue('$asistentes'),
        xls.TextCellValue('${conteo?.sobrecupo ?? 0}'),
        xls.TextCellValue(
          inscritos == 0
              ? '0%'
              : '${(asistentes / inscritos * 100).toStringAsFixed(0)}%',
        ),
      ]);
    }
    ExcelSheetStyler.aplicar(
      sheet: resumen,
      cabeceras: _cabecerasTalleres,
      filasDatos: talleres.length,
    );

    final bytes = excel.encode();
    if (bytes == null) throw Exception('No se pudo generar el archivo Excel.');
    return ExcelSheetStyler.congelarPrimeraFila(Uint8List.fromList(bytes));
  }
}

class _ColumnaTaller {
  const _ColumnaTaller(this.id, this.titulo);

  final String id;
  final String titulo;
}

class _ConteoTaller {
  int inscritos = 0;
  int asistentes = 0;
  int sobrecupo = 0;
}

List<Subevento> _ordenar(List<Subevento> subeventos) {
  final copia = [...subeventos];
  copia.sort((a, b) {
    final dia = DateTime(a.dia.year, a.dia.month, a.dia.day).compareTo(
      DateTime(b.dia.year, b.dia.month, b.dia.day),
    );
    if (dia != 0) return dia;
    final hora =
        (a.horaInicio.hour * 60 + a.horaInicio.minute) -
        (b.horaInicio.hour * 60 + b.horaInicio.minute);
    if (hora != 0) return hora;
    final orden = a.orden.compareTo(b.orden);
    if (orden != 0) return orden;
    return a.nombre.compareTo(b.nombre);
  });
  return copia;
}

List<_ColumnaTaller> _columnasTaller(List<Subevento> talleres) {
  final usados = <String>{};
  return [
    for (final taller in talleres)
      _ColumnaTaller(taller.id, _tituloUnico(taller, usados)),
  ];
}

String _tituloUnico(Subevento taller, Set<String> usados) {
  final base = taller.nombre.trim().isEmpty
      ? taller.codigo
      : taller.nombre.trim();
  if (usados.add(base)) return base;
  final conCodigo = taller.codigo.isEmpty
      ? '$base (${usados.length})'
      : '$base (${taller.codigo})';
  usados.add(conCodigo);
  return conCodigo;
}

Map<String, String> _estadoPorPersona(
  List<InscripcionSubevento> inscripciones,
  List<Registrado> registrados,
) {
  final personas = registrados.map((persona) => persona.id).toSet();
  final estado = <String, String>{};
  for (final fila in inscripciones) {
    if (!personas.contains(fila.registradoId)) continue;
    estado['${fila.registradoId}|${fila.subeventoId}'] = fila.asistio
        ? 'Asistió'
        : 'Inscrito';
  }
  return estado;
}

Map<String, _ConteoTaller> _conteoPorTaller(
  List<InscripcionSubevento> inscripciones,
  List<Registrado> registrados,
) {
  final personas = registrados.map((persona) => persona.id).toSet();
  final conteos = <String, _ConteoTaller>{};
  for (final fila in inscripciones) {
    if (!personas.contains(fila.registradoId)) continue;
    final conteo = conteos.putIfAbsent(fila.subeventoId, _ConteoTaller.new);
    conteo.inscritos++;
    if (fila.asistio) conteo.asistentes++;
    if (fila.sobrecupo) conteo.sobrecupo++;
  }
  return conteos;
}

String _fecha(DateTime dia) {
  final d = dia.day.toString().padLeft(2, '0');
  final m = dia.month.toString().padLeft(2, '0');
  return '$d/$m/${dia.year}';
}

String _fechaHora(DateTime fecha) {
  final local = fecha.toLocal();
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '${_fecha(local)} $h:$min';
}
