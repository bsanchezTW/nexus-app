import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { esCodigoQrValido, generarQrPng } from "../_shared/qr.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { log } from "../_shared/log.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  const codigo = (new URL(req.url).searchParams.get("c") ?? "").trim().toUpperCase();
  if (!esCodigoQrValido(codigo)) {
    log("warn", "qr_invalido", {}, "qr-imagen");
    return new Response("Código inválido", {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "text/plain; charset=utf-8" },
    });
  }
  const png = await generarQrPng(codigo);
  return new Response(png, {
    status: 200,
    headers: {
      ...corsHeaders,
      "Content-Type": "image/png",
      "Cache-Control": "public, max-age=31536000, immutable",
    },
  });
});
