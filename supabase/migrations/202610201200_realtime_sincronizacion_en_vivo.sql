-- Sincronización en vivo de la app (sincronizacionEnVivoProvider): publica en
-- Realtime los cambios de eventos, actividades de captura, asignaciones y
-- leads. Cada suscriptor solo recibe las filas que su RLS de SELECT le deja
-- ver, igual que en una consulta normal.
-- Idempotente: también vive en supabase/schema.sql.

DO $$
DECLARE
  v_tabla text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    RETURN;
  END IF;

  FOREACH v_tabla IN ARRAY ARRAY['eventos', 'eventos_leads', 'usuarios_eventos', 'leads']
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = v_tabla
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', v_tabla);
    END IF;
  END LOOP;
END;
$$;
