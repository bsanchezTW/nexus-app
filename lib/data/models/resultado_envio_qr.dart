import 'dart:convert';

/// Canales que entiende la Edge Function `enviar-qr`.
abstract final class CanalesEnvioQr {
  static const email = 'email';
  static const sms = 'sms';
  static const List<String> ambos = [email, sms];
}

class ResultadoCanalQr {
  const ResultadoCanalQr({required this.status, this.reason});

  final String status;
  final String? reason;

  bool get enviado => status == 'sent';
  bool get omitido => status == 'skipped';
  bool get fallido => status == 'failed';
  bool get noPedido => status == 'not_requested';

  /// Texto usable en UI: si Brevo devolvió JSON, extrae `message`.
  String get mensajeBrevo {
    final raw = reason?.trim() ?? '';
    if (raw.isEmpty) return '';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['message'] != null) {
        final msg = decoded['message'].toString();
        if (msg.toLowerCase().contains('sms related addons')) {
          return 'Brevo no tiene el complemento SMS en esta cuenta. '
              'Contrata SMS transaccional en Brevo (Add-ons / SMS).';
        }
        return msg;
      }
    } catch (_) {}
    return raw;
  }

  factory ResultadoCanalQr.fromJson(Object? raw) {
    if (raw is Map) {
      return ResultadoCanalQr(
        status: raw['status'] as String? ?? 'failed',
        reason: raw['reason'] as String?,
      );
    }
    return const ResultadoCanalQr(status: 'not_requested');
  }
}

class ResultadoEnvioQr {
  const ResultadoEnvioQr({required this.email, required this.sms});

  final ResultadoCanalQr email;
  final ResultadoCanalQr sms;

  factory ResultadoEnvioQr.fromJson(Object? raw) {
    if (raw is Map) {
      return ResultadoEnvioQr(
        email: ResultadoCanalQr.fromJson(raw['email']),
        sms: ResultadoCanalQr.fromJson(raw['sms']),
      );
    }
    return const ResultadoEnvioQr(
      email: ResultadoCanalQr(status: 'not_requested'),
      sms: ResultadoCanalQr(status: 'not_requested'),
    );
  }
}
