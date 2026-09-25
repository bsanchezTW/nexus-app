import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/features/acreditacion/qr_codigo_parser.dart';

void main() {
  const codigo = 'TW1-3F2A9C0B7D1E4F5A8B6C2D0E9F1A7B3C';
  const uuid = 'A1B2C3D4-E5F6-7890-ABCD-EF1234567890';

  test('acepta un código válido', () {
    final lectura = interpretarQr(codigo);
    expect(lectura.tipo, QrLecturaTipo.valido);
    expect(lectura.codigo, codigo);
  });

  test('normaliza minúsculas', () {
    final lectura = interpretarQr(codigo.toLowerCase());
    expect(lectura.tipo, QrLecturaTipo.valido);
    expect(lectura.codigo, codigo);
  });

  test('un UUID es formato antiguo', () {
    expect(interpretarQr(uuid).tipo, QrLecturaTipo.formatoAntiguo);
  });

  test('basura es inválida', () {
    expect(interpretarQr('hola mundo').tipo, QrLecturaTipo.invalido);
  });
}
