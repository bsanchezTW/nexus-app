-- Administración atómica del alcance de un evento: qué usuarios `user` y
-- `externo` quedan autorizados. Admin y organizador conservan acceso global
-- y no se materializan en usuarios_eventos.

CREATE OR REPLACE FUNCTION public.rpe_configurar_acceso_evento(
  p_evento_id uuid,
  p_usuario_ids uuid[] DEFAULT '{}'::uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_usuario_ids uuid[];
  v_evento_activo boolean;
  v_evento_fecha date;
  r record;
BEGIN
  IF NOT public.rpe_is_admin() THEN
    RAISE EXCEPTION 'Solo un administrador puede configurar accesos';
  END IF;

  SELECT e.activo, e.fecha
  INTO v_evento_activo, v_evento_fecha
  FROM public.eventos e
  WHERE e.id = p_evento_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Evento no encontrado';
  END IF;

  SELECT COALESCE(array_agg(DISTINCT uid), '{}'::uuid[])
  INTO v_usuario_ids
  FROM unnest(COALESCE(p_usuario_ids, '{}'::uuid[])) AS uid
  WHERE uid IS NOT NULL;

  IF EXISTS (
    SELECT 1
    FROM unnest(v_usuario_ids) AS uid
    WHERE uid = '00000000-0000-0000-0000-000000000001'::uuid
       OR NOT EXISTS (
         SELECT 1
         FROM public.perfiles p
         WHERE p.id = uid
           AND p.rol IN ('user', 'externo')
       )
  ) THEN
    RAISE EXCEPTION 'Solo se puede asignar acceso a usuarios o usuarios externos';
  END IF;

  IF v_evento_activo IS NOT TRUE OR v_evento_fecha < CURRENT_DATE THEN
    IF EXISTS (
      SELECT 1
      FROM unnest(v_usuario_ids) AS uid
      JOIN public.perfiles p ON p.id = uid
      WHERE p.rol = 'externo'
        AND NOT EXISTS (
          SELECT 1
          FROM public.usuarios_eventos ue
          WHERE ue.usuario_id = uid
            AND ue.evento_id = p_evento_id
        )
    ) THEN
      RAISE EXCEPTION 'Los externos solo pueden usar eventos activos y no finalizados';
    END IF;
  END IF;

  FOR r IN
    SELECT p.id, p.nombre_completo, p.rol
    FROM public.usuarios_eventos ue
    JOIN public.perfiles p ON p.id = ue.usuario_id
    WHERE ue.evento_id = p_evento_id
      AND NOT (ue.usuario_id = ANY (v_usuario_ids))
    FOR UPDATE OF p
  LOOP
    IF r.rol = 'externo' AND NOT EXISTS (
      SELECT 1
      FROM public.usuarios_eventos ue
      WHERE ue.usuario_id = r.id
        AND ue.evento_id <> p_evento_id
    ) THEN
      RAISE EXCEPTION
        'No se puede quitar el acceso de %: el usuario externo debe conservar al menos un evento',
        r.nombre_completo;
    END IF;
  END LOOP;

  DELETE FROM public.usuarios_eventos ue
  WHERE ue.evento_id = p_evento_id
    AND NOT (ue.usuario_id = ANY (v_usuario_ids));

  IF to_regclass('public.usuarios_eventos_fijados') IS NOT NULL THEN
    DELETE FROM public.usuarios_eventos_fijados f
    WHERE f.evento_id = p_evento_id
      AND NOT (f.usuario_id = ANY (v_usuario_ids));
  END IF;

  INSERT INTO public.usuarios_eventos (usuario_id, evento_id, rol_evento)
  SELECT
    p.id,
    p_evento_id,
    CASE WHEN p.rol = 'externo' THEN 'externo' ELSE 'vendedor' END
  FROM public.perfiles p
  WHERE p.id = ANY (v_usuario_ids)
  ON CONFLICT (usuario_id, evento_id) DO NOTHING;

  UPDATE public.perfiles p
  SET evento_asignado_id = (
    SELECT ue.evento_id
    FROM public.usuarios_eventos ue
    WHERE ue.usuario_id = p.id
    ORDER BY ue.created_at
    LIMIT 1
  )
  WHERE p.rol = 'externo'
    AND p.evento_asignado_id = p_evento_id
    AND NOT (p.id = ANY (v_usuario_ids));

  UPDATE public.perfiles p
  SET evento_asignado_id = p_evento_id
  WHERE p.rol = 'externo'
    AND p.id = ANY (v_usuario_ids)
    AND p.evento_asignado_id IS NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpe_configurar_acceso_evento(
  uuid, uuid[]
) TO authenticated;
REVOKE ALL ON FUNCTION public.rpe_configurar_acceso_evento(
  uuid, uuid[]
) FROM PUBLIC;
