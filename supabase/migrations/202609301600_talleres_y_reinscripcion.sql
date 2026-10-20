-- Talleres y reinscripción. Idempotente.
--
-- 1. Un evento que ya tiene talleres no puede pasar a tipo taller (se perdería su programa).
-- 2. Un taller no puede tener talleres propios (solo un evento agrupa talleres).
-- 3. rpe_publico_registrar: si el correo ya está inscrito en el evento responde
--    {ok:false, motivo:'ya_inscrito'} sin escribir ni reenviar el QR. Antes sumaba talleres
--    y reenviaba; modificar una inscripción será un flujo aparte (enlace por correo).

CREATE OR REPLACE FUNCTION public.rpe_eventos_tipo_con_talleres()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.tipo = 'taller' AND OLD.tipo IS DISTINCT FROM 'taller'
     AND EXISTS (SELECT 1 FROM public.subeventos s WHERE s.evento_id = NEW.id) THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'RPE_EVENTO_CON_TALLERES',
      HINT = 'Este evento tiene talleres: quítalos antes de convertirlo en taller.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_eventos_tipo_con_talleres ON public.eventos;
CREATE TRIGGER trg_eventos_tipo_con_talleres
  BEFORE UPDATE OF tipo ON public.eventos
  FOR EACH ROW EXECUTE FUNCTION public.rpe_eventos_tipo_con_talleres();

CREATE OR REPLACE FUNCTION public.rpe_subeventos_en_evento_principal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.eventos e WHERE e.id = NEW.evento_id AND e.tipo = 'taller') THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'RPE_TALLER_SIN_TALLERES',
      HINT = 'Un taller no puede tener talleres propios: agrégalo a un evento.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_subeventos_en_evento_principal ON public.subeventos;
CREATE TRIGGER trg_subeventos_en_evento_principal
  BEFORE INSERT OR UPDATE OF evento_id ON public.subeventos
  FOR EACH ROW EXECUTE FUNCTION public.rpe_subeventos_en_evento_principal();

REVOKE ALL ON FUNCTION public.rpe_eventos_tipo_con_talleres() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpe_subeventos_en_evento_principal() FROM PUBLIC, anon, authenticated;

-- CREATE OR REPLACE conserva los permisos (anon, authenticated).
CREATE OR REPLACE FUNCTION public.rpe_publico_registrar(
  p_slug text,
  p_datos jsonb,
  p_subeventos text[] DEFAULT '{}'
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_evento public.eventos%ROWTYPE;
  v_datos jsonb;
  v_codigos text[];
  v_codigo text;
  v_sub public.subeventos%ROWTYPE;
  v_rechazados jsonb := '[]'::jsonb;
  v_ids uuid[] := '{}';
  v_map jsonb := '{}'::jsonb;
  v_hoy date;
  v_reg public.registrados%ROWTYPE;
  v_ya text[] := '{}';
  v_nuevos uuid[] := '{}';
  v_nuevos_codigos text[] := '{}';
  v_disp int;
  v_ins jsonb;
  v_envio text;
  v_motivo text;
  v_resultado text;
  v_el jsonb;
BEGIN
  SELECT * INTO v_evento FROM public.eventos e WHERE e.slug = lower(btrim(COALESCE(p_slug, '')));
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'RPE_EVENTO_NO_ENCONTRADO';
  END IF;
  IF NOT public.rpe_evento_registro_abierto(v_evento) THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'registro_cerrado', 'rechazados', '[]'::jsonb);
  END IF;

  PERFORM set_config('rpe.pais_evento', v_evento.pais, true);
  v_datos := public.rpe_validar_datos_asistente(p_datos, false);

  -- Correo ya inscrito en el evento: no se escribe ni se reenvía nada. La web avisa y ofrece
  -- modificar la inscripción con un enlace por correo (flujo aparte).
  IF EXISTS (
    SELECT 1 FROM public.registrados r
    WHERE r.evento_id = v_evento.id AND r.email = v_datos->>'email'
  ) THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'ya_inscrito', 'rechazados', '[]'::jsonb);
  END IF;

  SELECT COALESCE(array_agg(DISTINCT c), '{}'::text[])
  INTO v_codigos
  FROM unnest(COALESCE(p_subeventos, '{}'::text[])) AS c
  WHERE btrim(c) <> '';
  IF cardinality(v_codigos) > 20 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'RPE_DATOS_INVALIDOS',
      DETAIL = '{"campo":"subeventos","regla":"largo"}';
  END IF;

  v_hoy := (now() AT TIME ZONE public.rpe_zona_horaria_pais(v_evento.pais))::date;
  FOREACH v_codigo IN ARRAY v_codigos LOOP
    SELECT * INTO v_sub FROM public.subeventos s
    WHERE s.evento_id = v_evento.id AND s.codigo = lower(btrim(v_codigo));
    IF NOT FOUND THEN
      v_rechazados := v_rechazados || jsonb_build_array(
        jsonb_build_object('codigo', lower(btrim(v_codigo)), 'motivo', 'no_existe'));
    ELSIF NOT v_sub.visible_publico OR v_sub.dia < v_hoy THEN
      v_rechazados := v_rechazados || jsonb_build_array(
        jsonb_build_object('codigo', v_sub.codigo, 'motivo', 'no_disponible'));
    ELSE
      v_ids := v_ids || v_sub.id;
      v_map := v_map || jsonb_build_object(v_sub.id::text, v_sub.codigo);
    END IF;
  END LOOP;
  IF jsonb_array_length(v_rechazados) > 0 THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'subeventos_rechazados', 'rechazados', v_rechazados);
  END IF;

  PERFORM public.rpe_lock_cupo_evento(v_evento.id);

  SELECT * INTO v_reg FROM public.registrados r
  WHERE r.evento_id = v_evento.id AND r.email = v_datos->>'email';

  IF NOT FOUND THEN
    v_disp := public.rpe_cupo_disponible_evento(v_evento.id);
    IF v_disp IS NOT NULL AND v_disp <= 0 THEN
      RETURN jsonb_build_object('ok', false, 'motivo', 'sin_cupo_evento', 'rechazados', '[]'::jsonb);
    END IF;

    BEGIN
      INSERT INTO public.registrados (
        evento_id, nombre_completo, email, empresa, cargo, telefono,
        origen, utm_source, utm_medium, utm_campaign, utm_content
      ) VALUES (
        v_evento.id, v_datos->>'nombre_completo', v_datos->>'email',
        v_datos->>'empresa', v_datos->>'cargo', v_datos->>'telefono',
        'publico', v_datos->>'utm_source', v_datos->>'utm_medium',
        v_datos->>'utm_campaign', v_datos->>'utm_content'
      ) RETURNING * INTO v_reg;

      v_ins := public.rpe_insertar_inscripciones(v_reg.id, v_evento.id, v_ids, 'publico', false);
      IF (v_ins->>'ok')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'RPE_INSCRIPCIONES_RECHAZADAS';
      END IF;
    EXCEPTION
      WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM = 'RPE_INSCRIPCIONES_RECHAZADAS' THEN
          v_rechazados := '[]'::jsonb;
          FOR v_el IN SELECT value FROM jsonb_array_elements(COALESCE(v_ins->'rechazados', '[]'::jsonb)) LOOP
            v_rechazados := v_rechazados || jsonb_build_array(jsonb_build_object(
              'codigo', v_map->> (v_el->>'subevento_id'),
              'motivo', v_el->>'motivo'
            ));
          END LOOP;
          RETURN jsonb_build_object('ok', false, 'motivo', 'subeventos_rechazados', 'rechazados', v_rechazados);
        END IF;
        RAISE;
    END;

    v_envio := public.rpe_encolar_envio_qr(v_reg.id, ARRAY['email', 'sms'], 'registro', 'publico');
    SELECT COALESCE(array_agg(v_map->>x), '{}'::text[]) INTO v_nuevos_codigos
    FROM jsonb_array_elements_text(COALESCE(v_ins->'agregados', '[]'::jsonb)) AS x;
    RETURN jsonb_build_object(
      'ok', true, 'resultado', 'inscrito',
      'agregados', to_jsonb(v_nuevos_codigos),
      'ya_inscrito_en', '[]'::jsonb,
      'envio', v_envio
    );
  END IF;

  v_ya := ARRAY(
    SELECT s.codigo
    FROM public.subeventos s
    WHERE s.id = ANY (v_ids)
      AND EXISTS (
        SELECT 1 FROM public.inscripciones_subevento i
        WHERE i.registrado_id = v_reg.id AND i.subevento_id = s.id
      )
  );
  SELECT COALESCE(array_agg(s.id ORDER BY s.id), '{}'::uuid[]) INTO v_nuevos
  FROM public.subeventos s
  WHERE s.id = ANY (v_ids)
    AND NOT EXISTS (
      SELECT 1 FROM public.inscripciones_subevento i
      WHERE i.registrado_id = v_reg.id AND i.subevento_id = s.id
    );

  IF cardinality(v_nuevos) = 0 THEN
    v_resultado := 'sin_cambios';
    v_motivo := 'reenvio';
    v_ins := jsonb_build_object('agregados', '[]'::jsonb);
  ELSE
    v_ins := public.rpe_insertar_inscripciones(v_reg.id, v_evento.id, v_nuevos, 'publico', false);
    IF (v_ins->>'ok')::boolean IS NOT TRUE THEN
      v_rechazados := '[]'::jsonb;
      FOR v_el IN SELECT value FROM jsonb_array_elements(COALESCE(v_ins->'rechazados', '[]'::jsonb)) LOOP
        v_rechazados := v_rechazados || jsonb_build_array(jsonb_build_object(
          'codigo', v_map->> (v_el->>'subevento_id'),
          'motivo', v_el->>'motivo'
        ));
      END LOOP;
      RETURN jsonb_build_object('ok', false, 'motivo', 'subeventos_rechazados', 'rechazados', v_rechazados);
    END IF;
    v_resultado := 'actualizado';
    v_motivo := 'talleres_agregados';
  END IF;

  v_envio := public.rpe_encolar_envio_qr(v_reg.id, ARRAY['email', 'sms'], v_motivo, 'publico');
  SELECT COALESCE(array_agg(v_map->>x), '{}'::text[]) INTO v_nuevos_codigos
  FROM jsonb_array_elements_text(COALESCE(v_ins->'agregados', '[]'::jsonb)) AS x;
  RETURN jsonb_build_object(
    'ok', true,
    'resultado', v_resultado,
    'agregados', to_jsonb(v_nuevos_codigos),
    'ya_inscrito_en', to_jsonb(v_ya),
    'envio', v_envio
  );
END;
$$;
