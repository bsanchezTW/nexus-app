-- Correcciones de la revisión 1. Idempotente.
-- No modifica 202609251200_subeventos_cupos_ids_opacos.sql.

DROP FUNCTION IF EXISTS public.rpe_validar_datos_asistente(jsonb, boolean);

CREATE OR REPLACE FUNCTION public.rpe_validar_datos_asistente(
  p_datos jsonb,
  p_exigir_certificacion boolean,
  p_certificacion_opcional boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_nombre text;
  v_email text;
  v_empresa text;
  v_cargo text;
  v_telefono text;
  v_digitos text;
  v_local text;
  v_dominio text;
  v_label text;
  v_pais text := COALESCE(current_setting('rpe.pais_evento', true), 'Chile');
  v_rut text;
  v_compacto text;
  v_cuerpo text;
  v_dv text;
  v_esperado text;
  v_suma int := 0;
  v_mul int := 2;
  i int;
  v_patente text;
  v_utm text;
  v_clave text;
  v_out jsonb;
BEGIN
  IF p_datos IS NULL OR jsonb_typeof(p_datos) <> 'object' THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023', MESSAGE = 'RPE_DATOS_INVALIDOS',
      DETAIL = '{"campo":"datos","regla":"objeto"}',
      HINT = 'Los datos del asistente no son válidos.';
  END IF;

  v_nombre := public.rpe_a_title_case(p_datos->>'nombre_completo');
  IF v_nombre = ''
     OR array_length(regexp_split_to_array(v_nombre, ' '), 1) < 2
     OR EXISTS (
       SELECT 1 FROM unnest(regexp_split_to_array(v_nombre, ' ')) AS w(palabra)
       WHERE char_length(replace(w.palabra, '-', '')) < 2
     ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023', MESSAGE = 'RPE_DATOS_INVALIDOS',
      DETAIL = '{"campo":"nombre_completo","regla":"formato"}',
      HINT = 'Ingresa nombre y apellido.';
  END IF;

  v_email := lower(btrim(COALESCE(p_datos->>'email', '')));
  IF v_email = '' OR char_length(v_email) > 254 OR position(' ' IN v_email) > 0
     OR v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]{2,}$' THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023', MESSAGE = 'RPE_DATOS_INVALIDOS',
      DETAIL = '{"campo":"email","regla":"formato"}',
      HINT = 'El email no es válido.';
  END IF;
  v_local := split_part(v_email, '@', 1);
  v_dominio := split_part(v_email, '@', 2);
  IF split_part(v_email, '@', 3) <> ''
     OR position('..' IN v_email) > 0
     OR v_local !~ '^[a-z0-9]([a-z0-9._%+-]*[a-z0-9])?$' THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023', MESSAGE = 'RPE_DATOS_INVALIDOS',
      DETAIL = '{"campo":"email","regla":"formato"}',
      HINT = 'El email no es válido.';
  END IF;
  IF array_length(regexp_split_to_array(v_dominio, '\.'), 1) < 2 THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023', MESSAGE = 'RPE_DATOS_INVALIDOS',
      DETAIL = '{"campo":"email","regla":"formato"}',
      HINT = 'El email no es válido.';
  END IF;
  FOR v_label IN SELECT unnest(regexp_split_to_array(v_dominio, '\.')) LOOP
    IF v_label !~ '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$' THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023', MESSAGE = 'RPE_DATOS_INVALIDOS',
        DETAIL = '{"campo":"email","regla":"formato"}',
        HINT = 'El email no es válido.';
    END IF;
  END LOOP;
  IF regexp_replace(v_dominio, '^.*\.', '') !~ '^[a-z]{2,}$' THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023', MESSAGE = 'RPE_DATOS_INVALIDOS',
      DETAIL = '{"campo":"email","regla":"formato"}',
      HINT = 'El email no es válido.';
  END IF;

  v_empresa := regexp_replace(btrim(COALESCE(p_datos->>'empresa', '')), '\s+', ' ', 'g');
  IF v_empresa = '' THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023', MESSAGE = 'RPE_DATOS_INVALIDOS',
      DETAIL = '{"campo":"empresa","regla":"requerido"}',
      HINT = 'La empresa es obligatoria.';
  END IF;

  v_cargo := public.rpe_a_title_case(p_datos->>'cargo');
  IF v_cargo = '' THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023', MESSAGE = 'RPE_DATOS_INVALIDOS',
      DETAIL = '{"campo":"cargo","regla":"requerido"}',
      HINT = 'El cargo es obligatorio.';
  END IF;

  v_telefono := btrim(COALESCE(p_datos->>'telefono', ''));
  v_digitos := regexp_replace(v_telefono, '\D', '', 'g');
  IF char_length(v_digitos) < 8 OR char_length(v_digitos) > 15 THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023', MESSAGE = 'RPE_DATOS_INVALIDOS',
      DETAIL = '{"campo":"telefono","regla":"formato"}',
      HINT = 'El teléfono debe tener entre 8 y 15 dígitos.';
  END IF;

  v_out := jsonb_build_object(
    'nombre_completo', v_nombre,
    'email', v_email,
    'empresa', v_empresa,
    'cargo', v_cargo,
    'telefono', v_telefono
  );

  FOREACH v_clave IN ARRAY ARRAY['utm_source', 'utm_medium', 'utm_campaign', 'utm_content'] LOOP
    v_utm := NULLIF(btrim(COALESCE(p_datos->>v_clave, '')), '');
    IF v_utm IS NOT NULL AND char_length(v_utm) > 100 THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023', MESSAGE = 'RPE_DATOS_INVALIDOS',
        DETAIL = format('{"campo":"%s","regla":"largo"}', v_clave),
        HINT = 'Un parámetro UTM supera el largo permitido.';
    END IF;
    v_out := v_out || jsonb_build_object(v_clave, v_utm);
  END LOOP;

  IF COALESCE(p_exigir_certificacion, false) THEN
    IF NOT (COALESCE(p_certificacion_opcional, false) AND btrim(COALESCE(p_datos->>'rut', '')) = '') THEN
    IF v_pais = 'Perú' THEN
      v_compacto := upper(regexp_replace(btrim(COALESCE(p_datos->>'rut', '')), '[\s.\-]', '', 'g'));
      IF v_compacto !~ '^[A-Z0-9]{5,20}$' THEN
        RAISE EXCEPTION USING
          ERRCODE = '22023', MESSAGE = 'RPE_DATOS_INVALIDOS',
          DETAIL = '{"campo":"rut","regla":"formato"}',
          HINT = 'El RUC no es válido.';
      END IF;
      v_rut := v_compacto;
    ELSE
      v_compacto := regexp_replace(upper(btrim(COALESCE(p_datos->>'rut', ''))), '[^0-9K]', '', 'g');
      IF v_compacto !~ '^[0-9]{7,9}[0-9K]$' THEN
        RAISE EXCEPTION USING
          ERRCODE = '22023', MESSAGE = 'RPE_DATOS_INVALIDOS',
          DETAIL = '{"campo":"rut","regla":"formato"}',
          HINT = 'El RUT no es válido.';
      END IF;
      v_cuerpo := substr(v_compacto, 1, char_length(v_compacto) - 1);
      v_dv := right(v_compacto, 1);
      FOR i IN REVERSE char_length(v_cuerpo)..1 LOOP
        v_suma := v_suma + substr(v_cuerpo, i, 1)::int * v_mul;
        v_mul := CASE WHEN v_mul = 7 THEN 2 ELSE v_mul + 1 END;
      END LOOP;
      v_esperado := CASE
        WHEN (11 - (v_suma % 11)) = 11 THEN '0'
        WHEN (11 - (v_suma % 11)) = 10 THEN 'K'
        ELSE (11 - (v_suma % 11))::text
      END;
      IF v_dv IS DISTINCT FROM v_esperado THEN
        RAISE EXCEPTION USING
          ERRCODE = '22023', MESSAGE = 'RPE_DATOS_INVALIDOS',
          DETAIL = '{"campo":"rut","regla":"formato"}',
          HINT = 'El RUT no es válido.';
      END IF;
      v_rut := v_compacto;
    END IF;
    END IF;

    IF NOT (COALESCE(p_certificacion_opcional, false) AND btrim(COALESCE(p_datos->>'patente', '')) = '') THEN
    v_patente := upper(regexp_replace(btrim(COALESCE(p_datos->>'patente', '')), '[^A-Za-z0-9]', '', 'g'));
    IF v_patente !~ '^[A-Z]{4}[0-9]{2}$' AND v_patente !~ '^[A-Z]{2}[0-9]{4}$' THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023', MESSAGE = 'RPE_DATOS_INVALIDOS',
        DETAIL = '{"campo":"patente","regla":"formato"}',
        HINT = 'La patente no es válida.';
    END IF;
    END IF;
    IF v_rut IS NOT NULL OR v_patente IS NOT NULL THEN
      v_out := v_out || jsonb_build_object('rut', v_rut, 'patente', v_patente);
    END IF;
  END IF;

  RETURN v_out;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpe_registrar_asistente(
  p_evento_id uuid,
  p_datos jsonb,
  p_subevento_ids uuid[] DEFAULT '{}',
  p_acreditar boolean DEFAULT false,
  p_forzar_sobrecupo boolean DEFAULT false,
  p_enviar_qr boolean DEFAULT true
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
  v_forzar boolean;
  v_puede boolean;
  v_disp int;
  v_existente uuid;
  v_reg_id uuid;
  v_ins jsonb;
  v_sobrecupo boolean := false;
  v_envio text := 'no_solicitado';
  v_codigo text;
BEGIN
  IF NOT (public.rpe_is_internal_user() AND public.rpe_puede_operar_evento(p_evento_id)) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'RPE_NO_AUTORIZADO',
      HINT = 'No tienes permiso para registrar asistentes en este evento.';
  END IF;

  SELECT * INTO v_evento FROM public.eventos e WHERE e.id = p_evento_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'RPE_EVENTO_NO_ENCONTRADO';
  END IF;
  IF NOT public.rpe_evento_vigente(v_evento) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'RPE_EVENTO_FINALIZADO',
      HINT = 'El evento ya finalizó.';
  END IF;

  v_puede := public.rpe_can_create_content();
  v_forzar := COALESCE(p_forzar_sobrecupo, false) AND v_puede;
  PERFORM set_config('rpe.pais_evento', v_evento.pais, true);
  v_datos := public.rpe_validar_datos_asistente(
    p_datos, v_evento.certificacion_capacitacion, false);

  PERFORM public.rpe_lock_cupo_evento(p_evento_id);

  SELECT r.id INTO v_existente
  FROM public.registrados r
  WHERE r.evento_id = p_evento_id AND r.email = v_datos->>'email';
  IF FOUND THEN
    RETURN jsonb_build_object(
      'ok', false,
      'motivo', 'email_duplicado',
      'registrado_id_existente', v_existente,
      'puede_forzar', false
    );
  END IF;

  v_disp := public.rpe_cupo_disponible_evento(p_evento_id);
  IF v_disp IS NOT NULL AND v_disp <= 0 AND NOT v_forzar THEN
    RETURN jsonb_build_object(
      'ok', false,
      'motivo', 'sin_cupo_evento',
      'puede_forzar', v_puede
    );
  END IF;

  v_reg_id := gen_random_uuid();
  v_sobrecupo := v_disp IS NOT NULL AND v_disp <= 0;

  BEGIN
    INSERT INTO public.registrados (
      id, evento_id, nombre_completo, email, empresa, cargo, telefono,
      rut, patente, origen, ingresado_por, acreditado, acreditado_por,
      sobrecupo, utm_source, utm_medium, utm_campaign, utm_content
    ) VALUES (
      v_reg_id, p_evento_id,
      v_datos->>'nombre_completo', v_datos->>'email', v_datos->>'empresa',
      v_datos->>'cargo', v_datos->>'telefono',
      v_datos->>'rut', v_datos->>'patente',
      'app', auth.uid(), COALESCE(p_acreditar, false),
      CASE WHEN COALESCE(p_acreditar, false) THEN auth.uid() ELSE NULL END,
      v_sobrecupo,
      v_datos->>'utm_source', v_datos->>'utm_medium',
      v_datos->>'utm_campaign', v_datos->>'utm_content'
    );

    v_ins := public.rpe_insertar_inscripciones(
      v_reg_id, p_evento_id, p_subevento_ids, 'app', v_forzar);
    IF (v_ins->>'ok')::boolean IS NOT TRUE THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'RPE_INSCRIPCIONES_RECHAZADAS';
    END IF;
  EXCEPTION
    WHEN SQLSTATE 'P0001' THEN
      IF SQLERRM = 'RPE_INSCRIPCIONES_RECHAZADAS' THEN
        RETURN jsonb_build_object(
          'ok', false,
          'motivo', 'subeventos_rechazados',
          'rechazados', COALESCE(v_ins->'rechazados', '[]'::jsonb),
          'puede_forzar', v_puede AND NOT EXISTS (
            SELECT 1
            FROM jsonb_array_elements(COALESCE(v_ins->'rechazados', '[]'::jsonb)) el
            WHERE el->>'motivo' IS DISTINCT FROM 'sin_cupo'
          )
        );
      END IF;
      RAISE;
  END;

  SELECT r.codigo_qr INTO v_codigo FROM public.registrados r WHERE r.id = v_reg_id;
  SELECT v_sobrecupo OR EXISTS (
    SELECT 1 FROM public.inscripciones_subevento i
    WHERE i.registrado_id = v_reg_id AND i.sobrecupo
  ) INTO v_sobrecupo;

  IF COALESCE(p_enviar_qr, false) THEN
    v_envio := public.rpe_encolar_envio_qr(
      v_reg_id, ARRAY['email', 'sms'], 'registro', 'app');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'registrado_id', v_reg_id,
    'codigo_qr', v_codigo,
    'sobrecupo', v_sobrecupo,
    'envio', v_envio
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.rpe_importar_registrados(
  p_evento_id uuid,
  p_filas jsonb,
  p_forzar_sobrecupo boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_evento public.eventos%ROWTYPE;
  v_puede boolean;
  v_forzar boolean;
  v_fila jsonb;
  v_idx int := 0;
  v_datos jsonb;
  v_detalle text;
  v_sqlstate text;
  v_invalidos jsonb := '[]'::jsonb;
  v_validos jsonb := '[]'::jsonb;
  v_vistos text[] := '{}';
  v_omitidos int := 0;
  v_insertados int := 0;
  v_disp int;
  v_nuevos int;
  v_email text;
  v_sobrecupo boolean;
  v_item jsonb;
BEGIN
  IF NOT (public.rpe_is_internal_user() AND public.rpe_puede_operar_evento(p_evento_id)) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'RPE_NO_AUTORIZADO';
  END IF;
  SELECT * INTO v_evento FROM public.eventos e WHERE e.id = p_evento_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'RPE_EVENTO_NO_ENCONTRADO';
  END IF;
  IF NOT public.rpe_evento_vigente(v_evento) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'RPE_EVENTO_FINALIZADO';
  END IF;
  IF p_filas IS NULL OR jsonb_typeof(p_filas) <> 'array' THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'RPE_DATOS_INVALIDOS',
      DETAIL = '{"campo":"filas","regla":"arreglo"}';
  END IF;

  v_puede := public.rpe_can_create_content();
  v_forzar := COALESCE(p_forzar_sobrecupo, false) AND v_puede;
  PERFORM set_config('rpe.pais_evento', v_evento.pais, true);

  FOR v_fila IN SELECT value FROM jsonb_array_elements(p_filas) LOOP
    v_idx := v_idx + 1;
    BEGIN
      v_datos := public.rpe_validar_datos_asistente(
        v_fila, v_evento.certificacion_capacitacion, true);
    EXCEPTION
      WHEN SQLSTATE '22023' THEN
        GET STACKED DIAGNOSTICS v_sqlstate = RETURNED_SQLSTATE, v_detalle = PG_EXCEPTION_DETAIL;
        IF SQLERRM = 'RPE_DATOS_INVALIDOS' THEN
          v_invalidos := v_invalidos || jsonb_build_array(
            COALESCE(v_detalle::jsonb, '{}'::jsonb) || jsonb_build_object('fila', v_idx));
          CONTINUE;
        END IF;
        RAISE;
    END;
    v_email := v_datos->>'email';
    IF v_email = ANY (v_vistos) OR EXISTS (
      SELECT 1 FROM public.registrados r
      WHERE r.evento_id = p_evento_id AND r.email = v_email
    ) THEN
      v_omitidos := v_omitidos + 1;
      CONTINUE;
    END IF;
    v_vistos := v_vistos || v_email;
    v_validos := v_validos || jsonb_build_array(v_datos);
  END LOOP;

  v_nuevos := jsonb_array_length(v_validos);
  PERFORM public.rpe_lock_cupo_evento(p_evento_id);
  v_disp := public.rpe_cupo_disponible_evento(p_evento_id);

  IF v_disp IS NOT NULL AND v_nuevos > GREATEST(v_disp, 0) AND NOT v_forzar THEN
    RETURN jsonb_build_object(
      'insertados', 0,
      'omitidos_duplicado', v_omitidos,
      'invalidos', v_invalidos,
      'excede_cupo', v_nuevos - GREATEST(v_disp, 0),
      'puede_forzar', v_puede
    );
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(v_validos) LOOP
    IF EXISTS (
      SELECT 1 FROM public.registrados r
      WHERE r.evento_id = p_evento_id AND r.email = v_item->>'email'
    ) THEN
      v_omitidos := v_omitidos + 1;
      CONTINUE;
    END IF;
    v_disp := public.rpe_cupo_disponible_evento(p_evento_id);
    v_sobrecupo := v_disp IS NOT NULL AND v_disp <= 0;
    INSERT INTO public.registrados (
      evento_id, nombre_completo, email, empresa, cargo, telefono,
      rut, patente, origen, ingresado_por, sobrecupo,
      utm_source, utm_medium, utm_campaign, utm_content
    ) VALUES (
      p_evento_id, v_item->>'nombre_completo', v_item->>'email',
      v_item->>'empresa', v_item->>'cargo', v_item->>'telefono',
      v_item->>'rut', v_item->>'patente', 'excel', auth.uid(), v_sobrecupo,
      v_item->>'utm_source', v_item->>'utm_medium',
      v_item->>'utm_campaign', v_item->>'utm_content'
    );
    v_insertados := v_insertados + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'insertados', v_insertados,
    'omitidos_duplicado', v_omitidos,
    'invalidos', v_invalidos,
    'excede_cupo', 0,
    'puede_forzar', false
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.rpe_inscribir_subevento(
  p_registrado_id uuid,
  p_subevento_id uuid,
  p_forzar_sobrecupo boolean DEFAULT false,
  p_marcar_asistencia boolean DEFAULT false,
  p_reemplazar_superpuestos boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_reg public.registrados%ROWTYPE;
  v_sub public.subeventos%ROWTYPE;
  v_puede boolean;
  v_forzar boolean;
  v_conflictos uuid[] := '{}';
  v_asistieron int;
  v_disp int;
  v_ins_id uuid;
  v_ya_asistio boolean := false;
  v_acredito boolean := false;
BEGIN
  SELECT * INTO v_reg FROM public.registrados r WHERE r.id = p_registrado_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'RPE_REGISTRADO_NO_ENCONTRADO';
  END IF;
  IF NOT (public.rpe_is_internal_user() AND public.rpe_puede_operar_evento(v_reg.evento_id)) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'RPE_NO_AUTORIZADO';
  END IF;

  SELECT * INTO v_sub FROM public.subeventos s
  WHERE s.id = p_subevento_id AND s.evento_id = v_reg.evento_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'RPE_SUBEVENTO_NO_ENCONTRADO';
  END IF;

  SELECT i.id, i.asistio INTO v_ins_id, v_ya_asistio
  FROM public.inscripciones_subevento i
  WHERE i.registrado_id = p_registrado_id AND i.subevento_id = p_subevento_id;
  IF FOUND THEN
    IF COALESCE(p_marcar_asistencia, false) AND NOT COALESCE(v_ya_asistio, false) THEN
      UPDATE public.inscripciones_subevento
      SET asistio = true, asistio_en = now(), asistio_por = auth.uid()
      WHERE id = v_ins_id;
      UPDATE public.registrados
      SET acreditado = true, acreditado_por = auth.uid()
      WHERE id = p_registrado_id AND NOT acreditado;
      v_acredito := FOUND OR EXISTS (
        SELECT 1 FROM public.registrados r WHERE r.id = p_registrado_id AND r.acreditado
      );
    ELSE
      SELECT r.acreditado INTO v_acredito
      FROM public.registrados r WHERE r.id = p_registrado_id;
    END IF;
    RETURN jsonb_build_object(
      'ok', true,
      'inscripcion_id', v_ins_id,
      'ya_inscrito', true,
      'acreditado_principal', COALESCE(v_acredito, false),
      'reemplazados', '[]'::jsonb
    );
  END IF;

  v_puede := public.rpe_can_create_content();
  v_forzar := COALESCE(p_forzar_sobrecupo, false) AND v_puede;
  PERFORM public.rpe_lock_cupo_subevento(p_subevento_id);

  SELECT COALESCE(array_agg(b.id ORDER BY b.id), '{}'::uuid[])
  INTO v_conflictos
  FROM public.inscripciones_subevento i
  JOIN public.subeventos b ON b.id = i.subevento_id
  WHERE i.registrado_id = p_registrado_id
    AND i.subevento_id <> p_subevento_id
    AND b.dia = v_sub.dia
    AND v_sub.hora_inicio < b.hora_fin
    AND b.hora_inicio < v_sub.hora_fin;

  IF cardinality(v_conflictos) > 0 THEN
    SELECT count(*) INTO v_asistieron
    FROM public.inscripciones_subevento i
    WHERE i.registrado_id = p_registrado_id
      AND i.subevento_id = ANY (v_conflictos)
      AND i.asistio;
    IF v_asistieron > 0 OR NOT COALESCE(p_reemplazar_superpuestos, false) THEN
      RETURN jsonb_build_object(
        'ok', false, 'motivo', 'superpuesto',
        'conflictos', to_jsonb(v_conflictos), 'puede_forzar', false);
    END IF;
    DELETE FROM public.inscripciones_subevento i
    WHERE i.registrado_id = p_registrado_id
      AND i.subevento_id = ANY (v_conflictos)
      AND NOT i.asistio;
  END IF;

  v_disp := public.rpe_cupo_disponible_subevento(p_subevento_id);
  IF v_disp IS NOT NULL AND v_disp <= 0 AND NOT v_forzar THEN
    RETURN jsonb_build_object(
      'ok', false, 'motivo', 'sin_cupo',
      'conflictos', '[]'::jsonb, 'puede_forzar', v_puede);
  END IF;

  INSERT INTO public.inscripciones_subevento (
    evento_id, registrado_id, subevento_id, origen, inscrito_por, sobrecupo,
    asistio, asistio_en, asistio_por
  ) VALUES (
    v_reg.evento_id, p_registrado_id, p_subevento_id, 'app', auth.uid(),
    v_disp IS NOT NULL AND v_disp <= 0,
    COALESCE(p_marcar_asistencia, false),
    CASE WHEN COALESCE(p_marcar_asistencia, false) THEN now() ELSE NULL END,
    CASE WHEN COALESCE(p_marcar_asistencia, false) THEN auth.uid() ELSE NULL END
  )
  RETURNING id INTO v_ins_id;

  IF COALESCE(p_marcar_asistencia, false) THEN
    UPDATE public.registrados
    SET acreditado = true, acreditado_por = auth.uid()
    WHERE id = p_registrado_id AND NOT acreditado;
    v_acredito := FOUND OR EXISTS (
      SELECT 1 FROM public.registrados r WHERE r.id = p_registrado_id AND r.acreditado
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'inscripcion_id', v_ins_id,
    'acreditado_principal', v_acredito,
    'reemplazados', to_jsonb(CASE WHEN COALESCE(p_reemplazar_superpuestos, false)
      THEN v_conflictos ELSE '{}'::uuid[] END)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.rpe_marcar_asistencia_subevento(
  p_registrado_id uuid,
  p_subevento_id uuid,
  p_asistio boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_evento_id uuid;
  v_ins public.inscripciones_subevento%ROWTYPE;
  v_acredito boolean := false;
BEGIN
  SELECT r.evento_id INTO v_evento_id FROM public.registrados r WHERE r.id = p_registrado_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'RPE_REGISTRADO_NO_ENCONTRADO';
  END IF;
  IF NOT public.rpe_puede_operar_evento(v_evento_id) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'RPE_NO_AUTORIZADO';
  END IF;

  SELECT * INTO v_ins FROM public.inscripciones_subevento i
  WHERE i.registrado_id = p_registrado_id AND i.subevento_id = p_subevento_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'no_inscrito');
  END IF;

  IF COALESCE(p_asistio, true) THEN
    IF v_ins.asistio THEN
      SELECT r.acreditado INTO v_acredito FROM public.registrados r WHERE r.id = p_registrado_id;
      RETURN jsonb_build_object('ok', true, 'estado', 'ya_marcado', 'acreditado_principal', v_acredito);
    END IF;
    UPDATE public.inscripciones_subevento
    SET asistio = true, asistio_en = now(), asistio_por = auth.uid()
    WHERE id = v_ins.id;
    UPDATE public.registrados
    SET acreditado = true, acreditado_por = auth.uid()
    WHERE id = p_registrado_id AND NOT acreditado;
    RETURN jsonb_build_object('ok', true, 'estado', 'marcado', 'acreditado_principal', true);
  END IF;

  IF NOT public.rpe_can_create_content() THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'RPE_NO_AUTORIZADO';
  END IF;
  UPDATE public.inscripciones_subevento
  SET asistio = false, asistio_en = NULL, asistio_por = NULL
  WHERE id = v_ins.id;
  SELECT r.acreditado INTO v_acredito FROM public.registrados r WHERE r.id = p_registrado_id;
  RETURN jsonb_build_object('ok', true, 'estado', 'desmarcado', 'acreditado_principal', v_acredito);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpe_publico_calendario(
  p_desde date DEFAULT NULL,
  p_hasta date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_desde date := COALESCE(p_desde, CURRENT_DATE - 365);
  v_hasta date := COALESCE(p_hasta, CURRENT_DATE + 365);
  v_out jsonb;
BEGIN
  IF v_hasta < v_desde OR (v_hasta - v_desde) > 800 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'RPE_DATOS_INVALIDOS',
      DETAIL = '{"campo":"rango","regla":"largo"}',
      HINT = 'El rango del calendario no puede superar 800 días.';
  END IF;

  SELECT COALESCE(jsonb_agg(fila ORDER BY fila->>'fecha_inicio', fila->>'slug'), '[]'::jsonb)
  INTO v_out
  FROM (
    SELECT jsonb_build_object(
      'slug', e.slug,
      'nombre', e.nombre,
      'tematica', e.tematica,
      'pais', e.pais,
      'fecha_inicio', to_char(e.fecha, 'YYYY-MM-DD'),
      'fecha_fin', to_char(public.rpe_fecha_termino_evento(e.fecha, e.duracion_dias), 'YYYY-MM-DD'),
      'hora_inicio', to_char(e.hora_inicio, 'HH24:MI'),
      'hora_fin', to_char(e.hora_fin, 'HH24:MI'),
      'zona_horaria', public.rpe_zona_horaria_pais(e.pais),
      'lugar', e.lugar,
      'direccion', e.direccion,
      'imagen_url', e.imagen_url,
      'banner_url', e.banner_url,
      'estado', CASE
        WHEN (now() AT TIME ZONE public.rpe_zona_horaria_pais(e.pais)) < public.rpe_evento_inicio_local(e) THEN 'proximo'
        WHEN (now() AT TIME ZONE public.rpe_zona_horaria_pais(e.pais)) > public.rpe_evento_fin_local(e) THEN 'finalizado'
        ELSE 'en_curso'
      END,
      'registro_abierto', public.rpe_evento_registro_abierto(e),
      'tiene_subeventos', EXISTS (SELECT 1 FROM public.subeventos s WHERE s.evento_id = e.id AND s.visible_publico),
      'agotado', e.cupo_maximo IS NOT NULL AND COALESCE(public.rpe_cupo_disponible_evento(e.id), 0) <= 0
    ) AS fila
    FROM public.eventos e
    WHERE e.fecha <= v_hasta
      AND public.rpe_fecha_termino_evento(e.fecha, e.duracion_dias) >= v_desde
  ) q;
  RETURN v_out;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpe_publico_evento(p_slug text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_evento public.eventos%ROWTYPE;
  v_zona text;
  v_hoy date;
  v_disp int;
  v_base jsonb;
  v_subs jsonb;
BEGIN
  SELECT * INTO v_evento FROM public.eventos e WHERE e.slug = lower(btrim(COALESCE(p_slug, '')));
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'RPE_EVENTO_NO_ENCONTRADO',
      HINT = 'No encontramos ese evento.';
  END IF;

  v_zona := public.rpe_zona_horaria_pais(v_evento.pais);
  v_hoy := (now() AT TIME ZONE v_zona)::date;
  v_disp := public.rpe_cupo_disponible_evento(v_evento.id);

  SELECT jsonb_build_object(
    'slug', v_evento.slug,
    'nombre', v_evento.nombre,
    'tematica', v_evento.tematica,
    'pais', v_evento.pais,
    'fecha_inicio', to_char(v_evento.fecha, 'YYYY-MM-DD'),
    'fecha_fin', to_char(public.rpe_fecha_termino_evento(v_evento.fecha, v_evento.duracion_dias), 'YYYY-MM-DD'),
    'hora_inicio', to_char(v_evento.hora_inicio, 'HH24:MI'),
    'hora_fin', to_char(v_evento.hora_fin, 'HH24:MI'),
    'zona_horaria', v_zona,
    'lugar', v_evento.lugar,
    'direccion', v_evento.direccion,
    'imagen_url', v_evento.imagen_url,
    'banner_url', v_evento.banner_url,
    'estado', CASE
      WHEN (now() AT TIME ZONE v_zona) < public.rpe_evento_inicio_local(v_evento) THEN 'proximo'
      WHEN (now() AT TIME ZONE v_zona) > public.rpe_evento_fin_local(v_evento) THEN 'finalizado'
      ELSE 'en_curso'
    END,
    'registro_abierto', public.rpe_evento_registro_abierto(v_evento),
    'tiene_subeventos', EXISTS (SELECT 1 FROM public.subeventos s WHERE s.evento_id = v_evento.id AND s.visible_publico),
    'agotado', v_evento.cupo_maximo IS NOT NULL AND COALESCE(v_disp, 0) <= 0,
    'descripcion', v_evento.descripcion,
    'mapa_url', v_evento.mapa_url,
    'inscripciones_cierre', to_char(v_evento.inscripciones_cierre, 'YYYY-MM-DD"T"HH24:MI:SS'),
    'cupo', jsonb_build_object(
      'limitado', v_evento.cupo_maximo IS NOT NULL,
      'disponibles', CASE WHEN v_evento.cupo_maximo IS NULL THEN NULL ELSE GREATEST(v_disp, 0) END
    ),
    'formulario', jsonb_build_object(
      'campos', jsonb_build_array('nombre_completo', 'email', 'empresa', 'cargo', 'telefono')
    )
  ) INTO v_base;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'codigo', s.codigo,
    'nombre', s.nombre,
    'descripcion', s.descripcion,
    'dia', to_char(s.dia, 'YYYY-MM-DD'),
    'hora_inicio', to_char(s.hora_inicio, 'HH24:MI'),
    'hora_fin', to_char(s.hora_fin, 'HH24:MI'),
    'sala', s.sala,
    'expositor', s.expositor,
    'imagen_url', s.imagen_url,
    'cupo', jsonb_build_object(
      'limitado', s.cupo_maximo IS NOT NULL,
      'disponibles', CASE
        WHEN s.cupo_maximo IS NULL THEN NULL
        ELSE GREATEST(public.rpe_cupo_disponible_subevento(s.id), 0)
      END
    ),
    'agotado', s.cupo_maximo IS NOT NULL AND COALESCE(public.rpe_cupo_disponible_subevento(s.id), 0) <= 0
  ) ORDER BY s.dia, s.hora_inicio, s.orden), '[]'::jsonb)
  INTO v_subs
  FROM public.subeventos s
  WHERE s.evento_id = v_evento.id
    AND s.visible_publico
    AND s.dia >= v_hoy;

  RETURN v_base || jsonb_build_object('subeventos', v_subs);
END;
$$;

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

-- ----------------------------------------------------------------

REVOKE ALL ON FUNCTION public.rpe_validar_datos_asistente(jsonb, boolean, boolean) FROM PUBLIC, anon, authenticated;
