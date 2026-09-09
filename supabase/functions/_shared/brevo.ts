/**
 * Envío transaccional vía Brevo, con cabeceras para que Outlook
 * lo trate como prioritario (bandeja Prioritarios, no "Otros").
 *
 * Remitentes:
 * - `soporte@` — casos internos (credenciales, reset, alta de usuario).
 * - `contacto@` — QR de eventos y comunicaciones a asistentes.
 *
 * Brevo solo reenvía cabeceras no estándar; X-Priority / X-MSMail-Priority
 * son las que Outlook lee para marcar importancia alta.
 */
export const cabecerasPrioridadOutlook: Record<string, string> = {
  "X-Priority": "1",
  "X-MSMail-Priority": "High",
};

export const remitenteSoporte = {
  name: "Soporte Transworld",
  email: "soporte@transworld.cl",
} as const;

export const remitenteContacto = {
  name: "Transworld",
  email: "contacto@transworld.cl",
} as const;

type Remitente = { name: string; email: string };

function apiKeyBrevo(): string {
  const apiKey = Deno.env.get("BREVO_API_KEY");
  if (!apiKey) {
    throw new Error("Falta el secreto BREVO_API_KEY en Supabase.");
  }
  return apiKey;
}

/** Dígitos internacionales para SMS (`+56 9 1234 5678` → `56912345678`). */
export function telefonoSms(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  let digits = raw.replace(/\D/g, "");
  if (digits.startsWith("00")) digits = digits.slice(2);
  if (digits.length < 10 || digits.length > 15) return null;
  return digits;
}

export async function enviarCorreoBrevo(
  payload: Record<string, unknown>,
): Promise<Response> {
  const apiKey = apiKeyBrevo();

  const headersExtra = (payload.headers ?? {}) as Record<string, string>;
  const sender = payload.sender as Remitente | undefined;
  return await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: {
      accept: "application/json",
      "api-key": apiKey,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      ...payload,
      replyTo: payload.replyTo ?? sender ?? remitenteSoporte,
      headers: {
        ...cabecerasPrioridadOutlook,
        ...headersExtra,
      },
      tags: [
        "transactional",
        ...((payload.tags as string[] | undefined) ?? []),
      ],
    }),
  });
}

/**
 * SMS transaccional de Brevo. El remitente alfanumérico (máx. 11 caracteres)
 * sale de `BREVO_SMS_SENDER` o, si falta, `Transworld`.
 */
export async function enviarSmsBrevo(args: {
  recipient: string;
  content: string;
}): Promise<Response> {
  const apiKey = apiKeyBrevo();
  const rawSender = (Deno.env.get("BREVO_SMS_SENDER") ?? "Transworld").trim();
  const sender = rawSender.replace(/[^A-Za-z0-9]/g, "").slice(0, 11);
  if (sender.length < 3) {
    throw new Error(
      "BREVO_SMS_SENDER debe tener entre 3 y 11 caracteres alfanuméricos.",
    );
  }

  return await fetch("https://api.brevo.com/v3/transactionalSMS/sms", {
    method: "POST",
    headers: {
      accept: "application/json",
      "api-key": apiKey,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      sender,
      recipient: args.recipient,
      content: args.content,
      type: "transactional",
      unicodeEnabled: true,
      tag: "confirmacion-registro-qr",
    }),
  });
}
