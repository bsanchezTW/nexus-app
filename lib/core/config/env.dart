import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Acceso centralizado a la configuración de entorno.
///
/// Corrige un problema de higiene detectado en la auditoría del proyecto
/// legado (documentacion_zips_registro_pro.md, Sección 17.11): allí un
/// `.env` real quedó embebido dentro del ZIP entregado pese a estar en
/// `.gitignore`. Acá el `.env` real NUNCA se versiona (ver `.gitignore` y
/// `.env.example`); esta clase solo sabe leerlo y falla de forma explícita
/// y temprana si falta, en vez de dejar que Supabase falle más adelante
/// con errores confusos.
class Env {
  Env._();

  static Future<void> load() => dotenv.load(fileName: '.env');

  static String get supabaseUrl => _require('SUPABASE_URL');

  /// Clave pública del cliente (`sb_publishable_…` de `nexus_app`).
  ///
  /// Acepta `SUPABASE_PUBLISHABLE_KEY` o, por compatibilidad, el valor que
  /// ya esté en `SUPABASE_ANON_KEY`.
  static String get supabasePublishableKey => resolverClavePublicable(
    publishableKey: dotenv.env['SUPABASE_PUBLISHABLE_KEY'],
    anonKey: dotenv.env['SUPABASE_ANON_KEY'],
  );

  /// Publishable del formulario público (`eventos_web`).
  /// Si no está `SUPABASE_PUBLISHABLE_KEY_FORM`, se reusa la de la app.
  static String get supabasePublishableKeyForm =>
      resolverClavePublicableFormulario(
        formKey: dotenv.env['SUPABASE_PUBLISHABLE_KEY_FORM'],
        publishableKey: dotenv.env['SUPABASE_PUBLISHABLE_KEY'],
        anonKey: dotenv.env['SUPABASE_ANON_KEY'],
      );

  static String get supabaseAnonKey => supabasePublishableKey;

  static String get bucketImagenes =>
      dotenv.env['SUPABASE_BUCKET_IMAGENES'] ?? 'imagenes';

  static String get bucketFotosLeads =>
      dotenv.env['SUPABASE_BUCKET_FOTOS_LEADS'] ?? 'leads-privados';

  static String get bucketPlantillas =>
      dotenv.env['SUPABASE_BUCKET_PLANTILLAS'] ?? 'plantillas';

  /// Base de la web pública de eventos (`https://eventos.transworld.cl`).
  static String get publicWebBaseUrl =>
      dotenv.env['PUBLIC_WEB_BASE_URL'] ?? 'https://eventos.transworld.cl';

  /// Owner del repo GitHub usado como fuente OTA (`/releases/latest`).
  static String get githubOwner => dotenv.env['GITHUB_OWNER'] ?? 'bsanchezTW';

  /// Nombre del repo GitHub usado como fuente OTA.
  static String get githubRepo =>
      dotenv.env['GITHUB_REPO'] ?? 'transworld-nexus';

  /// Canal de actualizaciones (reservado; v1 solo usa `stable`).
  static String get updateChannel => dotenv.env['UPDATE_CHANNEL'] ?? 'stable';

  static String _require(String key) {
    final value = dotenv.env[key];
    if (!valorEnvConfigurado(value)) {
      throw StateError(
        'Falta configurar "$key" en el archivo .env (copia .env.example a '
        '.env y completa los valores reales de tu proyecto Supabase).',
      );
    }
    return value!;
  }
}

bool valorEnvConfigurado(String? value) =>
    value != null && value.isNotEmpty && !value.startsWith('TU_');

/// Resuelve la clave pública sin tocar dotenv: útil en tests y para aceptar
/// tanto el nombre nuevo como `SUPABASE_ANON_KEY`.
String resolverClavePublicable({String? publishableKey, String? anonKey}) {
  if (valorEnvConfigurado(publishableKey)) return publishableKey!;
  if (valorEnvConfigurado(anonKey)) return anonKey!;
  throw StateError(
    'Falta configurar "SUPABASE_PUBLISHABLE_KEY" o "SUPABASE_ANON_KEY" en '
    'el archivo .env.',
  );
}

String resolverClavePublicableFormulario({
  String? formKey,
  String? publishableKey,
  String? anonKey,
}) {
  if (valorEnvConfigurado(formKey)) return formKey!;
  return resolverClavePublicable(
    publishableKey: publishableKey,
    anonKey: anonKey,
  );
}
