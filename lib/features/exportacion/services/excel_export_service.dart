import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:intl/intl.dart';

import '../../../core/utils/excel_sheet_styler.dart';
import '../../../data/models/registrado.dart';

/// Genera el `.xlsx` de descarga (registrados o acreditados) a partir de
/// una lista de [Registrado]. Reemplaza a `xlsx.utils.json_to_sheet` /
/// `XLSX.writeFile` del proyecto legado, sin depender de Electron
/// (`window.ipcRenderer`, ver Sección 4.13/17.4 de la auditoría): la
/// entrega del archivo la resuelve `export_file_delivery` (guardar en
/// Windows; guardar o compartir en móvil; compartir en el resto).
class ExcelExportService {
  const ExcelExportService();

  static const _cabeceras = [
    'Nombre y Apellido',
    'Email',
    'Empresa',
    'Cargo',
    'Teléfono',
    'RUT / RUC',
    'Patente',
    'Acreditado',
    'Fecha de registro',
  ];

  Uint8List generar(
    List<Registrado> registrados, {
    required String tituloHoja,
  }) {
    final excel = xls.Excel.createExcel();
    final nombreHojaOriginal = excel.getDefaultSheet()!;
    excel.rename(nombreHojaOriginal, tituloHoja);
    final sheet = excel[tituloHoja];

    sheet.appendRow([for (final h in _cabeceras) xls.TextCellValue(h)]);

    final formatoFecha = DateFormat('dd/MM/yyyy HH:mm');
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
          r.createdAt != null ? formatoFecha.format(r.createdAt!) : '',
        ),
      ]);
    }

    ExcelSheetStyler.aplicar(
      sheet: sheet,
      cabeceras: _cabeceras,
      filasDatos: registrados.length,
    );

    final bytes = excel.encode();
    if (bytes == null) throw Exception('No se pudo generar el archivo Excel.');
    return ExcelSheetStyler.congelarPrimeraFila(Uint8List.fromList(bytes));
  }
}
