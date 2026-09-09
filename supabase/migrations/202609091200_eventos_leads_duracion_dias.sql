-- Duración de una actividad de captura: [fecha] es el primer día.
-- Puede durar 1 día, 3 días o más (hasta un año). No se hereda del evento
-- de registro: las internas también la editan en la ficha de captura.
-- Idempotente: también vive en supabase/schema.sql.

ALTER TABLE public.eventos_leads
  ADD COLUMN IF NOT EXISTS duracion_dias integer NOT NULL DEFAULT 1;

ALTER TABLE public.eventos_leads
  DROP CONSTRAINT IF EXISTS eventos_leads_duracion_dias_check;
ALTER TABLE public.eventos_leads
  ADD CONSTRAINT eventos_leads_duracion_dias_check
  CHECK (duracion_dias >= 1 AND duracion_dias <= 366);
