-- Sondeo de salud de la base de datos para la app.
--
-- La app sondea el backend cada 15 s para decidir si opera en línea o con su
-- copia local (ver lib/core/conexion/monitor_conexion.dart). Hasta ahora
-- preguntaba a /auth/v1/health, que solo prueba el servicio de
-- autenticación: si la base de datos caía pero Auth seguía respondiendo, la
-- app no se enteraba.
--
-- rpe_ping() recorre el mismo camino que los datos reales (gateway →
-- PostgREST → Postgres) y no lee ninguna tabla. Si Postgres no responde,
-- PostgREST devuelve 503 y la app avisa "Problemas con la conexión a la base
-- de datos".
--
-- Se concede a anon porque el sondeo corre también en el login, antes de que
-- haya sesión. Solo devuelve la hora del servidor.
--
-- Idempotente: también vive en supabase/schema.sql.

CREATE OR REPLACE FUNCTION public.rpe_ping()
RETURNS timestamptz
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT now();
$$;

REVOKE ALL ON FUNCTION public.rpe_ping() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpe_ping() TO anon, authenticated;

-- PostgREST no ve la función hasta recargar su caché de esquema.
NOTIFY pgrst, 'reload schema';
