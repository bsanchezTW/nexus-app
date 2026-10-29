-- Alcance por evento para AppRole.user, privacidad/deduplicación de leads y
-- notificaciones acotadas. No asigna eventos automáticamente a users legacy:
-- el acceso permanece cerrado hasta configuración administrativa explícita.

BEGIN;

-- ---------------------------------------------------------------------------
-- Leads: identidad normalizada y nombre del capturador sin abrir perfiles.
-- ---------------------------------------------------------------------------
ALTER TABLE public.leads
  ADD COLUMN IF NOT EXISTS email_normalizado text;
ALTER TABLE public.leads
  ADD COLUMN IF NOT EXISTS capturador_nombre text;

DROP TRIGGER IF EXISTS trg_leads_server_fields ON public.leads;
ALTER TABLE public.leads
  DROP CONSTRAINT IF EXISTS leads_email_formato_check;

UPDATE public.leads l
SET capturador_nombre = COALESCE(
  NULLIF(btrim(p.nombre_completo), ''),
  'Sin identificar'
)
FROM public.perfiles p
WHERE p.id = l.perfil_id
  AND NULLIF(btrim(l.capturador_nombre), '') IS NULL;

UPDATE public.leads
SET capturador_nombre = 'Sin identificar'
WHERE NULLIF(btrim(capturador_nombre), '') IS NULL;

ALTER TABLE public.leads
  ALTER COLUMN capturador_nombre SET DEFAULT 'Sin identificar';
ALTER TABLE public.leads
  ALTER COLUMN capturador_nombre SET NOT NULL;

-- Se conserva una sola clave normalizada por campaña sin borrar ni fusionar
-- duplicados históricos. El RPC/trigger también compara lower(trim(email)) y
-- por ello detecta las filas legacy que quedan con NULL en esta columna.
WITH normalizados AS (
  SELECT
    l.id,
    NULLIF(lower(btrim(l.email)), '') AS email_normalizado,
    row_number() OVER (
      PARTITION BY l.evento_id, NULLIF(lower(btrim(l.email)), '')
      ORDER BY l.created_at NULLS LAST, l.id
    ) AS posicion
  FROM public.leads l
  WHERE NULLIF(lower(btrim(l.email)), '') IS NOT NULL
)
UPDATE public.leads l
SET email_normalizado = CASE
  WHEN n.posicion = 1 THEN n.email_normalizado
  ELSE NULL
END
FROM normalizados n
WHERE n.id = l.id
  AND l.email_normalizado IS DISTINCT FROM CASE
    WHEN n.posicion = 1 THEN n.email_normalizado
    ELSE NULL
  END;

UPDATE public.leads
SET email_normalizado = NULL
WHERE NULLIF(lower(btrim(email)), '') IS NULL
  AND email_normalizado IS NOT NULL;

ALTER TABLE public.leads
  ADD CONSTRAINT leads_email_formato_check
  CHECK (
    email IS NOT NULL
    AND btrim(email) <> ''
    AND email ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  ) NOT VALID;

CREATE UNIQUE INDEX IF NOT EXISTS idx_leads_evento_email_normalizado_unique
  ON public.leads (evento_id, email_normalizado)
  WHERE email_normalizado IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Helpers de autorización.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpe_puede_operar_evento(p_evento_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.perfiles p
    WHERE p.id = auth.uid()
      AND p.activo = true
      AND (
        p.rol IN ('admin', 'organizador')
        OR (
          p.rol IN ('user', 'externo')
          AND EXISTS (
            SELECT 1
            FROM public.usuarios_eventos ue
            WHERE ue.usuario_id = p.id
              AND ue.evento_id = p_evento_id
          )
        )
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.rpe_puede_ver_notificacion(p_evento_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.perfiles p
    WHERE p.id = auth.uid()
      AND p.activo = true
      AND (
        p.rol IN ('admin', 'organizador')
        OR (
          p.rol = 'user'
          AND p_evento_id IS NOT NULL
          AND EXISTS (
            SELECT 1
            FROM public.usuarios_eventos ue
            WHERE ue.usuario_id = p.id
              AND ue.evento_id = p_evento_id
          )
        )
      )
  );
$$;

-- El evento preferido del perfil no constituye una autorización. Estos
-- helpers dependen exclusivamente de la junction administrada y evitan que un
-- valor legacy/stale reabra una campaña después de revocarla.
CREATE OR REPLACE FUNCTION public.cl_externo_campana_autorizada(p_campana_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.eventos_leads el
    JOIN public.eventos e
      ON lower(trim(e.nombre)) = lower(trim(el.nombre))
    WHERE el.id = p_campana_id
      AND public.rpe_is_externo()
      AND public.rpe_externo_tiene_evento(e.id)
  );
$$;

CREATE OR REPLACE FUNCTION public.cl_externo_nombre_campana_autorizado(p_nombre text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.eventos e
    WHERE lower(trim(e.nombre)) = lower(trim(p_nombre))
      AND public.rpe_is_externo()
      AND public.rpe_externo_tiene_evento(e.id)
  );
$$;

CREATE OR REPLACE FUNCTION public.cl_set_lead_server_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email_normalizado text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF auth.uid() IS NOT NULL THEN
      NEW.perfil_id := auth.uid();
    END IF;

    SELECT COALESCE(NULLIF(btrim(p.nombre_completo), ''), 'Sin identificar')
    INTO NEW.capturador_nombre
    FROM public.perfiles p
    WHERE p.id = NEW.perfil_id;

    IF NOT FOUND THEN
      NEW.capturador_nombre := 'Sin identificar';
    END IF;
  ELSE
    NEW.perfil_id := OLD.perfil_id;
    NEW.capturador_nombre := OLD.capturador_nombre;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.email := NULLIF(btrim(NEW.email), '');
    v_email_normalizado := NULLIF(lower(NEW.email), '');
    NEW.email_normalizado := v_email_normalizado;

    IF v_email_normalizado IS NOT NULL AND EXISTS (
      SELECT 1
      FROM public.leads l
      WHERE l.evento_id = NEW.evento_id
        AND l.id IS DISTINCT FROM NEW.id
        AND NULLIF(lower(btrim(l.email)), '') = v_email_normalizado
    ) THEN
      RAISE EXCEPTION USING
        ERRCODE = '23505',
        MESSAGE = 'El email ya fue capturado en esta campaña',
        CONSTRAINT = 'idx_leads_evento_email_normalizado_unique';
    END IF;
  ELSIF NEW.evento_id IS DISTINCT FROM OLD.evento_id
        OR NEW.email IS DISTINCT FROM OLD.email THEN
    NEW.email := NULLIF(btrim(NEW.email), '');
    v_email_normalizado := NULLIF(lower(NEW.email), '');
    NEW.email_normalizado := v_email_normalizado;

    IF v_email_normalizado IS NOT NULL AND EXISTS (
      SELECT 1
      FROM public.leads l
      WHERE l.evento_id = NEW.evento_id
        AND l.id IS DISTINCT FROM NEW.id
        AND NULLIF(lower(btrim(l.email)), '') = v_email_normalizado
    ) THEN
      RAISE EXCEPTION USING
        ERRCODE = '23505',
        MESSAGE = 'El email ya fue capturado en esta campaña',
        CONSTRAINT = 'idx_leads_evento_email_normalizado_unique';
    END IF;
  ELSE
    NEW.email_normalizado := OLD.email_normalizado;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_leads_server_fields
  BEFORE INSERT OR UPDATE ON public.leads
  FOR EACH ROW EXECUTE FUNCTION public.cl_set_lead_server_fields();

-- ---------------------------------------------------------------------------
-- Administración atómica de rol y asignaciones.
-- ---------------------------------------------------------------------------
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
      AND (e.activo IS NOT TRUE OR e.fecha < CURRENT_DATE)
  ) THEN
    RAISE EXCEPTION 'Los externos solo pueden usar eventos activos y no finalizados';
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

CREATE OR REPLACE FUNCTION public.rpe_sincronizar_eventos_usuario(
  p_usuario_id uuid,
  p_evento_ids uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rol text;
BEGIN
  IF NOT public.rpe_is_admin() THEN
    RAISE EXCEPTION 'Solo un administrador puede sincronizar eventos';
  END IF;

  SELECT p.rol INTO v_rol
  FROM public.perfiles p
  WHERE p.id = p_usuario_id;

  IF v_rol IS NULL THEN
    RAISE EXCEPTION 'Usuario no encontrado';
  END IF;
  IF v_rol NOT IN ('user', 'externo') THEN
    RAISE EXCEPTION 'Solo se asignan eventos a usuarios user o externo';
  END IF;

  PERFORM public.rpe_configurar_acceso_usuario(
    p_usuario_id,
    v_rol,
    COALESCE(p_evento_ids, '{}'::uuid[])
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.rpe_actualizar_rol_usuario(
  usuario_id uuid,
  nuevo_rol text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF nuevo_rol = 'externo' THEN
    RAISE EXCEPTION 'Use rpe_configurar_acceso_usuario para asignar un externo';
  END IF;
  PERFORM public.rpe_configurar_acceso_usuario(
    usuario_id,
    nuevo_rol,
    '{}'::uuid[]
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.rpe_sincronizar_eventos_externo(
  p_usuario_id uuid,
  p_evento_ids uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rol text;
BEGIN
  SELECT p.rol INTO v_rol
  FROM public.perfiles p
  WHERE p.id = p_usuario_id;

  IF v_rol IS DISTINCT FROM 'externo' THEN
    RAISE EXCEPTION 'Solo se pueden sincronizar eventos de usuarios externos';
  END IF;

  PERFORM public.rpe_sincronizar_eventos_usuario(p_usuario_id, p_evento_ids);
END;
$$;

-- Limpia pins históricos de users que no tienen la asignación correspondiente;
-- no toca admin/organizador ni pins de campañas.
DELETE FROM public.usuarios_eventos_fijados f
USING public.perfiles p
WHERE p.id = f.usuario_id
  AND p.rol = 'user'
  AND NOT EXISTS (
    SELECT 1
    FROM public.usuarios_eventos ue
    WHERE ue.usuario_id = f.usuario_id
      AND ue.evento_id = f.evento_id
  );

-- ---------------------------------------------------------------------------
-- Guardado de leads idempotente y race-safe.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cl_guardar_lead(
  p_evento_id uuid,
  p_nombre_completo text,
  p_empresa text,
  p_cargo text,
  p_telefono text,
  p_email text,
  p_descripcion text,
  p_lead_id uuid DEFAULT NULL
)
RETURNS TABLE (
  resultado text,
  lead_id uuid,
  primer_capturador_nombre text,
  es_propio boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_usuario_id uuid := auth.uid();
  v_rol text;
  v_activo boolean;
  v_capturador_nombre text;
  v_email text := NULLIF(btrim(p_email), '');
  v_email_normalizado text := NULLIF(lower(btrim(p_email)), '');
  v_lead_id uuid := COALESCE(p_lead_id, gen_random_uuid());
  v_existente public.leads%ROWTYPE;
  v_duplicado public.leads%ROWTYPE;
  v_guardado public.leads%ROWTYPE;
  v_puede_editar_global boolean;
BEGIN
  IF v_usuario_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'No autenticado';
  END IF;

  SELECT
    p.rol,
    p.activo,
    COALESCE(NULLIF(btrim(p.nombre_completo), ''), 'Sin identificar')
  INTO v_rol, v_activo, v_capturador_nombre
  FROM public.perfiles p
  WHERE p.id = v_usuario_id;

  IF NOT FOUND OR v_activo IS NOT TRUE THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Usuario inactivo o sin perfil';
  END IF;

  v_puede_editar_global := v_rol IN ('admin', 'organizador');

  IF NOT EXISTS (
    SELECT 1 FROM public.eventos_leads el WHERE el.id = p_evento_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'Campaña no encontrada';
  END IF;

  IF v_rol NOT IN ('admin', 'organizador', 'user')
     AND NOT (
       v_rol = 'externo'
       AND public.cl_externo_campana_autorizada(p_evento_id)
     ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Sin acceso a la campaña';
  END IF;

  IF NULLIF(btrim(p_nombre_completo), '') IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'El nombre es obligatorio';
  END IF;

  IF v_email IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'El email es obligatorio';
  END IF;

  IF v_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'El email no es válido';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_evento_id::text || ':' || v_email_normalizado, 0)
  );

  IF p_lead_id IS NOT NULL THEN
    SELECT l.* INTO v_existente
    FROM public.leads l
    WHERE l.id = p_lead_id
    FOR UPDATE;

    IF FOUND THEN
      IF v_existente.evento_id <> p_evento_id THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'El lead pertenece a otra campaña';
      END IF;
      IF NOT v_puede_editar_global
         AND v_existente.perfil_id IS DISTINCT FROM v_usuario_id THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Solo puedes editar tus propios leads';
      END IF;
    END IF;
  END IF;

  SELECT l.* INTO v_duplicado
  FROM public.leads l
  WHERE l.evento_id = p_evento_id
    AND l.id IS DISTINCT FROM v_lead_id
    AND NULLIF(lower(btrim(l.email)), '') = v_email_normalizado
  ORDER BY l.created_at NULLS LAST, l.id
  LIMIT 1;

  IF FOUND THEN
    RETURN QUERY SELECT
      'duplicado'::text,
      v_duplicado.id,
      v_duplicado.capturador_nombre,
      v_duplicado.perfil_id = v_usuario_id;
    RETURN;
  END IF;

  IF v_existente.id IS NOT NULL THEN
    UPDATE public.leads l
    SET nombre_completo = btrim(p_nombre_completo),
        empresa = NULLIF(btrim(p_empresa), ''),
        cargo = NULLIF(btrim(p_cargo), ''),
        telefono = NULLIF(btrim(p_telefono), ''),
        email = v_email,
        descripcion = NULLIF(btrim(p_descripcion), '')
    WHERE l.id = v_existente.id
    RETURNING l.* INTO v_guardado;

    RETURN QUERY SELECT
      'actualizado'::text,
      v_guardado.id,
      v_guardado.capturador_nombre,
      v_guardado.perfil_id = v_usuario_id;
    RETURN;
  END IF;

  INSERT INTO public.leads (
    id,
    evento_id,
    nombre_completo,
    empresa,
    cargo,
    telefono,
    email,
    descripcion,
    perfil_id,
    capturador_nombre
  ) VALUES (
    v_lead_id,
    p_evento_id,
    btrim(p_nombre_completo),
    NULLIF(btrim(p_empresa), ''),
    NULLIF(btrim(p_cargo), ''),
    NULLIF(btrim(p_telefono), ''),
    v_email,
    NULLIF(btrim(p_descripcion), ''),
    v_usuario_id,
    v_capturador_nombre
  )
  RETURNING * INTO v_guardado;

  RETURN QUERY SELECT
    'creado'::text,
    v_guardado.id,
    v_guardado.capturador_nombre,
    true;
  RETURN;
EXCEPTION
  WHEN unique_violation THEN
    SELECT l.* INTO v_duplicado
    FROM public.leads l
    WHERE l.evento_id = p_evento_id
      AND l.id IS DISTINCT FROM v_lead_id
      AND NULLIF(lower(btrim(l.email)), '') = v_email_normalizado
    ORDER BY l.created_at NULLS LAST, l.id
    LIMIT 1;

    IF FOUND THEN
      RETURN QUERY SELECT
        'duplicado'::text,
        v_duplicado.id,
        v_duplicado.capturador_nombre,
        v_duplicado.perfil_id = v_usuario_id;
      RETURN;
    END IF;
    RAISE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpe_configurar_acceso_usuario(
  uuid, text, uuid[]
) TO authenticated;
REVOKE ALL ON FUNCTION public.rpe_configurar_acceso_usuario(
  uuid, text, uuid[]
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpe_sincronizar_eventos_usuario(
  uuid, uuid[]
) TO authenticated;
REVOKE ALL ON FUNCTION public.rpe_sincronizar_eventos_usuario(
  uuid, uuid[]
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpe_actualizar_rol_usuario(
  uuid, text
) TO authenticated;
REVOKE ALL ON FUNCTION public.rpe_actualizar_rol_usuario(
  uuid, text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpe_sincronizar_eventos_externo(
  uuid, uuid[]
) TO authenticated;
REVOKE ALL ON FUNCTION public.rpe_sincronizar_eventos_externo(
  uuid, uuid[]
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cl_guardar_lead(
  uuid, text, text, text, text, text, text, uuid
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cl_guardar_lead(
  uuid, text, text, text, text, text, text, uuid
) TO authenticated;

-- ---------------------------------------------------------------------------
-- RLS por alcance.
-- ---------------------------------------------------------------------------
-- Policies legacy detectadas en producción. PostgreSQL combina policies
-- permisivas con OR: si quedara una sola policy `true`, anularía las nuevas.
DROP POLICY IF EXISTS "Acceso total perfiles" ON public.perfiles;
DROP POLICY IF EXISTS "Perfiles visibles para usuarios autenticados" ON public.perfiles;
DROP POLICY IF EXISTS "Usuarios editan su propio perfil" ON public.perfiles;
DROP POLICY IF EXISTS "Acceso total a eventos para autenticados" ON public.eventos;
DROP POLICY IF EXISTS "Acceso total eventos" ON public.eventos;
DROP POLICY IF EXISTS "Permitir lectura pública de eventos" ON public.eventos;
DROP POLICY IF EXISTS anon_select_eventos ON public.eventos;
DROP POLICY IF EXISTS "Acceso total a registrados para autenticados" ON public.registrados;
DROP POLICY IF EXISTS "Permitir registro público anónimo" ON public.registrados;
DROP POLICY IF EXISTS anon_insert_registrados ON public.registrados;
DROP POLICY IF EXISTS "Lectura pública de bloques activos" ON public.evento_bloques;
DROP POLICY IF EXISTS anon_select_evento_bloques ON public.evento_bloques;

DROP POLICY IF EXISTS rpe_perfiles_select ON public.perfiles;
CREATE POLICY rpe_perfiles_select ON public.perfiles
  FOR SELECT TO authenticated
  USING (id = auth.uid() OR public.rpe_can_manage_users());
DROP POLICY IF EXISTS rpe_perfiles_insert_own ON public.perfiles;
CREATE POLICY rpe_perfiles_insert_own ON public.perfiles
  FOR INSERT TO authenticated WITH CHECK (id = auth.uid());
DROP POLICY IF EXISTS rpe_perfiles_update ON public.perfiles;
CREATE POLICY rpe_perfiles_update ON public.perfiles
  FOR UPDATE TO authenticated
  USING (id = auth.uid() OR public.rpe_is_admin())
  WITH CHECK (id = auth.uid() OR public.rpe_is_admin());

DROP POLICY IF EXISTS rpe_eventos_all ON public.eventos;
DROP POLICY IF EXISTS rpe_eventos_select ON public.eventos;
CREATE POLICY rpe_eventos_select ON public.eventos
  FOR SELECT TO authenticated
  USING (public.rpe_puede_operar_evento(id));
DROP POLICY IF EXISTS rpe_eventos_select_publico ON public.eventos;
CREATE POLICY rpe_eventos_select_publico ON public.eventos
  FOR SELECT TO anon USING (activo = true);

DROP POLICY IF EXISTS rpe_registrados_all ON public.registrados;
DROP POLICY IF EXISTS rpe_registrados_select ON public.registrados;
CREATE POLICY rpe_registrados_select ON public.registrados
  FOR SELECT TO authenticated
  USING (public.rpe_puede_operar_evento(evento_id));

DROP POLICY IF EXISTS rpe_registrados_insert ON public.registrados;
CREATE POLICY rpe_registrados_insert ON public.registrados
  FOR INSERT TO authenticated
  WITH CHECK (
    public.rpe_is_internal_user()
    AND public.rpe_puede_operar_evento(evento_id)
  );

DROP POLICY IF EXISTS rpe_registrados_update ON public.registrados;
CREATE POLICY rpe_registrados_update ON public.registrados
  FOR UPDATE TO authenticated
  USING (public.rpe_puede_operar_evento(evento_id))
  WITH CHECK (public.rpe_puede_operar_evento(evento_id));

DROP POLICY IF EXISTS rpe_registrados_insert_publico ON public.registrados;
CREATE POLICY rpe_registrados_insert_publico ON public.registrados
  FOR INSERT TO anon
  WITH CHECK (
    acreditado = false
    AND ingresado_por IS NULL
    AND EXISTS (
      SELECT 1 FROM public.eventos e
      WHERE e.id = evento_id AND e.activo = true
    )
  );

DROP POLICY IF EXISTS rpe_evento_bloques_select ON public.evento_bloques;
CREATE POLICY rpe_evento_bloques_select ON public.evento_bloques
  FOR SELECT TO authenticated
  USING (public.rpe_puede_operar_evento(evento_id));
DROP POLICY IF EXISTS rpe_evento_bloques_select_publico ON public.evento_bloques;
CREATE POLICY rpe_evento_bloques_select_publico ON public.evento_bloques
  FOR SELECT TO anon
  USING (
    (activo = true OR activo IS NULL)
    AND EXISTS (
      SELECT 1 FROM public.eventos e
      WHERE e.id = evento_id AND e.activo = true
    )
  );
DROP POLICY IF EXISTS rpe_evento_bloques_write ON public.evento_bloques;
CREATE POLICY rpe_evento_bloques_write ON public.evento_bloques
  FOR ALL TO authenticated
  USING (public.rpe_can_create_content())
  WITH CHECK (public.rpe_can_create_content());

DROP POLICY IF EXISTS rpe_usuarios_eventos_select ON public.usuarios_eventos;
CREATE POLICY rpe_usuarios_eventos_select ON public.usuarios_eventos
  FOR SELECT TO authenticated
  USING (usuario_id = auth.uid() OR public.rpe_is_admin());

DROP POLICY IF EXISTS rpe_usuarios_eventos_fijados_select
  ON public.usuarios_eventos_fijados;
CREATE POLICY rpe_usuarios_eventos_fijados_select
  ON public.usuarios_eventos_fijados FOR SELECT TO authenticated
  USING (
    usuario_id = auth.uid()
    AND public.rpe_puede_operar_evento(evento_id)
  );
DROP POLICY IF EXISTS rpe_usuarios_eventos_fijados_insert
  ON public.usuarios_eventos_fijados;
CREATE POLICY rpe_usuarios_eventos_fijados_insert
  ON public.usuarios_eventos_fijados FOR INSERT TO authenticated
  WITH CHECK (
    usuario_id = auth.uid()
    AND public.rpe_puede_operar_evento(evento_id)
  );

-- Las campañas continúan visibles globalmente para users. Solo las filas de
-- leads se vuelven privadas para user/externo.
DROP POLICY IF EXISTS cl_leads_select ON public.leads;
CREATE POLICY cl_leads_select ON public.leads
  FOR SELECT TO authenticated
  USING (public.rpe_can_create_content() OR perfil_id = auth.uid());

DROP POLICY IF EXISTS cl_leads_insert ON public.leads;
CREATE POLICY cl_leads_insert ON public.leads
  FOR INSERT TO authenticated
  WITH CHECK (
    perfil_id = auth.uid()
    AND (
      public.rpe_is_internal_user()
      OR public.cl_externo_campana_autorizada(evento_id)
    )
  );

DROP POLICY IF EXISTS cl_leads_update ON public.leads;
CREATE POLICY cl_leads_update ON public.leads
  FOR UPDATE TO authenticated
  USING (public.rpe_can_create_content() OR perfil_id = auth.uid())
  WITH CHECK (public.rpe_can_create_content() OR perfil_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Inbox: admin/organizador globales; user solo eventos asignados; externo no.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpe_ocultar_todas_notificaciones()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;
  IF NOT public.rpe_is_internal_user() THEN
    RAISE EXCEPTION 'No tienes acceso a notificaciones';
  END IF;

  INSERT INTO public.notificaciones_ocultas (usuario_id, notificacion_id)
  SELECT v_user_id, n.id
  FROM public.notificaciones n
  WHERE public.rpe_puede_ver_notificacion(n.evento_id)
  ON CONFLICT (usuario_id, notificacion_id) DO NOTHING;
END;
$$;

DROP POLICY IF EXISTS rpe_notificaciones_select ON public.notificaciones;
CREATE POLICY rpe_notificaciones_select ON public.notificaciones
  FOR SELECT TO authenticated
  USING (public.rpe_puede_ver_notificacion(evento_id));

DROP POLICY IF EXISTS rpe_notificaciones_leidas_select
  ON public.notificaciones_leidas;
CREATE POLICY rpe_notificaciones_leidas_select ON public.notificaciones_leidas
  FOR SELECT TO authenticated
  USING (
    usuario_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.notificaciones n
      WHERE n.id = notificacion_id
        AND public.rpe_puede_ver_notificacion(n.evento_id)
    )
  );

DROP POLICY IF EXISTS rpe_notificaciones_leidas_insert
  ON public.notificaciones_leidas;
CREATE POLICY rpe_notificaciones_leidas_insert ON public.notificaciones_leidas
  FOR INSERT TO authenticated
  WITH CHECK (
    usuario_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.notificaciones n
      WHERE n.id = notificacion_id
        AND public.rpe_puede_ver_notificacion(n.evento_id)
    )
  );

DROP POLICY IF EXISTS rpe_notificaciones_leidas_update
  ON public.notificaciones_leidas;
CREATE POLICY rpe_notificaciones_leidas_update ON public.notificaciones_leidas
  FOR UPDATE TO authenticated
  USING (
    usuario_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.notificaciones n
      WHERE n.id = notificacion_id
        AND public.rpe_puede_ver_notificacion(n.evento_id)
    )
  )
  WITH CHECK (
    usuario_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.notificaciones n
      WHERE n.id = notificacion_id
        AND public.rpe_puede_ver_notificacion(n.evento_id)
    )
  );

DROP POLICY IF EXISTS rpe_notificaciones_ocultas_select
  ON public.notificaciones_ocultas;
CREATE POLICY rpe_notificaciones_ocultas_select
  ON public.notificaciones_ocultas
  FOR SELECT TO authenticated
  USING (
    usuario_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.notificaciones n
      WHERE n.id = notificacion_id
        AND public.rpe_puede_ver_notificacion(n.evento_id)
    )
  );

DROP POLICY IF EXISTS rpe_notificaciones_ocultas_insert
  ON public.notificaciones_ocultas;
CREATE POLICY rpe_notificaciones_ocultas_insert
  ON public.notificaciones_ocultas
  FOR INSERT TO authenticated
  WITH CHECK (
    usuario_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.notificaciones n
      WHERE n.id = notificacion_id
        AND public.rpe_puede_ver_notificacion(n.evento_id)
    )
  );

DROP POLICY IF EXISTS rpe_notificaciones_ocultas_delete
  ON public.notificaciones_ocultas;
CREATE POLICY rpe_notificaciones_ocultas_delete
  ON public.notificaciones_ocultas
  FOR DELETE TO authenticated
  USING (
    usuario_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.notificaciones n
      WHERE n.id = notificacion_id
        AND public.rpe_puede_ver_notificacion(n.evento_id)
    )
  );

GRANT EXECUTE ON FUNCTION public.rpe_ocultar_todas_notificaciones()
  TO authenticated;

-- ---------------------------------------------------------------------------
-- Storage: el path estable de una foto de lead no concede propiedad. La
-- policy valida la fila antes de permitir INSERT/UPSERT y también cierra las
-- policies permisivas que existen en producción.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpe_puede_escribir_imagen(
  p_object_name text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
DECLARE
  v_carpeta text := split_part(COALESCE(p_object_name, ''), '/', 1);
  v_archivo text := split_part(COALESCE(p_object_name, ''), '/', 2);
  v_id_text text := split_part(v_archivo, '.', 1);
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL
    OR p_object_name !~* '^(eventos|perfiles|leads)/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|jpeg|png|webp|heic|heif)$'
  THEN
    RETURN false;
  END IF;

  v_id := v_id_text::uuid;
  CASE v_carpeta
    WHEN 'eventos' THEN
      RETURN public.rpe_can_create_content();
    WHEN 'perfiles' THEN
      RETURN v_id = auth.uid() OR public.rpe_is_admin();
    WHEN 'leads' THEN
      RETURN public.rpe_can_create_content() OR EXISTS (
        SELECT 1
        FROM public.leads l
        WHERE l.id = v_id AND l.perfil_id = auth.uid()
      );
    ELSE
      RETURN false;
  END CASE;
EXCEPTION
  WHEN invalid_text_representation THEN
    RETURN false;
END;
$$;

REVOKE ALL ON FUNCTION public.rpe_puede_escribir_imagen(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpe_puede_escribir_imagen(text)
  TO authenticated;

INSERT INTO storage.buckets (id, name, public)
VALUES ('leads-privados', 'leads-privados', false)
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS "Permitir subidas a imagenes" ON storage.objects;
DROP POLICY IF EXISTS "Permitir actualizar imagenes" ON storage.objects;

DROP POLICY IF EXISTS rpe_storage_imagenes_write ON storage.objects;
CREATE POLICY rpe_storage_imagenes_write ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'imagenes'
    AND split_part(name, '/', 1) <> 'leads'
    AND public.rpe_puede_escribir_imagen(name)
  );

DROP POLICY IF EXISTS rpe_storage_imagenes_update ON storage.objects;
CREATE POLICY rpe_storage_imagenes_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'imagenes'
    AND split_part(name, '/', 1) <> 'leads'
    AND public.rpe_puede_escribir_imagen(name)
  )
  WITH CHECK (
    bucket_id = 'imagenes'
    AND split_part(name, '/', 1) <> 'leads'
    AND public.rpe_puede_escribir_imagen(name)
  );

DROP POLICY IF EXISTS rpe_storage_leads_read ON storage.objects;
CREATE POLICY rpe_storage_leads_read ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'leads-privados'
    AND public.rpe_puede_escribir_imagen(name)
  );

DROP POLICY IF EXISTS rpe_storage_leads_write ON storage.objects;
CREATE POLICY rpe_storage_leads_write ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'leads-privados'
    AND split_part(name, '/', 1) = 'leads'
    AND public.rpe_puede_escribir_imagen(name)
  );

DROP POLICY IF EXISTS rpe_storage_leads_update ON storage.objects;
CREATE POLICY rpe_storage_leads_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'leads-privados'
    AND public.rpe_puede_escribir_imagen(name)
  )
  WITH CHECK (
    bucket_id = 'leads-privados'
    AND public.rpe_puede_escribir_imagen(name)
  );

DO $$
BEGIN
  IF to_regclass('storage.prefixes') IS NULL THEN
    RETURN;
  END IF;

  DROP POLICY IF EXISTS rpe_storage_prefixes_read ON storage.prefixes;
  CREATE POLICY rpe_storage_prefixes_read ON storage.prefixes
    FOR SELECT
    USING (bucket_id IN ('imagenes', 'plantillas', 'leads-privados'));

  DROP POLICY IF EXISTS rpe_storage_prefixes_write ON storage.prefixes;
  CREATE POLICY rpe_storage_prefixes_write ON storage.prefixes
    FOR INSERT TO authenticated
    WITH CHECK (bucket_id IN ('imagenes', 'leads-privados'));

  DROP POLICY IF EXISTS rpe_storage_prefixes_update ON storage.prefixes;
  CREATE POLICY rpe_storage_prefixes_update ON storage.prefixes
    FOR UPDATE TO authenticated
    USING (bucket_id IN ('imagenes', 'leads-privados'));
END $$;

COMMIT;
