import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/models/envio_qr.dart';

EnvioQr _envio({
  String estado = 'completado',
  String motivo = 'registro',
  Map<String, dynamic>? resultado,
}) => EnvioQr.fromMap({
  'id': 'e1',
  'canales': ['email', 'sms'],
  'motivo': motivo,
  'estado': estado,
  'created_at': '2026-10-22T16:20:05.898704Z',
  'resultado': resultado,
});

void main() {
  test('el motivo se muestra en palabras, no como clave de la base', () {
    expect(
      _envio(motivo: 'registro').etiquetaMotivo,
      'Confirmación de registro',
    );
    expect(_envio(motivo: 'reenvio').etiquetaMotivo, 'Reenvío');
    expect(_envio(motivo: 'codigo_regenerado').etiquetaMotivo, 'QR regenerado');
    expect(
      _envio(motivo: 'talleres_agregados').etiquetaMotivo,
      'Talleres agregados',
    );
    expect(EnvioQr.etiquetaCanal('email'), 'Correo');
    expect(EnvioQr.etiquetaCanal('sms'), 'SMS');
  });

  test('cada canal toma su estado del resultado', () {
    final envio = _envio(
      resultado: {
        'email': {'status': 'sent'},
        'sms': {'status': 'failed', 'reason': 'brevo'},
      },
    );
    expect(envio.estadoDe('email'), EstadoCanalEnvio.enviado);
    expect(envio.estadoDe('sms'), EstadoCanalEnvio.fallido);
  });

  test('sin procesar todavía, los canales están en cola', () {
    expect(
      _envio(estado: 'pendiente').estadoDe('email'),
      EstadoCanalEnvio.enCola,
    );
    expect(
      _envio(estado: 'procesando').estadoDe('sms'),
      EstadoCanalEnvio.enCola,
    );
  });

  test('sin detalle por canal se usa el estado del envío', () {
    expect(_envio().estadoDe('email'), EstadoCanalEnvio.enviado);
    expect(
      _envio(estado: 'fallido').estadoDe('email'),
      EstadoCanalEnvio.fallido,
    );
    expect(
      _envio(
        resultado: {
          'sms': {'status': 'skipped'},
        },
      ).estadoDe('sms'),
      EstadoCanalEnvio.omitido,
    );
  });
}
