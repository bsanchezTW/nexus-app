import { createClient, type SupabaseClient, type User } from "./supabase_js.ts";
import { json } from "./cors.ts";
import { fetchConSesionUsuario, readPublishableKey } from "./api_keys.ts";

export type CallerAuthOk = {
  ok: true;
  callerClient: SupabaseClient;
  user: User;
  authHeader: string;
};

export type CallerAuthFail = {
  ok: false;
  response: Response;
};

/**
 * Resuelve el usuario llamante a partir del Bearer del request.
 *
 * En Edge, `getUser()` sin JWT no tiene sesión persistida aunque
 * `global.headers.Authorization` esté seteado; hay que pasar el token.
 */
export async function resolveCallerAuth(
  req: Request,
): Promise<CallerAuthOk | CallerAuthFail> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return { ok: false, response: json({ error: "No autorizado" }, 401) };
  }

  const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) {
    return { ok: false, response: json({ error: "No autorizado" }, 401) };
  }
  if (jwt.startsWith("sb_")) {
    return { ok: false, response: json({ error: "Sesión inválida" }, 401) };
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const publishableKey = readPublishableKey();

  const callerClient = createClient(supabaseUrl, publishableKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
    global: {
      headers: { Authorization: authHeader, apikey: publishableKey },
      fetch: fetchConSesionUsuario(publishableKey, authHeader),
    },
  });

  const { data: callerData, error: callerError } = await callerClient.auth
    .getUser(jwt);
  if (callerError || !callerData.user) {
    return {
      ok: false,
      response: json({ error: "Sesión inválida" }, 401),
    };
  }

  return {
    ok: true,
    callerClient,
    user: callerData.user,
    authHeader,
  };
}
