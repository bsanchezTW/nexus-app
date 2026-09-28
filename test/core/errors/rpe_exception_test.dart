import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:transworld_nexus/core/errors/rpe_exception.dart';

void main() {
  test('details como JSON de texto usa la etiqueta del campo', () {
    final error = PostgrestException(
      message: 'RPE_DATOS_INVALIDOS',
      code: '22023',
      details: '{"campo":"email","regla":"formato"}',
    );
    expect(
      rpeExceptionDesde(error)!.mensaje,
      'El campo correo no es válido.',
    );
  });

  test('details como mapa usa la misma etiqueta', () {
    final error = PostgrestException(
      message: 'RPE_DATOS_INVALIDOS',
      code: '22023',
      details: {'campo': 'nombre_completo', 'regla': 'formato'},
    );
    expect(
      rpeExceptionDesde(error)!.mensaje,
      'El campo nombre y apellido no es válido.',
    );
  });

  test('un texto que no es JSON deja el mensaje genérico', () {
    final error = PostgrestException(
      message: 'RPE_DATOS_INVALIDOS',
      code: '22023',
      details: 'no-es-json',
    );
    expect(
      rpeExceptionDesde(error)!.mensaje,
      'Hay datos que no son válidos.',
    );
  });

  test('utm_source avisa de un parámetro de campaña', () {
    final error = PostgrestException(
      message: 'RPE_DATOS_INVALIDOS',
      code: '22023',
      details: {'campo': 'utm_source', 'regla': 'largo'},
    );
    expect(
      rpeExceptionDesde(error)!.mensaje,
      'Un parámetro de campaña no es válido.',
    );
  });

  test('sin campo, el hint en español es el mensaje', () {
    final error = PostgrestException(
      message: 'RPE_EVENTO_FINALIZADO',
      code: 'P0001',
      hint: 'El evento ya finalizó.',
    );
    expect(rpeExceptionDesde(error)!.mensaje, 'El evento ya finalizó.');
  });
}
