export function log(
  nivel: "info" | "warn" | "error",
  evento: string,
  datos: Record<string, unknown> = {},
  fn = "enviar-qr",
): void {
  console.log(JSON.stringify({
    fn,
    nivel,
    evento,
    ...datos,
    ts: new Date().toISOString(),
  }));
}
