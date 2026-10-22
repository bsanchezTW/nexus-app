import 'supabase_row_parsers.dart';

/// Marca de borrado lógico (`leads.eliminado_at`). El servidor ya no entrega
/// los leads borrados; en la app solo aparece como cambio encolado de un
/// borrado hecho sin red.
const campoLeadEliminadoAt = 'eliminado_at';

/// Lead capturado en un evento de leads (`public.leads`).
class Lead {
  const Lead({
    required this.id,
    required this.eventoId,
    required this.nombreCompleto,
    this.empresa,
    this.cargo,
    this.telefono,
    this.email,
    this.descripcion,
    this.fotosUrls = const [],
    this.perfilId,
    this.createdAt,
    this.vendedorNombre,
    this.pendienteDeSincronizar = false,
  });

  final String id;
  final String eventoId;
  final String nombreCompleto;
  final String? empresa;
  final String? cargo;
  final String? telefono;
  final String? email;
  final String? descripcion;
  final List<String> fotosUrls;
  final String? perfilId;
  final DateTime? createdAt;

  /// Nombre del capturador (join `perfiles.nombre_completo`).
  final String? vendedorNombre;

  /// True cuando el lead tiene algo sin subir: o vive solo en la cola local,
  /// o ya está en el servidor pero con una edición esperando en la cola.
  ///
  /// Sirve para la insignia de la UI. Para decidir si se puede hacer UPDATE o
  /// DELETE contra el servidor hay que preguntar por el id, con
  /// `esIdSoloLocal` (ver data/offline/sync_queue_service.dart).
  final bool pendienteDeSincronizar;

  factory Lead.fromMap(Map<String, dynamic> map) {
    return Lead(
      id: SupabaseRowParsers.asString(map['id']),
      eventoId: SupabaseRowParsers.asString(map['evento_id']),
      nombreCompleto: SupabaseRowParsers.asString(map['nombre_completo']),
      empresa: SupabaseRowParsers.asStringOrNull(map['empresa']),
      cargo: SupabaseRowParsers.asStringOrNull(map['cargo']),
      telefono: SupabaseRowParsers.asStringOrNull(map['telefono']),
      email: SupabaseRowParsers.asStringOrNull(map['email']),
      descripcion: SupabaseRowParsers.asStringOrNull(map['descripcion']),
      fotosUrls: SupabaseRowParsers.parseStringList(map['fotos_urls']),
      perfilId: SupabaseRowParsers.asStringOrNull(map['perfil_id']),
      createdAt: SupabaseRowParsers.parseDateTimeOrNull(map['created_at']),
      vendedorNombre:
          SupabaseRowParsers.asStringOrNull(map['capturador_nombre']) ??
          SupabaseRowParsers.nombrePerfilEmbed(map['perfiles']),
      pendienteDeSincronizar:
          (map['pendiente_de_sincronizar'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'evento_id': eventoId,
      'nombre_completo': nombreCompleto,
      'empresa': empresa,
      'cargo': cargo,
      'telefono': telefono,
      'email': email,
      'descripcion': descripcion,
      'fotos_urls': fotosUrls,
      if (perfilId != null) 'perfil_id': perfilId,
    };
  }

  /// Serializa el lead tal como vendría de PostgREST, para poder volver a
  /// leerlo con [Lead.fromMap] desde la caché offline sin perder el id, la
  /// fecha ni el nombre del capturador (que llega como embed `perfiles`).
  Map<String, dynamic> toCacheMap() {
    return {
      'id': id,
      'evento_id': eventoId,
      'nombre_completo': nombreCompleto,
      'empresa': empresa,
      'cargo': cargo,
      'telefono': telefono,
      'email': email,
      'descripcion': descripcion,
      'fotos_urls': fotosUrls,
      'perfil_id': perfilId,
      'created_at': createdAt?.toIso8601String(),
      if (vendedorNombre != null) 'capturador_nombre': vendedorNombre,
      if (vendedorNombre != null)
        'perfiles': {'nombre_completo': vendedorNombre},
    };
  }

  /// Devuelve el lead con los [cambios] de una operación de la cola aplicados
  /// encima, para mostrar una edición hecha sin conexión antes de que llegue
  /// al servidor.
  ///
  /// Consulta `containsKey` en vez de usar `??`: vaciar un campo se guarda
  /// como `null` entre los cambios, y con `??` ese borrado se perdería y la
  /// UI seguiría mostrando el valor viejo.
  Lead conCambiosPendientes(Map<String, dynamic> cambios) {
    String? texto(String columna, String? actual) =>
        cambios.containsKey(columna) ? cambios[columna] as String? : actual;

    return Lead(
      id: id,
      eventoId: eventoId,
      nombreCompleto:
          texto('nombre_completo', nombreCompleto) ?? nombreCompleto,
      empresa: texto('empresa', empresa),
      cargo: texto('cargo', cargo),
      telefono: texto('telefono', telefono),
      email: texto('email', email),
      descripcion: texto('descripcion', descripcion),
      // `fotos_urls` es una lista, no un `String?`: el helper `texto` no
      // sirve. Sin este caso, una foto adjuntada sin conexión no se vería
      // hasta que la cola sincronizara.
      fotosUrls: cambios.containsKey('fotos_urls')
          ? SupabaseRowParsers.parseStringList(cambios['fotos_urls'])
          : fotosUrls,
      perfilId: perfilId,
      createdAt: createdAt,
      vendedorNombre: vendedorNombre,
      pendienteDeSincronizar: true,
    );
  }

  Lead copyWith({
    String? id,
    String? nombreCompleto,
    String? empresa,
    String? cargo,
    String? telefono,
    String? email,
    String? descripcion,
    List<String>? fotosUrls,
    String? perfilId,
    bool? pendienteDeSincronizar,
    String? vendedorNombre,
  }) {
    return Lead(
      id: id ?? this.id,
      eventoId: eventoId,
      nombreCompleto: nombreCompleto ?? this.nombreCompleto,
      empresa: empresa ?? this.empresa,
      cargo: cargo ?? this.cargo,
      telefono: telefono ?? this.telefono,
      email: email ?? this.email,
      descripcion: descripcion ?? this.descripcion,
      fotosUrls: fotosUrls ?? this.fotosUrls,
      perfilId: perfilId ?? this.perfilId,
      createdAt: createdAt,
      vendedorNombre: vendedorNombre ?? this.vendedorNombre,
      pendienteDeSincronizar:
          pendienteDeSincronizar ?? this.pendienteDeSincronizar,
    );
  }
}
