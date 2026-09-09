import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createAdminClient } from "../_shared/admin_client.ts";
import { resolveCallerAuth } from "../_shared/caller_auth.ts";
import { corsHeaders, json } from "../_shared/cors.ts";

/**
 * Vacía la cola `storage_basura`: borra de Storage los objetos que ya no tiene
 * dueño ninguna fila.
 *
 * Quién encola es cosa de los triggers (ver la sección 7 de schema.sql), que
 * son lo único que ve los borrados en cascada. Acá solo se drena, y hace falta
 * la service role por dos motivos: la cola tiene RLS sin políticas, y el bucket
 * `leads-privados` no expone DELETE a nadie más.
 *
 * Es idempotente y sin efectos si la cola está vacía, así que la app la puede
 * invocar tras cada borrado y una vez por sesión sin coordinarse con nadie.
 */

/** Tope por invocación: acota el tiempo de la función, y lo que sobra se
 * drena en la siguiente. */
const LOTE_MAXIMO = 200;

type FilaBasura = { id: string; bucket: string; path: string };

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Cualquier sesión válida puede pedir el drenaje: solo borra objetos que ya
  // no referencia ninguna fila, así que no hay nada que un rol pueda destruir.
  const auth = await resolveCallerAuth(req);
  if (!auth.ok) return auth.response;

  const admin = createAdminClient();

  const { data, error } = await admin.rpc("rpe_storage_basura_tomar", {
    p_limite: LOTE_MAXIMO,
  });
  if (error) {
    return json({ error: `No se pudo leer la cola: ${error.message}` }, 500);
  }

  const filas = (data ?? []) as FilaBasura[];
  if (filas.length === 0) {
    return json({ borrados: 0, fallidos: 0, pendientes: 0 });
  }

  const porBucket = new Map<string, FilaBasura[]>();
  for (const fila of filas) {
    const grupo = porBucket.get(fila.bucket);
    if (grupo) grupo.push(fila);
    else porBucket.set(fila.bucket, [fila]);
  }

  const drenados: string[] = [];
  const fallos: string[] = [];

  for (const [bucket, grupo] of porBucket) {
    const paths = grupo.map((f) => f.path);
    const { error: errorStorage } = await admin.storage.from(bucket).remove(
      paths,
    );
    if (errorStorage) {
      // La cola conserva el lote: se reintenta en la próxima invocación.
      fallos.push(`${bucket}: ${errorStorage.message}`);
      continue;
    }
    // Un objeto que ya no existía no es un error: igual sale de la cola.
    drenados.push(...grupo.map((f) => f.id));
  }

  if (drenados.length > 0) {
    const { error: errorCola } = await admin
      .from("storage_basura")
      .delete()
      .in("id", drenados);
    if (errorCola) {
      // Los archivos ya no están; la fila se reintentará y quedará descartada
      // por `rpe_storage_en_uso` o por un remove que no encuentra nada.
      fallos.push(`cola: ${errorCola.message}`);
    }
  }

  const { count } = await admin
    .from("storage_basura")
    .select("id", { count: "exact", head: true });

  return json({
    borrados: drenados.length,
    fallidos: fallos.length,
    pendientes: count ?? 0,
    ...(fallos.length > 0 ? { errores: fallos } : {}),
  });
});
