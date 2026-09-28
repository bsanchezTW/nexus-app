import { formatearDia, formatearHora, linksCalendario, type RangoEvento } from "./zona_horaria.ts";

const GSM7 = new Set(
  "@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà"
    .split(""),
);

export function aGsm7(texto: string): string {
  const plano = texto.normalize("NFD").replace(/\u0300-\u036F/g, "").replaceAll("…", "...");
  let salida = "";
  for (const caracter of plano) {
    salida += GSM7.has(caracter) ? caracter : "?";
  }
  return salida;
}

export type Tono = "autoinscrito" | "registrado_por" | "neutral";
export type MotivoEnvio =
  | "registro"
  | "talleres_agregados"
  | "reenvio"
  | "codigo_regenerado";

export type TallerCorreo = {
  nombre: string;
  dia: string;
  horaInicio: string;
  horaFin: string;
  sala: string | null;
  expositor: string | null;
};

export type DatosConfirmacion = {
  tono: Tono;
  motivo: MotivoEnvio;
  evento: RangoEvento & {
    accesoQr: boolean;
    mapaUrl: string | null;
  };
  persona: { nombre: string };
  registradoPor?: string | null;
  talleres: TallerCorreo[];
  qrUrl?: string | null;
  pieUrl: string;
};

export function escaparHtml(valor: string): string {
  return valor
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

export function tonoDe(origen: string | null, ingresadoPor: string | null): Tono {
  if (origen === "publico") return "autoinscrito";
  if (ingresadoPor) return "registrado_por";
  return "neutral";
}

export function asuntoDe(motivo: MotivoEnvio, evento: string): string {
  switch (motivo) {
    case "registro":
      return `Confirmación de registro: ${evento}`;
    case "talleres_agregados":
      return `Actualización de tu registro: ${evento}`;
    case "reenvio":
      return `Tu registro: ${evento}`;
    case "codigo_regenerado":
      return `Tu nuevo código de acceso: ${evento}`;
  }
}

function intro(datos: DatosConfirmacion): string {
  const nombre = escaparHtml(datos.persona.nombre);
  const evento = escaparHtml(datos.evento.nombre);
  const cuando = escaparHtml(formatearDia(datos.evento.fecha));
  const lugar = escaparHtml(datos.evento.lugar || "el lugar del evento");
  if (datos.tono === "registrado_por") {
    const quien = escaparHtml(datos.registradoPor || "nuestro equipo");
    return `<p>Hola <strong>${nombre}</strong>.</p><p><strong>${quien}</strong> te registró en <strong>${evento}</strong> (${cuando}, ${lugar}).</p>`;
  }
  if (datos.tono === "autoinscrito") {
    return `<p>Hola <strong>${nombre}</strong>.</p><p>Tu registro en <strong>${evento}</strong> quedó confirmado (${cuando}, ${lugar}).</p>`;
  }
  return `<p>Hola <strong>${nombre}</strong>.</p><p>Este es tu registro en <strong>${evento}</strong> (${cuando}, ${lugar}).</p>`;
}

function tablaTalleres(talleres: TallerCorreo[]): string {
  if (talleres.length === 0) return "";
  const filas = talleres.map((t) => {
    const sala = t.sala ? escaparHtml(t.sala) : "";
    const expositor = t.expositor ? escaparHtml(t.expositor) : "";
    return `<tr><td>${escaparHtml(formatearDia(t.dia))}</td><td>${
      escaparHtml(formatearHora(t.horaInicio))
    }–${escaparHtml(formatearHora(t.horaFin))}</td><td>${
      escaparHtml(t.nombre)
    }</td><td>${sala}</td><td>${expositor}</td></tr>`;
  }).join("");
  return `<h2>Tus talleres</h2><table><thead><tr><th>Día</th><th>Hora</th><th>Taller</th><th>Sala</th><th>Expositor</th></tr></thead><tbody>${filas}</tbody></table>`;
}

export function htmlConfirmacion(datos: DatosConfirmacion): string {
  const links = linksCalendario({
    ...datos.evento,
    descripcion: datos.motivo === "codigo_regenerado"
      ? "Tu código anterior ya no sirve."
      : "Tu registro está confirmado.",
  });
  const aviso = datos.motivo === "codigo_regenerado"
    ? "<p>El código anterior ya no sirve. Usa solo este.</p>"
    : "";
  const qr = datos.evento.accesoQr && datos.qrUrl
    ? `<p>Presenta este código en la acreditación.</p><img src="${
      escaparHtml(datos.qrUrl)
    }" width="250" alt="Código QR">`
    : "";
  const mapa = datos.evento.mapaUrl
    ? `<p><a href="${escaparHtml(datos.evento.mapaUrl)}">Cómo llegar</a></p>`
    : "";
  return `<!DOCTYPE html><html><body style="font-family: Arial, sans-serif; background-color: #f4f4f4; padding: 20px; color: #000;">
    <div style="max-width: 600px; margin: 0 auto;">
      ${intro(datos)}
      ${aviso}
      ${qr}
      ${tablaTalleres(datos.talleres)}
      ${mapa}
      <p>Agéndalo en tu calendario: <a href="${links.google}">Google</a> · <a href="${links.outlook}">Outlook</a></p>
      <p style="text-decoration: underline; font-weight: bold;">Saludos cordiales.</p>
      <p>Marketing</p>
      <p style="font-weight: bold;">Transworld</p>
      <img src="${escaparHtml(datos.pieUrl)}" alt="Transworld" width="560">
    </div>
  </body></html>`;
}

export function textoSms(args: {
  evento: string;
  talleres: number;
  urlQr: string;
  accesoQr: boolean;
}): { status: "ready"; text: string } | { status: "skipped"; reason: string } {
  if (!args.accesoQr) return { status: "skipped", reason: "sin_acceso_qr" };
  const extra = args.talleres > 0 ? `, ${args.talleres} talleres` : "";
  const sufijo = `${extra}. QR: ${args.urlQr}`;
  const medio = ": registro confirmado";
  let nombre = aGsm7(args.evento);
  let texto = `${nombre}${medio}${sufijo}`;
  if (texto.length > 160) {
    const disponible = 160 - medio.length - sufijo.length;
    nombre = disponible > 3 ? `${nombre.slice(0, disponible - 3)}...` : "Evento";
    texto = `${nombre}${medio}${sufijo}`;
  }
  return { status: "ready", text: texto.slice(0, 160) };
}
