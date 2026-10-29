-- Conteos de campaña (total de leads y leads con empresa) para todos los
-- roles internos, sin exponer filas ajenas. SECURITY DEFINER evita que RLS
-- recorte el SELECT a "mis leads" para AppRole.user.

BEGIN;

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

  IF NOT public.rpe_is_internal_user() THEN
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
  WHERE l.evento_id = p_evento_id;
END;
$$;

REVOKE ALL ON FUNCTION public.cl_resumen_campana(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cl_resumen_campana(uuid) TO authenticated;

COMMIT;
