enum OrigenRegistro {
  app,
  excel,
  publico;

  static OrigenRegistro fromString(String? raw) {
    return OrigenRegistro.values.firstWhere(
      (o) => o.name == raw,
      orElse: () => OrigenRegistro.app,
    );
  }
}

class Registrado {
  const Registrado({
    required this.id,
    required this.eventoId,
    required this.nombreCompleto,
    required this.email,
    this.acreditado = false,
    this.rut,
    this.patente,
    this.empresa,
    this.cargo,
    this.telefono,
    this.codigoQr = '',
    this.sobrecupo = false,
    this.acreditadoEn,
    this.origen = OrigenRegistro.app,
    this.ingresadoPor,
    this.emailConfirmacionEnviado = false,
    this.smsConfirmacionEnviado = false,
    this.createdAt,
    this.pendienteDeSincronizar = false,
  });

  final String id;
  final String eventoId;
  final String nombreCompleto;
  final String email;
  final bool acreditado;
  final String? rut;
  final String? patente;
  final String? empresa;
  final String? cargo;
  final String? telefono;
  final String codigoQr;
  final bool sobrecupo;
  final DateTime? acreditadoEn;

  /// Origen lógico del registro (app / excel / formulario público).
  final OrigenRegistro origen;
  final String? ingresadoPor;
  final bool emailConfirmacionEnviado;
  final bool smsConfirmacionEnviado;
  final DateTime? createdAt;

  /// true cuando esta fila tiene algo sin subir: o vive solo en la cola local
  /// y el servidor aún no la confirma, o ya está en el servidor pero con una
  /// edición esperando en la cola.
  ///
  /// Sirve para la insignia de la UI. Para decidir si se puede hacer UPDATE o
  /// DELETE contra el servidor —o si su QR ya es válido— hay que preguntar por
  /// el id, con `esIdSoloLocal` (ver data/offline/sync_queue_service.dart).
  final bool pendienteDeSincronizar;

  factory Registrado.fromMap(Map<String, dynamic> map) {
    return Registrado(
      id: map['id'] as String,
      eventoId: map['evento_id'] as String,
      nombreCompleto: map['nombre_completo'] as String,
      email: map['email'] as String,
      acreditado: (map['acreditado'] as bool?) ?? false,
      rut: map['rut'] as String?,
      patente: map['patente'] as String?,
      empresa: map['empresa'] as String?,
      cargo: map['cargo'] as String?,
      telefono: map['telefono'] as String?,
      codigoQr: map['codigo_qr'] as String? ?? '',
      sobrecupo: (map['sobrecupo'] as bool?) ?? false,
      acreditadoEn: map['acreditado_en'] != null
          ? DateTime.tryParse(map['acreditado_en'] as String)
          : null,
      origen: OrigenRegistro.fromString(map['origen'] as String?),
      ingresadoPor: map['ingresado_por'] as String?,
      emailConfirmacionEnviado:
          (map['email_confirmacion_enviado'] as bool?) ?? false,
      smsConfirmacionEnviado:
          (map['sms_confirmacion_enviado'] as bool?) ?? false,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'evento_id': eventoId,
      'nombre_completo': nombreCompleto,
      'email': email.trim().toLowerCase(),
      'acreditado': acreditado,
      'rut': rut,
      'patente': patente,
      'empresa': empresa,
      'cargo': cargo,
      'telefono': telefono,
      'origen': origen.name,
      'ingresado_por': ingresadoPor,
    };
  }

  /// Serializa la fila completa para la caché offline, de modo que
  /// [Registrado.fromMap] la reconstruya sin pérdidas. No sirve `toInsertMap`:
  /// ese omite `id`, `created_at` y los flags de confirmación
  /// porque los pone la base de datos al insertar.
  Map<String, dynamic> toCacheMap() {
    return {
      'id': id,
      'evento_id': eventoId,
      'nombre_completo': nombreCompleto,
      'email': email,
      'acreditado': acreditado,
      'rut': rut,
      'patente': patente,
      'empresa': empresa,
      'cargo': cargo,
      'telefono': telefono,
      'codigo_qr': codigoQr,
      'sobrecupo': sobrecupo,
      'acreditado_en': acreditadoEn?.toIso8601String(),
      'origen': origen.name,
      'ingresado_por': ingresadoPor,
      'email_confirmacion_enviado': emailConfirmacionEnviado,
      'sms_confirmacion_enviado': smsConfirmacionEnviado,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  /// Devuelve la fila con los [cambios] de una operación de la cola aplicados
  /// encima, para mostrar una edición hecha sin conexión antes de que llegue
  /// al servidor.
  ///
  /// Consulta `containsKey` en vez de usar `??`: vaciar un campo se guarda
  /// como `null` entre los cambios, y con `??` ese borrado se perdería y la
  /// UI seguiría mostrando el valor viejo.
  Registrado conCambiosPendientes(Map<String, dynamic> cambios) {
    String? texto(String columna, String? actual) =>
        cambios.containsKey(columna) ? cambios[columna] as String? : actual;

    bool booleano(String columna, bool actual) => cambios.containsKey(columna)
        ? (cambios[columna] as bool? ?? actual)
        : actual;

    return Registrado(
      id: id,
      eventoId: eventoId,
      nombreCompleto:
          texto('nombre_completo', nombreCompleto) ?? nombreCompleto,
      email: texto('email', email) ?? email,
      acreditado: booleano('acreditado', acreditado),
      rut: texto('rut', rut),
      patente: texto('patente', patente),
      empresa: texto('empresa', empresa),
      cargo: texto('cargo', cargo),
      telefono: texto('telefono', telefono),
      codigoQr: texto('codigo_qr', codigoQr) ?? codigoQr,
      sobrecupo: booleano('sobrecupo', sobrecupo),
      acreditadoEn: acreditadoEn,
      origen: origen,
      ingresadoPor: ingresadoPor,
      emailConfirmacionEnviado: booleano(
        'email_confirmacion_enviado',
        emailConfirmacionEnviado,
      ),
      smsConfirmacionEnviado: booleano(
        'sms_confirmacion_enviado',
        smsConfirmacionEnviado,
      ),
      createdAt: createdAt,
      pendienteDeSincronizar: true,
    );
  }

  Registrado copyWith({
    bool? acreditado,
    String? nombreCompleto,
    String? empresa,
    String? cargo,
    String? telefono,
    String? rut,
    String? patente,
    String? codigoQr,
    bool? pendienteDeSincronizar,
  }) {
    return Registrado(
      id: id,
      eventoId: eventoId,
      nombreCompleto: nombreCompleto ?? this.nombreCompleto,
      email: email,
      acreditado: acreditado ?? this.acreditado,
      rut: rut ?? this.rut,
      patente: patente ?? this.patente,
      empresa: empresa ?? this.empresa,
      cargo: cargo ?? this.cargo,
      telefono: telefono ?? this.telefono,
      codigoQr: codigoQr ?? this.codigoQr,
      sobrecupo: sobrecupo,
      acreditadoEn: acreditadoEn,
      origen: origen,
      ingresadoPor: ingresadoPor,
      emailConfirmacionEnviado: emailConfirmacionEnviado,
      smsConfirmacionEnviado: smsConfirmacionEnviado,
      createdAt: createdAt,
      pendienteDeSincronizar:
          pendienteDeSincronizar ?? this.pendienteDeSincronizar,
    );
  }
}
