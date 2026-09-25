import 'package:mobile_scanner/mobile_scanner.dart';

final _codigoQr = RegExp(r'^TW1-[0-9A-F]{32}$');
final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

String _limpiar(String raw) {
  return raw
      .trim()
      .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
      .replaceAll(RegExp(r'''^["']|["']$'''), '');
}

enum QrLecturaTipo { valido, formatoAntiguo, invalido }

class QrLectura {
  const QrLectura._(this.tipo, [this.codigo]);

  const QrLectura.valido(String codigo) : this._(QrLecturaTipo.valido, codigo);
  const QrLectura.formatoAntiguo() : this._(QrLecturaTipo.formatoAntiguo);
  const QrLectura.invalido() : this._(QrLecturaTipo.invalido);

  final QrLecturaTipo tipo;
  final String? codigo;
}

QrLectura interpretarQr(String raw) {
  final texto = _limpiar(raw).toUpperCase();
  if (texto.isEmpty) return const QrLectura.invalido();
  if (_codigoQr.hasMatch(texto)) return QrLectura.valido(texto);
  if (_uuid.hasMatch(texto)) return const QrLectura.formatoAntiguo();
  return const QrLectura.invalido();
}

QrLectura interpretarQrDeCaptura(BarcodeCapture capture) {
  final texto = textoLeidoDeCaptura(capture);
  if (texto == null) return const QrLectura.invalido();
  return interpretarQr(texto);
}

String? textoLeidoDeCaptura(BarcodeCapture capture) {
  for (final barcode in capture.barcodes) {
    final raw = barcode.rawValue;
    if (raw != null && raw.isNotEmpty) return raw;
    final display = barcode.displayValue;
    if (display != null && display.isNotEmpty) return display;
  }
  return null;
}
