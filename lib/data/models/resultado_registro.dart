sealed class ResultadoRegistro {
  const ResultadoRegistro();
}

class RegistroOk extends ResultadoRegistro {
  const RegistroOk({
    required this.registradoId,
    required this.codigoQr,
    required this.sobrecupo,
    required this.envio,
  });

  final String registradoId;
  final String codigoQr;
  final bool sobrecupo;
  final String envio;
}

class RechazoSubevento {
  const RechazoSubevento({required this.subeventoId, required this.motivo});

  final String subeventoId;
  final String motivo;
}

class RegistroRechazado extends ResultadoRegistro {
  const RegistroRechazado({
    required this.motivo,
    this.registradoIdExistente,
    this.rechazados = const [],
    required this.puedeForzar,
  });

  final String motivo;
  final String? registradoIdExistente;
  final List<RechazoSubevento> rechazados;
  final bool puedeForzar;
}

class ResultadoImportacion {
  const ResultadoImportacion({
    required this.insertados,
    required this.omitidosDuplicado,
    required this.invalidos,
    required this.excedeCupo,
    required this.puedeForzar,
  });

  final int insertados;
  final int omitidosDuplicado;
  final List<Map<String, dynamic>> invalidos;
  final int excedeCupo;
  final bool puedeForzar;

  factory ResultadoImportacion.fromJson(Map<String, dynamic> json) {
    final invalidos = json['invalidos'];
    return ResultadoImportacion(
      insertados: (json['insertados'] as num?)?.toInt() ?? 0,
      omitidosDuplicado: (json['omitidos_duplicado'] as num?)?.toInt() ?? 0,
      invalidos: invalidos is List
          ? invalidos.whereType<Map>().map(Map<String, dynamic>.from).toList()
          : const [],
      excedeCupo: (json['excede_cupo'] as num?)?.toInt() ?? 0,
      puedeForzar: json['puede_forzar'] == true,
    );
  }
}
