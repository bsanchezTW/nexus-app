import 'package:supabase_flutter/supabase_flutter.dart';

enum RpeErrorCode {
  noAutorizado,
  eventoNoEncontrado,
  subeventoNoEncontrado,
  registradoNoEncontrado,
  datosInvalidos,
  eventoFinalizado,
  subeventoFueraDeRango,
  subeventoSolapeInscritos,
  subeventosFueraDeRango,
  campoInmutable,
  slugDuplicado,
  slugInvalido,
  noInscrito,
  envioLimitado,
  desconocido,
}

const kMensajesRpe = <RpeErrorCode, String>{
  RpeErrorCode.noAutorizado: 'No tienes permiso para esta operación.',
  RpeErrorCode.eventoNoEncontrado: 'No encontramos ese evento.',
  RpeErrorCode.subeventoNoEncontrado: 'No encontramos ese taller.',
  RpeErrorCode.registradoNoEncontrado: 'No encontramos a ese asistente.',
  RpeErrorCode.datosInvalidos: 'Hay datos que no son válidos.',
  RpeErrorCode.eventoFinalizado: 'Este evento ha finalizado.',
  RpeErrorCode.subeventoFueraDeRango:
      'El día del taller tiene que caer dentro del evento.',
  RpeErrorCode.subeventoSolapeInscritos:
      'Hay asistentes inscritos en talleres que quedarían superpuestos con este horario.',
  RpeErrorCode.subeventosFueraDeRango:
      'Hay talleres fuera del nuevo rango de fechas del evento.',
  RpeErrorCode.campoInmutable: 'Ese dato no se puede cambiar.',
  RpeErrorCode.slugDuplicado: 'Ese enlace ya está en uso.',
  RpeErrorCode.slugInvalido: 'El enlace del evento no es válido.',
  RpeErrorCode.noInscrito: 'Esa persona no está inscrita en el taller.',
  RpeErrorCode.envioLimitado: 'Espera un momento antes de volver a enviar.',
  RpeErrorCode.desconocido: 'No se pudo completar la operación.',
};

class RpeException implements Exception {
  const RpeException(this.code, {this.campo, this.regla, this.detalle});

  final RpeErrorCode code;
  final String? campo;
  final String? regla;
  final Object? detalle;

  String get mensaje {
    if (code == RpeErrorCode.datosInvalidos && campo != null) {
      return 'El campo $campo no es válido.';
    }
    return kMensajesRpe[code] ?? kMensajesRpe[RpeErrorCode.desconocido]!;
  }

  @override
  String toString() => mensaje;
}

RpeException? rpeExceptionDesde(Object error) {
  String? message;
  Object? details;
  if (error is PostgrestException) {
    message = error.message;
    details = error.details;
  } else if (error is FunctionException) {
    final data = error.details;
    if (data is Map && data['error'] is String) {
      message = data['error'] as String;
    } else {
      message = error.reasonPhrase;
    }
    details = data;
  }
  if (message == null || !message.startsWith('RPE_')) return null;
  return RpeException(
    _codigo(message),
    campo: _texto(details, 'campo'),
    regla: _texto(details, 'regla'),
    detalle: details,
  );
}

Future<T> conErroresRpe<T>(Future<T> Function() llamada) async {
  try {
    return await llamada();
  } on RpeException {
    rethrow;
  } catch (error) {
    final mapeado = rpeExceptionDesde(error);
    if (mapeado != null) throw mapeado;
    rethrow;
  }
}

RpeErrorCode _codigo(String message) {
  return switch (message) {
    'RPE_NO_AUTORIZADO' => RpeErrorCode.noAutorizado,
    'RPE_EVENTO_NO_ENCONTRADO' => RpeErrorCode.eventoNoEncontrado,
    'RPE_SUBEVENTO_NO_ENCONTRADO' => RpeErrorCode.subeventoNoEncontrado,
    'RPE_REGISTRADO_NO_ENCONTRADO' => RpeErrorCode.registradoNoEncontrado,
    'RPE_DATOS_INVALIDOS' => RpeErrorCode.datosInvalidos,
    'RPE_EVENTO_FINALIZADO' => RpeErrorCode.eventoFinalizado,
    'RPE_SUBEVENTO_FUERA_DE_RANGO' => RpeErrorCode.subeventoFueraDeRango,
    'RPE_SUBEVENTO_SOLAPE_INSCRITOS' => RpeErrorCode.subeventoSolapeInscritos,
    'RPE_SUBEVENTOS_FUERA_DE_RANGO' => RpeErrorCode.subeventosFueraDeRango,
    'RPE_CAMPO_INMUTABLE' => RpeErrorCode.campoInmutable,
    'RPE_SLUG_DUPLICADO' => RpeErrorCode.slugDuplicado,
    'RPE_SLUG_INVALIDO' => RpeErrorCode.slugInvalido,
    'RPE_NO_INSCRITO' => RpeErrorCode.noInscrito,
    'RPE_ENVIO_LIMITADO' => RpeErrorCode.envioLimitado,
    _ => RpeErrorCode.desconocido,
  };
}

String? _texto(Object? details, String clave) {
  if (details is Map && details[clave] != null) {
    return details[clave].toString();
  }
  if (details is String && details.startsWith('{')) {
    return null;
  }
  return null;
}
