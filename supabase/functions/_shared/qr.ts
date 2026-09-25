import QRCode from "npm:qrcode@1.5.4";

const PATRON = /^TW1-[0-9A-F]{32}$/;

export function esCodigoQrValido(codigo: string): boolean {
  return PATRON.test(codigo);
}

export async function generarQrPng(texto: string): Promise<Uint8Array> {
  const buffer = await QRCode.toBuffer(texto, {
    type: "png",
    errorCorrectionLevel: "M",
    width: 600,
    margin: 2,
  });
  return new Uint8Array(buffer);
}

export function urlImagenQr(supabaseUrl: string, codigo: string): string {
  const base = supabaseUrl.replace(/\/$/, "");
  return `${base}/functions/v1/qr-imagen?c=${codigo}`;
}
