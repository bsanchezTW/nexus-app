-- Leads: borrado lógico y edición completa del capturador sobre sus leads.
--
-- 1. leads.eliminado_at / eliminado_por. Un lead borrado deja de verse para
--    todos (RLS de SELECT), sale de conteos y búsquedas de duplicado y libera
--    su email en la actividad. La fila y sus fotos se conservan: el admin lo
--    recupera desde el SQL Editor con
--      UPDATE public.leads SET eliminado_at = NULL, eliminado_por = NULL
--      WHERE id = '<lead>';
--    (falla con unique_violation si alguien ya capturó ese email después).
-- 2. cl_eliminar_lead(p_lead_id): admin o quien lo capturó. Idempotente, para
--    que la cola offline de la app pueda reintentarlo sin quedar atascada.
-- 3. cl_guardar_lead: quien capturó el lead también puede cambiar email y
--    teléfono (antes solo admin y organizador). El plazo del capturador
--    (fin de la actividad + 24 h) y qué contacto se muestra lo decide la app.
--
-- Idempotente: también vive en supabase/schema.sql.

ALTER TABLE public.leads
  ADD COLUMN IF NOT EXISTS eliminado_at timestamptz,
  ADD COLUMN IF NOT EXISTS eliminado_por uuid
    REFERENCES public.perfiles (id) ON DELETE SET NULL;

-- El email solo es único entre los leads vigentes.
DROP INDEX IF EXISTS public.idx_leads_evento_email_normalizado_unique;
CREATE UNIQUE INDEX IF NOT EXISTS idx_leads_evento_email_normalizado_unique
  ON public.leads (evento_id, email_normalizado)
  WHERE email_normalizado IS NOT NULL AND eliminado_at IS NULL;

DROP POLICY IF EXISTS cl_leads_select ON public.leads;
CREATE POLICY cl_leads_select ON public.leads
  FOR SELECT TO authenticated
  USING (
    eliminado_at IS NULL
    AND public.cl_campana_autorizada(evento_id)
  );

-- El borrado físico deja de ser parte de la app: se borra con cl_eliminar_lead.
-- La política de DELETE del admin se mantiene para limpiezas manuales.

-- Duplicados de email: solo contra leads vigentes.
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
    -- La autoría es inmutable incluso si un cliente intenta reasignarla.
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
        AND l.eliminado_at IS NULL
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
        AND l.eliminado_at IS NULL
    ) THEN
      RAISE EXCEPTION USING
        ERRCODE = '23505',
        MESSAGE = 'El email ya fue capturado en esta campaña',
        CONSTRAINT = 'idx_leads_evento_email_normalizado_unique';
    END IF;
  ELSE
    -- Evita que un cliente cambie directamente la clave normalizada.
    NEW.email_normalizado := OLD.email_normalizado;
  END IF;

  RETURN NEW;
END;
$$;


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
  v_telefono text := NULLIF(btrim(p_telefono), '');
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

  IF NOT public.cl_campana_autorizada(p_evento_id) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Sin acceso a la campaña';
  END IF;

  IF NULLIF(btrim(p_nombre_completo), '') IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'El nombre es obligatorio';
  END IF;

  -- Quien capturó el lead lo edita completo, contacto incluido; el resto
  -- necesita rol global. El plazo de edición del capturador (fin de la
  -- actividad + 24 h) lo aplica la app.
  IF p_lead_id IS NOT NULL THEN
    SELECT l.* INTO v_existente
    FROM public.leads l
    WHERE l.id = p_lead_id
    FOR UPDATE;

    IF FOUND THEN
      IF v_existente.eliminado_at IS NOT NULL THEN
        RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'El lead fue eliminado';
      END IF;
      IF v_existente.evento_id <> p_evento_id THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'El lead pertenece a otra campaña';
      END IF;
      IF NOT v_puede_editar_global
         AND v_existente.perfil_id IS DISTINCT FROM v_usuario_id THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Solo puedes editar tus propios leads';
      END IF;
    END IF;
  END IF;

  IF v_email IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'El email es obligatorio';
  END IF;

  IF v_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'El email no es válido';
  END IF;

  -- Serializa por campaña+email. El índice único sigue siendo la última línea
  -- de defensa para escrituras directas y clientes concurrentes.
  IF v_email_normalizado IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(
      hashtextextended(p_evento_id::text || ':' || v_email_normalizado, 0)
    );
  END IF;

  IF v_email_normalizado IS NOT NULL THEN
    SELECT l.* INTO v_duplicado
    FROM public.leads l
    WHERE l.evento_id = p_evento_id
      AND l.id IS DISTINCT FROM v_lead_id
      AND NULLIF(lower(btrim(l.email)), '') = v_email_normalizado
      AND l.eliminado_at IS NULL
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
  END IF;

  IF v_existente.id IS NOT NULL THEN
    UPDATE public.leads l
    SET nombre_completo = btrim(p_nombre_completo),
        empresa = NULLIF(btrim(p_empresa), ''),
        cargo = NULLIF(btrim(p_cargo), ''),
        telefono = v_telefono,
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
    v_telefono,
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
      AND l.eliminado_at IS NULL
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


CREATE OR REPLACE FUNCTION public.cl_resumen_campana(p_evento_id uuid)
RETURNS TABLE (total bigint, empresas bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
BEGIN
  IF p_evento_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'Campaña inválida';
  END IF;

  IF NOT public.cl_campana_autorizada(p_evento_id) THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'Sin acceso al resumen de la campaña';
  END IF;

  RETURN QUERY
  SELECT
    count(*)::bigint AS total,
    count(*) FILTER (
      WHERE nullif(btrim(l.empresa), '') IS NOT NULL
    )::bigint AS empresas
  FROM public.leads l
  WHERE l.evento_id = p_evento_id
    AND l.eliminado_at IS NULL;
END;
$$;


CREATE OR REPLACE FUNCTION public.cl_buscar_lead_por_email(
  p_evento_id uuid,
  p_email text
)
RETURNS TABLE (
  lead_id uuid,
  capturador_nombre text,
  es_propio boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_usuario_id uuid := auth.uid();
  v_rol text;
  v_activo boolean;
  v_email_normalizado text := NULLIF(lower(btrim(p_email)), '');
  v_existente public.leads%ROWTYPE;
BEGIN
  IF v_usuario_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'No autenticado';
  END IF;

  SELECT p.rol, p.activo
  INTO v_rol, v_activo
  FROM public.perfiles p
  WHERE p.id = v_usuario_id;

  IF NOT FOUND OR v_activo IS NOT TRUE THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Usuario inactivo o sin perfil';
  END IF;

  IF p_evento_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.eventos_leads el WHERE el.id = p_evento_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'Campaña no encontrada';
  END IF;

  IF NOT public.cl_campana_autorizada(p_evento_id) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Sin acceso a la campaña';
  END IF;

  IF v_email_normalizado IS NULL THEN
    RETURN;
  END IF;

  SELECT l.* INTO v_existente
  FROM public.leads l
  WHERE l.evento_id = p_evento_id
    AND NULLIF(lower(btrim(l.email)), '') = v_email_normalizado
    AND l.eliminado_at IS NULL
  ORDER BY l.created_at NULLS LAST, l.id
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  lead_id := v_existente.id;
  capturador_nombre := v_existente.capturador_nombre;
  es_propio := v_existente.perfil_id = v_usuario_id;
  RETURN NEXT;
END;
$$;

-- Borrado lógico de un lead: admin o quien lo capturó.
CREATE OR REPLACE FUNCTION public.cl_eliminar_lead(p_lead_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_usuario_id uuid := auth.uid();
  v_activo boolean;
  v_lead public.leads%ROWTYPE;
BEGIN
  IF v_usuario_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'No autenticado';
  END IF;

  SELECT p.activo INTO v_activo
  FROM public.perfiles p
  WHERE p.id = v_usuario_id;

  IF NOT FOUND OR v_activo IS NOT TRUE THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Usuario inactivo o sin perfil';
  END IF;

  SELECT l.* INTO v_lead
  FROM public.leads l
  WHERE l.id = p_lead_id
  FOR UPDATE;

  -- Ya no existe o ya estaba borrado: un reintento de la cola offline no
  -- puede quedar fallando para siempre.
  IF NOT FOUND OR v_lead.eliminado_at IS NOT NULL THEN
    RETURN;
  END IF;

  IF NOT public.cl_campana_autorizada(v_lead.evento_id) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Sin acceso a la campaña';
  END IF;

  IF NOT public.rpe_is_admin()
     AND v_lead.perfil_id IS DISTINCT FROM v_usuario_id THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Solo puedes eliminar tus propios leads';
  END IF;

  UPDATE public.leads
  SET eliminado_at = now(),
      eliminado_por = v_usuario_id
  WHERE id = p_lead_id;
END;
$$;

REVOKE ALL ON FUNCTION public.cl_eliminar_lead(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cl_eliminar_lead(uuid) TO authenticated;
