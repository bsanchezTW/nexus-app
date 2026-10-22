/// Cómo terminó un envío en un canal.
enum EstadoCanalEnvio { enviado, fallido, omitido, enCola }

class EnvioQr {
  const EnvioQr({
    required this.id,
    required this.canales,
    required this.motivo,
    required this.estado,
    required this.createdAt,
    this.resultado,
  });

  final String id;
  final List<String> canales;
  final String motivo;
  final String estado;
  final DateTime? createdAt;
  final Map<String, dynamic>? resultado;

  factory EnvioQr.fromMap(Map<String, dynamic> map) {
    final canales = map['canales'];
    final resultado = map['resultado'];
    return EnvioQr(
      id: map['id'] as String,
      canales: canales is List
          ? canales.map((c) => c.toString()).toList()
          : const [],
      motivo: map['motivo'] as String? ?? '',
      estado: map['estado'] as String? ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      resultado: resultado is Map ? Map<String, dynamic>.from(resultado) : null,
    );
  }

  /// Por qué se envió, para mostrar (`motivo` viene como clave de la base).
  String get etiquetaMotivo => switch (motivo) {
    'registro' => 'Confirmación de registro',
    'talleres_agregados' => 'Talleres agregados',
    'reenvio' => 'Reenvío',
    'codigo_regenerado' => 'QR regenerado',
    _ => 'Envío de QR',
  };

  static String etiquetaCanal(String canal) => switch (canal) {
    'email' => 'Correo',
    'sms' => 'SMS',
    'whatsapp' => 'WhatsApp',
    _ => canal,
  };

  /// Estado de un canal: lo dice `resultado.<canal>.status` cuando el envío
  /// ya se procesó; antes de eso, está en cola.
  EstadoCanalEnvio estadoDe(String canal) {
    if (estado == 'pendiente' || estado == 'procesando') {
      return EstadoCanalEnvio.enCola;
    }
    final detalle = resultado?[canal];
    final status = detalle is Map ? detalle['status']?.toString() : null;
    return switch (status) {
      'sent' => EstadoCanalEnvio.enviado,
      'failed' => EstadoCanalEnvio.fallido,
      'skipped' => EstadoCanalEnvio.omitido,
      _ =>
        estado == 'fallido'
            ? EstadoCanalEnvio.fallido
            : EstadoCanalEnvio.enviado,
    };
  }
}
