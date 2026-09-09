import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import 'omitir_api_key_en_bearer_client.dart';

/// Inicializa el SDK de Supabase una sola vez, al arrancar la app
/// (ver `main.dart`), y expone el cliente ya configurado al resto de la app
/// a través de Riverpod, en vez de que cada archivo cree su propio cliente
/// (como hacían `lib/supabase.js` y `src/lib/supabase.ts` por separado en
/// el proyecto legado, uno por app).
Future<void> initSupabase() async {
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabasePublishableKey,
    // El SDK, sin sesión, manda la publishable como Bearer. Eso no es un
    // JWT y el gateway responde Invalid JWT cuando las anon legacy están
    // apagadas (login y formulario público).
    httpClient: OmitirApiKeyEnBearerClient(),
    // A diferencia de la web legada, dejamos detectSessionInUrl en true:
    // Flutter Web también necesita procesar el callback de recuperación de
    // contraseña / magic link cuando corre en navegador.
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
}

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Cliente sin sesión para el formulario público (otra publishable).
///
/// No reusa [Supabase.instance]: si alguien abre el form logueado, el
/// cliente principal mandaría el JWT de staff y no el rol `anon`.
final supabasePublicClientProvider = Provider<SupabaseClient>((ref) {
  return SupabaseClient(
    Env.supabaseUrl,
    Env.supabasePublishableKeyForm,
    httpClient: OmitirApiKeyEnBearerClient(),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
});

/// Todas las tablas de negocio viven en el esquema `public` (a diferencia
/// del legado, que mezclaba `public` y un `registro_eventos` inconsistente,
/// ver documentacion_zips_registro_pro.md Sección 7.2/17.2). No hace falta
/// configurar `db.schema`: `public` es el default del cliente de Supabase.
