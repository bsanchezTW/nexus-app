import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createAdminClient } from "../_shared/admin_client.ts";
import { isSecretKeyRequest } from "../_shared/api_keys.ts";
import { corsHeaders, json } from "../_shared/cors.ts";

const FIREBASE_SERVICE_ACCOUNT_JSON = Deno.env.get(
  "FIREBASE_SERVICE_ACCOUNT_JSON",
);

const supabase = createAdminClient();

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

type NotificacionRecord = {
  id: string;
  tipo: string;
  titulo: string;
  cuerpo: string;
  evento_id: string | null;
  registrado_id: string | null;
  /** Con valor, el aviso es para una sola persona (comentarios de lead). */
  destinatario_id: string | null;
  lead_id: string | null;
  evento_lead_id: string | null;
};

type DeviceTokenRow = {
  token: string;
  usuario_id: string;
  perfiles: { rol: string; activo: boolean } | null;
};

function base64UrlEncode(data: Uint8Array | string): string {
  const bytes = typeof data === "string"
    ? new TextEncoder().encode(data)
    : data;
  const bin = String.fromCharCode(...bytes);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function importPrivateKey(pem: string): Promise<CryptoKey> {
  const cleaned = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const binary = Uint8Array.from(atob(cleaned), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    binary,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function getAccessToken(account: ServiceAccount): Promise<string> {
  const header = base64UrlEncode(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const now = Math.floor(Date.now() / 1000);
  const payload = base64UrlEncode(JSON.stringify({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${payload}`;
  const key = await importPrivateKey(account.private_key);
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${base64UrlEncode(new Uint8Array(signature))}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!tokenRes.ok) {
    const err = await tokenRes.text();
    throw new Error(`OAuth token error: ${err}`);
  }

  const tokenData = await tokenRes.json();
  return tokenData.access_token as string;
}

async function sendFcmMessage(
  accessToken: string,
  projectId: string,
  token: string,
  notificacion: NotificacionRecord,
): Promise<{ ok: boolean; invalidToken: boolean }> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: {
            title: notificacion.titulo,
            body: notificacion.cuerpo,
          },
          data: {
            notificacion_id: notificacion.id,
            tipo: notificacion.tipo,
            evento_id: notificacion.evento_id ?? "",
            registrado_id: notificacion.registrado_id ?? "",
            lead_id: notificacion.lead_id ?? "",
            evento_lead_id: notificacion.evento_lead_id ?? "",
          },
          // Sin `priority: HIGH` Android lo trata como normal y Doze / OEM
          // lo aplazan o lo tiran. `channel_id` tiene que existir en la app
          // (`nexus_registros`); si falta, va a "Misceláneas", a menudo muteado.
          android: {
            priority: "HIGH",
            notification: {
              channel_id: "nexus_registros",
              sound: "default",
              default_sound: true,
              default_vibrate_timings: true,
              notification_priority: "PRIORITY_HIGH",
            },
          },
        },
      }),
    },
  );

  if (res.ok) return { ok: true, invalidToken: false };

  const body = await res.text();
  const invalid = body.includes("UNREGISTERED") ||
    body.includes("INVALID_ARGUMENT") ||
    body.includes("NOT_FOUND");
  console.error(`FCM error for token ${token.slice(0, 12)}…: ${body}`);
  return { ok: false, invalidToken: invalid };
}

/** Envía a una lista de dispositivos y purga los tokens que FCM rechaza. */
async function enviarA(
  filas: DeviceTokenRow[],
  account: ServiceAccount,
  record: NotificacionRecord,
): Promise<Response> {
  if (filas.length === 0) {
    return json({ ok: true, sent: 0, reason: "no_authorized_tokens" });
  }

  const accessToken = await getAccessToken(account);
  const invalidTokens: string[] = [];
  let sent = 0;

  for (const row of filas) {
    const result = await sendFcmMessage(
      accessToken,
      account.project_id,
      row.token,
      record,
    );
    if (result.ok) {
      sent++;
    } else if (result.invalidToken) {
      invalidTokens.push(row.token);
    }
  }

  if (invalidTokens.length > 0) {
    await supabase.from("device_tokens").delete().in("token", invalidTokens);
  }

  return json({ ok: true, sent, invalid_removed: invalidTokens.length });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Destino de Database Webhook. Autoriza por `apikey` secret (o Bearer
    // legacy de service_role mientras esa key siga inyectada).
    if (!isSecretKeyRequest(req)) {
      return json({ ok: false, error: "unauthorized" }, 401);
    }

    if (!FIREBASE_SERVICE_ACCOUNT_JSON) {
      return json({ ok: false, skipped: true, reason: "no_firebase_config" });
    }

    const payload = await req.json();
    const recordId = payload?.record?.id ?? payload?.id;

    if (typeof recordId !== "string" || !recordId) {
      return json({ ok: false, error: "invalid_payload" }, 400);
    }

    // No confiar en título/cuerpo recibidos: el webhook solo aporta el id y el
    // contenido real se vuelve a leer desde la tabla con service role.
    const { data: notification, error: notificationError } = await supabase
      .from("notificaciones")
      .select(
        "id, tipo, titulo, cuerpo, evento_id, registrado_id, destinatario_id, lead_id, evento_lead_id",
      )
      .eq("id", recordId)
      .maybeSingle();

    if (notificationError) throw notificationError;
    if (!notification) {
      return json({ ok: false, error: "notification_not_found" }, 404);
    }
    const record = notification as NotificacionRecord;

    const account = JSON.parse(
      FIREBASE_SERVICE_ACCOUNT_JSON,
    ) as ServiceAccount;

    // Aviso dirigido: solo los dispositivos de esa persona. El resto de la
    // lógica de rol/evento no aplica, porque la RLS ya lo hizo privado.
    let consulta = supabase
      .from("device_tokens")
      .select("token, usuario_id, perfiles!inner(rol, activo)")
      .in("perfiles.rol", ["admin", "organizador", "user"])
      .eq("perfiles.activo", true);

    if (record.destinatario_id) {
      consulta = consulta.eq("usuario_id", record.destinatario_id);
    }

    const { data: tokens, error } = await consulta;

    if (error) throw error;
    if (!tokens?.length) {
      return json({ ok: true, sent: 0, reason: "no_tokens" });
    }

    const tokenRows = tokens as unknown as DeviceTokenRow[];

    if (record.destinatario_id) {
      return await enviarA(tokenRows, account, record);
    }

    const userIds = [
      ...new Set(
        tokenRows
          .filter((row) => row.perfiles?.rol === "user")
          .map((row) => row.usuario_id),
      ),
    ];
    const usersAutorizados = new Set<string>();

    // Admin/organizador reciben el inbox global. `user` solo recibe push del
    // evento que tiene asignado; una notificación sin evento no se distribuye
    // a users. La consulta usa service role porque esta función es privada.
    if (record.evento_id && userIds.length > 0) {
      const { data: asignaciones, error: asignacionesError } = await supabase
        .from("usuarios_eventos")
        .select("usuario_id")
        .eq("evento_id", record.evento_id)
        .in("usuario_id", userIds);

      if (asignacionesError) throw asignacionesError;
      for (const row of asignaciones ?? []) {
        usersAutorizados.add(row.usuario_id as string);
      }
    }

    const tokensAutorizados = tokenRows.filter((row) =>
      row.perfiles?.rol === "admin" ||
      row.perfiles?.rol === "organizador" ||
      (row.perfiles?.rol === "user" && usersAutorizados.has(row.usuario_id))
    );

    return await enviarA(tokensAutorizados, account, record);
  } catch (e) {
    console.error("enviar-push error:", e);
    return json(
      { ok: false, error: e instanceof Error ? e.message : String(e) },
      500,
    );
  }
});
