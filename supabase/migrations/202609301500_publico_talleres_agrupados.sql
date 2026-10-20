-- Web pública: los talleres agrupados se publican dentro de su evento. Idempotente.
--
-- 1. rpe_publico_calendario deja fuera las fichas de tipo taller que ya son subevento de un
--    evento (subeventos.evento_origen_id): antes aparecían además como eventos sueltos.
-- 2. rpe_publico_evento entrega todos los talleres visibles, también los ya realizados, para
--    mostrar el programa de eventos pasados. La inscripción no cambia: rpe_publico_registrar
--    sigue rechazando talleres de días anteriores (no_disponible).
-- CREATE OR REPLACE conserva los permisos (anon, authenticated).

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
      -- Ficha de taller agrupada en un evento: se publica como taller de ese evento.
      AND NOT EXISTS (SELECT 1 FROM public.subeventos s WHERE s.evento_origen_id = e.id)
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
    AND s.visible_publico;

  RETURN v_base || jsonb_build_object('subeventos', v_subs);
END;
$$;
