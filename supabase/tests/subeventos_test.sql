-- Tests de la fase 1. SQL Editor sobre staging o `supabase start`.
-- Nunca en producción. Todo queda deshecho por el ROLLBACK final.
--
-- Paridad con Dart (registro_asistente.dart). Si difiere del §10, manda Dart.
-- nombre: title case, al menos 2 palabras, cada una con 2+ letras sin contar guiones. Sin tope 120.
-- email: reglas de validarEmailRegistro, más tope 254 del §10.
-- empresa y cargo: no vacíos. Sin tope 120.
-- telefono: 8–15 dígitos (el §10). Dart valida por país; ver TODO del migration.
-- rut Chile 12.345.678-5 módulo 11 cuando rpe.pais_evento no es Perú.
-- patente ABCD12 o AB1234 si se exige certificación.

BEGIN;

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, is_super_admin, is_sso_user, is_anonymous,
  banned_until, confirmation_token, recovery_token,
  email_change_token_new, email_change
) VALUES
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f1-admin@test.local', crypt('x', gen_salt('bf')), now(), '{}'::jsonb, '{}'::jsonb, now(), now(), false, false, false, NULL, '', '', '', ''),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f1-org@test.local', crypt('x', gen_salt('bf')), now(), '{}'::jsonb, '{}'::jsonb, now(), now(), false, false, false, NULL, '', '', '', ''),
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f1-user@test.local', crypt('x', gen_salt('bf')), now(), '{}'::jsonb, '{}'::jsonb, now(), now(), false, false, false, NULL, '', '', '', ''),
  ('44444444-4444-4444-4444-444444444444', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'f1-ext@test.local', crypt('x', gen_salt('bf')), now(), '{}'::jsonb, '{}'::jsonb, now(), now(), false, false, false, NULL, '', '', '', '')
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.perfiles DISABLE TRIGGER trg_perfiles_prevent_role_escalation;
ALTER TABLE public.perfiles DISABLE TRIGGER trg_perfiles_validate_externo;
INSERT INTO public.perfiles (id, nombre_completo, rol, activo)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'Admin Fase1', 'admin', true),
  ('22222222-2222-2222-2222-222222222222', 'Org Fase1', 'organizador', true),
  ('33333333-3333-3333-3333-333333333333', 'User Fase1', 'user', true),
  ('44444444-4444-4444-4444-444444444444', 'Ext Fase1', 'externo', true)
ON CONFLICT (id) DO UPDATE SET rol = EXCLUDED.rol, activo = true, nombre_completo = EXCLUDED.nombre_completo;
ALTER TABLE public.perfiles ENABLE TRIGGER trg_perfiles_validate_externo;
ALTER TABLE public.perfiles ENABLE TRIGGER trg_perfiles_prevent_role_escalation;

INSERT INTO public.eventos (id, nombre, pais, fecha, lugar, direccion, cupo_maximo, hora_inicio, hora_fin, duracion_dias, creado_por)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Transworld Connect Fase 1', 'Chile', CURRENT_DATE + 30, 'Hotel X', 'Av. Y 123', 2, '09:00', '18:00', 1, '11111111-1111-1111-1111-111111111111');

INSERT INTO public.usuarios_eventos (usuario_id, evento_id, rol_evento) VALUES
  ('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'vendedor'),
  ('44444444-4444-4444-4444-444444444444', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'externo');
UPDATE public.perfiles SET evento_asignado_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
WHERE id = '44444444-4444-4444-4444-444444444444';

INSERT INTO public.subeventos (id, evento_id, codigo, nombre, dia, hora_inicio, hora_fin, cupo_maximo, orden)
VALUES
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'tlr001', 'Taller A', CURRENT_DATE + 30, '10:00', '11:00', 1, 1),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'tlr002', 'Taller B', CURRENT_DATE + 30, '11:00', '12:00', NULL, 2),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb3', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'tlr003', 'Taller C', CURRENT_DATE + 30, '10:30', '11:30', NULL, 3),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb4', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'tlr004', 'Taller D', CURRENT_DATE + 30, '14:00', '15:00', NULL, 4);

CREATE OR REPLACE FUNCTION pg_temp.f1_como(p_uid uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE format('SET LOCAL request.jwt.claims = %L', json_build_object('sub', p_uid, 'role', 'authenticated')::text);
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
END;
$$;

-- 1. Slug
DO $$
DECLARE v_slug text; v_slug2 text;
BEGIN
  SELECT slug INTO v_slug FROM public.eventos WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  IF v_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' OR char_length(v_slug) < 3 THEN
    RAISE EXCEPTION 'caso 1 slug inválido: %', v_slug;
  END IF;
  UPDATE public.eventos SET nombre = 'Otro nombre' WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  SELECT slug INTO v_slug2 FROM public.eventos WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  IF v_slug2 IS DISTINCT FROM v_slug THEN
    RAISE EXCEPTION 'caso 1 el nombre cambió el slug';
  END IF;
  BEGIN
    UPDATE public.eventos SET slug = 'NO VALE' WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    RAISE EXCEPTION 'caso 1 debió rechazar el slug';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%RPE_SLUG_INVALIDO%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK caso 1 slug';
END $$;

-- 2. codigo_qr
DO $$
DECLARE v_id uuid; v_qr text; v_qr2 text;
BEGIN
  PERFORM pg_temp.f1_como('22222222-2222-2222-2222-222222222222');
  PERFORM public.rpe_registrar_asistente(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '{"nombre_completo":"Ana Pérez","email":"ana-qr@x.cl","empresa":"X","cargo":"Cto","telefono":"+56912345678"}'::jsonb
  );
  SELECT id, codigo_qr INTO v_id, v_qr FROM public.registrados WHERE email = 'ana-qr@x.cl';
  IF v_qr !~ '^TW1-[0-9A-F]{32}$' THEN
    RAISE EXCEPTION 'caso 2 formato %', v_qr;
  END IF;
  BEGIN
    UPDATE public.registrados SET codigo_qr = public.rpe_generar_codigo_qr() WHERE id = v_id;
    RAISE EXCEPTION 'caso 2 debió bloquear el update';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%RPE_CAMPO_INMUTABLE%' THEN RAISE; END IF;
  END;
  v_qr2 := public.rpe_regenerar_codigo_qr(v_id, false)->>'codigo_qr';
  IF v_qr2 = v_qr OR v_qr2 !~ '^TW1-[0-9A-F]{32}$' THEN
    RAISE EXCEPTION 'caso 2 regenerar no cambió el código';
  END IF;
  RAISE NOTICE 'OK caso 2 codigo_qr';
END $$;

-- 3. Cupo del evento
DO $$
DECLARE r jsonb;
BEGIN
  PERFORM pg_temp.f1_como('22222222-2222-2222-2222-222222222222');
  r := public.rpe_registrar_asistente('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '{"nombre_completo":"Luis Soto","email":"luis@x.cl","empresa":"X","cargo":"Analista","telefono":"56911111111"}'::jsonb);
  IF (r->>'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'caso 3 segundo registro %', r; END IF;
  r := public.rpe_registrar_asistente('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '{"nombre_completo":"Mia Díaz","email":"mia@x.cl","empresa":"X","cargo":"Analista","telefono":"56922222222"}'::jsonb);
  IF r->>'motivo' IS DISTINCT FROM 'sin_cupo_evento' THEN RAISE EXCEPTION 'caso 3 tercero %', r; END IF;
  PERFORM pg_temp.f1_como('33333333-3333-3333-3333-333333333333');
  r := public.rpe_registrar_asistente('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '{"nombre_completo":"Nora Díaz","email":"nora@x.cl","empresa":"X","cargo":"Analista","telefono":"56933333333"}'::jsonb,
    '{}', false, true, false);
  IF r->>'motivo' IS DISTINCT FROM 'sin_cupo_evento' OR (r->>'puede_forzar')::boolean THEN
    RAISE EXCEPTION 'caso 3 user %', r;
  END IF;
  PERFORM pg_temp.f1_como('22222222-2222-2222-2222-222222222222');
  r := public.rpe_registrar_asistente('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '{"nombre_completo":"Nora Díaz","email":"nora@x.cl","empresa":"X","cargo":"Analista","telefono":"56933333333"}'::jsonb,
    '{}', false, true, false);
  IF (r->>'ok')::boolean IS NOT TRUE OR (r->>'sobrecupo')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'caso 3 forzar %', r;
  END IF;
  RAISE NOTICE 'OK caso 3 cupo evento';
END $$;

-- 4. Cupo de taller
DO $$
DECLARE r jsonb; v_reg uuid;
BEGIN
  SELECT id INTO v_reg FROM public.registrados WHERE email = 'ana-qr@x.cl';
  PERFORM pg_temp.f1_como('33333333-3333-3333-3333-333333333333');
  r := public.rpe_inscribir_subevento(v_reg, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', false, false, false);
  IF (r->>'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'caso 4 primera %', r; END IF;
  SELECT id INTO v_reg FROM public.registrados WHERE email = 'luis@x.cl';
  r := public.rpe_inscribir_subevento(v_reg, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', true, false, false);
  IF r->>'motivo' IS DISTINCT FROM 'sin_cupo' OR (r->>'puede_forzar')::boolean THEN
    RAISE EXCEPTION 'caso 4 user %', r;
  END IF;
  PERFORM pg_temp.f1_como('22222222-2222-2222-2222-222222222222');
  r := public.rpe_inscribir_subevento(v_reg, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', true, false, false);
  IF (r->>'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'caso 4 forzar %', r; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.inscripciones_subevento
    WHERE registrado_id = v_reg AND subevento_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1' AND sobrecupo
  ) THEN RAISE EXCEPTION 'caso 4 sin sobrecupo'; END IF;
  RAISE NOTICE 'OK caso 4 cupo taller';
END $$;

-- 5. Solape en la misma solicitud, nada insertado
DO $$
DECLARE r jsonb; n int; antes int;
BEGIN
  SELECT count(*) INTO antes FROM public.registrados WHERE evento_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  PERFORM pg_temp.f1_como('22222222-2222-2222-2222-222222222222');
  UPDATE public.eventos SET cupo_maximo = 10 WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  r := public.rpe_registrar_asistente(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '{"nombre_completo":"Olga Ruiz","email":"olga@x.cl","empresa":"X","cargo":"Analista","telefono":"56944444444"}'::jsonb,
    ARRAY['bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2'::uuid, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb3'::uuid],
    false, false, false);
  IF r->>'motivo' IS DISTINCT FROM 'subeventos_rechazados' THEN RAISE EXCEPTION 'caso 5 %', r; END IF;
  SELECT count(*) INTO n FROM public.registrados WHERE email = 'olga@x.cl';
  IF n <> 0 THEN RAISE EXCEPTION 'caso 5 insertó a la persona'; END IF;
  RAISE NOTICE 'OK caso 5 solape en la solicitud';
END $$;

-- 6 y 7 y 13. Reinscripción pública
DO $$
DECLARE v_slug text; r jsonb; nombre text; n int;
BEGIN
  SELECT slug INTO v_slug FROM public.eventos WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  RESET ROLE;
  r := public.rpe_publico_registrar(v_slug,
    '{"nombre_completo":"Paz León","email":"paz@x.cl","empresa":"Acme","cargo":"Jefa","telefono":"+56 9 5555 5555"}'::jsonb,
    ARRAY['tlr002']);
  IF r->>'resultado' IS DISTINCT FROM 'inscrito' OR r->>'envio' IS DISTINCT FROM 'programado' THEN
    RAISE EXCEPTION 'caso 6 alta %', r;
  END IF;
  UPDATE public.envios_qr e
  SET created_at = now() - interval '1 hour'
  FROM public.registrados rg
  WHERE rg.id = e.registrado_id AND rg.email = 'paz@x.cl';
  r := public.rpe_publico_registrar(v_slug,
    '{"nombre_completo":"Otra Persona","email":"paz@x.cl","empresa":"Otra","cargo":"Otra","telefono":"+56 9 5555 5555"}'::jsonb,
    ARRAY['tlr002', 'tlr004']);
  IF r->>'resultado' IS DISTINCT FROM 'actualizado' THEN RAISE EXCEPTION 'caso 6 update %', r; END IF;
  IF NOT ((r->'ya_inscrito_en') ? 'tlr002') THEN RAISE EXCEPTION 'caso 6 ya_inscrito %', r; END IF;
  SELECT nombre_completo INTO nombre FROM public.registrados WHERE email = 'paz@x.cl';
  IF nombre IS DISTINCT FROM 'Paz León' THEN RAISE EXCEPTION 'caso 6 pisó el nombre %', nombre; END IF;
  SELECT count(*) INTO n FROM public.registrados WHERE email = 'paz@x.cl';
  IF n <> 1 THEN RAISE EXCEPTION 'caso 6 cupo/filas %', n; END IF;
  r := public.rpe_publico_registrar(v_slug,
    '{"nombre_completo":"Paz León","email":"paz@x.cl","empresa":"Acme","cargo":"Jefa","telefono":"+56 9 5555 5555"}'::jsonb,
    ARRAY['tlr002', 'tlr004']);
  IF r->>'envio' IS DISTINCT FROM 'limitado' THEN RAISE EXCEPTION 'caso 13 %', r; END IF;
  SELECT count(*) INTO n FROM public.envios_qr e
  JOIN public.registrados rg ON rg.id = e.registrado_id
  WHERE rg.email = 'paz@x.cl' AND e.estado = 'pendiente';
  IF n <> 2 THEN RAISE EXCEPTION 'caso 13 filas % (se esperaban 2: alta y talleres)', n; END IF;
  RAISE NOTICE 'OK caso 6 reinscripcion';
  RAISE NOTICE 'OK caso 13 envio limitado';
END $$;

-- 7. Solape contra inscripción existente
DO $$
DECLARE r jsonb; v_id uuid;
BEGIN
  PERFORM pg_temp.f1_como('22222222-2222-2222-2222-222222222222');
  SELECT id INTO v_id FROM public.registrados WHERE email = 'paz@x.cl';
  r := public.rpe_inscribir_subevento(v_id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb3', false, false, false);
  IF r->>'motivo' IS DISTINCT FROM 'superpuesto' THEN RAISE EXCEPTION 'caso 7 %', r; END IF;
  RAISE NOTICE 'OK caso 7 solape con inscripcion';
END $$;

-- 8. Asistencia, externo
DO $$
DECLARE r jsonb; v_id uuid;
BEGIN
  SELECT id INTO v_id FROM public.registrados WHERE email = 'ana-qr@x.cl';
  PERFORM pg_temp.f1_como('44444444-4444-4444-4444-444444444444');
  r := public.rpe_marcar_asistencia_subevento(v_id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', true);
  IF r->>'estado' IS DISTINCT FROM 'marcado' OR (r->>'acreditado_principal')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'caso 8 marcar %', r;
  END IF;
  r := public.rpe_marcar_asistencia_subevento(v_id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', true);
  IF r->>'estado' IS DISTINCT FROM 'ya_marcado' THEN RAISE EXCEPTION 'caso 8 idempotente %', r; END IF;
  BEGIN
    PERFORM public.rpe_marcar_asistencia_subevento(v_id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', false);
    RAISE EXCEPTION 'caso 8 externo desmarcó';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%RPE_NO_AUTORIZADO%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.rpe_inscribir_subevento(v_id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2', false, false, false);
    RAISE EXCEPTION 'caso 8 externo inscribió';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%RPE_NO_AUTORIZADO%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK caso 8 asistencia externo';
END $$;

-- 9. acreditado_en
DO $$
DECLARE v_id uuid; v_en timestamptz;
BEGIN
  SELECT id INTO v_id FROM public.registrados WHERE email = 'luis@x.cl';
  PERFORM pg_temp.f1_como('11111111-1111-1111-1111-111111111111');
  UPDATE public.registrados SET acreditado = true, acreditado_por = '11111111-1111-1111-1111-111111111111' WHERE id = v_id;
  SELECT acreditado_en INTO v_en FROM public.registrados WHERE id = v_id;
  IF v_en IS NULL THEN RAISE EXCEPTION 'caso 9 no llenó acreditado_en'; END IF;
  UPDATE public.registrados SET acreditado = false WHERE id = v_id;
  SELECT acreditado_en INTO v_en FROM public.registrados WHERE id = v_id;
  IF v_en IS NOT NULL THEN RAISE EXCEPTION 'caso 9 no limpió acreditado_en'; END IF;
  RAISE NOTICE 'OK caso 9 acreditado_en';
END $$;

-- 10. Horario y rango
DO $$
DECLARE v_ana uuid;
BEGIN
  SELECT id INTO v_ana FROM public.registrados WHERE email = 'ana-qr@x.cl';
  PERFORM pg_temp.f1_como('11111111-1111-1111-1111-111111111111');
  PERFORM public.rpe_inscribir_subevento(
    v_ana, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2', false, false, false);
  BEGIN
    UPDATE public.subeventos SET hora_inicio = '10:00', hora_fin = '11:30'
    WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2';
    RAISE EXCEPTION 'caso 10 debió rechazar el horario';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%RPE_SUBEVENTO_SOLAPE_INSCRITOS%' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.eventos SET fecha = CURRENT_DATE + 40
    WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    RAISE EXCEPTION 'caso 10 debió rechazar el rango';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%RPE_SUBEVENTOS_FUERA_DE_RANGO%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK caso 10 rango y solape';
END $$;

-- 11 y 12. anon
DO $$
DECLARE n int; cal jsonb; det jsonb; reg jsonb; v_slug text;
BEGIN
  SET LOCAL ROLE anon;
  BEGIN
    SELECT count(*) INTO n FROM public.eventos;
  EXCEPTION WHEN insufficient_privilege THEN
    n := 0;
  END;
  IF n <> 0 THEN RAISE EXCEPTION 'caso 11 anon leyó eventos %', n; END IF;
  BEGIN
    SELECT count(*) INTO n FROM public.subeventos;
  EXCEPTION WHEN insufficient_privilege THEN
    n := 0;
  END;
  IF n <> 0 THEN RAISE EXCEPTION 'caso 11 anon leyó subeventos %', n; END IF;
  BEGIN
    SELECT count(*) INTO n FROM public.registrados;
  EXCEPTION WHEN insufficient_privilege THEN
    n := 0;
  END;
  IF n <> 0 THEN RAISE EXCEPTION 'caso 11 anon leyó registrados %', n; END IF;
  BEGIN
    SELECT count(*) INTO n FROM public.inscripciones_subevento;
  EXCEPTION WHEN insufficient_privilege THEN
    n := 0;
  END;
  IF n <> 0 THEN RAISE EXCEPTION 'caso 11 anon leyó inscripciones %', n; END IF;
  RESET ROLE;
  SELECT slug INTO v_slug FROM public.eventos WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  SET LOCAL ROLE anon;
  cal := public.rpe_publico_calendario(CURRENT_DATE, CURRENT_DATE + 60);
  det := public.rpe_publico_evento(v_slug);
  IF cal::text ~ '[0-9a-f]{8}-[0-9a-f]{4}-' OR det::text ~ '[0-9a-f]{8}-[0-9a-f]{4}-' THEN
    RAISE EXCEPTION 'caso 12 UUID en respuesta pública';
  END IF;
  BEGIN
    PERFORM public.rpe_registrar_asistente('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '{}'::jsonb);
    RAISE EXCEPTION 'caso 11 anon registró';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%RPE_NO_AUTORIZADO%' AND SQLERRM NOT LIKE '%permission denied%' THEN RAISE; END IF;
  END;
  reg := public.rpe_publico_registrar(v_slug,
    '{"nombre_completo":"Quique Mora","email":"quique@x.cl","empresa":"X","cargo":"Analista","telefono":"56966666666"}'::jsonb,
    ARRAY[]::text[]);
  IF reg::text ~ '[0-9a-f]{8}-[0-9a-f]{4}-' THEN
    RAISE EXCEPTION 'caso 12 UUID en registrar %', reg;
  END IF;
  IF (reg->>'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'caso 11 registrar %', reg; END IF;
  RAISE NOTICE 'OK caso 11 anon';
  RAISE NOTICE 'OK caso 12 sin uuid';
END $$;

-- 14. Registro cerrado. El staff igual registra.
DO $$
DECLARE r jsonb; v_slug text;
BEGIN
  RESET ROLE;
  UPDATE public.eventos SET inscripciones_cierre = CURRENT_DATE - 1
  WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  SELECT slug INTO v_slug FROM public.eventos WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  r := public.rpe_publico_registrar(v_slug,
    '{"nombre_completo":"Rosa Díaz","email":"rosa@x.cl","empresa":"X","cargo":"Analista","telefono":"56977777777"}'::jsonb);
  IF r->>'motivo' IS DISTINCT FROM 'registro_cerrado' THEN RAISE EXCEPTION 'caso 14 %', r; END IF;
  PERFORM pg_temp.f1_como('22222222-2222-2222-2222-222222222222');
  r := public.rpe_registrar_asistente('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '{"nombre_completo":"Rosa Díaz","email":"rosa@x.cl","empresa":"X","cargo":"Analista","telefono":"56977777777"}'::jsonb,
    '{}', false, false, false);
  IF (r->>'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'caso 14 staff %', r; END IF;
  RAISE NOTICE 'OK caso 14 registro cerrado';
END $$;

-- 15. Concurrencia: no se puede simular con dos transacciones en este script.
-- Abrir dos pestañas del SQL Editor, BEGIN en ambas, registrar el último cupo
-- y hacer COMMIT. Solo una debe devolver ok. Anotar el resultado en el reporte.
DO $$
BEGIN
  RAISE NOTICE 'PENDIENTE caso 15 concurrencia manual (dos sesiones)';
END $$;

-- 16. Dos altas públicas seguidas con el mismo email.
DO $$
DECLARE r jsonb; v_slug text;
BEGIN
  RESET ROLE;
  INSERT INTO public.eventos (
    id, nombre, pais, fecha, lugar, direccion, cupo_maximo,
    hora_inicio, hora_fin, duracion_dias, creado_por
  ) VALUES (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa16', 'Evento Caso 16', 'Chile',
    CURRENT_DATE + 40, 'Hotel', 'Calle 1', 5, '09:00', '18:00', 1,
    '11111111-1111-1111-1111-111111111111'
  );
  SELECT slug INTO v_slug FROM public.eventos WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa16';
  r := public.rpe_publico_registrar(v_slug,
    '{"nombre_completo":"Nico Paz","email":"nico16@x.cl","empresa":"X","cargo":"Analista","telefono":"56911112222"}'::jsonb);
  IF r->>'resultado' IS DISTINCT FROM 'inscrito' THEN RAISE EXCEPTION 'caso 16 alta %', r; END IF;
  r := public.rpe_publico_registrar(v_slug,
    '{"nombre_completo":"Nico Paz","email":"nico16@x.cl","empresa":"X","cargo":"Analista","telefono":"56911112222"}'::jsonb);
  IF r->>'resultado' IS DISTINCT FROM 'sin_cambios' THEN RAISE EXCEPTION 'caso 16 re %', r; END IF;
  RAISE NOTICE 'OK caso 16 email repetido';
END $$;

-- 17. Inscribir a quien ya está no consume cupo y marca asistencia.
DO $$
DECLARE r jsonb; v_id uuid; antes int; despues int; v_asistio boolean;
BEGIN
  PERFORM pg_temp.f1_como('11111111-1111-1111-1111-111111111111');
  SELECT id INTO v_id FROM public.registrados WHERE email = 'paz@x.cl';
  SELECT count(*) INTO antes FROM public.inscripciones_subevento
  WHERE registrado_id = v_id AND subevento_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2';
  r := public.rpe_inscribir_subevento(
    v_id, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2', false, true, false);
  IF (r->>'ok')::boolean IS NOT TRUE OR (r->>'ya_inscrito')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'caso 17 %', r;
  END IF;
  SELECT count(*) INTO despues FROM public.inscripciones_subevento
  WHERE registrado_id = v_id AND subevento_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2';
  SELECT asistio INTO v_asistio FROM public.inscripciones_subevento
  WHERE registrado_id = v_id AND subevento_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb2';
  IF antes <> 1 OR despues <> antes OR v_asistio IS NOT TRUE THEN
    RAISE EXCEPTION 'caso 17 conteo % -> % asistio %', antes, despues, v_asistio;
  END IF;
  RAISE NOTICE 'OK caso 17 ya inscrito';
END $$;

-- 18. Permiso antes de decir si está inscrito.
DO $$
DECLARE v_ana uuid; v_luis uuid;
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, is_super_admin, is_sso_user, is_anonymous,
    banned_until, confirmation_token, recovery_token,
    email_change_token_new, email_change
  ) VALUES (
    '55555555-5555-5555-5555-555555555555', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'f1-ajeno@test.local', crypt('x', gen_salt('bf')),
    now(), '{}'::jsonb, '{}'::jsonb, now(), now(), false, false, false, NULL, '', '', '', ''
  ) ON CONFLICT (id) DO NOTHING;
  ALTER TABLE public.perfiles DISABLE TRIGGER trg_perfiles_prevent_role_escalation;
  INSERT INTO public.perfiles (id, nombre_completo, rol, activo)
  VALUES ('55555555-5555-5555-5555-555555555555', 'Ajeno Fase1', 'user', true)
  ON CONFLICT (id) DO UPDATE SET rol = 'user', activo = true;
  ALTER TABLE public.perfiles ENABLE TRIGGER trg_perfiles_prevent_role_escalation;

  SELECT id INTO v_ana FROM public.registrados WHERE email = 'ana-qr@x.cl';
  SELECT id INTO v_luis FROM public.registrados WHERE email = 'luis@x.cl';
  PERFORM pg_temp.f1_como('55555555-5555-5555-5555-555555555555');
  BEGIN
    PERFORM public.rpe_marcar_asistencia_subevento(v_ana, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1', true);
    RAISE EXCEPTION 'caso 18 dejó marcar a un inscrito';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%RPE_NO_AUTORIZADO%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.rpe_marcar_asistencia_subevento(v_luis, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb4', true);
    RAISE EXCEPTION 'caso 18 dejó marcar a quien no está en el taller';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%RPE_NO_AUTORIZADO%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK caso 18 permiso antes de existencia';
END $$;

-- 19. RUT con k minúscula.
DO $$
DECLARE v jsonb;
BEGIN
  PERFORM set_config('rpe.pais_evento', 'Chile', true);
  v := public.rpe_validar_datos_asistente(
    '{"nombre_completo":"Rita Sol","email":"rita19@x.cl","empresa":"X","cargo":"Analista","telefono":"56912345678","rut":"10.000.013-k","patente":"ABCD12"}'::jsonb,
    true, false);
  IF v->>'rut' IS DISTINCT FROM '10000013K' THEN RAISE EXCEPTION 'caso 19 k %', v->>'rut'; END IF;
  v := public.rpe_validar_datos_asistente(
    '{"nombre_completo":"Rita Sol","email":"rita19@x.cl","empresa":"X","cargo":"Analista","telefono":"56912345678","rut":"10.000.013-K","patente":"ABCD12"}'::jsonb,
    true, false);
  IF v->>'rut' IS DISTINCT FROM '10000013K' THEN RAISE EXCEPTION 'caso 19 K %', v->>'rut'; END IF;
  RAISE NOTICE 'OK caso 19 rut k';
END $$;

-- 20. tiene_subeventos ignora talleres ocultos.
DO $$
DECLARE v_slug text; det jsonb;
BEGIN
  RESET ROLE;
  INSERT INTO public.eventos (
    id, nombre, pais, fecha, lugar, direccion, cupo_maximo,
    hora_inicio, hora_fin, duracion_dias, creado_por
  ) VALUES (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa20', 'Evento Caso 20', 'Chile',
    CURRENT_DATE + 40, 'Hotel', 'Calle 1', NULL, '09:00', '18:00', 1,
    '11111111-1111-1111-1111-111111111111'
  );
  INSERT INTO public.subeventos (
    id, evento_id, codigo, nombre, dia, hora_inicio, hora_fin, visible_publico
  ) VALUES (
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb20', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa20',
    'oculto', 'Oculto', CURRENT_DATE + 40, '10:00', '11:00', false
  );
  SELECT slug INTO v_slug FROM public.eventos WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa20';
  det := public.rpe_publico_evento(v_slug);
  IF (det->>'tiene_subeventos')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION 'caso 20 %', det->>'tiene_subeventos';
  END IF;
  RAISE NOTICE 'OK caso 20 talleres ocultos';
END $$;

-- 21. Excel con certificación: RUT y patente opcionales, formato si vienen.
DO $$
DECLARE r jsonb; n int;
BEGIN
  RESET ROLE;
  INSERT INTO public.eventos (
    id, nombre, pais, fecha, lugar, direccion, cupo_maximo,
    hora_inicio, hora_fin, duracion_dias, creado_por, certificacion_capacitacion
  ) VALUES (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa21', 'Evento Caso 21', 'Chile',
    CURRENT_DATE + 40, 'Hotel', 'Calle 1', 10, '09:00', '18:00', 1,
    '11111111-1111-1111-1111-111111111111', true
  );
  PERFORM pg_temp.f1_como('11111111-1111-1111-1111-111111111111');
  r := public.rpe_importar_registrados(
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa21',
    jsonb_build_array(
      jsonb_build_object(
        'nombre_completo', 'Rita Sol', 'email', 'rita21@x.cl',
        'empresa', 'X', 'cargo', 'Analista', 'telefono', '56988888888'
      ),
      jsonb_build_object(
        'nombre_completo', 'Hugo Mal', 'email', 'hugo21@x.cl',
        'empresa', 'X', 'cargo', 'Analista', 'telefono', '56988888889',
        'rut', '1', 'patente', 'ABCD12'
      )
    ),
    false);
  SELECT count(*) INTO n FROM public.registrados WHERE email = 'rita21@x.cl';
  IF (r->>'insertados')::int IS DISTINCT FROM 1 OR n <> 1
     OR jsonb_array_length(r->'invalidos') IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'caso 21 %', r;
  END IF;
  RAISE NOTICE 'OK caso 21 importacion certificacion';
END $$;

ROLLBACK;
