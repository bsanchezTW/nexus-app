-- La vigencia de un evento de registro la marca su rango de fechas
-- (fecha + duracion_dias). Se elimina eventos.activo.
-- Corre después de 202609091500 (rpe_fecha_termino_evento).
-- Idempotente: también vive en supabase/schema.sql.

DROP POLICY IF EXISTS rpe_eventos_select_publico ON public.eventos;
CREATE POLICY rpe_eventos_select_publico ON public.eventos
  FOR SELECT TO anon USING (true);

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

DROP INDEX IF EXISTS idx_eventos_activo_fecha;
CREATE INDEX IF NOT EXISTS idx_eventos_fecha ON public.eventos (fecha DESC);

ALTER TABLE public.eventos DROP COLUMN IF EXISTS activo;
