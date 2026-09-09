import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createAdminClient } from "../_shared/admin_client.ts";
import {
  enviarCorreoBrevo,
  enviarSmsBrevo,
  remitenteContacto,
  telefonoSms,
} from "../_shared/brevo.ts";

// --- 1. CABECERAS CORS (Obligatorias para llamar desde React) ---
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type Canal = "email" | "sms";
type EstadoCanal = "sent" | "skipped" | "failed" | "not_requested";
type ResultadoCanal = { status: EstadoCanal; reason?: string };

const supabase = createAdminClient();
const PIE_DE_FIRMA_URL =
  "https://evjocwzmlsyjixzihxep.supabase.co/storage/v1/object/public/imagenes/PIE-DE-FIRMA.png";

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
    status,
  });
}

/** Si el caller manda `canales`, se respeta tal cual (nunca se agrega email). */
function parseCanales(raw: unknown): Set<Canal> {
  if (Array.isArray(raw)) {
    const out = new Set<Canal>();
    for (const c of raw) {
      if (c === "email" || c === "sms") out.add(c);
    }
    return out;
  }
  return new Set<Canal>(["email"]);
}

function urlQr(id: string): string {
  return `https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=${
    encodeURIComponent(id)
  }`;
}

function mensajeError(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

serve(async (req) => {
  // --- 2. MANEJO DE PREFLIGHT (CORS) ---
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const payload = await req.json();
    const registro = payload.record;
    if (!registro) {
      return jsonResponse({ error: "Sin registro" }, 400);
    }

    const canales = parseCanales(payload.canales);
    if (canales.size === 0) {
      return jsonResponse({ error: "Sin canales" }, 400);
    }

    // 2. Obtener info del evento
    const { data: evento, error: errorEvento } = await supabase
      .from("eventos")
      .select("nombre, tipo_registro, fecha, lugar, direccion")
      .eq("id", registro.evento_id)
      .single();

    if (errorEvento) throw errorEvento;

    const nombreEvento = evento?.nombre || "Evento Transworld";

    // 3. Obtener el nombre del usuario de la App que hizo el registro
    let nombreRegistrador = "nuestro equipo";
    if (registro.ingresado_por) {
      const { data: perfil } = await supabase
        .from("perfiles")
        .select("nombre_completo")
        .eq("id", registro.ingresado_por)
        .single();

      if (perfil?.nombre_completo) {
        nombreRegistrador = perfil.nombre_completo;
      }
    }

    // 4. Formatear la fecha
    let fechaTexto = evento?.fecha || "[Fecha]";
    let anio = "2026", mes = "01", dia = "01";

    if (evento?.fecha && evento.fecha.includes("-")) {
      [anio, mes, dia] = evento.fecha.split("-");
      fechaTexto = `${dia}-${mes}-${anio}`;
    }

    // Calcular el día siguiente para el calendario
    const fechaObj = new Date(parseInt(anio), parseInt(mes) - 1, parseInt(dia));
    fechaObj.setDate(fechaObj.getDate() + 1);
    const anioFin = fechaObj.getFullYear();
    const mesFin = String(fechaObj.getMonth() + 1).padStart(2, "0");
    const diaFin = String(fechaObj.getDate()).padStart(2, "0");

    const lugarEvento = evento?.lugar || "Lugar del evento";
    const direccionEvento = evento?.direccion || "nuestras dependencias";

    // --- ENLACES PARA BOTONES DE CALENDARIO ---
    const ubicacion = `${direccionEvento}, ${lugarEvento}`;
    let desc = "";

    if (evento?.tipo_registro === "cliente") {
      desc =
        "Recuerda presentar tu código QR enviado al correo para la acreditación.";
    } else {
      desc =
        `Te esperamos en ${nombreEvento}. Contacto: contacto@transworld.cl`;
    }

    const googleCalUrl =
      `https://calendar.google.com/calendar/render?action=TEMPLATE&text=${
        encodeURIComponent(nombreEvento)
      }&dates=${anio}${mes}${dia}/${anioFin}${mesFin}${diaFin}&details=${
        encodeURIComponent(desc)
      }&location=${encodeURIComponent(ubicacion)}`;
    const outlookCalUrl =
      `https://outlook.live.com/calendar/0/deeplink/compose?path=/calendar/action/compose&rru=addevent&subject=${
        encodeURIComponent(nombreEvento)
      }&startdt=${anio}-${mes}-${dia}&enddt=${anioFin}-${mesFin}-${diaFin}&allday=true&body=${
        encodeURIComponent(desc)
      }&location=${encodeURIComponent(ubicacion)}`;
    // ------------------------------------------

    const resultado: { email: ResultadoCanal; sms: ResultadoCanal } = {
      email: { status: "not_requested" },
      sms: { status: "not_requested" },
    };

    if (canales.has("email")) {
      resultado.email = await enviarCanalEmail({
        registro,
        evento,
        nombreEvento,
        nombreRegistrador,
        fechaTexto,
        lugarEvento,
        direccionEvento,
        googleCalUrl,
        outlookCalUrl,
      });
    }

    if (canales.has("sms")) {
      resultado.sms = await enviarCanalSms({
        registro,
        tipoRegistro: evento?.tipo_registro,
        nombreEvento,
        fechaTexto,
      });
    }

    return jsonResponse(resultado, 200);
  } catch (error) {
    const mensaje = mensajeError(error);
    console.error("Error Edge Function:", mensaje);
    return jsonResponse({ error: mensaje }, 500);
  }
});

async function enviarCanalEmail(args: {
  registro: Record<string, unknown>;
  evento: { tipo_registro?: string } | null;
  nombreEvento: string;
  nombreRegistrador: string;
  fechaTexto: string;
  lugarEvento: string;
  direccionEvento: string;
  googleCalUrl: string;
  outlookCalUrl: string;
}): Promise<ResultadoCanal> {
  const email = typeof args.registro.email === "string"
    ? args.registro.email.trim()
    : "";
  if (!email) {
    return { status: "skipped", reason: "sin_email" };
  }

  const nombreCompleto = String(args.registro.nombre_completo ?? "");
  let htmlContent = "";

  if (args.evento?.tipo_registro === "cliente") {
    const qrUrl = urlQr(String(args.registro.id ?? ""));
    htmlContent = `
          <!DOCTYPE html>
          <html>
            <body style="font-family: Arial, sans-serif; background-color: #f4f4f4; padding: 20px; color: #000; margin: 0;">
              <div style="max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f4f4f4;">
                
                <p style="font-size: 16px; margin-bottom: 5px;">Hola <strong>${nombreCompleto}</strong>.</p>
                <p style="font-size: 16px; line-height: 1.5; margin-top: 5px;">
                  Tu registro ha finalizado exitosamente para asistir a <strong>${args.nombreEvento}</strong> a realizarse el <strong>${args.fechaTexto}</strong> en <strong>${args.lugarEvento}</strong>, ubicado en <strong>${args.direccionEvento}</strong>.
                </p>
                

                
                <p style="font-size: 16px; margin-bottom: 40px; margin-top: 40px; text-align: center;">
                  Presenta el siguiente Código QR en la acreditación del evento para poder ingresar:
                </p>
                
                <div style="text-align: center; margin-bottom: 40px;">
                   <img src="${qrUrl}" alt="Código QR" width="250" height="250" style="display: block; margin: 0 auto; background-color: #fff;" />
                </div>
                
                <div style="text-align: center; font-size: 16px; font-weight: bold; margin-bottom: 50px;">
                  <p style="margin: 0;">Consultas a</p>
                  <p style="margin: 0; color: #206591; text-decoration: underline;">contacto@transworld.cl</p>
                </div>
                                <div style="margin-top: 35px; margin-bottom: 45px; text-align: center;">
                  <p style="font-size: 15px; margin-bottom: 20px; color: #555;">Agéndalo en tu calendario:</p>
                  
                  <table border="0" cellpadding="0" cellspacing="0" style="margin: 0 auto;">
                    <tr>
                      <td align="center" style="padding: 0 10px 10px 10px;">
                        <table border="0" cellspacing="0" cellpadding="0">
                          <tr>
                            <td align="center" bgcolor="#0078D4" style="border-radius: 6px;">
                              <a href="${args.outlookCalUrl}" target="_blank" style="font-size: 15px; font-family: Arial, sans-serif; color: #ffffff; text-decoration: none; padding: 12px 24px; display: inline-block; font-weight: bold; border-radius: 6px; border: 1px solid #0078D4;">
                                📅 Outlook
                              </a>
                            </td>
                          </tr>
                        </table>
                      </td>
                      <td align="center" style="padding: 0 10px 10px 10px;">
                        <table border="0" cellspacing="0" cellpadding="0">
                          <tr>
                            <td align="center" bgcolor="#4285F4" style="border-radius: 6px;">
                              <a href="${args.googleCalUrl}" target="_blank" style="font-size: 15px; font-family: Arial, sans-serif; color: #ffffff; text-decoration: none; padding: 12px 24px; display: inline-block; font-weight: bold; border-radius: 6px; border: 1px solid #4285F4;">
                                📅 Google Calendar
                              </a>
                            </td>
                          </tr>
                        </table>
                      </td>
                    </tr>
                  </table>
                </div>
                
                <div style="font-size: 16px; margin-bottom: 10px;">
                  <p style="margin: 0; text-decoration: underline; font-weight: bold;">Saludos cordiales.</p>
                  <p style="margin: 0;">Marketing</p>
                  <p style="margin: 0; font-weight: bold;">Transworld</p>
                </div>

                <div>
                   <img src="${PIE_DE_FIRMA_URL}" alt="Transworld" width="560" style="width: 100%; max-width: 560px; height: auto; display: block; border: none;" />
                </div>

              </div>
            </body>
          </html>
        `;
  } else {
    htmlContent = `
          <!DOCTYPE html>
          <html>
            <body style="font-family: Arial, sans-serif; background-color: #f4f4f4; padding: 20px; color: #000; margin: 0;">
              <div style="max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f4f4f4;">
                
                <p style="font-size: 16px; margin-bottom: 5px;">Hola <strong>${nombreCompleto}</strong>.</p>
                
                <p style="font-size: 16px; line-height: 1.5; margin-top: 5px;">
                  Te informamos que <strong>${args.nombreRegistrador}</strong> te ha registrado para participar en el evento/actividad <strong>${args.nombreEvento}</strong> a realizarse el <strong>${args.fechaTexto}</strong> en <strong>${args.lugarEvento}</strong>, ubicado en <strong>${args.direccionEvento}</strong>.
                </p>
                
                <p style="font-size: 16px; line-height: 1.5; margin-top: 15px;">
                  Si tienes alguna consulta, comunícate con <strong>${args.nombreRegistrador}</strong> o escríbenos a <a href="mailto:contacto@transworld.cl" style="color: #206591; text-decoration: underline;">contacto@transworld.cl</a>.
                </p>

                <div style="margin-top: 35px; margin-bottom: 55px; text-align: center;">
                  <p style="font-size: 16px; margin-bottom: 20px; font-weight: bold; color: #333;">¡Agéndalo para que no te lo pierdas!</p>
                  
                  <table border="0" cellpadding="0" cellspacing="0" style="margin: 0 auto;">
                    <tr>
                      <td align="center" style="padding: 0 10px 10px 10px;">
                        <table border="0" cellspacing="0" cellpadding="0">
                          <tr>
                            <td align="center" bgcolor="#0078D4" style="border-radius: 6px;">
                              <a href="${args.outlookCalUrl}" target="_blank" style="font-size: 15px; font-family: Arial, sans-serif; color: #ffffff; text-decoration: none; padding: 12px 24px; display: inline-block; font-weight: bold; border-radius: 6px; border: 1px solid #0078D4;">
                                📅 Outlook
                              </a>
                            </td>
                          </tr>
                        </table>
                      </td>
                      <td align="center" style="padding: 0 10px 10px 10px;">
                        <table border="0" cellspacing="0" cellpadding="0">
                          <tr>
                            <td align="center" bgcolor="#4285F4" style="border-radius: 6px;">
                              <a href="${args.googleCalUrl}" target="_blank" style="font-size: 15px; font-family: Arial, sans-serif; color: #ffffff; text-decoration: none; padding: 12px 24px; display: inline-block; font-weight: bold; border-radius: 6px; border: 1px solid #4285F4;">
                                📅 Google Calendar
                              </a>
                            </td>
                          </tr>
                        </table>
                      </td>
                    </tr>
                  </table>
                </div>

                <div style="font-size: 16px; margin-bottom: 10px;">
                  <p style="margin: 0; text-decoration: underline; font-weight: bold;">Saludos cordiales.</p>
                  <p style="margin: 0;">Marketing</p>
                  <p style="margin: 0; font-weight: bold;">Transworld</p>
                </div>

                <div>
                   <img src="${PIE_DE_FIRMA_URL}" alt="Transworld" width="560" style="width: 100%; max-width: 560px; height: auto; display: block; border: none;" />
                </div>

              </div>
            </body>
          </html>
        `;
  }

  try {
    const res = await enviarCorreoBrevo({
      sender: {
        name: `Registro evento ${args.nombreEvento}`,
        email: remitenteContacto.email,
      },
      replyTo: remitenteContacto,
      to: [
        { email, name: nombreCompleto },
      ],
      subject: `Confirmación de Registro a ${args.nombreEvento}`,
      htmlContent: htmlContent,
      tags: ["confirmacion-registro"],
    });

    if (!res.ok) {
      const errorData = await res.text();
      console.error("Error Brevo email:", errorData);
      return { status: "failed", reason: errorData };
    }
    return { status: "sent" };
  } catch (error) {
    const mensaje = mensajeError(error);
    console.error("Error Brevo email:", mensaje);
    return { status: "failed", reason: mensaje };
  }
}

async function enviarCanalSms(args: {
  registro: Record<string, unknown>;
  tipoRegistro: string | undefined;
  nombreEvento: string;
  fechaTexto: string;
}): Promise<ResultadoCanal> {
  if (args.tipoRegistro !== "cliente") {
    return { status: "skipped", reason: "evento_comercial" };
  }

  const numero = telefonoSms(args.registro.telefono);
  if (!numero) {
    return { status: "skipped", reason: "sin_telefono" };
  }

  const id = typeof args.registro.id === "string" ? args.registro.id.trim() : "";
  if (!id) {
    return { status: "skipped", reason: "sin_id" };
  }

  const nombre = String(args.registro.nombre_completo ?? "").trim();
  const content =
    `Hola ${nombre}. Registro a ${args.nombreEvento} (${args.fechaTexto}) confirmado. QR acreditacion: ${
      urlQr(id)
    }`;

  try {
    const res = await enviarSmsBrevo({
      recipient: numero,
      content,
    });

    if (!res.ok) {
      const errorData = await res.text();
      console.error("Error Brevo SMS:", errorData);
      return { status: "failed", reason: errorData };
    }
    return { status: "sent" };
  } catch (error) {
    const mensaje = mensajeError(error);
    console.error("Error Brevo SMS:", mensaje);
    return { status: "failed", reason: mensaje };
  }
}
