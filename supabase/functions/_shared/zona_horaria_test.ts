import { assertStringIncludes } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { formatearDia, linksCalendario } from "./zona_horaria.ts";

Deno.test("formatea el día local", () => {
  assertStringIncludes(formatearDia("2026-11-12"), "12-11-2026");
});

Deno.test("links de un día con horas y de varios días sin horas", () => {
  const conHoras = linksCalendario({
    nombre: "E",
    fecha: "2026-11-12",
    duracionDias: 1,
    horaInicio: "09:00",
    horaFin: "18:00",
    lugar: "Hotel",
    direccion: "Av",
    descripcion: "ok",
  });
  assertStringIncludes(conHoras.google, "20261112T090000/20261112T180000");
  const varios = linksCalendario({
    nombre: "E",
    fecha: "2026-11-12",
    duracionDias: 2,
    horaInicio: null,
    horaFin: null,
    lugar: "Hotel",
    direccion: "Av",
    descripcion: "ok",
  });
  assertStringIncludes(varios.google, "20261112/20261114");
  assertStringIncludes(varios.outlook, "allday=true");
});
