import { createAdminClient } from "../_shared/admin_client.ts";
import { resolveCallerAuth } from "../_shared/caller_auth.ts";
import { corsHeaders, json } from "../_shared/cors.ts";
import { enviarCredenciales } from "../_shared/enviar_credenciales.ts";
import { findAuthUserByEmail } from "../_shared/find_user.ts";
import {
  esContrasenaFuerte,
  LARGO_MINIMO_PASSWORD,
} from "../_shared/password.ts";

const ROLES_VALIDOS = new Set(["admin", "organizador", "user", "externo"]);

function parseEventoIds(body: Record<string, unknown>): string[] {
  const rawIds = body.evento_ids;
  if (Array.isArray(rawIds)) {
    return rawIds
      .map((v) => String(v ?? "").trim())
      .filter((id) => id.length > 0);
  }
  const single = String(body.evento_id ?? "").trim();
  return single ? [single] : [];
}

function eventoYaFinalizo(fecha: unknown, duracionDias: unknown): boolean {
  const raw = String(fecha ?? "");
  if (!raw) return false;
  const dias = Math.max(1, Number(duracionDias) || 1);
  const termino = new Date(`${raw}T00:00:00`);
  if (Number.isNaN(termino.getTime())) return false;
  termino.setDate(termino.getDate() + dias - 1);
  const hoy = new Date();
  hoy.setHours(0, 0, 0, 0);
  return termino < hoy;
}

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
      return json({ error: "Solo un administrador puede crear usuarios" }, 403);
    }

    const body = await req.json();
    const nombreCompleto = (body.nombre_completo ?? "").trim();
    const email = (body.email ?? "").trim().toLowerCase();
    const password = body.password ?? "";
    const rol = (body.rol ?? "").trim();
    const eventoIds = [...new Set(parseEventoIds(body))];

    if (!nombreCompleto || !email || !password || !rol) {
      return json({ error: "Faltan campos obligatorios" }, 400);
    }
    if (!ROLES_VALIDOS.has(rol)) {
      return json({ error: "Rol inválido" }, 400);
    }
    if (!esContrasenaFuerte(password)) {
      return json(
        {
          error:
            `La contraseña debe tener al menos ${LARGO_MINIMO_PASSWORD} caracteres, ` +
            "con mayúscula, minúscula, número y símbolo (! # % $)",
        },
        400,
      );
    }

    let eventoNombres: string[] = [];
    let primerEventoId: string | null = null;

    if (rol === "externo" || (rol === "user" && eventoIds.length > 0)) {
      if (rol === "externo" && eventoIds.length < 1) {
        return json(
          { error: "Selecciona al menos un evento para el usuario externo" },
          400,
        );
      }

      const { data: eventos, error: eventosError } = await adminClient
        .from("eventos")
        .select("id, nombre, fecha, duracion_dias")
        .in("id", eventoIds);

      if (eventosError || !eventos || eventos.length !== eventoIds.length) {
        return json({ error: "Uno o más eventos no fueron encontrados" }, 404);
      }

      if (rol === "externo") {
        for (const evento of eventos) {
          if (eventoYaFinalizo(evento.fecha, evento.duracion_dias)) {
            return json(
              { error: `El evento "${evento.nombre}" ya finalizó` },
              400,
            );
          }
        }
      }

      // Preservar orden solicitado.
      const porId = new Map(eventos.map((e) => [e.id as string, e]));
      eventoNombres = eventoIds.map((id) => porId.get(id)?.nombre ?? id);
      if (rol === "externo") primerEventoId = eventoIds[0];
    }

    let existing;
    try {
      existing = await findAuthUserByEmail(adminClient, email);
    } catch (findErr) {
      return json({ error: String(findErr) }, 500);
    }
    if (existing) {
      return json({ error: "El email ya está registrado" }, 409);
    }

    const userMetadata: Record<string, string> = {
      nombre_completo: nombreCompleto,
    };
    if (rol === "externo" && primerEventoId) {
      userMetadata.rol = "externo";
      userMetadata.evento_id = primerEventoId;
    }

    const { data: created, error: createError } = await adminClient.auth.admin
      .createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: userMetadata,
      });

    if (createError || !created.user) {
      return json(
        { error: createError?.message ?? "No se pudo crear el usuario" },
        500,
      );
    }

    const userId = created.user.id;

    // Rol y eventos se persisten dentro de una única transacción SQL. Esto
    // evita perfiles parcialmente configurados si falla una asignación.
    const { error: accesoError } = await callerClient.rpc(
      "rpe_configurar_acceso_usuario",
      {
        p_usuario_id: userId,
        p_nuevo_rol: rol,
        p_evento_ids: rol === "user" || rol === "externo" ? eventoIds : [],
      },
    );
    if (accesoError) {
      await adminClient.auth.admin.deleteUser(userId);
      return json(
        {
          error: accesoError.message ??
            "No se pudieron configurar el rol y los eventos",
        },
        500,
      );
    }

    try {
      await enviarCredenciales({
        to: email,
        nombre: nombreCompleto,
        email,
        password,
        rol,
        motivo: "cuenta_nueva",
      });
    } catch (mailErr) {
      await adminClient.auth.admin.deleteUser(userId);
      return json(
        {
          error: mailErr instanceof Error
            ? mailErr.message
            : "No se pudo enviar el correo de credenciales",
        },
        500,
      );
    }

    return json({
      user_id: userId,
      email,
      password,
      rol,
      evento_nombre: eventoNombres[0] ?? null,
      evento_nombres: eventoNombres,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
