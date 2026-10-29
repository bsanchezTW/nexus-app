import {
  formatearFecha,
  formatearHora,
  linksCalendario,
  type RangoEvento,
  sumarDias,
} from "./zona_horaria.ts";

const GSM7 = new Set(
  "@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà"
    .split(""),
);

export function aGsm7(texto: string): string {
  const plano = texto.normalize("NFD").replace(/̀-ͯ/g, "").replaceAll("…", "...");
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
    tipo?: "evento" | "taller";
    accesoQr: boolean;
    mapaUrl: string | null;
  };
  persona: { nombre: string };
  registradoPor?: string | null;
  talleres: TallerCorreo[];
  qrUrl?: string | null;
  pieUrl: string;
};

const CONTACTO = "contacto@transworld.cl";
const AZUL = "#206591";
const TEXTO = "#1f2933";
const SUAVE = "#5f6b76";
const BORDE = "#e3e8ee";
const FUENTE = "Arial, Helvetica, sans-serif";

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

/**
 * Las frases del correo se arman una sola vez y se pintan en HTML (con
 * negritas y escapadas) o en texto plano.
 */
type Pintor = { texto: (s: string) => string; fuerte: (s: string) => string };

const pintorHtml: Pintor = {
  texto: escaparHtml,
  fuerte: (s) => `<strong>${escaparHtml(s)}</strong>`,
};

const pintorPlano: Pintor = { texto: (s) => s, fuerte: (s) => s };

/**
 * "el 18-03-2026, entre las 09:00 y las 18:00, en Hotel, ubicado en Av. 1".
 * Sin hora de término queda "a partir de las 09:00"; sin hora de inicio, sin
 * horario. Lugar y dirección se omiten si faltan.
 */
function cuandoYDonde(evento: DatosConfirmacion["evento"], p: Pintor): string {
  const dias = Math.max(evento.duracionDias, 1);
  const inicio = formatearFecha(evento.fecha);
  const partes = [
    dias > 1
      ? `${p.texto("del ")}${p.fuerte(inicio)}${p.texto(" al ")}${
        p.fuerte(formatearFecha(sumarDias(evento.fecha, dias - 1)))
      }`
      : `${p.texto("el ")}${p.fuerte(inicio)}`,
  ];
  const desde = formatearHora(evento.horaInicio);
  const hasta = formatearHora(evento.horaFin);
  if (desde && hasta) {
    partes.push(`${p.texto("entre las ")}${p.fuerte(desde)}${p.texto(" y las ")}${p.fuerte(hasta)}`);
  } else if (desde) {
    partes.push(`${p.texto("a partir de las ")}${p.fuerte(desde)}`);
  }
  const lugar = evento.lugar.trim();
  const direccion = evento.direccion.trim();
  if (lugar && direccion) {
    partes.push(`${p.texto("en ")}${p.fuerte(lugar)}${p.texto(", ubicado en ")}${p.fuerte(direccion)}`);
  } else if (lugar || direccion) {
    partes.push(`${p.texto("en ")}${p.fuerte(lugar || direccion)}`);
  }
  return partes.join(p.texto(", "));
}

function frases(datos: DatosConfirmacion, p: Pintor): {
  saludo: string;
  cuerpo: string;
  consulta: string | null;
} {
  const saludo = `${p.texto("Hola ")}${p.fuerte(datos.persona.nombre)}${p.texto(".")}`;
  const evento = p.fuerte(datos.evento.nombre);
  const articulo = datos.evento.tipo === "taller" ? "la actividad" : "el evento";
  const cuando = cuandoYDonde(datos.evento, p);
  const contacto = p.texto(CONTACTO);

  if (datos.tono === "autoinscrito") {
    return {
      saludo,
      cuerpo: `${p.texto("Tu registro ha finalizado exitosamente para asistir a ")}${evento}${
        p.texto(" a realizarse ")
      }${cuando}${p.texto(".")}`,
      consulta: null,
    };
  }
  if (datos.tono === "registrado_por") {
    const quien = p.fuerte(datos.registradoPor?.trim() || "nuestro equipo");
    return {
      saludo,
      cuerpo: `${p.texto("Te informamos que ")}${quien}${
        p.texto(` te ha registrado para participar en ${articulo} `)
      }${evento}${p.texto(" a realizarse ")}${cuando}${p.texto(".")}`,
      consulta: `${p.texto("Si tienes alguna consulta, comunícate con ")}${quien}${
        p.texto(" o escríbenos a ")
      }${contacto}${p.texto(".")}`,
    };
  }
  return {
    saludo,
    cuerpo: `${p.texto(`Te informamos que tu registro para participar en ${articulo} `)}${evento}${
      p.texto(" a realizarse ")
    }${cuando}${p.texto(" está confirmado.")}`,
    consulta: `${p.texto("Si tienes alguna consulta, escríbenos a ")}${contacto}${p.texto(".")}`,
  };
}

function etiquetaMotivo(motivo: MotivoEnvio): string {
  switch (motivo) {
    case "registro":
      return "Registro confirmado";
    case "talleres_agregados":
      return "Registro actualizado";
    case "reenvio":
      return "Tu registro";
    case "codigo_regenerado":
      return "Nuevo código de acceso";
  }
}

function avisoMotivo(motivo: MotivoEnvio): string | null {
  if (motivo === "codigo_regenerado") {
    return "Generamos un nuevo código de acceso. El anterior ya no es válido: usa solo el de este correo.";
  }
  if (motivo === "talleres_agregados") {
    return "Tu registro se actualizó con los talleres que agregaste.";
  }
  return null;
}

function linksDe(datos: DatosConfirmacion) {
  return linksCalendario({
    ...datos.evento,
    descripcion: datos.motivo === "codigo_regenerado"
      ? "Tu código anterior ya no sirve."
      : "Tu registro está confirmado.",
  });
}

const parrafo = (contenido: string, extra = "") =>
  `<p style="margin: 0 0 16px 0; font-family: ${FUENTE}; font-size: 16px; line-height: 24px; color: ${TEXTO};${extra}">${contenido}</p>`;

function boton(href: string, etiqueta: string, fondo: string): string {
  return `<table role="presentation" border="0" cellspacing="0" cellpadding="0" style="display: inline-block; margin: 0 6px 10px 6px;"><tr><td align="center" bgcolor="${fondo}" style="border-radius: 6px; background-color: ${fondo};"><a href="${
    escaparHtml(href)
  }" target="_blank" style="display: inline-block; padding: 12px 22px; font-family: ${FUENTE}; font-size: 15px; font-weight: bold; color: #ffffff; text-decoration: none; border-radius: 6px; border: 1px solid ${fondo};">${
    escaparHtml(etiqueta)
  }</a></td></tr></table>`;
}

function bloqueQr(qrUrl: string): string {
  return `<table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0" style="margin: 8px 0 24px 0;"><tr><td align="center" bgcolor="#f7f9fb" style="background-color: #f7f9fb; border: 1px solid ${BORDE}; border-radius: 8px; padding: 24px 16px;">
      <p style="margin: 0 0 4px 0; font-family: ${FUENTE}; font-size: 13px; line-height: 18px; letter-spacing: 1px; text-transform: uppercase; font-weight: bold; color: ${AZUL};">Tu código de acceso</p>
      <p style="margin: 0 0 16px 0; font-family: ${FUENTE}; font-size: 14px; line-height: 20px; color: ${SUAVE};">Preséntalo en la acreditación del evento.</p>
      <img src="${escaparHtml(qrUrl)}" alt="Código QR de acceso" width="220" height="220" style="display: block; margin: 0 auto; width: 220px; height: 220px; border: 8px solid #ffffff; background-color: #ffffff;">
      <p style="margin: 16px 0 0 0; font-family: ${FUENTE}; font-size: 13px; line-height: 18px; color: ${SUAVE};">Si no ves la imagen, el código también va adjunto a este correo.</p>
    </td></tr></table>`;
}

function tablaTalleres(talleres: TallerCorreo[]): string {
  if (talleres.length === 0) return "";
  const ordenados = [...talleres].sort((a, b) =>
    `${a.dia} ${a.horaInicio}`.localeCompare(`${b.dia} ${b.horaInicio}`)
  );
  const filas = ordenados.map((t) => {
    const detalle = [t.sala ? `Sala ${t.sala}` : "", t.expositor ?? ""].filter(Boolean).join(" · ");
    return `<tr><td valign="top" style="padding: 12px 12px 12px 0; border-top: 1px solid ${BORDE}; font-family: ${FUENTE}; font-size: 14px; line-height: 20px; color: ${SUAVE}; white-space: nowrap;">${
      escaparHtml(formatearFecha(t.dia))
    }<br>${escaparHtml(formatearHora(t.horaInicio))}–${
      escaparHtml(formatearHora(t.horaFin))
    }</td><td valign="top" style="padding: 12px 0; border-top: 1px solid ${BORDE}; font-family: ${FUENTE}; font-size: 15px; line-height: 20px; color: ${TEXTO};"><strong>${
      escaparHtml(t.nombre)
    }</strong>${
      detalle
        ? `<br><span style="font-size: 13px; color: ${SUAVE};">${escaparHtml(detalle)}</span>`
        : ""
    }</td></tr>`;
  }).join("");
  return `<p style="margin: 8px 0 8px 0; font-family: ${FUENTE}; font-size: 13px; line-height: 18px; letter-spacing: 1px; text-transform: uppercase; font-weight: bold; color: ${AZUL};">Tus talleres</p>
    <table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0" style="margin: 0 0 24px 0; border-bottom: 1px solid ${BORDE};">${filas}</table>`;
}

export function htmlConfirmacion(datos: DatosConfirmacion): string {
  const { saludo, cuerpo, consulta } = frases(datos, pintorHtml);
  const links = linksDe(datos);
  const aviso = avisoMotivo(datos.motivo);
  const qr = datos.evento.accesoQr && datos.qrUrl ? bloqueQr(datos.qrUrl) : "";
  const mapa = datos.evento.mapaUrl
    ? `<p style="margin: 0 0 24px 0; font-family: ${FUENTE}; font-size: 15px; line-height: 22px;"><a href="${
      escaparHtml(datos.evento.mapaUrl)
    }" target="_blank" style="color: ${AZUL}; font-weight: bold; text-decoration: underline;">Ver cómo llegar</a></p>`
    : "";
  const correo = `<a href="mailto:${CONTACTO}" style="color: ${AZUL}; text-decoration: underline;">${CONTACTO}</a>`;
  const consultaHtml = consulta
    ? parrafo(consulta.replace(escaparHtml(CONTACTO), correo))
    : "";
  const consultaPie = consulta
    ? ""
    : `<p style="margin: 0 0 16px 0; font-family: ${FUENTE}; font-size: 14px; line-height: 20px; color: ${SUAVE};">¿Consultas? Escríbenos a ${correo}.</p>`;
  const preencabezado = escaparHtml(
    `${etiquetaMotivo(datos.motivo)} · ${datos.evento.nombre} · ${formatearFecha(datos.evento.fecha)}`,
  );

  return `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<meta name="supported-color-schemes" content="light">
<title>${escaparHtml(asuntoDe(datos.motivo, datos.evento.nombre))}</title>
</head>
<body style="margin: 0; padding: 0; background-color: #f4f4f4;">
<div style="display: none; max-height: 0; overflow: hidden; mso-hide: all; font-size: 1px; line-height: 1px; color: #f4f4f4;">${preencabezado}</div>
<table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0" bgcolor="#f4f4f4" style="background-color: #f4f4f4;">
  <tr><td align="center" style="padding: 24px 12px;">
    <table role="presentation" width="600" border="0" cellspacing="0" cellpadding="0" style="width: 100%; max-width: 600px;">
      <tr><td bgcolor="${AZUL}" style="background-color: ${AZUL}; border-radius: 8px 8px 0 0; padding: 24px 32px;">
        <p style="margin: 0 0 6px 0; font-family: ${FUENTE}; font-size: 13px; line-height: 18px; letter-spacing: 1px; text-transform: uppercase; color: #cfe3f0;">${
    escaparHtml(etiquetaMotivo(datos.motivo))
  }</p>
        <p style="margin: 0; font-family: ${FUENTE}; font-size: 22px; line-height: 28px; font-weight: bold; color: #ffffff;">${
    escaparHtml(datos.evento.nombre)
  }</p>
      </td></tr>
      <tr><td bgcolor="#ffffff" style="background-color: #ffffff; padding: 32px 32px 8px 32px;">
        ${parrafo(saludo)}
        ${parrafo(cuerpo)}
        ${
    aviso
      ? `<table role="presentation" width="100%" border="0" cellspacing="0" cellpadding="0" style="margin: 0 0 16px 0;"><tr><td style="background-color: #fff6e0; border-left: 4px solid #e0a100; padding: 12px 16px; font-family: ${FUENTE}; font-size: 15px; line-height: 22px; color: ${TEXTO};">${
        escaparHtml(aviso)
      }</td></tr></table>`
      : ""
  }
        ${consultaHtml}
        ${qr}
        ${tablaTalleres(datos.talleres)}
        ${mapa}
        <p style="margin: 0 0 12px 0; font-family: ${FUENTE}; font-size: 15px; line-height: 22px; color: ${SUAVE}; text-align: center;">Agéndalo en tu calendario:</p>
        <div style="text-align: center; margin: 0 0 24px 0;">${boton(links.outlook, "Outlook", "#0078D4")}${
    boton(links.google, "Google Calendar", "#4285F4")
  }</div>
      </td></tr>
      <tr><td bgcolor="#ffffff" style="background-color: #ffffff; border-radius: 0 0 8px 8px; padding: 8px 32px 32px 32px; border-top: 1px solid ${BORDE};">
        <p style="margin: 16px 0 0 0; font-family: ${FUENTE}; font-size: 15px; line-height: 22px; color: ${TEXTO};">Saludos cordiales,</p>
        <p style="margin: 0; font-family: ${FUENTE}; font-size: 15px; line-height: 22px; color: ${TEXTO};">Marketing</p>
        <p style="margin: 0 0 16px 0; font-family: ${FUENTE}; font-size: 15px; line-height: 22px; font-weight: bold; color: ${TEXTO};">Transworld</p>
        ${consultaPie}
        <img src="${escaparHtml(datos.pieUrl)}" alt="Transworld" width="536" style="display: block; width: 100%; max-width: 536px; height: auto; border: 0;">
      </td></tr>
    </table>
  </td></tr>
</table>
</body>
</html>`;
}

/** Versión en texto plano del mismo correo (clientes sin HTML y filtros de spam). */
export function textoConfirmacion(datos: DatosConfirmacion): string {
  const { saludo, cuerpo, consulta } = frases(datos, pintorPlano);
  const links = linksDe(datos);
  const aviso = avisoMotivo(datos.motivo);
  const lineas = [saludo, "", cuerpo];
  if (aviso) lineas.push("", aviso);
  if (consulta) lineas.push("", consulta);
  if (datos.evento.accesoQr && datos.qrUrl) {
    lineas.push("", "Tu código de acceso va adjunto a este correo. Preséntalo en la acreditación.");
  }
  if (datos.talleres.length > 0) {
    lineas.push("", "Tus talleres:");
    for (const t of datos.talleres) {
      lineas.push(
        `- ${formatearFecha(t.dia)} ${formatearHora(t.horaInicio)}–${formatearHora(t.horaFin)}: ${t.nombre}`,
      );
    }
  }
  if (datos.evento.mapaUrl) lineas.push("", `Cómo llegar: ${datos.evento.mapaUrl}`);
  lineas.push("", `Agregar a Google Calendar: ${links.google}`, `Agregar a Outlook: ${links.outlook}`);
  if (!consulta) lineas.push("", `¿Consultas? Escríbenos a ${CONTACTO}.`);
  lineas.push("", "Saludos cordiales,", "Marketing", "Transworld");
  return lineas.join("\n");
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
