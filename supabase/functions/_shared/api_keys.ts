/**
 * Lectura de API keys de Supabase en Edge Functions.
 *
 * Las keys nuevas (`sb_publishable_…` / `sb_secret_…`) viven en JSON
 * inyectado (`SUPABASE_PUBLISHABLE_KEYS` / `SUPABASE_SECRET_KEYS`).
 * Mientras las JWT legacy sigan activas, el runtime también inyecta
 * `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY`: se usan de fallback
 * para poder desplegar antes de apagarlas.
 *
 * Las keys nuevas no son JWT: van en `apikey`, nunca en
 * `Authorization: Bearer`.
 */

export function esApiKeyNueva(key: string): boolean {
  return key.startsWith("sb_publishable_") || key.startsWith("sb_secret_");
}

export function parseKeyMap(raw: string | undefined): Record<string, string> {
  if (!raw) return {};
  const trimmed = raw.trim();
  if (!trimmed) return {};
  if (trimmed.startsWith("sb_") || trimmed.startsWith("eyJ")) {
    return { default: trimmed };
  }
  try {
    const parsed: unknown = JSON.parse(trimmed);
    if (typeof parsed === "string" && parsed.length > 0) {
      return { default: parsed };
    }
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      const out: Record<string, string> = {};
      for (const [nombre, valor] of Object.entries(
        parsed as Record<string, unknown>,
      )) {
        if (typeof valor === "string" && valor.length > 0) {
          out[nombre] = valor;
        }
      }
      return out;
    }
  } catch {
    return {};
  }
  return {};
}

/** Nombre en el Dashboard de la publishable de la app (login / staff). */
export const PUBLISHABLE_KEY_NAME_APP = "nexus_app";

/** Nombre en el Dashboard de la publishable del formulario público. */
export const PUBLISHABLE_KEY_NAME_FORM = "eventos_web";

function pickNamedKey(
  raw: string | undefined,
  preferir: string[] = [],
): string | undefined {
  const map = parseKeyMap(raw);
  for (const nombre of preferir) {
    const trimmed = nombre.trim();
    if (trimmed && map[trimmed]) return map[trimmed];
  }
  return Object.values(map)[0];
}

/**
 * Publishable para clientes de usuario (`getUser`, RLS).
 * Prefiere `nexus_app`; se puede sobrescribir con
 * `SUPABASE_PUBLISHABLE_KEY_NAME`.
 */
export function readPublishableKey(): string {
  const override = Deno.env.get("SUPABASE_PUBLISHABLE_KEY_NAME") ?? "";
  const fromNew = pickNamedKey(
    Deno.env.get("SUPABASE_PUBLISHABLE_KEYS"),
    override ? [override, PUBLISHABLE_KEY_NAME_APP] : [PUBLISHABLE_KEY_NAME_APP],
  );
  if (fromNew) return fromNew;
  const legacy = Deno.env.get("SUPABASE_ANON_KEY");
  if (legacy) return legacy;
  throw new Error("Falta SUPABASE_PUBLISHABLE_KEYS o SUPABASE_ANON_KEY");
}

export function readPublishableKeyForm(): string {
  const fromNew = pickNamedKey(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS"), [
    PUBLISHABLE_KEY_NAME_FORM,
  ]);
  if (fromNew) return fromNew;
  return readPublishableKey();
}

export function readSecretKey(): string {
  const fromNew = pickNamedKey(Deno.env.get("SUPABASE_SECRET_KEYS"), [
    "default",
  ]);
  if (fromNew) return fromNew;
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return legacy;
  throw new Error("Falta SUPABASE_SECRET_KEYS o SUPABASE_SERVICE_ROLE_KEY");
}

export function knownSecretKeys(): string[] {
  const fromMap = Object.values(
    parseKeyMap(Deno.env.get("SUPABASE_SECRET_KEYS")),
  );
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const keys = [...fromMap];
  if (legacy) keys.push(legacy);
  return [...new Set(keys.filter((k) => k.length > 0))];
}

export function isSecretKeyRequest(req: Request): boolean {
  const apiKey = req.headers.get("apikey") ?? "";
  const authorization = req.headers.get("authorization") ?? "";
  const bearer = authorization.replace(/^Bearer\s+/i, "").trim();
  const accepted = knownSecretKeys();
  return accepted.includes(apiKey) || accepted.includes(bearer);
}

function headersDesde(input: unknown, init?: RequestInit): Headers {
  const headers = new Headers(init?.headers);
  if (input instanceof Request) {
    input.headers.forEach((value, key) => {
      if (!headers.has(key)) headers.set(key, value);
    });
  }
  return headers;
}

function destinoFetch(input: unknown): string | URL | Request {
  return input instanceof Request
    ? input.url
    : input as string | URL | Request;
}

export function fetchConSecret(secretKey: string): typeof fetch {
  return ((input, init) => {
    const headers = headersDesde(input, init);
    headers.set("apikey", secretKey);
    if (esApiKeyNueva(secretKey)) {
      // El runtime reenvía el Authorization del caller; hay que sacarlo.
      // La secret no es JWT: no puede ir como Bearer.
      headers.delete("Authorization");
    } else {
      headers.set("Authorization", `Bearer ${secretKey}`);
    }
    return fetch(destinoFetch(input), { ...init, headers });
  }) as typeof fetch;
}

export function fetchConSesionUsuario(
  publishableKey: string,
  authHeader: string,
): typeof fetch {
  return ((input, init) => {
    const headers = headersDesde(input, init);
    headers.set("apikey", publishableKey);
    headers.set("Authorization", authHeader);
    return fetch(destinoFetch(input), { ...init, headers });
  }) as typeof fetch;
}
