import { createClient, type SupabaseClient } from "./supabase_js.ts";
import { esApiKeyNueva, fetchConSecret, readSecretKey } from "./api_keys.ts";

/**
 * Cliente admin (secret / service_role).
 *
 * El runtime de Edge reenvía el `Authorization` del request original; hay
 * que forzar la credencial de servicio. Con JWT `service_role` eso iba en
 * Bearer. Con `sb_secret_…` solo va en `apikey` (no es un JWT).
 */
export function createAdminClient(
  supabaseUrl = Deno.env.get("SUPABASE_URL")!,
  secretKey = readSecretKey(),
): SupabaseClient {
  const headers: Record<string, string> = { apikey: secretKey };
  if (!esApiKeyNueva(secretKey)) {
    headers.Authorization = `Bearer ${secretKey}`;
  }

  return createClient(supabaseUrl, secretKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
    global: {
      headers,
      fetch: fetchConSecret(secretKey),
    },
  });
}
