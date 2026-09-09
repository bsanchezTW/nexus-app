import { createAdminClient } from "../_shared/admin_client.ts";
import { corsHeaders, json } from "../_shared/cors.ts";
import { enviarCredenciales } from "../_shared/enviar_credenciales.ts";
import { findAuthUserByEmail } from "../_shared/find_user.ts";
import { generarContrasena } from "../_shared/password.ts";

/**
 * Recuperación pública: genera nueva contraseña, la aplica y la envía por correo.
 * Responde siempre 200 con mensaje genérico para no filtrar si el email existe.
 */
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const genericOk = () =>
    json({
      ok: true,
      message:
        "Si el correo existe, te enviamos una nueva contraseña de acceso.",
    });

  try {
    const body = await req.json();
    const email = (body.email ?? "").trim().toLowerCase();
    if (!email || !email.includes("@")) {
      return json({ error: "Correo inválido" }, 400);
    }

    const adminClient = createAdminClient();

    const user = await findAuthUserByEmail(adminClient, email);
    if (!user) {
      return genericOk();
    }

    const { data: perfil } = await adminClient
      .from("perfiles")
      .select("nombre_completo, rol, activo")
      .eq("id", user.id)
      .maybeSingle();

    if (perfil && perfil.activo === false) {
      return genericOk();
    }

    const nombre = (perfil?.nombre_completo as string | undefined)?.trim() ||
      (user.user_metadata?.nombre_completo as string | undefined) ||
      email.split("@")[0] ||
      "usuario";

    const password = generarContrasena();

    const { error: updateError } = await adminClient.auth.admin.updateUserById(
      user.id,
      { password },
    );
    if (updateError) {
      console.error("reset-password updateUserById", updateError);
      return genericOk();
    }

    await adminClient
      .from("perfiles")
      .update({ cambiar_pass: false })
      .eq("id", user.id);

    try {
      await enviarCredenciales({
        to: email,
        nombre,
        email,
        password,
        rol: perfil?.rol as string | undefined,
        motivo: "password_restablecida",
      });
    } catch (mailErr) {
      console.error("reset-password email", mailErr);
    }

    return genericOk();
  } catch (e) {
    console.error("reset-password", e);
    return genericOk();
  }
});
