-- Completa columnas de auditoría que el schema declarativo y los triggers de
-- acreditación ya utilizan, pero que faltaban en la instancia productiva
-- legacy. Idempotente y segura para filas existentes.

BEGIN;

ALTER TABLE public.registrados
  ADD COLUMN IF NOT EXISTS acreditado_en timestamptz;
ALTER TABLE public.registrados
  ADD COLUMN IF NOT EXISTS updated_at timestamptz
  NOT NULL DEFAULT timezone('utc', now());
ALTER TABLE public.registrados
  ADD COLUMN IF NOT EXISTS origen text
  NOT NULL DEFAULT 'app';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.registrados'::regclass
      AND conname = 'registrados_origen_check'
  ) THEN
    ALTER TABLE public.registrados
      ADD CONSTRAINT registrados_origen_check
      CHECK (origen = ANY (ARRAY['app', 'excel', 'publico']));
  END IF;
END $$;

DROP POLICY IF EXISTS rpe_registrados_insert_publico ON public.registrados;
CREATE POLICY rpe_registrados_insert_publico ON public.registrados
  FOR INSERT TO anon
  WITH CHECK (
    origen = 'publico'
    AND acreditado = false
    AND ingresado_por IS NULL
    AND EXISTS (
      SELECT 1
      FROM public.eventos e
      WHERE e.id = evento_id AND e.activo = true
    )
  );

COMMIT;
