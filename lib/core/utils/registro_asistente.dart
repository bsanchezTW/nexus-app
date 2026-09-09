/// Formato y validación del formulario de registro de asistentes.
///
/// Se aplica al salir de cada campo y otra vez al enviar, para que el valor
/// que llega a Supabase coincida con lo que el usuario ve.
library;

import '../constants/paises_evento.dart';

/// País para el selector de código telefónico. La validación es por cantidad
/// de dígitos nacionales (sin el código); Chile además exige prefijo 9 o 2.
class PaisTelefono {
  const PaisTelefono({
    required this.iso,
    required this.nombre,
    required this.dialCode,
    required this.minDigitos,
    required this.maxDigitos,
    this.prefijosNacionales = const [],
    this.hint = '',
  });

  final String iso;
  final String nombre;
  final String dialCode;
  final int minDigitos;
  final int maxDigitos;

  /// Si no está vacío, el número nacional debe empezar por uno de estos
  /// dígitos (Chile: 9 móvil, 2 fijo Santiago).
  final List<String> prefijosNacionales;
  final String hint;

  String get bandera {
    final upper = iso.toUpperCase();
    return String.fromCharCodes(upper.codeUnits.map((c) => 0x1F1E6 - 65 + c));
  }

  String get etiquetaCodigo => '+$dialCode';
}

const kPaisTelefonoChile = PaisTelefono(
  iso: 'CL',
  nombre: 'Chile',
  dialCode: '56',
  minDigitos: 9,
  maxDigitos: 9,
  prefijosNacionales: ['9', '2'],
  hint: '9 1234 5678',
);

const kPaisTelefonoPeru = PaisTelefono(
  iso: 'PE',
  nombre: 'Perú',
  dialCode: '51',
  minDigitos: 9,
  maxDigitos: 9,
  hint: '912 345 678',
);

/// Chile y Perú primero; el resto en español, orden alfabético.
const kPaisesTelefono = <PaisTelefono>[
  kPaisTelefonoChile,
  kPaisTelefonoPeru,
  PaisTelefono(
    iso: 'DE',
    nombre: 'Alemania',
    dialCode: '49',
    minDigitos: 10,
    maxDigitos: 11,
    hint: '151 2345678',
  ),
  PaisTelefono(
    iso: 'AR',
    nombre: 'Argentina',
    dialCode: '54',
    minDigitos: 10,
    maxDigitos: 11,
    hint: '11 1234 5678',
  ),
  PaisTelefono(
    iso: 'AU',
    nombre: 'Australia',
    dialCode: '61',
    minDigitos: 9,
    maxDigitos: 9,
    hint: '412 345 678',
  ),
  PaisTelefono(
    iso: 'BO',
    nombre: 'Bolivia',
    dialCode: '591',
    minDigitos: 8,
    maxDigitos: 8,
    hint: '71234567',
  ),
  PaisTelefono(
    iso: 'BR',
    nombre: 'Brasil',
    dialCode: '55',
    minDigitos: 10,
    maxDigitos: 11,
    hint: '11 91234 5678',
  ),
  PaisTelefono(
    iso: 'CA',
    nombre: 'Canadá',
    dialCode: '1',
    minDigitos: 10,
    maxDigitos: 10,
    hint: '416 555 0199',
  ),
  PaisTelefono(
    iso: 'CN',
    nombre: 'China',
    dialCode: '86',
    minDigitos: 11,
    maxDigitos: 11,
    hint: '131 2345 6789',
  ),
  PaisTelefono(
    iso: 'CO',
    nombre: 'Colombia',
    dialCode: '57',
    minDigitos: 10,
    maxDigitos: 10,
    hint: '300 123 4567',
  ),
  PaisTelefono(
    iso: 'CR',
    nombre: 'Costa Rica',
    dialCode: '506',
    minDigitos: 8,
    maxDigitos: 8,
    hint: '8312 3456',
  ),
  PaisTelefono(
    iso: 'EC',
    nombre: 'Ecuador',
    dialCode: '593',
    minDigitos: 9,
    maxDigitos: 9,
    hint: '99 123 4567',
  ),
  PaisTelefono(
    iso: 'SV',
    nombre: 'El Salvador',
    dialCode: '503',
    minDigitos: 8,
    maxDigitos: 8,
    hint: '7012 3456',
  ),
  PaisTelefono(
    iso: 'ES',
    nombre: 'España',
    dialCode: '34',
    minDigitos: 9,
    maxDigitos: 9,
    hint: '612 345 678',
  ),
  PaisTelefono(
    iso: 'US',
    nombre: 'Estados Unidos',
    dialCode: '1',
    minDigitos: 10,
    maxDigitos: 10,
    hint: '202 555 0147',
  ),
  PaisTelefono(
    iso: 'FR',
    nombre: 'Francia',
    dialCode: '33',
    minDigitos: 9,
    maxDigitos: 9,
    hint: '6 12 34 56 78',
  ),
  PaisTelefono(
    iso: 'GT',
    nombre: 'Guatemala',
    dialCode: '502',
    minDigitos: 8,
    maxDigitos: 8,
    hint: '5123 4567',
  ),
  PaisTelefono(
    iso: 'IT',
    nombre: 'Italia',
    dialCode: '39',
    minDigitos: 9,
    maxDigitos: 10,
    hint: '312 345 6789',
  ),
  PaisTelefono(
    iso: 'JP',
    nombre: 'Japón',
    dialCode: '81',
    minDigitos: 10,
    maxDigitos: 10,
    hint: '90 1234 5678',
  ),
  PaisTelefono(
    iso: 'MX',
    nombre: 'México',
    dialCode: '52',
    minDigitos: 10,
    maxDigitos: 10,
    hint: '55 1234 5678',
  ),
  PaisTelefono(
    iso: 'PA',
    nombre: 'Panamá',
    dialCode: '507',
    minDigitos: 7,
    maxDigitos: 8,
    hint: '6123 4567',
  ),
  PaisTelefono(
    iso: 'PY',
    nombre: 'Paraguay',
    dialCode: '595',
    minDigitos: 9,
    maxDigitos: 9,
    hint: '981 123456',
  ),
  PaisTelefono(
    iso: 'PT',
    nombre: 'Portugal',
    dialCode: '351',
    minDigitos: 9,
    maxDigitos: 9,
    hint: '912 345 678',
  ),
  PaisTelefono(
    iso: 'GB',
    nombre: 'Reino Unido',
    dialCode: '44',
    minDigitos: 10,
    maxDigitos: 10,
    hint: '7400 123456',
  ),
  PaisTelefono(
    iso: 'DO',
    nombre: 'República Dominicana',
    dialCode: '1',
    minDigitos: 10,
    maxDigitos: 10,
    hint: '809 555 1234',
  ),
  PaisTelefono(
    iso: 'UY',
    nombre: 'Uruguay',
    dialCode: '598',
    minDigitos: 8,
    maxDigitos: 8,
    hint: '91 123 456',
  ),
  PaisTelefono(
    iso: 'VE',
    nombre: 'Venezuela',
    dialCode: '58',
    minDigitos: 10,
    maxDigitos: 10,
    hint: '412 1234567',
  ),
];

PaisTelefono paisTelefonoPorIso(String iso) {
  for (final pais in kPaisesTelefono) {
    if (pais.iso == iso) return pais;
  }
  return kPaisTelefonoChile;
}

PaisTelefono paisTelefonoPorPaisEvento(String? pais) {
  return normalizarPaisEvento(pais) == kPaisEventoPeru
      ? kPaisTelefonoPeru
      : kPaisTelefonoChile;
}

/// Detecta el prefijo de un teléfono internacional ya persistido.
///
/// Los códigos más largos se evalúan primero para no confundir, por ejemplo,
/// `+591` (Bolivia) con códigos de menor longitud.
PaisTelefono? detectarPaisTelefono(String? raw) {
  final value = (raw ?? '').trim();
  if (!value.startsWith('+') && !value.startsWith('00')) return null;
  var digits = value.replaceAll(RegExp(r'\D'), '');
  if (value.startsWith('00') && digits.startsWith('00')) {
    digits = digits.substring(2);
  }
  final paises = List<PaisTelefono>.of(kPaisesTelefono)
    ..sort((a, b) => b.dialCode.length.compareTo(a.dialCode.length));
  for (final pais in paises) {
    if (digits.startsWith(pais.dialCode)) return pais;
  }
  return null;
}

/// Title case Unicode: cada palabra (y cada tramo tras un guion) con inicial
/// mayúscula. Colapsa espacios.
String aTitleCase(String value) {
  final compacto = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (compacto.isEmpty) return '';
  return compacto.split(' ').map(_capitalizarPalabra).join(' ');
}

String _capitalizarPalabra(String word) {
  return word
      .split('-')
      .map((parte) {
        if (parte.isEmpty) return parte;
        final lower = parte.toLowerCase();
        return '${lower[0].toUpperCase()}${lower.substring(1)}';
      })
      .join('-');
}

String formatearNombreCompleto(String value) => aTitleCase(value);

String formatearCargo(String value) => aTitleCase(value);

String formatearEmpresa(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

String formatearEmail(String value) => value.trim().toLowerCase();

/// Solo dígitos nacionales, sin el código de país si el usuario lo pegó.
String extraerDigitosNacionales(String raw, PaisTelefono pais) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  final codigo = pais.dialCode;
  if (digits.startsWith('00$codigo')) {
    digits = digits.substring(2 + codigo.length);
  } else if (digits.startsWith(codigo) && digits.length > pais.maxDigitos) {
    digits = digits.substring(codigo.length);
  }
  if (digits.startsWith('0') && digits.length > pais.minDigitos) {
    digits = digits.replaceFirst(RegExp(r'^0+'), '');
  }
  return digits;
}

String formatearTelefonoNacional(String raw, PaisTelefono pais) {
  var digits = extraerDigitosNacionales(raw, pais);
  if (digits.length > pais.maxDigitos) {
    digits = digits.substring(0, pais.maxDigitos);
  }
  if (pais.iso == 'CL' && digits.length == 9) {
    return '${digits[0]} ${digits.substring(1, 5)} ${digits.substring(5)}';
  }
  return digits;
}

/// Valor que se persiste: código de país + número nacional.
String telefonoInternacional(String raw, PaisTelefono pais) {
  final digits = extraerDigitosNacionales(raw, pais);
  if (digits.isEmpty) return '';
  if (pais.iso == 'CL' && digits.length == 9) {
    return '+${pais.dialCode} ${digits[0]} ${digits.substring(1, 5)} ${digits.substring(5)}';
  }
  return '+${pais.dialCode} $digits';
}

String? validarNombreCompleto(String? value) {
  final nombre = aTitleCase(value ?? '');
  if (nombre.isEmpty) return 'Requerido';
  final palabras = nombre.split(' ');
  if (palabras.length < 2) {
    return 'Ingresa nombre y apellido';
  }
  if (palabras.any((p) => p.replaceAll('-', '').length < 2)) {
    return 'Ingresa nombre y apellido';
  }
  return null;
}

String? validarEmpresa(String? value) {
  if (formatearEmpresa(value ?? '').isEmpty) return 'Requerido';
  return null;
}

String? validarCargo(String? value) {
  if (aTitleCase(value ?? '').isEmpty) return 'Requerido';
  return null;
}

final _localEmail = RegExp(r'^[a-z0-9](?:[a-z0-9._%+\-]*[a-z0-9])?$');
final _labelDominio = RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$');
final _tld = RegExp(r'^[a-z]{2,}$');

String? validarEmailRegistro(String? value, {bool requerido = true}) {
  final email = formatearEmail(value ?? '');
  if (email.isEmpty) return requerido ? 'Requerido' : null;
  if (email.contains(' ')) return 'Email inválido';
  final partes = email.split('@');
  if (partes.length != 2) return 'Email inválido';
  final local = partes[0];
  final dominio = partes[1];
  if (local.isEmpty || dominio.isEmpty) return 'Email inválido';
  if (local.contains('..') || dominio.contains('..')) return 'Email inválido';
  if (!_localEmail.hasMatch(local)) return 'Email inválido';
  final labels = dominio.split('.');
  if (labels.length < 2) return 'Email inválido';
  if (labels.any((l) => l.isEmpty || !_labelDominio.hasMatch(l))) {
    return 'Email inválido';
  }
  if (!_tld.hasMatch(labels.last)) return 'Email inválido';
  return null;
}

String? validarTelefono(
  String? value,
  PaisTelefono pais, {
  bool requerido = true,
}) {
  final digits = extraerDigitosNacionales(value ?? '', pais);
  if (digits.isEmpty) return requerido ? 'Requerido' : null;
  if (digits.length < pais.minDigitos || digits.length > pais.maxDigitos) {
    if (pais.minDigitos == pais.maxDigitos) {
      return 'Ingresa ${pais.minDigitos} dígitos';
    }
    return 'Ingresa entre ${pais.minDigitos} y ${pais.maxDigitos} dígitos';
  }
  if (pais.prefijosNacionales.isNotEmpty &&
      !pais.prefijosNacionales.any(digits.startsWith)) {
    final opciones = pais.prefijosNacionales.join(' o ');
    return 'En ${pais.nombre} el número debe empezar con $opciones';
  }
  return null;
}

/// Cuerpo + dígito verificador, sin puntos ni guion. Acepta `k`/`K`.
String compactarRut(String raw) {
  return raw.replaceAll(RegExp(r'[^0-9kK]'), '').toUpperCase();
}

/// Formato chileno `12.345.678-5`. Si no hay cuerpo+DV, deja el recorte.
String formatearRut(String raw) {
  final compacto = compactarRut(raw);
  if (compacto.length < 2) return raw.trim();
  final cuerpo = compacto.substring(0, compacto.length - 1);
  final dv = compacto.substring(compacto.length - 1);
  final conMiles = _conSeparadorMiles(cuerpo);
  return '$conMiles-$dv';
}

String _conSeparadorMiles(String digitos) {
  final buf = StringBuffer();
  for (var i = 0; i < digitos.length; i++) {
    final desdeElFinal = digitos.length - i;
    if (i > 0 && desdeElFinal % 3 == 0) buf.write('.');
    buf.write(digitos[i]);
  }
  return buf.toString();
}

String? _digitoVerificadorRut(String cuerpo) {
  if (cuerpo.isEmpty || !RegExp(r'^\d+$').hasMatch(cuerpo)) return null;
  var suma = 0;
  var mul = 2;
  for (var i = cuerpo.length - 1; i >= 0; i--) {
    suma += int.parse(cuerpo[i]) * mul;
    mul = mul == 7 ? 2 : mul + 1;
  }
  final resto = 11 - (suma % 11);
  if (resto == 11) return '0';
  if (resto == 10) return 'K';
  return '$resto';
}

/// RUT chileno (módulo 11). [requerido] false: vacío pasa; valor inválido no.
///
/// Fuera de Chile el campo es un RUC/tax id: no vacío si [requerido], y si
/// hay texto, entre 5 y 20 caracteres alfanuméricos.
String? validarRut(
  String? value, {
  bool requerido = true,
  bool esChile = true,
}) {
  final recortado = (value ?? '').trim();
  if (recortado.isEmpty) return requerido ? 'Requerido' : null;
  if (!esChile) {
    final compacto = recortado.replaceAll(RegExp(r'[\s.\-]'), '');
    if (compacto.length < 5 || compacto.length > 20) {
      return 'RUC inválido';
    }
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(compacto)) {
      return 'RUC inválido';
    }
    return null;
  }
  final compacto = compactarRut(recortado);
  if (compacto.length < 8 || compacto.length > 10) return 'RUT inválido';
  final cuerpo = compacto.substring(0, compacto.length - 1);
  final dv = compacto.substring(compacto.length - 1);
  final esperado = _digitoVerificadorRut(cuerpo);
  if (esperado == null || dv != esperado) return 'RUT inválido';
  return null;
}

String compactarPatente(String raw) {
  return raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
}

/// Mayúsculas, sin espacios. Conserva un formato compacto de 6 caracteres.
String formatearPatente(String raw) => compactarPatente(raw);

/// Patente chilena: vigente `ABCD12` (4 letras + 2 dígitos) o antigua
/// `AB1234` (2 letras + 4 dígitos). Acepta guiones.
String? validarPatente(String? value, {bool requerido = true}) {
  final recortado = (value ?? '').trim();
  if (recortado.isEmpty) return requerido ? 'Requerido' : null;
  final compacto = compactarPatente(recortado);
  final vigente = RegExp(r'^[A-Z]{4}\d{2}$').hasMatch(compacto);
  final antigua = RegExp(r'^[A-Z]{2}\d{4}$').hasMatch(compacto);
  if (!vigente && !antigua) return 'Patente inválida';
  return null;
}

const kMensajeEmailDuplicado = 'Ese correo ya está registrado en este evento.';
const kMensajeEventoFinalizado = 'Este evento ha finalizado';
