-- Duración de eventos de registro: [fecha] es el primer día.
-- Los existentes quedan en 1 día. La actividad interna hereda el rango.
-- Idempotente: también vive en supabase/schema.sql.

ALTER TABLE public.eventos
  ADD COLUMN IF NOT EXISTS duracion_dias integer NOT NULL DEFAULT 1;
ALTER TABLE public.eventos
  DROP CONSTRAINT IF EXISTS eventos_duracion_dias_check;
ALTER TABLE public.eventos
  ADD CONSTRAINT eventos_duracion_dias_check
  CHECK (duracion_dias >= 1 AND duracion_dias <= 366);

CREATE OR REPLACE FUNCTION public.rpe_fecha_termino_evento(
  p_fecha date,
  p_duracion_dias integer
)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_fecha + (GREATEST(COALESCE(p_duracion_dias, 1), 1) - 1);
$$;

UPDATE public.eventos_leads el
SET duracion_dias = e.duracion_dias
FROM public.eventos e
WHERE el.tipo_evento_lead = 'interno'
  AND el.evento_origen_id = e.id;

CREATE OR REPLACE FUNCTION public.rpe_sync_actividad_interna_desde_evento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.eventos_leads
  SET
    nombre = NEW.nombre,
    fecha = NEW.fecha,
    duracion_dias = NEW.duracion_dias,
    pais = NEW.pais,
    tematica = NEW.tematica,
    certificacion_capacitacion = NEW.certificacion_capacitacion,
    imagen_url = NEW.imagen_url
  WHERE evento_origen_id = NEW.id
    AND tipo_evento_lead = 'interno';
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_eventos_sync_actividad_interna ON public.eventos;
CREATE TRIGGER trg_eventos_sync_actividad_interna
  AFTER UPDATE OF nombre, fecha, duracion_dias, pais, tematica,
    certificacion_capacitacion, imagen_url
  ON public.eventos
  FOR EACH ROW
  EXECUTE FUNCTION public.rpe_sync_actividad_interna_desde_evento();

CREATE OR REPLACE FUNCTION public.rpe_lock_actividad_interna_campos()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  coincide boolean;
BEGIN
  IF NEW.tipo_evento_lead IS DISTINCT FROM OLD.tipo_evento_lead
     OR NEW.evento_origen_id IS DISTINCT FROM OLD.evento_origen_id THEN
    RAISE EXCEPTION
      'No se puede cambiar el origen de una actividad de captura';
  END IF;

  IF NEW.tipo_evento_lead <> 'interno' THEN
    RETURN NEW;
  END IF;

  IF NEW.nombre IS NOT DISTINCT FROM OLD.nombre
     AND NEW.fecha IS NOT DISTINCT FROM OLD.fecha
     AND NEW.duracion_dias IS NOT DISTINCT FROM OLD.duracion_dias
     AND NEW.pais IS NOT DISTINCT FROM OLD.pais
     AND NEW.tematica IS NOT DISTINCT FROM OLD.tematica
     AND NEW.certificacion_capacitacion
           IS NOT DISTINCT FROM OLD.certificacion_capacitacion
     AND NEW.imagen_url IS NOT DISTINCT FROM OLD.imagen_url THEN
    RETURN NEW;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.eventos e
    WHERE e.id = NEW.evento_origen_id
      AND e.nombre IS NOT DISTINCT FROM NEW.nombre
      AND e.fecha IS NOT DISTINCT FROM NEW.fecha
      AND e.duracion_dias IS NOT DISTINCT FROM NEW.duracion_dias
      AND e.pais IS NOT DISTINCT FROM NEW.pais
      AND e.tematica IS NOT DISTINCT FROM NEW.tematica
      AND e.certificacion_capacitacion
            IS NOT DISTINCT FROM NEW.certificacion_capacitacion
      AND e.imagen_url IS NOT DISTINCT FROM NEW.imagen_url
  ) INTO coincide;

  IF NOT coincide THEN
    RAISE EXCEPTION
      'Los datos de una actividad de captura interna se heredan del evento ligado';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_eventos_leads_lock_interna ON public.eventos_leads;
CREATE TRIGGER trg_eventos_leads_lock_interna
  BEFORE UPDATE ON public.eventos_leads
  FOR EACH ROW
  EXECUTE FUNCTION public.rpe_lock_actividad_interna_campos();

CREATE OR REPLACE FUNCTION public.rpe_configurar_acceso_usuario(
  p_usuario_id uuid,
  p_nuevo_rol text,
  p_evento_ids uuid[] DEFAULT '{}'::uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rol_actual text;
  v_evento_ids uuid[];
  v_primer_evento uuid;
  v_rol_evento text;
BEGIN
  IF NOT public.rpe_is_admin() THEN
    RAISE EXCEPTION 'Solo un administrador puede configurar accesos';
  END IF;

  IF p_nuevo_rol NOT IN ('admin', 'organizador', 'user', 'externo') THEN
    RAISE EXCEPTION 'Rol inválido: %', p_nuevo_rol;
  END IF;

  SELECT p.rol
  INTO v_rol_actual
  FROM public.perfiles p
  WHERE p.id = p_usuario_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Usuario no encontrado';
  END IF;

  SELECT COALESCE(
    array_agg(ids.evento_id ORDER BY ids.primera_posicion),
    '{}'::uuid[]
  )
  INTO v_evento_ids
  FROM (
    SELECT entrada.evento_id, min(entrada.orden) AS primera_posicion
    FROM unnest(COALESCE(p_evento_ids, '{}'::uuid[]))
      WITH ORDINALITY AS entrada(evento_id, orden)
    WHERE entrada.evento_id IS NOT NULL
    GROUP BY entrada.evento_id
  ) ids;

  IF p_nuevo_rol IN ('admin', 'organizador') THEN
    v_evento_ids := '{}'::uuid[];
  ELSIF p_nuevo_rol = 'externo' AND cardinality(v_evento_ids) < 1 THEN
    RAISE EXCEPTION 'Debe seleccionar al menos un evento para el usuario externo';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM unnest(v_evento_ids) AS eid
    WHERE NOT EXISTS (SELECT 1 FROM public.eventos e WHERE e.id = eid)
  ) THEN
    RAISE EXCEPTION 'Uno o más eventos no existen';
  END IF;

  IF p_nuevo_rol = 'externo' AND EXISTS (
    SELECT 1
    FROM public.eventos e
    WHERE e.id = ANY(v_evento_ids)
      AND public.rpe_fecha_termino_evento(e.fecha, e.duracion_dias)
            < CURRENT_DATE
  ) THEN
    RAISE EXCEPTION 'Los externos solo pueden usar eventos no finalizados';
  END IF;

  v_primer_evento := v_evento_ids[1];
  v_rol_evento := CASE
    WHEN p_nuevo_rol = 'externo' THEN 'externo'
    ELSE 'vendedor'
  END;

  DELETE FROM public.usuarios_eventos ue
  WHERE ue.usuario_id = p_usuario_id;

  IF p_nuevo_rol IN ('user', 'externo') AND cardinality(v_evento_ids) > 0 THEN
    INSERT INTO public.usuarios_eventos (usuario_id, evento_id, rol_evento)
    SELECT p_usuario_id, eid, v_rol_evento
    FROM unnest(v_evento_ids) AS eid;
  END IF;

  IF to_regclass('public.usuarios_eventos_fijados') IS NOT NULL
     AND p_nuevo_rol IN ('user', 'externo') THEN
    DELETE FROM public.usuarios_eventos_fijados f
    WHERE f.usuario_id = p_usuario_id
      AND NOT (f.evento_id = ANY(v_evento_ids));
  END IF;

  UPDATE public.perfiles p
  SET rol = p_nuevo_rol,
      evento_asignado_id = CASE
        WHEN p_nuevo_rol = 'externo' THEN v_primer_evento
        ELSE NULL
      END
  WHERE p.id = p_usuario_id;
END;
$$;

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
  v_evento_fecha date;
  r record;
BEGIN
  IF NOT public.rpe_is_admin() THEN
    RAISE EXCEPTION 'Solo un administrador puede configurar accesos';
  END IF;

  SELECT public.rpe_fecha_termino_evento(e.fecha, e.duracion_dias)
  INTO v_evento_fecha
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

  IF v_evento_fecha < CURRENT_DATE THEN
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
      RAISE EXCEPTION 'Los externos solo pueden usar eventos no finalizados';
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

-- El registro y los bloques públicos siguen vigentes hasta el último día.
DROP POLICY IF EXISTS rpe_registrados_insert ON public.registrados;
CREATE POLICY rpe_registrados_insert ON public.registrados
  FOR INSERT TO authenticated
  WITH CHECK (
    public.rpe_is_internal_user()
    AND public.rpe_puede_operar_evento(evento_id)
    AND EXISTS (
      SELECT 1 FROM public.eventos e
      WHERE e.id = evento_id
        AND public.rpe_fecha_termino_evento(e.fecha, e.duracion_dias)
              >= CURRENT_DATE
    )
  );

DROP POLICY IF EXISTS rpe_registrados_insert_publico ON public.registrados;
CREATE POLICY rpe_registrados_insert_publico ON public.registrados
  FOR INSERT TO anon
  WITH CHECK (
    origen = 'publico'
    AND acreditado = false
    AND ingresado_por IS NULL
    AND EXISTS (
      SELECT 1 FROM public.eventos e
      WHERE e.id = evento_id
        AND public.rpe_fecha_termino_evento(e.fecha, e.duracion_dias)
              >= CURRENT_DATE
    )
  );

DROP POLICY IF EXISTS rpe_evento_bloques_select_publico ON public.evento_bloques;
CREATE POLICY rpe_evento_bloques_select_publico ON public.evento_bloques
  FOR SELECT TO anon
  USING (
    (activo = true OR activo IS NULL)
    AND EXISTS (
      SELECT 1 FROM public.eventos e
      WHERE e.id = evento_id
        AND public.rpe_fecha_termino_evento(e.fecha, e.duracion_dias)
              >= CURRENT_DATE
    )
  );
