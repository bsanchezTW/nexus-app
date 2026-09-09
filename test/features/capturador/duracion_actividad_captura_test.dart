import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const migracion =
      'supabase/migrations/202609091200_eventos_leads_duracion_dias.sql';

  test('la duración vive en eventos_leads y admite 1 a 366 días', () {
    final sql = File(migracion).readAsStringSync();

    expect(sql, contains('ADD COLUMN IF NOT EXISTS duracion_dias'));
    expect(sql, contains('eventos_leads_duracion_dias_check'));
    expect(sql, contains('duracion_dias >= 1 AND duracion_dias <= 366'));
  });

  test('los eventos de registro también tienen duración de 1 a 366 días', () {
    const migracionEventos =
        'supabase/migrations/202609091500_eventos_duracion_dias.sql';
    final sql = File(migracionEventos).readAsStringSync();

    expect(sql, contains('ALTER TABLE public.eventos'));
    expect(sql, contains('eventos_duracion_dias_check'));
    expect(sql, contains('duracion_dias = NEW.duracion_dias'));
    expect(sql, contains('public.rpe_fecha_termino_evento'));
    expect(
      sql,
      contains('public.rpe_fecha_termino_evento(e.fecha, e.duracion_dias)'),
    );
  });
}
