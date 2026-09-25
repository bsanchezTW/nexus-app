class InscripcionSubevento {
  const InscripcionSubevento({
    required this.id,
    required this.eventoId,
    required this.registradoId,
    required this.subeventoId,
    required this.origen,
    this.sobrecupo = false,
    this.asistio = false,
    this.asistioEn,
    this.asistioPor,
    this.pendienteDeSincronizar = false,
  });

  final String id;
  final String eventoId;
  final String registradoId;
  final String subeventoId;
  final String origen;
  final bool sobrecupo;
  final bool asistio;
  final DateTime? asistioEn;
  final String? asistioPor;
  final bool pendienteDeSincronizar;

  factory InscripcionSubevento.fromMap(Map<String, dynamic> map) {
    return InscripcionSubevento(
      id: map['id'] as String,
      eventoId: map['evento_id'] as String,
      registradoId: map['registrado_id'] as String,
      subeventoId: map['subevento_id'] as String,
      origen: map['origen'] as String? ?? 'app',
      sobrecupo: (map['sobrecupo'] as bool?) ?? false,
      asistio: (map['asistio'] as bool?) ?? false,
      asistioEn: map['asistio_en'] != null
          ? DateTime.tryParse(map['asistio_en'] as String)
          : null,
      asistioPor: map['asistio_por'] as String?,
    );
  }
}
