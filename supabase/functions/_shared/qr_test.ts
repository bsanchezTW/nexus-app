import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { esCodigoQrValido, generarQrPng } from "./qr.ts";

Deno.test("esCodigoQrValido acepta TW1 y rechaza el resto", () => {
  assertEquals(esCodigoQrValido("TW1-" + "A".repeat(32)), true);
  assertEquals(esCodigoQrValido("tw1-" + "a".repeat(32)), false);
  assertEquals(esCodigoQrValido("TW1-" + "A".repeat(31)), false);
});

Deno.test("generarQrPng devuelve un PNG", async () => {
  const png = await generarQrPng("TW1-" + "AB".repeat(16));
  assertEquals(Array.from(png.slice(0, 4)), [0x89, 0x50, 0x4e, 0x47]);
});
