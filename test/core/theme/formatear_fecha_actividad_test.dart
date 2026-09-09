import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:transworld_nexus/core/theme/tw_tokens.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es', null));

  test('un solo día usa la fecha larga', () {
    expect(
      formatearFechaActividad(DateTime(2026, 9, 12), 1),
      formatearFechaLarga(DateTime(2026, 9, 12)),
    );
  });

  test('varios días del mismo mes se comprimen', () {
    expect(
      formatearFechaActividad(DateTime(2026, 9, 12), 3),
      '12–14 · septiembre 2026',
    );
  });

  test('si cruza de mes muestra ambos', () {
    expect(
      formatearFechaActividad(DateTime(2026, 9, 30), 3),
      '30 · septiembre – 2 · octubre 2026',
    );
  });
}
