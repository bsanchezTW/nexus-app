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
      canales: canales is List ? canales.map((c) => c.toString()).toList() : const [],
      motivo: map['motivo'] as String? ?? '',
      estado: map['estado'] as String? ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      resultado: resultado is Map ? Map<String, dynamic>.from(resultado) : null,
    );
  }
}
