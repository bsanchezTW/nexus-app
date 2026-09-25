import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  asuntoDe,
  htmlConfirmacion,
  textoSms,
  tonoDe,
} from "./plantillas_confirmacion.ts";

const base = {
  tono: "neutral" as const,
  motivo: "registro" as const,
  evento: {
    nombre: "Connect",
    fecha: "2026-11-12",
    duracionDias: 1,
    horaInicio: "09:00",
    horaFin: "18:00",
    lugar: "Hotel",
    direccion: "Av. 1",
    descripcion: "",
    accesoQr: true,
    mapaUrl: null,
  },
  persona: { nombre: "Ana <Pérez> & Cía" },
  talleres: [{
    nombre: "IA",
    dia: "2026-11-12",
    horaInicio: "10:00",
    horaFin: "11:30",
    sala: "B",
    expositor: "Ana",
  }],
  qrUrl: "https://ejemplo/qr",
  pieUrl: "https://ejemplo/pie.png",
};

Deno.test("tono según origen", () => {
  assertEquals(tonoDe("publico", null), "autoinscrito");
  assertEquals(tonoDe("app", "uuid"), "registrado_por");
  assertEquals(tonoDe("excel", null), "neutral");
});

Deno.test("asuntos por motivo", () => {
  assertEquals(asuntoDe("registro", "E"), "Confirmación de registro: E");
  assertEquals(asuntoDe("talleres_agregados", "E"), "Actualización de tu registro: E");
  assertEquals(asuntoDe("reenvio", "E"), "Tu registro: E");
  assertEquals(asuntoDe("codigo_regenerado", "E"), "Tu nuevo código de acceso: E");
});

Deno.test("el HTML escapa y muestra QR solo con acceso", () => {
  const html = htmlConfirmacion(base);
  assertStringIncludes(html, "Ana &lt;Pérez&gt; &amp; Cía");
  assertStringIncludes(html, "Tus talleres");
  assertStringIncludes(html, "https://ejemplo/qr");
  const sinQr = htmlConfirmacion({
    ...base,
    evento: { ...base.evento, accesoQr: false },
  });
  assertEquals(sinQr.includes("https://ejemplo/qr"), false);
});

Deno.test("el SMS cabe en 160 y se omite sin acceso QR", () => {
  const corto = textoSms({
    evento: "Connect",
    talleres: 2,
    urlQr: "https://ejemplo/qr",
    accesoQr: true,
  });
  assertEquals(corto.status, "ready");
  if (corto.status === "ready") assertEquals(corto.text.length <= 160, true);
  assertEquals(
    textoSms({ evento: "X", talleres: 0, urlQr: "", accesoQr: false }).status,
    "skipped",
  );
});
