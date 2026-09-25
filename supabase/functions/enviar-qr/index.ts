import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import type { SupabaseClient } from "../_shared/supabase_js.ts";
import { createAdminClient } from "../_shared/admin_client.ts";
import { isSecretKeyRequest } from "../_shared/api_keys.ts";
import { enviarCorreoBrevo, enviarSmsBrevo, remitenteContacto, telefonoSms } from "../_shared/brevo.ts";
import { resolveCallerAuth } from "../_shared/caller_auth.ts";
import { corsHeaders, json } from "../_shared/cors.ts";
import { log } from "../_shared/log.ts";
import {
  asuntoDe,
  htmlConfirmacion,
  textoSms,
  tonoDe,
  type MotivoEnvio,
  type TallerCorreo,
} from "../_shared/plantillas_confirmacion.ts";
import { esCodigoQrValido, generarQrPng, urlImagenQr } from "../_shared/qr.ts";

const PIE_DE_FIRMA_URL =
  "https://evjocwzmlsyjixzihxep.supabase.co/storage/v1/object/public/imagenes/PIE-DE-FIRMA.png";

type Canal = "email" | "sms" | "whatsapp";
type EstadoCanal = "sent" | "skipped" | "failed" | "not_requested";

type ResultadoCanal = { status: EstadoCanal; reason?: string; message_id?: string };

type Envio = {
  id: string;
  registrado_id: string;
  evento_id: string;
  canales: Canal[];
  motivo: MotivoEnvio;
  origen: string;
  intentos: number;
};

function respuesta(body: Record<string, unknown>, status = 200): Response {
  return json(body, status);
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (isSecretKeyRequest(req)) {
    return await modoWebhook(req);
  }

  const auth = await resolveCallerAuth(req);
  if (!auth.ok) {
    log("warn", "auth_rechazada", {});
    return auth.response;
  }
  return await modoStaff(req, auth.callerClient, auth.user.id);
});

async function modoStaff(
  req: Request,
  callerClient: SupabaseClient,
  userId: string,
): Promise<Response> {
  const body = await req.json().catch(() => null) as
    | { registrado_id?: string; canales?: string[]; motivo?: string }
    | null;
  const registradoId = body?.registrado_id ?? "";
  if (!registradoId) {
    return respuesta({ error: "RPE_DATOS_INVALIDOS" }, 400);
  }

  const { data: fila } = await callerClient
    .from("registrados")
    .select("id, evento_id")
    .eq("id", registradoId)
    .maybeSingle();
  if (!fila) return respuesta({ error: "RPE_REGISTRADO_NO_ENCONTRADO" }, 404);

  const { data: externo } = await callerClient.rpc("rpe_is_externo");
  if (externo === true) return respuesta({ error: "RPE_NO_AUTORIZADO" }, 403);

  const admin = createAdminClient();
  const desde = new Date(Date.now() - 60_000).toISOString();
  const { data: reciente } = await admin
    .from("envios_qr")
    .select("id")
    .eq("registrado_id", registradoId)
    .neq("estado", "fallido")
    .gte("created_at", desde)
    .limit(1);
  if (reciente && reciente.length > 0) {
    return respuesta({ error: "RPE_ENVIO_LIMITADO" }, 429);
  }

  const canales = (body?.canales ?? ["email"]).filter((c): c is Canal =>
    c === "email" || c === "sms" || c === "whatsapp"
  );
  if (canales.length === 0) return respuesta({ error: "RPE_DATOS_INVALIDOS" }, 400);
  const motivo = (body?.motivo === "reenvio" || body?.motivo === "codigo_regenerado" ||
      body?.motivo === "talleres_agregados" || body?.motivo === "registro")
    ? body.motivo
    : "reenvio";

  const { data: creado, error } = await admin.from("envios_qr").insert({
    registrado_id: registradoId,
    evento_id: fila.evento_id,
    canales,
    motivo,
    origen: "app",
    solicitado_por: userId,
    estado: "procesando",
    intentos: 1,
  }).select("*").single();
  if (error || !creado) return respuesta({ error: "No se pudo crear el envío" }, 500);

  const resultado = await procesarEnvio(creado as Envio);
  return respuesta({ envio_id: creado.id, ...resultado });
}

async function modoWebhook(req: Request): Promise<Response> {
  const body = await req.json().catch(() => null) as
    | { record?: { id?: string } }
    | null;
  const id = body?.record?.id;
  if (!id) return respuesta({ error: "RPE_DATOS_INVALIDOS" }, 400);

  const admin = createAdminClient();
  const { data: tomado } = await admin
    .from("envios_qr")
    .update({ estado: "procesando", intentos: 1 })
    .eq("id", id)
    .eq("estado", "pendiente")
    .select("*")
    .maybeSingle();
  if (!tomado) {
    log("info", "envio_omitido", { envio_id: id });
    return respuesta({ skipped: "no_pendiente" });
  }
  log("info", "envio_tomado", {
    envio_id: tomado.id,
    registrado_id: tomado.registrado_id,
    evento_id: tomado.evento_id,
  });
  const resultado = await procesarEnvio(tomado as Envio);
  return respuesta(resultado);
}

async function procesarEnvio(envio: Envio): Promise<Record<string, unknown>> {
  const admin = createAdminClient();
  const resultado: Record<Canal, ResultadoCanal> = {
    email: { status: "not_requested" },
    sms: { status: "not_requested" },
    whatsapp: { status: "not_requested" },
  };
  let errorTexto: string | null = null;

  try {
    const { data: registrado } = await admin.from("registrados").select(
      "nombre_completo, email, telefono, codigo_qr, origen, ingresado_por",
    ).eq("id", envio.registrado_id).single();
    const { data: evento } = await admin.from("eventos").select(
      "nombre, slug, pais, fecha, duracion_dias, hora_inicio, hora_fin, lugar, direccion, mapa_url, acceso_qr",
    ).eq("id", envio.evento_id).single();
    const { data: inscripciones } = await admin.from("inscripciones_subevento").select(
      "subeventos(nombre, dia, hora_inicio, hora_fin, sala, expositor)",
    ).eq("registrado_id", envio.registrado_id);

    if (!registrado || !evento) throw new Error("RPE_REGISTRADO_NO_ENCONTRADO");

    let nombreRegistrador: string | null = null;
    if (registrado.ingresado_por) {
      const { data: perfil } = await admin.from("perfiles").select("nombre_completo")
        .eq("id", registrado.ingresado_por).maybeSingle();
      nombreRegistrador = perfil?.nombre_completo ?? null;
    }

    const talleres: TallerCorreo[] = (inscripciones ?? []).map((fila) => {
      const s = fila.subeventos as {
        nombre: string;
        dia: string;
        hora_inicio: string;
        hora_fin: string;
        sala: string | null;
        expositor: string | null;
      };
      return {
        nombre: s.nombre,
        dia: s.dia,
        horaInicio: s.hora_inicio,
        horaFin: s.hora_fin,
        sala: s.sala,
        expositor: s.expositor,
      };
    });

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const codigo = String(registrado.codigo_qr ?? "");
    const qrUrl = evento.acceso_qr && esCodigoQrValido(codigo)
      ? urlImagenQr(supabaseUrl, codigo)
      : null;

    if (envio.canales.includes("email")) {
      resultado.email = await enviarEmail({
        envio, registrado, evento, talleres, nombreRegistrador, qrUrl, codigo,
      });
    }
    if (envio.canales.includes("sms")) {
      resultado.sms = await enviarSms({
        evento: evento.nombre,
        accesoQr: Boolean(evento.acceso_qr),
        telefono: registrado.telefono,
        talleres: talleres.length,
        qrUrl,
      });
    }
    if (envio.canales.includes("whatsapp")) {
      resultado.whatsapp = { status: "skipped", reason: "no_implementado" };
    }
  } catch (error) {
    errorTexto = error instanceof Error ? error.message : "error";
    log("error", "envio_fallido", { envio_id: envio.id });
  } finally {
    const fallo = Object.values(resultado).some((c) => c.status === "failed") ||
      errorTexto !== null;
    await admin.from("envios_qr").update({
      estado: fallo ? "fallido" : "completado",
      resultado,
      error: errorTexto,
      procesado_en: new Date().toISOString(),
    }).eq("id", envio.id);

    if (resultado.email.status === "sent") {
      await admin.from("registrados").update({ email_confirmacion_enviado: true })
        .eq("id", envio.registrado_id);
    }
    if (resultado.sms.status === "sent") {
      await admin.from("registrados").update({ sms_confirmacion_enviado: true })
        .eq("id", envio.registrado_id);
    }
    log(fallo ? "error" : "info", fallo ? "envio_fallido" : "envio_completado", {
      envio_id: envio.id,
      registrado_id: envio.registrado_id,
      evento_id: envio.evento_id,
    });
  }

  return resultado;
}

async function enviarEmail(args: {
  envio: Envio;
  registrado: {
    nombre_completo: string;
    email: string;
    origen: string | null;
    ingresado_por: string | null;
  };
  evento: {
    nombre: string;
    slug: string;
    pais: string;
    fecha: string;
    duracion_dias: number;
    hora_inicio: string | null;
    hora_fin: string | null;
    lugar: string | null;
    direccion: string | null;
    mapa_url: string | null;
    acceso_qr: boolean;
  };
  talleres: TallerCorreo[];
  nombreRegistrador: string | null;
  qrUrl: string | null;
  codigo: string;
}): Promise<ResultadoCanal> {
  const email = args.registrado.email?.trim();
  if (!email) return { status: "skipped", reason: "sin_email" };
  const tono = tonoDe(args.registrado.origen, args.registrado.ingresado_por);
  const html = htmlConfirmacion({
    tono,
    motivo: args.envio.motivo,
    evento: {
      nombre: args.evento.nombre,
      fecha: args.evento.fecha,
      duracionDias: args.evento.duracion_dias ?? 1,
      horaInicio: args.evento.hora_inicio,
      horaFin: args.evento.hora_fin,
      lugar: args.evento.lugar ?? "",
      direccion: args.evento.direccion ?? "",
      descripcion: "",
      accesoQr: args.evento.acceso_qr,
      mapaUrl: args.evento.mapa_url,
    },
    persona: { nombre: args.registrado.nombre_completo },
    registradoPor: args.nombreRegistrador,
    talleres: args.talleres,
    qrUrl: args.qrUrl,
    pieUrl: PIE_DE_FIRMA_URL,
  });
  const attachment = args.evento.acceso_qr && esCodigoQrValido(args.codigo)
    ? [{
      name: `entrada-${args.evento.slug}.png`,
      content: bytesABase64(await generarQrPng(args.codigo)),
    }]
    : undefined;
  try {
    const res = await enviarCorreoBrevo({
      sender: { name: `Registro evento ${args.evento.nombre}`, email: remitenteContacto.email },
      replyTo: remitenteContacto,
      to: [{ email, name: args.registrado.nombre_completo }],
      subject: asuntoDe(args.envio.motivo, args.evento.nombre),
      htmlContent: html,
      attachment,
      tags: ["confirmacion-registro"],
    });
    if (!res.ok) return { status: "failed", reason: "brevo_email" };
    const data = await res.json().catch(() => ({})) as { messageId?: string };
    return { status: "sent", message_id: data.messageId };
  } catch {
    return { status: "failed", reason: "brevo_email" };
  }
}

function bytesABase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binary);
}

async function enviarSms(args: {
  evento: string;
  accesoQr: boolean;
  telefono: string | null;
  talleres: number;
  qrUrl: string | null;
}): Promise<ResultadoCanal> {
  const texto = textoSms({
    evento: args.evento,
    talleres: args.talleres,
    urlQr: args.qrUrl ?? "",
    accesoQr: args.accesoQr,
  });
  if (texto.status === "skipped") return { status: "skipped", reason: texto.reason };
  const numero = telefonoSms(args.telefono);
  if (!numero) return { status: "skipped", reason: "sin_telefono" };
  try {
    const res = await enviarSmsBrevo({ recipient: numero, content: texto.text });
    if (!res.ok) return { status: "failed", reason: "brevo_sms" };
    return { status: "sent" };
  } catch {
    return { status: "failed", reason: "brevo_sms" };
  }
}
