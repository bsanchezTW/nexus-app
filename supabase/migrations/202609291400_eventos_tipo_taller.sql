-- Separa la ficha en evento principal o taller. El principal elige talleres
-- ya creados y los guarda como subeventos, sin borrar la ficha de origen.

ALTER TABLE public.eventos
  ADD COLUMN IF NOT EXISTS tipo text NOT NULL DEFAULT 'evento';

ALTER TABLE public.eventos
  DROP CONSTRAINT IF EXISTS eventos_tipo_check;

ALTER TABLE public.eventos
  ADD CONSTRAINT eventos_tipo_check
  CHECK (tipo IN ('evento', 'taller'));

ALTER TABLE public.subeventos
  ADD COLUMN IF NOT EXISTS evento_origen_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'subeventos_evento_origen_id_fkey'
  ) THEN
    ALTER TABLE public.subeventos
      ADD CONSTRAINT subeventos_evento_origen_id_fkey
      FOREIGN KEY (evento_origen_id) REFERENCES public.eventos (id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'subeventos_origen_distinto'
  ) THEN
    ALTER TABLE public.subeventos
      ADD CONSTRAINT subeventos_origen_distinto
      CHECK (evento_origen_id IS NULL OR evento_origen_id <> evento_id);
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS subeventos_evento_origen_unique
  ON public.subeventos (evento_id, evento_origen_id)
  WHERE evento_origen_id IS NOT NULL;
