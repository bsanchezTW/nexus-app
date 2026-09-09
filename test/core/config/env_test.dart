import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/core/config/env.dart';

void main() {
  group('resolverClavePublicable', () {
    test('prefiere SUPABASE_PUBLISHABLE_KEY', () {
      expect(
        resolverClavePublicable(
          publishableKey: 'sb_publishable_app',
          anonKey: 'sb_publishable_anon',
        ),
        'sb_publishable_app',
      );
    });

    test('acepta SUPABASE_ANON_KEY si no hay publishable', () {
      expect(
        resolverClavePublicable(anonKey: 'sb_publishable_anon'),
        'sb_publishable_anon',
      );
    });

    test('rechaza placeholders TU_', () {
      expect(
        () => resolverClavePublicable(
          publishableKey: 'TU_PUBLISHABLE',
          anonKey: 'TU_ANON',
        ),
        throwsStateError,
      );
    });
  });

  group('resolverClavePublicableFormulario', () {
    test('usa la key del form si está', () {
      expect(
        resolverClavePublicableFormulario(
          formKey: 'sb_publishable_form',
          publishableKey: 'sb_publishable_app',
          anonKey: 'sb_publishable_anon',
        ),
        'sb_publishable_form',
      );
    });

    test('cae a la key de la app si no hay form', () {
      expect(
        resolverClavePublicableFormulario(publishableKey: 'sb_publishable_app'),
        'sb_publishable_app',
      );
    });
  });
}
