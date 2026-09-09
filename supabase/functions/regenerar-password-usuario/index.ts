/// <reference path="../deno.d.ts" />
import { createAdminClient } from "../_shared/admin_client.ts";
import { resolveCallerAuth } from "../_shared/caller_auth.ts";
import { corsHeaders, json } from "../_shared/cors.ts";
import { enviarCredenciales } from "../_shared/enviar_credenciales.ts";
import { generarContrasena } from "../_shared/password.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const caller = await resolveCallerAuth(req);
    if (!caller.ok) return caller.response;
    const { callerClient } = caller;

    const adminClient = createAdminClient();

    const { data: isAdmin, error: adminError } = await callerClient.rpc(
      "rpe_is_admin",
    );
    if (adminError || !isAdmin) {
      return json(
        { error: "Solo un administrador puede regenerar contraseñas" },
        403,
      );
    }

    const body = await req.json();
    const userId = (body.user_id ?? "").trim();
    if (!userId) {
      return json({ error: "Falta user_id" }, 400);
    }

    const { data: userData, error: userError } = await adminClient.auth.admin
      .getUserById(userId);
    if (userError || !userData.user?.email) {
      return json({ error: "Usuario no encontrado" }, 404);
    }

    const email = userData.user.email.toLowerCase();
    const { data: perfil } = await adminClient
      .from("perfiles")
      .select("nombre_completo, rol")
      .eq("id", userId)
      .maybeSingle();

    const nombre = (perfil?.nombre_completo as string | undefined)?.trim() ||
      (userData.user.user_metadata?.nombre_completo as string | undefined) ||
      email.split("@")[0] ||
      "usuario";

    const password = generarContrasena();

    const { error: updateError } = await adminClient.auth.admin.updateUserById(
      userId,
      { password },
    );
    if (updateError) {
      return json(
        { error: updateError.message ?? "No se pudo actualizar la contraseña" },
        500,
      );
    }

    await adminClient
      .from("perfiles")
      .update({ cambiar_pass: false })
      .eq("id", userId);

    await enviarCredenciales({
      to: email,
      nombre,
      email,
      password,
      rol: perfil?.rol as string | undefined,
      motivo: "password_restablecida",
    });

    return json({
      user_id: userId,
      email,
      password,
      nombre_completo: nombre,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
