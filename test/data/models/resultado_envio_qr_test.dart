import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/models/resultado_envio_qr.dart';

void main() {
  test('fromJson lee sent y skipped con reason', () {
    final resultado = ResultadoEnvioQr.fromJson({
      'email': {'status': 'sent'},
      'sms': {'status': 'skipped', 'reason': 'sin_telefono'},
    });

    expect(resultado.email.enviado, isTrue);
    expect(resultado.sms.omitido, isTrue);
    expect(resultado.sms.reason, 'sin_telefono');
  });

  test('fromJson tolera un cuerpo vacío', () {
    final resultado = ResultadoEnvioQr.fromJson(null);

    expect(resultado.email.noPedido, isTrue);
    expect(resultado.sms.noPedido, isTrue);
  });

  test('mensajeBrevo traduce la falta de complemento SMS', () {
    const canal = ResultadoCanalQr(
      status: 'failed',
      reason:
          '{"code":"invalid_parameter","message":"No sms related addons are found for the given organization"}',
    );

    expect(canal.mensajeBrevo, contains('complemento SMS'));
  });
}
