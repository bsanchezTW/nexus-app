-- Fase 1: subeventos, cupos e identificadores opacos.
-- Idempotente. Aplicar en el SQL Editor (staging o local). Nunca en producción
-- sin el release de las fases 1 a 3 juntas. No usar db push.
--
-- TODO(arquitectura): Dart (registro_asistente.dart) no limita el largo de
-- nombre, empresa ni cargo. El §10 pide 3–120 y 1–120. Manda Dart: sin tope.
-- TODO(arquitectura): el teléfono en Dart depende del país (Chile/Perú: 9
-- dígitos y prefijos). Esta función no recibe país; se aplica el §10 (8–15
-- dígitos) y se guarda el texto recortado.
-- TODO(arquitectura): rpe_validar_datos_asistente no recibe el país. Las RPC
-- internas fijan el GUC rpe.pais_evento ('Chile'|'Perú') antes de validar
-- RUT/RUC. Si el GUC falta, se asume Chile.

-- ----------------------------------------------------------------
-- 1. Utilidades
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpe_zona_horaria_pais(p_pais text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE WHEN p_pais = 'Perú' THEN 'America/Lima' ELSE 'America/Santiago' END;
$$;

CREATE OR REPLACE FUNCTION public.rpe_codigo_aleatorio(p_largo int)
RETURNS text
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  alfabeto constant text := 'abcdefghjkmnpqrstuvwxyz23456789';
  resultado text := '';
  i int;
BEGIN
  IF p_largo IS NULL OR p_largo < 1 THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'RPE_DATOS_INVALIDOS',
      HINT = 'El largo del código debe ser positivo.';
  END IF;
  FOR i IN 1..p_largo LOOP
    resultado := resultado || substr(alfabeto, 1 + floor(random() * 31)::int, 1);
  END LOOP;
  RETURN resultado;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpe_generar_codigo_qr()
RETURNS text
LANGUAGE sql
VOLATILE
AS $$
  SELECT 'TW1-' || upper(replace(gen_random_uuid()::text, '-', ''));
$$;

CREATE OR REPLACE FUNCTION public.rpe_slug_base(p_nombre text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v text := lower(COALESCE(p_nombre, ''));
BEGIN
  v := translate(v, 'áéíóúüñàèìòù', 'aeiouunaeiou');
  v := regexp_replace(v, '[^a-z0-9]+', '-', 'g');
  v := regexp_replace(v, '^-+|-+$', '', 'g');
  v := left(v, 60);
  v := regexp_replace(v, '-+$', '');
  IF v IS NULL OR v = '' THEN
    RETURN 'evento';
  END IF;
  RETURN v;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpe_a_title_case(p_texto text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v text := regexp_replace(btrim(COALESCE(p_texto, '')), '\s+', ' ', 'g');
  v_palabra text;
  v_parte text;
  v_palabras text[] := '{}';
  v_partes text[] := '{}';
BEGIN
  IF v = '' THEN
    RETURN '';
  END IF;
  FOREACH v_palabra IN ARRAY regexp_split_to_array(v, ' ') LOOP
    v_partes := '{}';
    FOREACH v_parte IN ARRAY regexp_split_to_array(v_palabra, '-') LOOP
      IF v_parte = '' THEN
        v_partes := v_partes || '';
      ELSE
        v_partes := v_partes || (upper(substr(v_parte, 1, 1)) || lower(substr(v_parte, 2)));
      END IF;
    END LOOP;
    v_palabras := v_palabras || array_to_string(v_partes, '-');
  END LOOP;
  RETURN array_to_string(v_palabras, ' ');
END;
$$;

-- ----------------------------------------------------------------
-- 2. eventos
-- ----------------------------------------------------------------
ALTER TABLE public.eventos
  ADD COLUMN IF NOT EXISTS slug text,
  ADD COLUMN IF NOT EXISTS acceso_qr boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS cupo_maximo int,
  ADD COLUMN IF NOT EXISTS descripcion text,
  ADD COLUMN IF NOT EXISTS hora_inicio time,
  ADD COLUMN IF NOT EXISTS hora_fin time,
  ADD COLUMN IF NOT EXISTS inscripciones_cierre timestamp,
  ADD COLUMN IF NOT EXISTS mapa_url text,
  ADD COLUMN IF NOT EXISTS banner_url text;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'eventos' AND column_name = 'tipo_registro'
  ) THEN
    UPDATE public.eventos SET acceso_qr = (tipo_registro = 'cliente');
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.rpe_eventos_slug()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_candidato text;
  v_intento int := 0;
BEGIN
  -- NULL también en UPDATE: el backfill hace SET slug = slug WHERE slug IS NULL.
  IF NEW.slug IS NULL OR (TG_OP = 'INSERT' AND btrim(NEW.slug) = '') THEN
    LOOP
      v_intento := v_intento + 1;
      v_candidato := public.rpe_slug_base(NEW.nombre) || '-' || public.rpe_codigo_aleatorio(4);
      EXIT WHEN NOT EXISTS (
        SELECT 1 FROM public.eventos e WHERE e.slug = v_candidato
      );
      IF v_intento >= 10 THEN
        RAISE EXCEPTION USING
          ERRCODE = '23505',
          MESSAGE = 'RPE_SLUG_DUPLICADO',
          HINT = 'No se pudo generar un slug único.';
      END IF;
    END LOOP;
    NEW.slug := v_candidato;
    RETURN NEW;
  END IF;

  IF NEW.slug IS NULL OR btrim(NEW.slug) = '' THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'RPE_SLUG_INVALIDO',
      HINT = 'El slug no puede quedar vacío.';
  END IF;

  NEW.slug := lower(btrim(NEW.slug));

  IF NEW.slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
     OR char_length(NEW.slug) < 3
     OR char_length(NEW.slug) > 80 THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'RPE_SLUG_INVALIDO',
      HINT = 'El slug debe tener entre 3 y 80 caracteres, en minúsculas, números y guiones.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.eventos e
    WHERE e.slug = NEW.slug AND e.id IS DISTINCT FROM NEW.id
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = '23505',
      MESSAGE = 'RPE_SLUG_DUPLICADO',
      HINT = 'Ese slug ya está en uso.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_eventos_slug ON public.eventos;
CREATE TRIGGER trg_eventos_slug
  BEFORE INSERT OR UPDATE OF slug ON public.eventos
  FOR EACH ROW EXECUTE FUNCTION public.rpe_eventos_slug();

UPDATE public.eventos SET slug = slug WHERE slug IS NULL;

ALTER TABLE public.eventos ALTER COLUMN slug SET NOT NULL;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'eventos' AND column_name = 'tipo_registro'
  ) THEN
    ALTER TABLE public.eventos DROP COLUMN tipo_registro;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'eventos_slug_unique') THEN
    ALTER TABLE public.eventos ADD CONSTRAINT eventos_slug_unique UNIQUE (slug);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'eventos_slug_formato') THEN
    ALTER TABLE public.eventos ADD CONSTRAINT eventos_slug_formato
      CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND char_length(slug) BETWEEN 3 AND 80);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'eventos_cupo_positivo') THEN
    ALTER TABLE public.eventos ADD CONSTRAINT eventos_cupo_positivo
      CHECK (cupo_maximo IS NULL OR cupo_maximo > 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'eventos_horas_validas') THEN
    ALTER TABLE public.eventos ADD CONSTRAINT eventos_horas_validas
      CHECK (hora_inicio IS NULL OR hora_fin IS NULL OR duracion_dias > 1 OR hora_fin > hora_inicio);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'eventos_descripcion_largo') THEN
    ALTER TABLE public.eventos ADD CONSTRAINT eventos_descripcion_largo
      CHECK (descripcion IS NULL OR char_length(descripcion) <= 5000);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'eventos_mapa_url_formato') THEN
    ALTER TABLE public.eventos ADD CONSTRAINT eventos_mapa_url_formato
      CHECK (mapa_url IS NULL OR mapa_url ~ '^https://');
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.rpe_evento_inicio_local(e public.eventos)
RETURNS timestamp
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT e.fecha + COALESCE(e.hora_inicio, '00:00'::time);
$$;

CREATE OR REPLACE FUNCTION public.rpe_evento_fin_local(e public.eventos)
RETURNS timestamp
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT public.rpe_fecha_termino_evento(e.fecha, e.duracion_dias)
       + COALESCE(e.hora_fin, '23:59:59'::time);
$$;

CREATE OR REPLACE FUNCTION public.rpe_evento_registro_abierto(e public.eventos)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT now() < (
    COALESCE(e.inscripciones_cierre, public.rpe_evento_fin_local(e))
    AT TIME ZONE public.rpe_zona_horaria_pais(e.pais)
  );
$$;

CREATE OR REPLACE FUNCTION public.rpe_evento_vigente(e public.eventos)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT public.rpe_fecha_termino_evento(e.fecha, e.duracion_dias) >= CURRENT_DATE;
$$;

CREATE OR REPLACE FUNCTION public.rpe_eventos_validar_rango_subeventos()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_fuera int;
BEGIN
  IF to_regclass('public.subeventos') IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT count(*) INTO v_fuera
  FROM public.subeventos s
  WHERE s.evento_id = NEW.id
    AND (
      s.dia < NEW.fecha
      OR s.dia > public.rpe_fecha_termino_evento(NEW.fecha, NEW.duracion_dias)
    );
  IF v_fuera > 0 THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'RPE_SUBEVENTOS_FUERA_DE_RANGO',
      DETAIL = v_fuera::text,
      HINT = 'Hay talleres fuera del nuevo rango de fechas del evento.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_eventos_validar_rango_subeventos ON public.eventos;
CREATE TRIGGER trg_eventos_validar_rango_subeventos
  BEFORE UPDATE OF fecha, duracion_dias ON public.eventos
  FOR EACH ROW EXECUTE FUNCTION public.rpe_eventos_validar_rango_subeventos();

CREATE OR REPLACE FUNCTION public.rpe_storage_basura_banner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.rpe_encolar_storage('imagenes', OLD.banner_url);
    RETURN OLD;
  END IF;
  IF NEW.banner_url IS DISTINCT FROM OLD.banner_url THEN
    PERFORM public.rpe_encolar_storage('imagenes', OLD.banner_url);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_eventos_storage_basura_banner ON public.eventos;
CREATE TRIGGER trg_eventos_storage_basura_banner
  AFTER UPDATE OF banner_url OR DELETE ON public.eventos
  FOR EACH ROW EXECUTE FUNCTION public.rpe_storage_basura_banner();

-- ----------------------------------------------------------------
-- 3. registrados
-- ----------------------------------------------------------------
ALTER TABLE public.registrados
  ADD COLUMN IF NOT EXISTS codigo_qr text,
  ADD COLUMN IF NOT EXISTS sobrecupo boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS whatsapp_confirmacion_enviado boolean NOT NULL DEFAULT false;

ALTER TABLE public.registrados DROP CONSTRAINT IF EXISTS registrados_bloque_id_fkey;
ALTER TABLE public.registrados DROP COLUMN IF EXISTS bloque_id CASCADE;
DROP TABLE IF EXISTS public.evento_bloques CASCADE;

UPDATE public.registrados
SET codigo_qr = public.rpe_generar_codigo_qr()
WHERE codigo_qr IS NULL;

ALTER TABLE public.registrados
  ALTER COLUMN codigo_qr SET DEFAULT public.rpe_generar_codigo_qr();
ALTER TABLE public.registrados
  ALTER COLUMN codigo_qr SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'registrados_codigo_qr_unique') THEN
    ALTER TABLE public.registrados
      ADD CONSTRAINT registrados_codigo_qr_unique UNIQUE (codigo_qr);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'registrados_codigo_qr_formato') THEN
    ALTER TABLE public.registrados
      ADD CONSTRAINT registrados_codigo_qr_formato
      CHECK (codigo_qr ~ '^TW1-[0-9A-F]{32}$');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'registrados_id_evento_unique') THEN
    ALTER TABLE public.registrados
      ADD CONSTRAINT registrados_id_evento_unique UNIQUE (id, evento_id);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.rpe_set_acreditado_en()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.acreditado IS TRUE THEN
      NEW.acreditado_en := now();
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.acreditado IS TRUE AND OLD.acreditado IS DISTINCT FROM TRUE THEN
    NEW.acreditado_en := now();
  ELSIF NEW.acreditado IS DISTINCT FROM TRUE AND OLD.acreditado IS TRUE THEN
    NEW.acreditado_en := NULL;
    NEW.acreditado_por := NULL;
  END IF;
  RETURN NEW;
END;
$$;

-- Corre antes de trg_registrados_restrict_externo_update (orden alfabético).
DROP TRIGGER IF EXISTS trg_registrados_acreditado_en ON public.registrados;
CREATE TRIGGER trg_registrados_acreditado_en
  BEFORE INSERT OR UPDATE OF acreditado ON public.registrados
  FOR EACH ROW EXECUTE FUNCTION public.rpe_set_acreditado_en();

CREATE OR REPLACE FUNCTION public.rpe_proteger_campos_registrado()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.evento_id IS DISTINCT FROM OLD.evento_id THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'RPE_CAMPO_INMUTABLE',
      HINT = 'El evento de un registrado no se puede cambiar.';
  END IF;
  IF NEW.codigo_qr IS DISTINCT FROM OLD.codigo_qr
     AND current_setting('rpe.regenerando_qr', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'RPE_CAMPO_INMUTABLE',
      HINT = 'El código QR solo se regenera con la función prevista.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_registrados_proteger_campos ON public.registrados;
CREATE TRIGGER trg_registrados_proteger_campos
  BEFORE UPDATE ON public.registrados
  FOR EACH ROW EXECUTE FUNCTION public.rpe_proteger_campos_registrado();

-- ----------------------------------------------------------------
-- 4. subeventos, inscripciones, envios
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.subeventos (
  id              uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  evento_id       uuid NOT NULL REFERENCES public.eventos (id) ON DELETE CASCADE,
  codigo          text NOT NULL,
  nombre          text NOT NULL,
  descripcion     text,
  dia             date NOT NULL,
  hora_inicio     time NOT NULL,
  hora_fin        time NOT NULL,
  sala            text,
  expositor       text,
  imagen_url      text,
  cupo_maximo     int,
  orden           int NOT NULL DEFAULT 0,
  visible_publico boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT timezone('utc', now()),
  updated_at      timestamptz NOT NULL DEFAULT timezone('utc', now())
);

CREATE INDEX IF NOT EXISTS idx_subeventos_evento_dia
  ON public.subeventos (evento_id, dia, hora_inicio, orden);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'subeventos_horas_validas') THEN
    ALTER TABLE public.subeventos ADD CONSTRAINT subeventos_horas_validas
      CHECK (hora_fin > hora_inicio);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'subeventos_cupo_positivo') THEN
    ALTER TABLE public.subeventos ADD CONSTRAINT subeventos_cupo_positivo
      CHECK (cupo_maximo IS NULL OR cupo_maximo > 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'subeventos_nombre_largo') THEN
    ALTER TABLE public.subeventos ADD CONSTRAINT subeventos_nombre_largo
      CHECK (char_length(btrim(nombre)) BETWEEN 2 AND 150);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'subeventos_codigo_formato') THEN
    ALTER TABLE public.subeventos ADD CONSTRAINT subeventos_codigo_formato
      CHECK (codigo ~ '^[a-z0-9]{6}$');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'subeventos_evento_codigo_unique') THEN
    ALTER TABLE public.subeventos ADD CONSTRAINT subeventos_evento_codigo_unique
      UNIQUE (evento_id, codigo);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'subeventos_id_evento_unique') THEN
    ALTER TABLE public.subeventos ADD CONSTRAINT subeventos_id_evento_unique
      UNIQUE (id, evento_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'subeventos_sala_largo') THEN
    ALTER TABLE public.subeventos ADD CONSTRAINT subeventos_sala_largo
      CHECK (sala IS NULL OR char_length(sala) <= 120);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'subeventos_expositor_largo') THEN
    ALTER TABLE public.subeventos ADD CONSTRAINT subeventos_expositor_largo
      CHECK (expositor IS NULL OR char_length(expositor) <= 120);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'subeventos_descripcion_largo') THEN
    ALTER TABLE public.subeventos ADD CONSTRAINT subeventos_descripcion_largo
      CHECK (descripcion IS NULL OR char_length(descripcion) <= 2000);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.inscripciones_subevento (
  id             uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  evento_id      uuid NOT NULL,
  registrado_id  uuid NOT NULL,
  subevento_id   uuid NOT NULL,
  origen         text NOT NULL CHECK (origen IN ('publico', 'app', 'excel', 'escaner')),
  inscrito_por   uuid REFERENCES public.perfiles (id) ON DELETE SET NULL,
  sobrecupo      boolean NOT NULL DEFAULT false,
  asistio        boolean NOT NULL DEFAULT false,
  asistio_en     timestamptz,
  asistio_por    uuid REFERENCES public.perfiles (id) ON DELETE SET NULL,
  created_at     timestamptz NOT NULL DEFAULT timezone('utc', now())
);

CREATE INDEX IF NOT EXISTS idx_insc_sub_evento
  ON public.inscripciones_subevento (evento_id);
CREATE INDEX IF NOT EXISTS idx_insc_sub_subevento
  ON public.inscripciones_subevento (subevento_id, asistio);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'insc_sub_registrado_fk') THEN
    ALTER TABLE public.inscripciones_subevento
      ADD CONSTRAINT insc_sub_registrado_fk
      FOREIGN KEY (registrado_id, evento_id)
      REFERENCES public.registrados (id, evento_id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'insc_sub_subevento_fk') THEN
    ALTER TABLE public.inscripciones_subevento
      ADD CONSTRAINT insc_sub_subevento_fk
      FOREIGN KEY (subevento_id, evento_id)
      REFERENCES public.subeventos (id, evento_id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'insc_sub_registrado_subevento_unique') THEN
    ALTER TABLE public.inscripciones_subevento
      ADD CONSTRAINT insc_sub_registrado_subevento_unique
      UNIQUE (registrado_id, subevento_id);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.envios_qr (
  id             uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  registrado_id  uuid NOT NULL REFERENCES public.registrados (id) ON DELETE CASCADE,
  evento_id      uuid NOT NULL REFERENCES public.eventos (id) ON DELETE CASCADE,
  canales        text[] NOT NULL,
  motivo         text NOT NULL,
  origen         text NOT NULL,
  solicitado_por uuid REFERENCES public.perfiles (id) ON DELETE SET NULL,
  estado         text NOT NULL DEFAULT 'pendiente',
  resultado      jsonb,
  error          text,
  intentos       int NOT NULL DEFAULT 0,
  created_at     timestamptz NOT NULL DEFAULT timezone('utc', now()),
  procesado_en   timestamptz
);

CREATE INDEX IF NOT EXISTS idx_envios_qr_registrado
  ON public.envios_qr (registrado_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_envios_qr_estado
  ON public.envios_qr (estado, created_at);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'envios_qr_canales_validos') THEN
    ALTER TABLE public.envios_qr ADD CONSTRAINT envios_qr_canales_validos
      CHECK (
        cardinality(canales) > 0
        AND canales <@ ARRAY['email', 'sms', 'whatsapp']::text[]
      );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'envios_qr_motivo_valido') THEN
    ALTER TABLE public.envios_qr ADD CONSTRAINT envios_qr_motivo_valido
      CHECK (motivo IN ('registro', 'talleres_agregados', 'reenvio', 'codigo_regenerado'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'envios_qr_origen_valido') THEN
    ALTER TABLE public.envios_qr ADD CONSTRAINT envios_qr_origen_valido
      CHECK (origen IN ('publico', 'app'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'envios_qr_estado_valido') THEN
    ALTER TABLE public.envios_qr ADD CONSTRAINT envios_qr_estado_valido
      CHECK (estado IN ('pendiente', 'procesando', 'completado', 'fallido'));
  END IF;
END $$;

DROP TRIGGER IF EXISTS trg_subeventos_updated_at ON public.subeventos;
CREATE TRIGGER trg_subeventos_updated_at
  BEFORE UPDATE ON public.subeventos
  FOR EACH ROW EXECUTE FUNCTION public.rpe_set_updated_at();

CREATE OR REPLACE FUNCTION public.rpe_validar_subevento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_evento public.eventos%ROWTYPE;
  v_intento int := 0;
  v_codigo text;
  v_solape int;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.evento_id IS DISTINCT FROM OLD.evento_id THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'RPE_CAMPO_INMUTABLE',
      HINT = 'El evento de un taller no se puede cambiar.';
  END IF;

  SELECT * INTO v_evento FROM public.eventos e WHERE e.id = NEW.evento_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0002',
      MESSAGE = 'RPE_EVENTO_NO_ENCONTRADO';
  END IF;

  IF TG_OP = 'INSERT' AND (NEW.codigo IS NULL OR btrim(NEW.codigo) = '') THEN
    LOOP
      v_intento := v_intento + 1;
      v_codigo := public.rpe_codigo_aleatorio(6);
      EXIT WHEN NOT EXISTS (
        SELECT 1 FROM public.subeventos s
        WHERE s.evento_id = NEW.evento_id AND s.codigo = v_codigo
      );
      IF v_intento >= 10 THEN
        RAISE EXCEPTION USING
          ERRCODE = '23505',
          MESSAGE = 'RPE_DATOS_INVALIDOS',
          DETAIL = '{"campo":"codigo","regla":"unico"}',
          HINT = 'No se pudo generar un código de taller único.';
      END IF;
    END LOOP;
    NEW.codigo := v_codigo;
  END IF;

  IF NEW.dia < v_evento.fecha
     OR NEW.dia > public.rpe_fecha_termino_evento(v_evento.fecha, v_evento.duracion_dias) THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'RPE_SUBEVENTO_FUERA_DE_RANGO',
      HINT = 'El día del taller tiene que caer dentro del evento.';
  END IF;

  IF TG_OP = 'UPDATE'
     AND (NEW.dia, NEW.hora_inicio, NEW.hora_fin)
         IS DISTINCT FROM (OLD.dia, OLD.hora_inicio, OLD.hora_fin) THEN
    SELECT count(DISTINCT i.registrado_id) INTO v_solape
    FROM public.inscripciones_subevento i
    JOIN public.inscripciones_subevento i2
      ON i2.registrado_id = i.registrado_id
     AND i2.evento_id = i.evento_id
     AND i2.subevento_id <> NEW.id
    JOIN public.subeventos s2 ON s2.id = i2.subevento_id
    WHERE i.subevento_id = NEW.id
      AND s2.dia = NEW.dia
      AND NEW.hora_inicio < s2.hora_fin
      AND s2.hora_inicio < NEW.hora_fin;
    IF v_solape > 0 THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'RPE_SUBEVENTO_SOLAPE_INSCRITOS',
        DETAIL = v_solape::text,
        HINT = 'Hay asistentes que quedarían en talleres superpuestos.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_subeventos_validar ON public.subeventos;
CREATE TRIGGER trg_subeventos_validar
  BEFORE INSERT OR UPDATE ON public.subeventos
  FOR EACH ROW EXECUTE FUNCTION public.rpe_validar_subevento();

DROP TRIGGER IF EXISTS trg_subeventos_storage_basura ON public.subeventos;
CREATE TRIGGER trg_subeventos_storage_basura
  AFTER UPDATE OF imagen_url OR DELETE ON public.subeventos
  FOR EACH ROW EXECUTE FUNCTION public.rpe_storage_basura_portada();

-- ----------------------------------------------------------------
-- 5. Helpers de inscripción (sin GRANT)
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpe_validar_datos_asistente(
  p_datos jsonb,
  p_exigir_certificacion boolean
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
      v_compacto := upper(regexp_replace(btrim(COALESCE(p_datos->>'rut', '')), '[^0-9K]', '', 'g'));
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

    v_patente := upper(regexp_replace(btrim(COALESCE(p_datos->>'patente', '')), '[^A-Za-z0-9]', '', 'g'));
    IF v_patente !~ '^[A-Z]{4}[0-9]{2}$' AND v_patente !~ '^[A-Z]{2}[0-9]{4}$' THEN
      RAISE EXCEPTION USING
        ERRCODE = '22023', MESSAGE = 'RPE_DATOS_INVALIDOS',
        DETAIL = '{"campo":"patente","regla":"formato"}',
        HINT = 'La patente no es válida.';
    END IF;
    v_out := v_out || jsonb_build_object('rut', v_rut, 'patente', v_patente);
  END IF;

  RETURN v_out;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpe_lock_cupo_evento(p_evento_id uuid)
RETURNS void
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT pg_advisory_xact_lock(hashtextextended('rpe_cupo_evento:' || p_evento_id::text, 0));
$$;

CREATE OR REPLACE FUNCTION public.rpe_lock_cupo_subevento(p_subevento_id uuid)
RETURNS void
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT pg_advisory_xact_lock(hashtextextended('rpe_cupo_sub:' || p_subevento_id::text, 0));
$$;

CREATE OR REPLACE FUNCTION public.rpe_cupo_disponible_evento(p_evento_id uuid)
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN e.cupo_maximo IS NULL THEN NULL
    ELSE e.cupo_maximo - (
      SELECT count(*)::int FROM public.registrados r WHERE r.evento_id = e.id
    )
  END
  FROM public.eventos e
  WHERE e.id = p_evento_id;
$$;

CREATE OR REPLACE FUNCTION public.rpe_cupo_disponible_subevento(p_subevento_id uuid)
RETURNS int
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN s.cupo_maximo IS NULL THEN NULL
    ELSE s.cupo_maximo - (
      SELECT count(*)::int FROM public.inscripciones_subevento i
      WHERE i.subevento_id = s.id
    )
  END
  FROM public.subeventos s
  WHERE s.id = p_subevento_id;
$$;

CREATE OR REPLACE FUNCTION public.rpe_subeventos_solapados(
  p_registrado_id uuid,
  p_subevento_ids uuid[]
)
RETURNS TABLE (subevento_id uuid, motivo text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH pedidos AS (
    SELECT s.id, s.dia, s.hora_inicio, s.hora_fin
    FROM public.subeventos s
    WHERE s.id = ANY (COALESCE(p_subevento_ids, '{}'::uuid[]))
  ),
  entre_pedidos AS (
    SELECT a.id AS subevento_id, 'superpuesto'::text AS motivo
    FROM pedidos a
    JOIN pedidos b ON a.id < b.id
    WHERE a.dia = b.dia
      AND a.hora_inicio < b.hora_fin
      AND b.hora_inicio < a.hora_fin
    UNION
    SELECT b.id, 'superpuesto'::text
    FROM pedidos a
    JOIN pedidos b ON a.id < b.id
    WHERE a.dia = b.dia
      AND a.hora_inicio < b.hora_fin
      AND b.hora_inicio < a.hora_fin
  ),
  contra_inscritos AS (
    SELECT a.id AS subevento_id, 'superpuesto_con_inscripcion'::text AS motivo
    FROM pedidos a
    JOIN public.inscripciones_subevento i
      ON i.registrado_id = p_registrado_id
     AND i.subevento_id <> a.id
    JOIN public.subeventos b ON b.id = i.subevento_id
    WHERE a.dia = b.dia
      AND a.hora_inicio < b.hora_fin
      AND b.hora_inicio < a.hora_fin
  )
  SELECT x.subevento_id,
         CASE
           WHEN bool_or(x.motivo = 'superpuesto_con_inscripcion')
             THEN 'superpuesto_con_inscripcion'
           ELSE 'superpuesto'
         END AS motivo
  FROM (
    SELECT * FROM entre_pedidos
    UNION ALL
    SELECT * FROM contra_inscritos
  ) x
  GROUP BY x.subevento_id;
$$;

CREATE OR REPLACE FUNCTION public.rpe_insertar_inscripciones(
  p_registrado_id uuid,
  p_evento_id uuid,
  p_subevento_ids uuid[],
  p_origen text,
  p_forzar boolean
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_ids uuid[];
  v_id uuid;
  v_rechazados jsonb := '[]'::jsonb;
  v_rechazo_ids uuid[] := '{}';
  v_sub public.subeventos%ROWTYPE;
  v_solape record;
  v_disp int;
  v_agregados uuid[] := '{}';
  v_sobrecupo boolean;
BEGIN
  SELECT COALESCE(array_agg(x ORDER BY x), '{}'::uuid[])
  INTO v_ids
  FROM (SELECT DISTINCT unnest(COALESCE(p_subevento_ids, '{}'::uuid[])) AS x) d;

  FOREACH v_id IN ARRAY v_ids LOOP
    PERFORM public.rpe_lock_cupo_subevento(v_id);
  END LOOP;

  FOREACH v_id IN ARRAY v_ids LOOP
    SELECT * INTO v_sub
    FROM public.subeventos s
    WHERE s.id = v_id AND s.evento_id = p_evento_id;
    IF NOT FOUND THEN
      v_rechazados := v_rechazados || jsonb_build_array(
        jsonb_build_object('subevento_id', v_id, 'motivo', 'no_existe'));
      v_rechazo_ids := v_rechazo_ids || v_id;
      CONTINUE;
    END IF;
    IF v_sub.dia < CURRENT_DATE THEN
      v_rechazados := v_rechazados || jsonb_build_array(
        jsonb_build_object('subevento_id', v_id, 'motivo', 'no_disponible'));
      v_rechazo_ids := v_rechazo_ids || v_id;
    END IF;
  END LOOP;

  FOR v_solape IN
    SELECT * FROM public.rpe_subeventos_solapados(p_registrado_id, v_ids)
  LOOP
    IF NOT (v_solape.subevento_id = ANY (v_rechazo_ids)) THEN
      v_rechazados := v_rechazados || jsonb_build_array(
        jsonb_build_object('subevento_id', v_solape.subevento_id, 'motivo', v_solape.motivo));
      v_rechazo_ids := v_rechazo_ids || v_solape.subevento_id;
    END IF;
  END LOOP;

  FOREACH v_id IN ARRAY v_ids LOOP
    IF v_id = ANY (v_rechazo_ids) THEN
      CONTINUE;
    END IF;
    v_disp := public.rpe_cupo_disponible_subevento(v_id);
    IF v_disp IS NOT NULL AND v_disp <= 0 AND NOT COALESCE(p_forzar, false) THEN
      v_rechazados := v_rechazados || jsonb_build_array(
        jsonb_build_object('subevento_id', v_id, 'motivo', 'sin_cupo'));
      v_rechazo_ids := v_rechazo_ids || v_id;
    END IF;
  END LOOP;

  IF jsonb_array_length(v_rechazados) > 0 THEN
    RETURN jsonb_build_object('ok', false, 'rechazados', v_rechazados);
  END IF;

  FOREACH v_id IN ARRAY v_ids LOOP
    v_disp := public.rpe_cupo_disponible_subevento(v_id);
    v_sobrecupo := v_disp IS NOT NULL AND v_disp <= 0;
    INSERT INTO public.inscripciones_subevento (
      evento_id, registrado_id, subevento_id, origen, inscrito_por, sobrecupo
    ) VALUES (
      p_evento_id, p_registrado_id, v_id, p_origen, auth.uid(), v_sobrecupo
    );
    v_agregados := v_agregados || v_id;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'agregados', to_jsonb(v_agregados));
END;
$$;

CREATE OR REPLACE FUNCTION public.rpe_encolar_envio_qr(
  p_registrado_id uuid,
  p_canales text[],
  p_motivo text,
  p_origen text
)
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_evento_id uuid;
  v_ventana interval := CASE WHEN p_origen = 'publico' THEN interval '10 minutes' ELSE interval '60 seconds' END;
BEGIN
  SELECT r.evento_id INTO v_evento_id
  FROM public.registrados r WHERE r.id = p_registrado_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'RPE_REGISTRADO_NO_ENCONTRADO';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.envios_qr e
    WHERE e.registrado_id = p_registrado_id
      AND e.origen = p_origen
      AND e.estado <> 'fallido'
      AND e.created_at > now() - v_ventana
  ) THEN
    RETURN 'limitado';
  END IF;

  INSERT INTO public.envios_qr (
    registrado_id, evento_id, canales, motivo, origen, solicitado_por
  ) VALUES (
    p_registrado_id,
    v_evento_id,
    p_canales,
    p_motivo,
    p_origen,
    CASE WHEN p_origen = 'app' THEN auth.uid() ELSE NULL END
  );
  RETURN 'programado';
END;
$$;

-- ----------------------------------------------------------------
-- 6. RPC internas
-- ----------------------------------------------------------------
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
    p_datos, v_evento.certificacion_capacitacion);

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
        v_fila, v_evento.certificacion_capacitacion);
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
  v_ins public.inscripciones_subevento%ROWTYPE;
  v_acredito boolean := false;
BEGIN
  SELECT * INTO v_ins FROM public.inscripciones_subevento i
  WHERE i.registrado_id = p_registrado_id AND i.subevento_id = p_subevento_id;
  IF NOT FOUND THEN
    IF NOT EXISTS (SELECT 1 FROM public.registrados r WHERE r.id = p_registrado_id) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'RPE_REGISTRADO_NO_ENCONTRADO';
    END IF;
    RETURN jsonb_build_object('ok', false, 'motivo', 'no_inscrito');
  END IF;
  IF NOT public.rpe_puede_operar_evento(v_ins.evento_id) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'RPE_NO_AUTORIZADO';
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

CREATE OR REPLACE FUNCTION public.rpe_quitar_inscripcion_subevento(
  p_registrado_id uuid,
  p_subevento_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_ins public.inscripciones_subevento%ROWTYPE;
BEGIN
  SELECT * INTO v_ins FROM public.inscripciones_subevento i
  WHERE i.registrado_id = p_registrado_id AND i.subevento_id = p_subevento_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'RPE_NO_INSCRITO';
  END IF;
  IF NOT (public.rpe_is_internal_user() AND public.rpe_puede_operar_evento(v_ins.evento_id)) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'RPE_NO_AUTORIZADO';
  END IF;
  IF v_ins.asistio AND NOT public.rpe_can_create_content() THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'RPE_NO_AUTORIZADO';
  END IF;
  DELETE FROM public.inscripciones_subevento WHERE id = v_ins.id;
  RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpe_regenerar_codigo_qr(
  p_registrado_id uuid,
  p_reenviar boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_evento_id uuid;
  v_codigo text;
  v_envio text := 'no_solicitado';
BEGIN
  SELECT r.evento_id INTO v_evento_id FROM public.registrados r WHERE r.id = p_registrado_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'RPE_REGISTRADO_NO_ENCONTRADO';
  END IF;
  IF NOT (public.rpe_can_create_content() AND public.rpe_puede_operar_evento(v_evento_id)) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'RPE_NO_AUTORIZADO';
  END IF;

  PERFORM set_config('rpe.regenerando_qr', 'on', true);
  UPDATE public.registrados
  SET codigo_qr = public.rpe_generar_codigo_qr()
  WHERE id = p_registrado_id
  RETURNING codigo_qr INTO v_codigo;

  IF COALESCE(p_reenviar, false) THEN
    v_envio := public.rpe_encolar_envio_qr(
      p_registrado_id, ARRAY['email', 'sms'], 'codigo_regenerado', 'app');
  END IF;
  RETURN jsonb_build_object('codigo_qr', v_codigo, 'envio', v_envio);
END;
$$;

CREATE OR REPLACE FUNCTION public.rpe_ocupacion_evento(p_evento_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_evento jsonb;
  v_subs jsonb;
BEGIN
  IF NOT public.rpe_puede_operar_evento(p_evento_id) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'RPE_NO_AUTORIZADO';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.eventos e WHERE e.id = p_evento_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'RPE_EVENTO_NO_ENCONTRADO';
  END IF;

  SELECT jsonb_build_object(
    'cupo_maximo', e.cupo_maximo,
    'inscritos', (SELECT count(*) FROM public.registrados r WHERE r.evento_id = e.id),
    'acreditados', (SELECT count(*) FROM public.registrados r WHERE r.evento_id = e.id AND r.acreditado),
    'sobrecupo', (SELECT count(*) FROM public.registrados r WHERE r.evento_id = e.id AND r.sobrecupo)
  ) INTO v_evento
  FROM public.eventos e WHERE e.id = p_evento_id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'subevento_id', s.id,
    'cupo_maximo', s.cupo_maximo,
    'inscritos', (SELECT count(*) FROM public.inscripciones_subevento i WHERE i.subevento_id = s.id),
    'asistentes', (SELECT count(*) FROM public.inscripciones_subevento i WHERE i.subevento_id = s.id AND i.asistio),
    'sobrecupo', (SELECT count(*) FROM public.inscripciones_subevento i WHERE i.subevento_id = s.id AND i.sobrecupo)
  ) ORDER BY s.dia, s.hora_inicio, s.orden), '[]'::jsonb)
  INTO v_subs
  FROM public.subeventos s WHERE s.evento_id = p_evento_id;

  RETURN jsonb_build_object('evento', v_evento, 'subeventos', v_subs);
END;
$$;

-- ----------------------------------------------------------------
-- 7. RPC públicas (nunca devuelven UUID)
-- ----------------------------------------------------------------
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
      'tiene_subeventos', EXISTS (SELECT 1 FROM public.subeventos s WHERE s.evento_id = e.id),
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
    'tiene_subeventos', EXISTS (SELECT 1 FROM public.subeventos s WHERE s.evento_id = v_evento.id),
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

  SELECT * INTO v_reg FROM public.registrados r
  WHERE r.evento_id = v_evento.id AND r.email = v_datos->>'email';

  IF NOT FOUND THEN
    PERFORM public.rpe_lock_cupo_evento(v_evento.id);
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

  SELECT COALESCE(array_agg(s.id), '{}'::uuid[]), COALESCE(array_agg(s.codigo), '{}'::text[])
  INTO v_nuevos, v_ya
  FROM public.subeventos s
  WHERE s.id = ANY (v_ids)
    AND EXISTS (
      SELECT 1 FROM public.inscripciones_subevento i
      WHERE i.registrado_id = v_reg.id AND i.subevento_id = s.id
    );
  -- v_ya quedó con los ya inscritos; los nuevos son el resto.
  SELECT COALESCE(array_agg(s.codigo), '{}'::text[]) INTO v_ya
  FROM public.subeventos s
  WHERE s.id = ANY (v_ids)
    AND EXISTS (
      SELECT 1 FROM public.inscripciones_subevento i
      WHERE i.registrado_id = v_reg.id AND i.subevento_id = s.id
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
-- 8. Permisos
-- ----------------------------------------------------------------
REVOKE ALL ON FUNCTION public.rpe_validar_datos_asistente(jsonb, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpe_lock_cupo_evento(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpe_lock_cupo_subevento(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpe_cupo_disponible_evento(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpe_cupo_disponible_subevento(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpe_subeventos_solapados(uuid, uuid[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpe_insertar_inscripciones(uuid, uuid, uuid[], text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpe_encolar_envio_qr(uuid, text[], text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.rpe_a_title_case(text) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.rpe_registrar_asistente(uuid, jsonb, uuid[], boolean, boolean, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpe_registrar_asistente(uuid, jsonb, uuid[], boolean, boolean, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.rpe_importar_registrados(uuid, jsonb, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpe_importar_registrados(uuid, jsonb, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.rpe_inscribir_subevento(uuid, uuid, boolean, boolean, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpe_inscribir_subevento(uuid, uuid, boolean, boolean, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.rpe_marcar_asistencia_subevento(uuid, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpe_marcar_asistencia_subevento(uuid, uuid, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.rpe_quitar_inscripcion_subevento(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpe_quitar_inscripcion_subevento(uuid, uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.rpe_regenerar_codigo_qr(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpe_regenerar_codigo_qr(uuid, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.rpe_ocupacion_evento(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpe_ocupacion_evento(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.rpe_publico_calendario(date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpe_publico_calendario(date, date) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.rpe_publico_evento(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpe_publico_evento(text) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.rpe_publico_registrar(text, jsonb, text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpe_publico_registrar(text, jsonb, text[]) TO anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.rpe_existe_email_registrado(uuid, text) FROM anon;

-- ----------------------------------------------------------------
-- 9. RLS
-- ----------------------------------------------------------------
DROP POLICY IF EXISTS rpe_eventos_select_publico ON public.eventos;
DROP POLICY IF EXISTS rpe_registrados_insert ON public.registrados;
DROP POLICY IF EXISTS rpe_registrados_insert_publico ON public.registrados;
DROP POLICY IF EXISTS "Permitir registro público anónimo" ON public.registrados;
DROP POLICY IF EXISTS anon_insert_registrados ON public.registrados;

REVOKE INSERT ON TABLE public.registrados FROM PUBLIC, anon, authenticated;

ALTER TABLE public.subeventos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inscripciones_subevento ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.envios_qr ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rpe_subeventos_select ON public.subeventos;
CREATE POLICY rpe_subeventos_select ON public.subeventos
  FOR SELECT TO authenticated
  USING (public.rpe_puede_operar_evento(evento_id));

DROP POLICY IF EXISTS rpe_subeventos_write ON public.subeventos;
CREATE POLICY rpe_subeventos_write ON public.subeventos
  FOR ALL TO authenticated
  USING (public.rpe_can_create_content())
  WITH CHECK (public.rpe_can_create_content());

DROP POLICY IF EXISTS rpe_insc_sub_select ON public.inscripciones_subevento;
CREATE POLICY rpe_insc_sub_select ON public.inscripciones_subevento
  FOR SELECT TO authenticated
  USING (public.rpe_puede_operar_evento(evento_id));

DROP POLICY IF EXISTS rpe_envios_qr_select ON public.envios_qr;
CREATE POLICY rpe_envios_qr_select ON public.envios_qr
  FOR SELECT TO authenticated
  USING (public.rpe_puede_operar_evento(evento_id) AND NOT public.rpe_is_externo());

REVOKE ALL ON TABLE public.subeventos FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.subeventos TO authenticated;
REVOKE ALL ON TABLE public.inscripciones_subevento FROM anon;
GRANT SELECT ON TABLE public.inscripciones_subevento TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.inscripciones_subevento FROM authenticated;
REVOKE ALL ON TABLE public.envios_qr FROM anon;
GRANT SELECT ON TABLE public.envios_qr TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.envios_qr FROM authenticated;

-- ----------------------------------------------------------------
-- 10. Storage y baja de usuario
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpe_storage_en_uso(p_bucket text, p_path text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
BEGIN
  IF p_bucket = 'imagenes' THEN
    RETURN EXISTS (
      SELECT 1 FROM public.eventos WHERE public.rpe_storage_path(imagen_url) = p_path
    ) OR EXISTS (
      SELECT 1 FROM public.eventos WHERE public.rpe_storage_path(banner_url) = p_path
    ) OR EXISTS (
      SELECT 1 FROM public.subeventos WHERE public.rpe_storage_path(imagen_url) = p_path
    ) OR EXISTS (
      SELECT 1 FROM public.eventos_leads WHERE public.rpe_storage_path(imagen_url) = p_path
    ) OR EXISTS (
      SELECT 1 FROM public.perfiles WHERE public.rpe_storage_path(foto_url) = p_path
    );
  END IF;

  IF p_bucket = 'leads-privados' THEN
    RETURN EXISTS (
      SELECT 1 FROM public.leads l, unnest(l.fotos_urls) AS u(url)
      WHERE public.rpe_storage_path(u.url) = p_path
    );
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.rpe_storage_en_uso(text, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.rpe_eliminar_usuario(usuario_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_sentinel constant uuid := '00000000-0000-0000-0000-000000000001';
  v_usuario_id uuid := usuario_id;
BEGIN
  IF usuario_id = v_sentinel THEN
    RAISE EXCEPTION 'No se puede eliminar el perfil sistema';
  END IF;
  IF NOT public.rpe_is_admin() THEN
    RAISE EXCEPTION 'Solo un administrador puede eliminar usuarios';
  END IF;
  IF usuario_id = auth.uid() THEN
    RAISE EXCEPTION 'No puedes eliminar tu propia cuenta';
  END IF;

  UPDATE public.registrados SET acreditado_por = v_sentinel WHERE acreditado_por = usuario_id;
  UPDATE public.registrados SET ingresado_por = v_sentinel WHERE ingresado_por = usuario_id;
  UPDATE public.eventos SET creado_por = v_sentinel WHERE creado_por = usuario_id;

  IF to_regclass('public.usuarios_eventos') IS NOT NULL THEN
    DELETE FROM public.usuarios_eventos ue WHERE ue.usuario_id = v_usuario_id;
  END IF;
  IF to_regclass('public.eventos_leads') IS NOT NULL THEN
    UPDATE public.eventos_leads SET perfil_id = v_sentinel WHERE perfil_id = usuario_id;
  END IF;
  IF to_regclass('public.leads') IS NOT NULL THEN
    UPDATE public.leads SET perfil_id = v_sentinel WHERE perfil_id = usuario_id;
  END IF;
  IF to_regclass('public.lead_comentarios') IS NOT NULL THEN
    UPDATE public.lead_comentarios SET autor_id = v_sentinel WHERE autor_id = usuario_id;
  END IF;
  IF to_regclass('public.inscripciones_subevento') IS NOT NULL THEN
    UPDATE public.inscripciones_subevento SET inscrito_por = v_sentinel WHERE inscrito_por = usuario_id;
    UPDATE public.inscripciones_subevento SET asistio_por = v_sentinel WHERE asistio_por = usuario_id;
  END IF;
  IF to_regclass('public.envios_qr') IS NOT NULL THEN
    UPDATE public.envios_qr SET solicitado_por = v_sentinel WHERE solicitado_por = usuario_id;
  END IF;

  DELETE FROM public.perfiles WHERE id = usuario_id;

  BEGIN
    DELETE FROM auth.users WHERE id = usuario_id;
  EXCEPTION WHEN foreign_key_violation THEN
    UPDATE auth.users SET banned_until = 'infinity' WHERE id = usuario_id;
    RETURN 'desactivado';
  END;
  RETURN 'eliminado';
END;
$$;
