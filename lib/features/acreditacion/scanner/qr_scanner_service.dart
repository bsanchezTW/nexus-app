import 'package:mobile_scanner/mobile_scanner.dart';

import '../qr_codigo_parser.dart';

/// Resultado tipado de un frame de escaneo.
class QrScanDecode {
  const QrScanDecode({required this.lectura, this.rawText});

  final QrLectura lectura;
  final String? rawText;

  bool get isValid => lectura.tipo == QrLecturaTipo.valido;
}

class QRScannerService {
  const QRScannerService();

  QrScanDecode decode(BarcodeCapture capture) {
    if (capture.barcodes.isEmpty) {
      return const QrScanDecode(lectura: QrLectura.invalido());
    }
    return QrScanDecode(
      lectura: interpretarQrDeCaptura(capture),
      rawText: textoLeidoDeCaptura(capture),
    );
  }
}
