-- Restricciones incrementales para Usuario Externo.
-- Idempotente: puede ejecutarse sobre una instalación existente después de
-- haber aplicado `schema.sql` o migraciones previas.

BEGIN;

-- Backfill para perfiles externos legacy. Sin esta fila, la UI conoce el
-- evento preferido pero RLS no lo considera una autorización operativa.
INSERT INTO public.usuarios_eventos (usuario_id, evento_id, rol_evento)
SELECT p.id, p.evento_asignado_id, 'externo'
FROM public.perfiles p
WHERE p.rol = 'externo'
  AND p.evento_asignado_id IS NOT NULL
ON CONFLICT (usuario_id, evento_id) DO NOTHING;

-- Un externo solo puede acreditar desde el escáner. Este trigger mantiene
-- compatible la cola offline (`UPDATE {acreditado: true}`) y completa la
-- auditoría en servidor.
CREATE OR REPLACE FUNCTION public.rpe_restrict_externo_registrado_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NOT public.rpe_is_externo() THEN
    RETURN NEW;
  END IF;

  IF NEW.acreditado IS NOT TRUE THEN
    RAISE EXCEPTION 'El usuario externo solo puede acreditar asistentes';
  END IF;

  IF (to_jsonb(NEW) - ARRAY[
        'acreditado', 'acreditado_en', 'acreditado_por', 'updated_at'
      ]) IS DISTINCT FROM
     (to_jsonb(OLD) - ARRAY[
        'acreditado', 'acreditado_en', 'acreditado_por', 'updated_at'
      ]) THEN
    RAISE EXCEPTION 'El usuario externo no puede editar datos del asistente';
  END IF;

  -- Idempotencia para cola offline y escáneres concurrentes: si otra sesión ya
  -- acreditó la fila, aceptar el no-op sin alterar quién/cuándo lo hizo.
  IF OLD.acreditado IS TRUE THEN
    NEW.acreditado := TRUE;
    NEW.acreditado_por := OLD.acreditado_por;
    NEW.acreditado_en := OLD.acreditado_en;
    RETURN NEW;
  END IF;

  IF NEW.acreditado_por IS NOT NULL AND NEW.acreditado_por <> auth.uid() THEN
    RAISE EXCEPTION 'La acreditación debe quedar asociada al usuario actual';
  END IF;

  NEW.acreditado_por := auth.uid();
  NEW.acreditado_en := timezone('utc', now());
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_registrados_restrict_externo_update
  ON public.registrados;
CREATE TRIGGER trg_registrados_restrict_externo_update
  BEFORE UPDATE ON public.registrados
  FOR EACH ROW EXECUTE FUNCTION public.rpe_restrict_externo_registrado_update();

-- Registrar asistentes queda reservado a usuarios internos. La policy `anon`
-- de autoregistro público permanece independiente y no se modifica.
DROP POLICY IF EXISTS rpe_registrados_insert ON public.registrados;
CREATE POLICY rpe_registrados_insert ON public.registrados
  FOR INSERT TO authenticated
  WITH CHECK (public.rpe_is_internal_user());

-- La RPC SECURITY DEFINER también valida el rol porque no depende de RLS.
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
  ON CONFLICT (usuario_id, notificacion_id) DO NOTHING;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpe_ocultar_todas_notificaciones()
  TO authenticated;

DROP POLICY IF EXISTS rpe_notificaciones_select ON public.notificaciones;
CREATE POLICY rpe_notificaciones_select ON public.notificaciones
  FOR SELECT TO authenticated USING (public.rpe_is_internal_user());

DROP POLICY IF EXISTS rpe_notificaciones_leidas_select
  ON public.notificaciones_leidas;
CREATE POLICY rpe_notificaciones_leidas_select ON public.notificaciones_leidas
  FOR SELECT TO authenticated
  USING (usuario_id = auth.uid() AND public.rpe_is_internal_user());

DROP POLICY IF EXISTS rpe_notificaciones_leidas_insert
  ON public.notificaciones_leidas;
CREATE POLICY rpe_notificaciones_leidas_insert ON public.notificaciones_leidas
  FOR INSERT TO authenticated
  WITH CHECK (usuario_id = auth.uid() AND public.rpe_is_internal_user());

DROP POLICY IF EXISTS rpe_notificaciones_leidas_update
  ON public.notificaciones_leidas;
CREATE POLICY rpe_notificaciones_leidas_update ON public.notificaciones_leidas
  FOR UPDATE TO authenticated
  USING (usuario_id = auth.uid() AND public.rpe_is_internal_user())
  WITH CHECK (usuario_id = auth.uid() AND public.rpe_is_internal_user());

DROP POLICY IF EXISTS rpe_notificaciones_ocultas_select
  ON public.notificaciones_ocultas;
CREATE POLICY rpe_notificaciones_ocultas_select ON public.notificaciones_ocultas
  FOR SELECT TO authenticated
  USING (usuario_id = auth.uid() AND public.rpe_is_internal_user());

DROP POLICY IF EXISTS rpe_notificaciones_ocultas_insert
  ON public.notificaciones_ocultas;
CREATE POLICY rpe_notificaciones_ocultas_insert ON public.notificaciones_ocultas
  FOR INSERT TO authenticated
  WITH CHECK (usuario_id = auth.uid() AND public.rpe_is_internal_user());

DROP POLICY IF EXISTS rpe_notificaciones_ocultas_delete
  ON public.notificaciones_ocultas;
CREATE POLICY rpe_notificaciones_ocultas_delete ON public.notificaciones_ocultas
  FOR DELETE TO authenticated
  USING (usuario_id = auth.uid() AND public.rpe_is_internal_user());

DROP POLICY IF EXISTS rpe_device_tokens_select ON public.device_tokens;
CREATE POLICY rpe_device_tokens_select ON public.device_tokens
  FOR SELECT TO authenticated
  USING (usuario_id = auth.uid() AND public.rpe_is_internal_user());

DROP POLICY IF EXISTS rpe_device_tokens_insert ON public.device_tokens;
CREATE POLICY rpe_device_tokens_insert ON public.device_tokens
  FOR INSERT TO authenticated
  WITH CHECK (usuario_id = auth.uid() AND public.rpe_is_internal_user());

DROP POLICY IF EXISTS rpe_device_tokens_update ON public.device_tokens;
CREATE POLICY rpe_device_tokens_update ON public.device_tokens
  FOR UPDATE TO authenticated
  USING (usuario_id = auth.uid() AND public.rpe_is_internal_user())
  WITH CHECK (usuario_id = auth.uid() AND public.rpe_is_internal_user());

-- Se conserva DELETE propio para que al degradar un usuario a externo la app
-- pueda retirar tokens creados cuando todavía era interno.
DROP POLICY IF EXISTS rpe_device_tokens_delete ON public.device_tokens;
CREATE POLICY rpe_device_tokens_delete ON public.device_tokens
  FOR DELETE TO authenticated USING (usuario_id = auth.uid());

COMMIT;
