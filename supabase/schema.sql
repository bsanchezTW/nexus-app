-- ============================================================
--  Transworld Nexus — esquema + RLS (CONSOLIDADO, fuente única)
--  (proyecto anteriormente conocido como "Registro Pro")
--  Esquema: public (según definición del proyecto).
--
--  Fuente única: fusiona las migraciones históricas (antes en
--  supabase/migrations/ y supabase/migracion_*.sql). La carpeta
--  migrations queda vacía a propósito. Aplicar este script en el SQL
--  Editor sobre una base nueva o ya existente; no usar `db push`.
--
--  Migraciones fusionadas aquí (orden cronológico):
--    fusion_leads · leads_policies · registrados_columnas ·
--    fix_invite_externo · roles_4_usuarios · obtener_email_usuario ·
--    auth_user_id_por_email · eliminar_usuario (+ reasignar_todas_fks) ·
--    campana_qr_roles · externo_multi_eventos · externo_leads_amarrados ·
--    delete_solo_admin · utm_registrados · restricciones_usuario_externo ·
--    acceso_user_y_privacidad_leads · completar_auditoria_registrados ·
--    configurar_acceso_evento · resumen_campana_leads ·
--    resumen_campana_acceso · normalizar_email_registrados ·
--    evento_lead_origen_interno_externo · lead_comentarios ·
--    resumen_campana_acceso_externo.
--
--  Es idempotente y (en su mayoría) no destructivo: usa
--  IF NOT EXISTS / OR REPLACE. Las correcciones de RLS SÍ
--  reemplazan políticas anteriores (DROP POLICY IF EXISTS + CREATE).
--
--  ⚠️ Esta base de datos puede seguir compartida con el proyecto
--  hermano "capturador-leads" (mismo project_ref). Las políticas y
--  funciones mantienen el prefijo "rpe_" / "rpe" para no chocar con
--  objetos de ese otro proyecto. Revisar antes de ejecutar en el
--  proyecto real si "capturador-leads" ya tiene políticas propias
--  sobre estas tablas.
--
--  Resumen de correcciones respecto al schema legado (ver doc):
--   1. CRÍTICO: perfiles.rol ya no es auto-editable (trigger BEFORE
--      UPDATE bloquea el cambio de rol salvo que lo haga un admin).
--   2. RLS por rol: admin gestiona usuarios; organizador crea contenido;
--      usuario opera sin crear; externo solo eventos autorizados vía
--      usuarios_eventos (evento_asignado_id = activo/preferido).
--   3. Constraint UNIQUE(evento_id, email) en registrados: los
--      duplicados ahora fallan también a nivel de base de datos,
--      no solo por chequeos de la app.
--   4. Tabla usuarios_eventos (M:N usuario↔evento; rol_evento incluye
--      'externo' para autorizaciones de usuarios externos).
--   5. Política dedicada y acotada de INSERT anónimo en registrados
--      para el flujo de "registro por cliente" (autoregistro público),
--      limitada a eventos vigentes (fecha ≥ hoy) y con columnas mínimas obligatorias,
--      en vez de depender de un formulario externo fuera de este
--      repositorio (ver Sección 17.5 de la auditoría).
--   6. Función helper is_admin() SECURITY DEFINER para no repetir
--      subconsultas y evitar recursión de RLS.
-- ============================================================

-- ----------------------------------------------------------------
-- 0. Extensiones necesarias
-- ----------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto; -- gen_random_uuid()

-- ----------------------------------------------------------------
-- 1. TABLAS
-- ----------------------------------------------------------------
-- ⚠️ perfiles ↔ eventos es una dependencia CIRCULAR:
--    eventos.creado_por          → perfiles.id
--    perfiles.evento_asignado_id → eventos.id
-- No se puede declarar ambos FKs inline. Por eso perfiles se crea SIN el FK
-- a eventos; ese FK se agrega más abajo, tras crear public.eventos (bloque
-- "FK circular"). Así el script es válido también en una base de datos nueva
-- (antes fallaba con "relation public.eventos does not exist").
CREATE TABLE IF NOT EXISTS public.perfiles (
  id              uuid NOT NULL,
  nombre_completo text,
  rol             text NOT NULL DEFAULT 'user'
                    CHECK (rol = ANY (ARRAY['admin', 'organizador', 'user', 'externo'])),
  evento_asignado_id uuid,
  cambiar_pass    boolean NOT NULL DEFAULT false,
  activo          boolean NOT NULL DEFAULT true,
  foto_url        text,
  created_at      timestamptz NOT NULL DEFAULT timezone('utc', now()),
  updated_at      timestamptz NOT NULL DEFAULT timezone('utc', now()),
  CONSTRAINT perfiles_pkey PRIMARY KEY (id),
  CONSTRAINT perfiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users (id) ON DELETE CASCADE
);

-- Migración suave: legacy vendedor → user; 4 roles globales.
UPDATE public.perfiles SET rol = 'user' WHERE rol = 'vendedor';
ALTER TABLE public.perfiles ADD COLUMN IF NOT EXISTS evento_asignado_id uuid;
ALTER TABLE public.perfiles DROP CONSTRAINT IF EXISTS perfiles_rol_check;
ALTER TABLE public.perfiles
  ADD CONSTRAINT perfiles_rol_check
  CHECK (rol = ANY (ARRAY['admin', 'organizador', 'user', 'externo']));
ALTER TABLE public.perfiles ALTER COLUMN rol SET DEFAULT 'user';
CREATE INDEX IF NOT EXISTS idx_perfiles_evento_asignado
  ON public.perfiles (evento_asignado_id)
  WHERE evento_asignado_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.eventos (
  id                          uuid NOT NULL DEFAULT gen_random_uuid(),
  nombre                      text NOT NULL,
  pais                        text NOT NULL DEFAULT 'Chile'
                                CHECK (pais IN ('Chile', 'Perú')),
  fecha                       date NOT NULL,
  tematica                    text,
  creado_por                  uuid,
  direccion                   text,
  lugar                       text,
  certificacion_capacitacion  boolean NOT NULL DEFAULT false,
  imagen_url                  text,
  slug                        text,
  acceso_qr                   boolean NOT NULL DEFAULT false,
  cupo_maximo                 int,
  descripcion                 text,
  hora_inicio                 time,
  hora_fin                    time,
  inscripciones_cierre        timestamp,
  mapa_url                    text,
  banner_url                  text,
  duracion_dias               integer NOT NULL DEFAULT 1,
  created_at                  timestamptz NOT NULL DEFAULT timezone('utc', now()),
  updated_at                  timestamptz NOT NULL DEFAULT timezone('utc', now()),
  CONSTRAINT eventos_pkey PRIMARY KEY (id),
  CONSTRAINT eventos_creado_por_fkey FOREIGN KEY (creado_por) REFERENCES public.perfiles (id) ON DELETE SET NULL
);

-- CREATE TABLE IF NOT EXISTS no agrega columnas ni endurece nullability.
ALTER TABLE public.eventos
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT timezone('utc', now());
ALTER TABLE public.eventos ALTER COLUMN certificacion_capacitacion SET DEFAULT false;
UPDATE public.eventos SET certificacion_capacitacion = false
  WHERE certificacion_capacitacion IS NULL;
ALTER TABLE public.eventos ALTER COLUMN certificacion_capacitacion SET NOT NULL;

-- Duración: [fecha] es el primer día. Los eventos actuales duran 1 día.
ALTER TABLE public.eventos
  ADD COLUMN IF NOT EXISTS duracion_dias integer NOT NULL DEFAULT 1;
ALTER TABLE public.eventos
  DROP CONSTRAINT IF EXISTS eventos_duracion_dias_check;
ALTER TABLE public.eventos
  ADD CONSTRAINT eventos_duracion_dias_check
  CHECK (duracion_dias >= 1 AND duracion_dias <= 366);

CREATE OR REPLACE FUNCTION public.rpe_fecha_termino_evento(
  p_fecha date,
  p_duracion_dias integer
)
RETURNS date
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_fecha + (GREATEST(COALESCE(p_duracion_dias, 1), 1) - 1);
$$;
ALTER TABLE public.eventos DROP CONSTRAINT IF EXISTS eventos_creado_por_fkey;
ALTER TABLE public.eventos
  ADD CONSTRAINT eventos_creado_por_fkey
  FOREIGN KEY (creado_por) REFERENCES public.perfiles (id) ON DELETE SET NULL;

ALTER TABLE public.perfiles ALTER COLUMN rol SET DEFAULT 'user';
UPDATE public.perfiles SET rol = 'user' WHERE rol IS NULL;
ALTER TABLE public.perfiles ALTER COLUMN rol SET NOT NULL;
ALTER TABLE public.perfiles ALTER COLUMN cambiar_pass SET DEFAULT false;
UPDATE public.perfiles SET cambiar_pass = false WHERE cambiar_pass IS NULL;
ALTER TABLE public.perfiles ALTER COLUMN cambiar_pass SET NOT NULL;

-- FK circular perfiles.evento_asignado_id → eventos: se agrega ahora que
-- ambas tablas existen. Idempotente (solo si aún no está creada).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'perfiles_evento_asignado_id_fkey'
  ) THEN
    ALTER TABLE public.perfiles
      ADD CONSTRAINT perfiles_evento_asignado_id_fkey
      FOREIGN KEY (evento_asignado_id) REFERENCES public.eventos (id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.registrados (
  id                          uuid NOT NULL DEFAULT gen_random_uuid(),
  evento_id                   uuid NOT NULL,
  nombre_completo             text NOT NULL,
  email                       text NOT NULL,
  acreditado                  boolean NOT NULL DEFAULT false,
  acreditado_en               timestamptz,
  acreditado_por              uuid,
  rut                         text,
  patente                     text,
  empresa                     text,
  cargo                       text,
  telefono                    text,
  origen                      text NOT NULL DEFAULT 'app'
                                 CHECK (origen = ANY (ARRAY['app', 'excel', 'publico'])),
  ingresado_por               uuid,
  email_confirmacion_enviado  boolean NOT NULL DEFAULT false,
  sms_confirmacion_enviado    boolean NOT NULL DEFAULT false,
  whatsapp_confirmacion_enviado boolean NOT NULL DEFAULT false,
  codigo_qr                   text,
  sobrecupo                   boolean NOT NULL DEFAULT false,
  utm_source                  text,
  utm_medium                  text,
  utm_campaign                text,
  utm_content                 text,
  created_at                  timestamptz NOT NULL DEFAULT timezone('utc', now()),
  updated_at                  timestamptz NOT NULL DEFAULT timezone('utc', now()),
  CONSTRAINT registrados_pkey PRIMARY KEY (id),
  CONSTRAINT registrados_evento_id_fkey FOREIGN KEY (evento_id) REFERENCES public.eventos (id) ON DELETE CASCADE,
  CONSTRAINT registrados_ingresado_por_fkey FOREIGN KEY (ingresado_por) REFERENCES public.perfiles (id) ON DELETE SET NULL,
  CONSTRAINT registrados_acreditado_por_fkey FOREIGN KEY (acreditado_por) REFERENCES public.perfiles (id) ON DELETE SET NULL,
  -- Corrige el riesgo "Sin constraints de duplicados" (doc Sección 8.2/17.7):
  -- ahora la unicidad se garantiza en la base de datos, no solo en la app.
  CONSTRAINT registrados_evento_email_unique UNIQUE (evento_id, email)
);

ALTER TABLE public.registrados ALTER COLUMN acreditado SET DEFAULT false;
UPDATE public.registrados SET acreditado = false WHERE acreditado IS NULL;
ALTER TABLE public.registrados ALTER COLUMN acreditado SET NOT NULL;
ALTER TABLE public.registrados ALTER COLUMN email_confirmacion_enviado SET DEFAULT false;
UPDATE public.registrados SET email_confirmacion_enviado = false
  WHERE email_confirmacion_enviado IS NULL;
ALTER TABLE public.registrados ALTER COLUMN email_confirmacion_enviado SET NOT NULL;
ALTER TABLE public.registrados
  ADD COLUMN IF NOT EXISTS sms_confirmacion_enviado boolean NOT NULL DEFAULT false;
ALTER TABLE public.registrados DROP CONSTRAINT IF EXISTS registrados_ingresado_por_fkey;
ALTER TABLE public.registrados
  ADD CONSTRAINT registrados_ingresado_por_fkey
  FOREIGN KEY (ingresado_por) REFERENCES public.perfiles (id) ON DELETE SET NULL;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'registrados_evento_email_unique'
  ) THEN
    ALTER TABLE public.registrados
      ADD CONSTRAINT registrados_evento_email_unique UNIQUE (evento_id, email);
  END IF;
END $$;

-- evento_bloques y registrados.bloque_id se eliminan. El modelo nuevo
-- (subeventos, inscripciones, envíos, RPC) está en
-- supabase/migrations/202609251200_subeventos_cupos_ids_opacos.sql.
-- Este DROP evita que reaplicar el schema recree la tabla vieja.
DROP TABLE IF EXISTS public.evento_bloques CASCADE;
ALTER TABLE public.registrados DROP CONSTRAINT IF EXISTS registrados_bloque_id_fkey;
ALTER TABLE public.registrados DROP COLUMN IF EXISTS bloque_id CASCADE;

-- UTM (migración 20260729172353): opcionales; la app aún no las escribe.
ALTER TABLE public.registrados
  ADD COLUMN IF NOT EXISTS utm_source text;
ALTER TABLE public.registrados
  ADD COLUMN IF NOT EXISTS utm_medium text;
ALTER TABLE public.registrados
  ADD COLUMN IF NOT EXISTS utm_campaign text;
ALTER TABLE public.registrados
  ADD COLUMN IF NOT EXISTS utm_content text;

-- Autorizaciones usuario↔evento (M:N). Para rol global `externo`,
-- `rol_evento = 'externo'` define los eventos operables; el activo/preferido
-- sigue en perfiles.evento_asignado_id.
CREATE TABLE IF NOT EXISTS public.usuarios_eventos (
  usuario_id  uuid NOT NULL REFERENCES public.perfiles (id) ON DELETE CASCADE,
  evento_id   uuid NOT NULL REFERENCES public.eventos (id) ON DELETE CASCADE,
  rol_evento  text NOT NULL DEFAULT 'vendedor'
                CHECK (rol_evento = ANY (ARRAY[
                  'admin_evento', 'vendedor', 'acreditador', 'visor', 'externo'
                ])),
  created_at  timestamptz NOT NULL DEFAULT timezone('utc', now()),
  PRIMARY KEY (usuario_id, evento_id)
);

-- Compatibilidad con perfiles externos creados antes de la relación M:N.
-- La app y RLS usan usuarios_eventos como fuente de autorización; por eso el
-- evento preferido legado debe materializarse una vez en esa tabla.
INSERT INTO public.usuarios_eventos (usuario_id, evento_id, rol_evento)
SELECT p.id, p.evento_asignado_id, 'externo'
FROM public.perfiles p
WHERE p.rol = 'externo'
  AND p.evento_asignado_id IS NOT NULL
ON CONFLICT (usuario_id, evento_id) DO NOTHING;

-- Módulo Capturador de leads (app hermana fusionada). leads.evento_id NUNCA
-- apunta a eventos: siempre a eventos_leads.
--
-- Un evento de leads es interno (nace de un evento de registro, vía el menú de
-- Evento o la primera captura desde registrados) o externo (alta manual, sin
-- evento de origen). El tipo se persiste, no se deduce del NULL.
CREATE TABLE IF NOT EXISTS public.eventos_leads (
  id                          uuid NOT NULL DEFAULT gen_random_uuid(),
  nombre                      text NOT NULL,
  pais                        text NOT NULL DEFAULT 'Chile'
                                CHECK (pais IN ('Chile', 'Perú')),
  fecha                       date NOT NULL,
  tematica                    text,
  certificacion_capacitacion  boolean DEFAULT false,
  perfil_id                   uuid,
  evento_origen_id            uuid,
  tipo_evento_lead            text NOT NULL DEFAULT 'externo',
  duracion_dias               integer NOT NULL DEFAULT 1,
  created_at                  timestamptz DEFAULT now(),
  CONSTRAINT eventos_leads_pkey PRIMARY KEY (id),
  CONSTRAINT eventos_leads_perfil_id_fkey FOREIGN KEY (perfil_id)
    REFERENCES public.perfiles (id)
);

-- Instalaciones previas: CREATE TABLE IF NOT EXISTS no agrega columnas.
ALTER TABLE public.eventos_leads
  ADD COLUMN IF NOT EXISTS evento_origen_id uuid;
ALTER TABLE public.eventos_leads
  ADD COLUMN IF NOT EXISTS tipo_evento_lead text NOT NULL DEFAULT 'externo';

-- RESTRICT: borrar el evento de origen exigiría decidir qué pasa con los leads
-- ya capturados, así que la app obliga a eliminar antes el evento de leads.
ALTER TABLE public.eventos_leads
  DROP CONSTRAINT IF EXISTS eventos_leads_evento_origen_id_fkey;
ALTER TABLE public.eventos_leads
  ADD CONSTRAINT eventos_leads_evento_origen_id_fkey
  FOREIGN KEY (evento_origen_id) REFERENCES public.eventos (id)
  ON DELETE RESTRICT;

ALTER TABLE public.eventos_leads
  DROP CONSTRAINT IF EXISTS eventos_leads_tipo_evento_lead_check;
ALTER TABLE public.eventos_leads
  ADD CONSTRAINT eventos_leads_tipo_evento_lead_check
  CHECK (tipo_evento_lead IN ('interno', 'externo'));

ALTER TABLE public.eventos_leads
  DROP CONSTRAINT IF EXISTS eventos_leads_tipo_origen_check;
ALTER TABLE public.eventos_leads
  ADD CONSTRAINT eventos_leads_tipo_origen_check
  CHECK (
    (tipo_evento_lead = 'interno' AND evento_origen_id IS NOT NULL)
    OR (tipo_evento_lead = 'externo' AND evento_origen_id IS NULL)
  );

-- Portada heredada del evento de origen (internas) o propia (externas).
ALTER TABLE public.eventos_leads
  ADD COLUMN IF NOT EXISTS imagen_url text;

-- Duración de la captura: [fecha] es el primer día; puede ser 1, 3 o más.
ALTER TABLE public.eventos_leads
  ADD COLUMN IF NOT EXISTS duracion_dias integer NOT NULL DEFAULT 1;
ALTER TABLE public.eventos_leads
  DROP CONSTRAINT IF EXISTS eventos_leads_duracion_dias_check;
ALTER TABLE public.eventos_leads
  ADD CONSTRAINT eventos_leads_duracion_dias_check
  CHECK (duracion_dias >= 1 AND duracion_dias <= 366);

UPDATE public.eventos_leads el
SET
  nombre = e.nombre,
  fecha = e.fecha,
  duracion_dias = e.duracion_dias,
  pais = e.pais,
  tematica = e.tematica,
  certificacion_capacitacion = e.certificacion_capacitacion,
  imagen_url = e.imagen_url
FROM public.eventos e
WHERE el.tipo_evento_lead = 'interno'
  AND el.evento_origen_id = e.id;

CREATE TABLE IF NOT EXISTS public.leads (
  id                 uuid NOT NULL DEFAULT gen_random_uuid(),
  evento_id          uuid NOT NULL,
  nombre_completo    text NOT NULL,
  empresa            text,
  cargo              text,
  telefono           text,
  email              text,
  email_normalizado  text,
  descripcion        text,
  fotos_urls         text[] NOT NULL DEFAULT '{}'::text[],
  perfil_id          uuid,
  capturador_nombre  text NOT NULL DEFAULT 'Sin identificar',
  created_at         timestamptz DEFAULT now(),
  CONSTRAINT leads_pkey PRIMARY KEY (id),
  CONSTRAINT leads_evento_id_fkey FOREIGN KEY (evento_id)
    REFERENCES public.eventos_leads (id),
  CONSTRAINT leads_perfil_id_fkey FOREIGN KEY (perfil_id)
    REFERENCES public.perfiles (id)
);

-- Hilo grupal por lead. El nombre del autor se denormaliza para no abrir
-- la RLS de perfiles y para sobrevivir a la baja de la cuenta.
CREATE TABLE IF NOT EXISTS public.lead_comentarios (
  id           uuid NOT NULL DEFAULT gen_random_uuid(),
  lead_id      uuid NOT NULL,
  autor_id     uuid,
  autor_nombre text NOT NULL DEFAULT 'Sin identificar',
  autor_rol    text,
  cuerpo       text NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT timezone('utc', now()),
  updated_at   timestamptz NOT NULL DEFAULT timezone('utc', now()),
  CONSTRAINT lead_comentarios_pkey PRIMARY KEY (id),
  CONSTRAINT lead_comentarios_lead_id_fkey FOREIGN KEY (lead_id)
    REFERENCES public.leads (id) ON DELETE CASCADE,
  CONSTRAINT lead_comentarios_autor_id_fkey FOREIGN KEY (autor_id)
    REFERENCES public.perfiles (id),
  CONSTRAINT lead_comentarios_cuerpo_check CHECK (
    char_length(btrim(cuerpo)) BETWEEN 1 AND 1000
  )
);

-- Columnas agregadas de forma explícita porque CREATE TABLE IF NOT EXISTS no
-- modifica instalaciones previas. `capturador_nombre` evita abrir la RLS de
-- perfiles para mostrar quién capturó un lead.
ALTER TABLE public.leads
  ADD COLUMN IF NOT EXISTS email_normalizado text;
ALTER TABLE public.leads
  ADD COLUMN IF NOT EXISTS capturador_nombre text;

ALTER TABLE public.lead_comentarios
  ADD COLUMN IF NOT EXISTS autor_rol text;
ALTER TABLE public.lead_comentarios
  ADD COLUMN IF NOT EXISTS updated_at timestamptz;
UPDATE public.lead_comentarios
SET updated_at = created_at
WHERE updated_at IS NULL;

-- Al reprovisionar sobre una base existente se retiran temporalmente las
-- defensas para poder completar el backfill de filas legacy; se reinstalan
-- más abajo en esta misma transacción/script.
DROP TRIGGER IF EXISTS trg_leads_server_fields ON public.leads;
ALTER TABLE public.leads
  DROP CONSTRAINT IF EXISTS leads_email_formato_check;

UPDATE public.leads l
SET capturador_nombre = COALESCE(
  NULLIF(btrim(p.nombre_completo), ''),
  'Sin identificar'
)
FROM public.perfiles p
WHERE p.id = l.perfil_id
  AND NULLIF(btrim(l.capturador_nombre), '') IS NULL;

UPDATE public.leads
SET capturador_nombre = 'Sin identificar'
WHERE NULLIF(btrim(capturador_nombre), '') IS NULL;

ALTER TABLE public.leads
  ALTER COLUMN capturador_nombre SET DEFAULT 'Sin identificar';
ALTER TABLE public.leads
  ALTER COLUMN capturador_nombre SET NOT NULL;

-- No se eliminan ni mezclan duplicados históricos. El primero por campaña
-- recibe la clave normalizada; los demás conservan íntegro su email y quedan
-- con email_normalizado NULL. El trigger/RPC de más abajo detecta también esos
-- legados mediante lower(trim(email)).
WITH normalizados AS (
  SELECT
    l.id,
    NULLIF(lower(btrim(l.email)), '') AS email_normalizado,
    row_number() OVER (
      PARTITION BY l.evento_id, NULLIF(lower(btrim(l.email)), '')
      ORDER BY l.created_at NULLS LAST, l.id
    ) AS posicion
  FROM public.leads l
  WHERE NULLIF(lower(btrim(l.email)), '') IS NOT NULL
)
UPDATE public.leads l
SET email_normalizado = CASE
  WHEN n.posicion = 1 THEN n.email_normalizado
  ELSE NULL
END
FROM normalizados n
WHERE n.id = l.id
  AND l.email_normalizado IS DISTINCT FROM CASE
    WHEN n.posicion = 1 THEN n.email_normalizado
    ELSE NULL
  END;

UPDATE public.leads
SET email_normalizado = NULL
WHERE NULLIF(lower(btrim(email)), '') IS NULL
  AND email_normalizado IS NOT NULL;

-- NOT VALID conserva históricos incompletos, pero PostgreSQL exige la regla a
-- todo INSERT/UPDATE posterior.
ALTER TABLE public.leads
  ADD CONSTRAINT leads_email_formato_check
  CHECK (
    email IS NOT NULL
    AND btrim(email) <> ''
    AND email ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  ) NOT VALID;

-- ----------------------------------------------------------------
-- 2. Índices
-- ----------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_registrados_evento_id     ON public.registrados (evento_id);
CREATE INDEX IF NOT EXISTS idx_registrados_email         ON public.registrados (email);
CREATE INDEX IF NOT EXISTS idx_registrados_acreditado     ON public.registrados (evento_id, acreditado);
CREATE INDEX IF NOT EXISTS idx_eventos_creado_por         ON public.eventos (creado_por);
DROP INDEX IF EXISTS idx_eventos_activo_fecha;
CREATE INDEX IF NOT EXISTS idx_eventos_fecha              ON public.eventos (fecha DESC);
CREATE INDEX IF NOT EXISTS idx_usuarios_eventos_evento_id ON public.usuarios_eventos (evento_id);
CREATE INDEX IF NOT EXISTS idx_eventos_leads_perfil_id ON public.eventos_leads (perfil_id);
-- Un evento de registro no puede tener dos eventos de leads internos.
CREATE UNIQUE INDEX IF NOT EXISTS idx_eventos_leads_evento_origen_unique
  ON public.eventos_leads (evento_origen_id)
  WHERE evento_origen_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_leads_evento_id ON public.leads (evento_id);
CREATE INDEX IF NOT EXISTS idx_leads_perfil_id ON public.leads (perfil_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_leads_evento_email_normalizado_unique
  ON public.leads (evento_id, email_normalizado)
  WHERE email_normalizado IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_lead_comentarios_lead_created
  ON public.lead_comentarios (lead_id, created_at);

-- ----------------------------------------------------------------
-- 3. Funciones helper
-- ----------------------------------------------------------------

-- SECURITY DEFINER + tabla calificada evita el problema clásico de RLS
-- recursiva (una policy de "perfiles" que hace SELECT sobre "perfiles").
CREATE OR REPLACE FUNCTION public.rpe_is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.perfiles p
    WHERE p.id = auth.uid() AND p.rol = 'admin' AND p.activo = true
  );
$$;

CREATE OR REPLACE FUNCTION public.rpe_is_organizador()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.perfiles p
    WHERE p.id = auth.uid() AND p.rol = 'organizador' AND p.activo = true
  );
$$;

CREATE OR REPLACE FUNCTION public.rpe_can_manage_users()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT public.rpe_is_admin();
$$;

CREATE OR REPLACE FUNCTION public.rpe_can_create_content()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT public.rpe_is_admin() OR public.rpe_is_organizador();
$$;

CREATE OR REPLACE FUNCTION public.rpe_is_externo()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.perfiles p
    WHERE p.id = auth.uid() AND p.rol = 'externo' AND p.activo = true
  );
$$;

CREATE OR REPLACE FUNCTION public.rpe_is_internal_user()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.perfiles p
    WHERE p.id = auth.uid()
      AND p.rol IN ('admin', 'organizador', 'user')
      AND p.activo = true
  );
$$;

-- Alcance operativo por evento. Admin y organizador conservan acceso global;
-- user y externo requieren una asignación explícita en usuarios_eventos.
-- Deliberadamente no hay fallback para users existentes: hasta que un admin
-- los asigne, no pueden leer ni operar eventos.
CREATE OR REPLACE FUNCTION public.rpe_puede_operar_evento(p_evento_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.perfiles p
    WHERE p.id = auth.uid()
      AND p.activo = true
      AND (
        p.rol IN ('admin', 'organizador')
        OR (
          p.rol IN ('user', 'externo')
          AND EXISTS (
            SELECT 1
            FROM public.usuarios_eventos ue
            WHERE ue.usuario_id = p.id
              AND ue.evento_id = p_evento_id
          )
        )
      )
  );
$$;

-- Notificaciones no forman parte de la interfaz externa. Admin/organizador
-- ven el inbox global; user solo las asociadas a eventos asignados.
CREATE OR REPLACE FUNCTION public.rpe_puede_ver_notificacion(p_evento_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.perfiles p
    WHERE p.id = auth.uid()
      AND p.activo = true
      AND (
        p.rol IN ('admin', 'organizador')
        OR (
          p.rol = 'user'
          AND p_evento_id IS NOT NULL
          AND EXISTS (
            SELECT 1
            FROM public.usuarios_eventos ue
            WHERE ue.usuario_id = p.id
              AND ue.evento_id = p_evento_id
          )
        )
      )
  );
$$;

-- Preferido/activo del externo (compat). El alcance RLS usa rpe_externo_tiene_evento.
CREATE OR REPLACE FUNCTION public.rpe_evento_asignado_externo()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT p.evento_asignado_id
  FROM public.perfiles p
  WHERE p.id = auth.uid() AND p.rol = 'externo' AND p.activo = true;
$$;

CREATE OR REPLACE FUNCTION public.rpe_externo_tiene_evento(p_evento_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.perfiles p
    JOIN public.usuarios_eventos ue
      ON ue.usuario_id = p.id
    WHERE p.id = auth.uid()
      AND p.rol = 'externo'
      AND p.activo = true
      AND ue.evento_id = p_evento_id
  );
$$;

-- Evento de leads interno cuyo evento de origen tiene autorizado el externo.
CREATE OR REPLACE FUNCTION public.cl_externo_evento_origen_autorizado(
  p_evento_origen_id uuid
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT p_evento_origen_id IS NOT NULL
     AND public.rpe_is_externo()
     AND public.rpe_externo_tiene_evento(p_evento_origen_id);
$$;

-- Misma regla que cl_eventos_leads_select: con origen manda el id; sin él se
-- conserva el match por nombre para no cortarle el acceso a las filas
-- anteriores al vínculo. Se reutilizan los mismos helpers del SELECT para
-- que listar la actividad y pedir su resumen no diverjan.
CREATE OR REPLACE FUNCTION public.cl_externo_campana_autorizada(p_campana_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.eventos_leads el
    WHERE el.id = p_campana_id
      AND (
        public.cl_externo_evento_origen_autorizado(el.evento_origen_id)
        OR (
          el.evento_origen_id IS NULL
          AND public.cl_externo_nombre_campana_autorizado(el.nombre)
        )
      )
  );
$$;

-- Nombre de campaña coincide con evento autorizado (INSERT/SELECT).
CREATE OR REPLACE FUNCTION public.cl_externo_nombre_campana_autorizado(p_nombre text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.eventos e
    WHERE lower(trim(e.nombre)) = lower(trim(p_nombre))
      AND public.rpe_is_externo()
      AND public.rpe_externo_tiene_evento(e.id)
  );
$$;

-- Alcance único del módulo de captura. Las actividades externas no tienen
-- granularidad y son visibles para todo perfil activo. Las internas heredan
-- exclusivamente el permiso de su evento de origen; el nombre nunca concede
-- acceso porque no representa una relación de autorización.
CREATE OR REPLACE FUNCTION public.cl_campana_autorizada(p_campana_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.eventos_leads el
    WHERE el.id = p_campana_id
      AND (
        (
          el.evento_origen_id IS NULL
          AND (
            public.rpe_is_internal_user()
            OR public.rpe_is_externo()
          )
        )
        OR (
          el.evento_origen_id IS NOT NULL
          AND public.rpe_puede_operar_evento(el.evento_origen_id)
        )
      )
  );
$$;

-- Campos de identidad del lead controlados por servidor. El índice único
-- resuelve carreras entre capturas nuevas y la consulta adicional detecta los
-- duplicados históricos cuyo email_normalizado quedó NULL durante el backfill.
CREATE OR REPLACE FUNCTION public.cl_set_lead_server_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email_normalizado text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF auth.uid() IS NOT NULL THEN
      NEW.perfil_id := auth.uid();
    END IF;

    SELECT COALESCE(NULLIF(btrim(p.nombre_completo), ''), 'Sin identificar')
    INTO NEW.capturador_nombre
    FROM public.perfiles p
    WHERE p.id = NEW.perfil_id;

    IF NOT FOUND THEN
      NEW.capturador_nombre := 'Sin identificar';
    END IF;
  ELSE
    -- La autoría es inmutable incluso si un cliente intenta reasignarla.
    NEW.perfil_id := OLD.perfil_id;
    NEW.capturador_nombre := OLD.capturador_nombre;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.email := NULLIF(btrim(NEW.email), '');
    v_email_normalizado := NULLIF(lower(NEW.email), '');
    NEW.email_normalizado := v_email_normalizado;

    IF v_email_normalizado IS NOT NULL AND EXISTS (
      SELECT 1
      FROM public.leads l
      WHERE l.evento_id = NEW.evento_id
        AND l.id IS DISTINCT FROM NEW.id
        AND NULLIF(lower(btrim(l.email)), '') = v_email_normalizado
    ) THEN
      RAISE EXCEPTION USING
        ERRCODE = '23505',
        MESSAGE = 'El email ya fue capturado en esta campaña',
        CONSTRAINT = 'idx_leads_evento_email_normalizado_unique';
    END IF;
  ELSIF NEW.evento_id IS DISTINCT FROM OLD.evento_id
        OR NEW.email IS DISTINCT FROM OLD.email THEN
    NEW.email := NULLIF(btrim(NEW.email), '');
    v_email_normalizado := NULLIF(lower(NEW.email), '');
    NEW.email_normalizado := v_email_normalizado;

    IF v_email_normalizado IS NOT NULL AND EXISTS (
      SELECT 1
      FROM public.leads l
      WHERE l.evento_id = NEW.evento_id
        AND l.id IS DISTINCT FROM NEW.id
        AND NULLIF(lower(btrim(l.email)), '') = v_email_normalizado
    ) THEN
      RAISE EXCEPTION USING
        ERRCODE = '23505',
        MESSAGE = 'El email ya fue capturado en esta campaña',
        CONSTRAINT = 'idx_leads_evento_email_normalizado_unique';
    END IF;
  ELSE
    -- Evita que un cliente cambie directamente la clave normalizada.
    NEW.email_normalizado := OLD.email_normalizado;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_leads_server_fields ON public.leads;
CREATE TRIGGER trg_leads_server_fields
  BEFORE INSERT OR UPDATE ON public.leads
  FOR EACH ROW EXECUTE FUNCTION public.cl_set_lead_server_fields();

CREATE OR REPLACE FUNCTION public.cl_set_lead_comentario_server_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_nombre text;
  v_rol text;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.cuerpo IS NOT DISTINCT FROM OLD.cuerpo
       AND NEW.lead_id IS NOT DISTINCT FROM OLD.lead_id THEN
      NEW.updated_at := OLD.updated_at;
      RETURN NEW;
    END IF;

    NEW.id := OLD.id;
    NEW.lead_id := OLD.lead_id;
    NEW.autor_id := OLD.autor_id;
    NEW.autor_nombre := OLD.autor_nombre;
    NEW.autor_rol := OLD.autor_rol;
    NEW.created_at := OLD.created_at;
    NEW.cuerpo := btrim(NEW.cuerpo);
    NEW.updated_at := timezone('utc', now());
    RETURN NEW;
  END IF;

  IF auth.uid() IS NOT NULL THEN
    NEW.autor_id := auth.uid();
  END IF;

  SELECT
    COALESCE(NULLIF(btrim(p.nombre_completo), ''), 'Sin identificar'),
    p.rol
  INTO v_nombre, v_rol
  FROM public.perfiles p
  WHERE p.id = NEW.autor_id;

  IF NOT FOUND THEN
    NEW.autor_nombre := 'Sin identificar';
    NEW.autor_rol := NULL;
  ELSE
    NEW.autor_nombre := v_nombre;
    NEW.autor_rol := v_rol;
  END IF;

  NEW.cuerpo := btrim(NEW.cuerpo);
  NEW.updated_at := COALESCE(NEW.created_at, timezone('utc', now()));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_lead_comentarios_server_fields ON public.lead_comentarios;
CREATE TRIGGER trg_lead_comentarios_server_fields
  BEFORE INSERT OR UPDATE ON public.lead_comentarios
  FOR EACH ROW
  EXECUTE FUNCTION public.cl_set_lead_comentario_server_fields();

CREATE OR REPLACE FUNCTION public.rpe_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = timezone('utc', now());
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_perfiles_updated_at ON public.perfiles;
CREATE TRIGGER trg_perfiles_updated_at BEFORE UPDATE ON public.perfiles
  FOR EACH ROW EXECUTE FUNCTION public.rpe_set_updated_at();

DROP TRIGGER IF EXISTS trg_eventos_updated_at ON public.eventos;
CREATE TRIGGER trg_eventos_updated_at BEFORE UPDATE ON public.eventos
  FOR EACH ROW EXECUTE FUNCTION public.rpe_set_updated_at();

DROP TRIGGER IF EXISTS trg_registrados_updated_at ON public.registrados;
CREATE TRIGGER trg_registrados_updated_at BEFORE UPDATE ON public.registrados
  FOR EACH ROW EXECUTE FUNCTION public.rpe_set_updated_at();

-- El email es el identificador irrepetible del asistente. Se fuerza a
-- minúsculas para que UNIQUE(evento_id, email) no deje pasar "Ana@x.cl"
-- junto a "ana@x.cl" (causa habitual de duplicados por doble envío).
CREATE OR REPLACE FUNCTION public.rpe_normalizar_email_registrado()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.email := lower(trim(NEW.email));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_registrados_normalizar_email ON public.registrados;
CREATE TRIGGER trg_registrados_normalizar_email
  BEFORE INSERT OR UPDATE OF email ON public.registrados
  FOR EACH ROW EXECUTE FUNCTION public.rpe_normalizar_email_registrado();

-- Consulta case-insensitive usable también por `anon` (el formulario
-- público no tiene SELECT sobre registrados). SECURITY DEFINER solo
-- expone un boolean: no filtra filas hacia el cliente.
CREATE OR REPLACE FUNCTION public.rpe_existe_email_registrado(
  p_evento_id uuid,
  p_email text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.registrados
    WHERE evento_id = p_evento_id
      AND lower(trim(email)) = lower(trim(p_email))
  );
$$;

-- El externo acredita desde el escáner, pero no puede usar UPDATE como un
-- editor genérico de asistentes. Se permiten únicamente la transición
-- false->true y los campos de auditoría que genera ese flujo. La cola offline
-- que envía solo `acreditado=true` sigue siendo compatible.
CREATE OR REPLACE FUNCTION public.rpe_restrict_externo_registrado_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NOT public.rpe_is_externo() THEN
    RETURN NEW;
  END IF;

  IF NEW.acreditado IS NOT TRUE THEN
    RAISE EXCEPTION 'El usuario externo solo puede acreditar asistentes';
  END IF;

  IF (to_jsonb(NEW) - ARRAY[
        'acreditado', 'acreditado_en', 'acreditado_por', 'updated_at'
      ]) IS DISTINCT FROM
     (to_jsonb(OLD) - ARRAY[
        'acreditado', 'acreditado_en', 'acreditado_por', 'updated_at'
      ]) THEN
    RAISE EXCEPTION 'El usuario externo no puede editar datos del asistente';
  END IF;

  -- Idempotencia para cola offline y escáneres concurrentes: si otra sesión ya
  -- acreditó la fila, aceptar el no-op sin alterar quién/cuándo lo hizo.
  IF OLD.acreditado IS TRUE THEN
    NEW.acreditado := TRUE;
    NEW.acreditado_por := OLD.acreditado_por;
    NEW.acreditado_en := OLD.acreditado_en;
    RETURN NEW;
  END IF;

  IF NEW.acreditado_por IS NOT NULL AND NEW.acreditado_por <> auth.uid() THEN
    RAISE EXCEPTION 'La acreditación debe quedar asociada al usuario actual';
  END IF;

  -- El cliente online informa acreditado_por; la cola offline puede omitirlo.
  NEW.acreditado_por := auth.uid();
  NEW.acreditado_en := timezone('utc', now());
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_registrados_restrict_externo_update ON public.registrados;
CREATE TRIGGER trg_registrados_restrict_externo_update
  BEFORE UPDATE ON public.registrados
  FOR EACH ROW EXECUTE FUNCTION public.rpe_restrict_externo_registrado_update();

-- Actividad de captura interna: los campos de ficha se heredan del evento
-- ligado. El trigger de sync replica el UPDATE del evento; el de lock
-- rechaza un UPDATE directo que se desvíe de esa copia.
CREATE OR REPLACE FUNCTION public.rpe_sync_actividad_interna_desde_evento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.eventos_leads
  SET
    nombre = NEW.nombre,
    fecha = NEW.fecha,
    duracion_dias = NEW.duracion_dias,
    pais = NEW.pais,
    tematica = NEW.tematica,
    certificacion_capacitacion = NEW.certificacion_capacitacion,
    imagen_url = NEW.imagen_url
  WHERE evento_origen_id = NEW.id
    AND tipo_evento_lead = 'interno';
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_eventos_sync_actividad_interna ON public.eventos;
CREATE TRIGGER trg_eventos_sync_actividad_interna
  AFTER UPDATE OF nombre, fecha, duracion_dias, pais, tematica,
    certificacion_capacitacion, imagen_url
  ON public.eventos
  FOR EACH ROW
  EXECUTE FUNCTION public.rpe_sync_actividad_interna_desde_evento();

CREATE OR REPLACE FUNCTION public.rpe_lock_actividad_interna_campos()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  coincide boolean;
BEGIN
  IF NEW.tipo_evento_lead IS DISTINCT FROM OLD.tipo_evento_lead
     OR NEW.evento_origen_id IS DISTINCT FROM OLD.evento_origen_id THEN
    RAISE EXCEPTION
      'No se puede cambiar el origen de una actividad de captura';
  END IF;

  IF NEW.tipo_evento_lead <> 'interno' THEN
    RETURN NEW;
  END IF;

  IF NEW.nombre IS NOT DISTINCT FROM OLD.nombre
     AND NEW.fecha IS NOT DISTINCT FROM OLD.fecha
     AND NEW.duracion_dias IS NOT DISTINCT FROM OLD.duracion_dias
     AND NEW.pais IS NOT DISTINCT FROM OLD.pais
     AND NEW.tematica IS NOT DISTINCT FROM OLD.tematica
     AND NEW.certificacion_capacitacion
           IS NOT DISTINCT FROM OLD.certificacion_capacitacion
     AND NEW.imagen_url IS NOT DISTINCT FROM OLD.imagen_url THEN
    RETURN NEW;
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.eventos e
    WHERE e.id = NEW.evento_origen_id
      AND e.nombre IS NOT DISTINCT FROM NEW.nombre
      AND e.fecha IS NOT DISTINCT FROM NEW.fecha
      AND e.duracion_dias IS NOT DISTINCT FROM NEW.duracion_dias
      AND e.pais IS NOT DISTINCT FROM NEW.pais
      AND e.tematica IS NOT DISTINCT FROM NEW.tematica
      AND e.certificacion_capacitacion
            IS NOT DISTINCT FROM NEW.certificacion_capacitacion
      AND e.imagen_url IS NOT DISTINCT FROM NEW.imagen_url
  ) INTO coincide;

  IF NOT coincide THEN
    RAISE EXCEPTION
      'Los datos de una actividad de captura interna se heredan del evento ligado';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_eventos_leads_lock_interna ON public.eventos_leads;
CREATE TRIGGER trg_eventos_leads_lock_interna
  BEFORE UPDATE ON public.eventos_leads
  FOR EACH ROW
  EXECUTE FUNCTION public.rpe_lock_actividad_interna_campos();

-- --- CORRECCIÓN CRÍTICA (doc Sección 8.2/17.6): anti-escalación de rol ---
-- RLS por sí sola no puede comparar OLD vs NEW en un UPDATE (WITH CHECK solo
-- ve la fila nueva). Por eso la regla de negocio "nadie puede cambiar su
-- propio rol salvo un admin" se implementa acá, en un trigger, que sí tiene
-- acceso a OLD y NEW.
CREATE OR REPLACE FUNCTION public.rpe_prevent_role_self_escalation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.rol IS DISTINCT FROM OLD.rol AND NOT public.rpe_is_admin() THEN
    RAISE EXCEPTION 'Solo un administrador puede cambiar el rol de un usuario';
  END IF;

  IF NEW.activo IS DISTINCT FROM OLD.activo AND NOT public.rpe_is_admin() THEN
    RAISE EXCEPTION 'Solo un administrador puede activar/desactivar un usuario';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_perfiles_prevent_role_escalation ON public.perfiles;
CREATE TRIGGER trg_perfiles_prevent_role_escalation
  BEFORE UPDATE ON public.perfiles
  FOR EACH ROW EXECUTE FUNCTION public.rpe_prevent_role_self_escalation();

CREATE OR REPLACE FUNCTION public.rpe_validate_perfil_externo()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.rol = 'externo' AND NEW.evento_asignado_id IS NULL THEN
    RAISE EXCEPTION 'Un usuario externo debe tener evento_asignado_id';
  END IF;
  IF NEW.rol <> 'externo' AND NEW.evento_asignado_id IS NOT NULL THEN
    NEW.evento_asignado_id := NULL;
  END IF;
  IF TG_OP = 'UPDATE'
     AND NEW.rol = 'externo'
     AND NEW.evento_asignado_id IS NOT NULL
     AND EXISTS (
       SELECT 1 FROM public.usuarios_eventos ue WHERE ue.usuario_id = NEW.id
     )
     AND NOT EXISTS (
       SELECT 1
       FROM public.usuarios_eventos ue
       WHERE ue.usuario_id = NEW.id
         AND ue.evento_id = NEW.evento_asignado_id
     ) THEN
    RAISE EXCEPTION 'El evento activo debe estar entre los autorizados del usuario';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_perfiles_validate_externo ON public.perfiles;
CREATE TRIGGER trg_perfiles_validate_externo
  BEFORE INSERT OR UPDATE ON public.perfiles
  FOR EACH ROW EXECUTE FUNCTION public.rpe_validate_perfil_externo();

-- Crea automáticamente el perfil al confirmarse un nuevo usuario en auth.users,
-- evitando el flujo manual/edge-case de "usuario ofuscado" documentado en
-- authService.ts (doc Sección 3.8). El rol por defecto es el más bajo posible.
CREATE OR REPLACE FUNCTION public.rpe_handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rol text := COALESCE(NEW.raw_user_meta_data ->> 'rol', 'user');
  v_evento_id uuid := NULL;
BEGIN
  IF v_rol = 'externo' THEN
    v_evento_id := NULLIF(NEW.raw_user_meta_data ->> 'evento_id', '')::uuid;
  ELSE
    v_rol := 'user';
  END IF;

  IF v_rol NOT IN ('admin', 'organizador', 'user', 'externo') THEN
    v_rol := 'user';
  END IF;

  INSERT INTO public.perfiles (id, nombre_completo, rol, evento_asignado_id)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data ->> 'nombre_completo', split_part(NEW.email, '@', 1)),
    v_rol,
    v_evento_id
  )
  ON CONFLICT (id) DO NOTHING;

  IF v_rol = 'externo' AND v_evento_id IS NOT NULL THEN
    INSERT INTO public.usuarios_eventos (usuario_id, evento_id, rol_evento)
    VALUES (NEW.id, v_evento_id, 'externo')
    ON CONFLICT (usuario_id, evento_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_on_auth_user_created ON auth.users;
CREATE TRIGGER trg_on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.rpe_handle_new_user();

-- ----------------------------------------------------------------
-- 4. RPCs usadas por la app (equivalentes a las del proyecto legado)
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marcar_recuperacion_pass(email_input text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.perfiles
  SET cambiar_pass = true
  WHERE id = (SELECT id FROM auth.users WHERE email = email_input);
END;
$$;

CREATE OR REPLACE FUNCTION public.verificar_usuario_registrado(email_check text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (SELECT 1 FROM auth.users WHERE email = email_check);
$$;

-- Lookup de auth.users por email para Edge Functions (service role).
-- La usa `reset-password` (vía _shared/find_user.ts) porque
-- auth.admin.listUsers() falla en este proyecto con "Database error finding
-- users". Solo service_role puede ejecutarla (no expuesta a authenticated/anon).
CREATE OR REPLACE FUNCTION public.rpe_auth_user_id_por_email(email_input text)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
STABLE
AS $$
  SELECT u.id
  FROM auth.users u
  WHERE lower(u.email) = lower(trim(email_input))
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.rpe_auth_user_id_por_email(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rpe_auth_user_id_por_email(text) TO service_role;

-- Admin: email de auth.users para formularios de gestión.
CREATE OR REPLACE FUNCTION public.rpe_obtener_email_usuario(usuario_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NOT public.rpe_is_admin() THEN
    RAISE EXCEPTION 'Solo un administrador puede consultar emails de usuarios';
  END IF;

  RETURN (
    SELECT u.email
    FROM auth.users u
    WHERE u.id = usuario_id
  );
END;
$$;

-- Configuración administrativa atómica: rol global y alcance de eventos se
-- cambian dentro de la misma transacción. `user` puede quedar sin eventos
-- (acceso cerrado); `externo` requiere al menos uno; admin/organizador son
-- globales y no conservan filas en usuarios_eventos.
CREATE OR REPLACE FUNCTION public.rpe_configurar_acceso_usuario(
  p_usuario_id uuid,
  p_nuevo_rol text,
  p_evento_ids uuid[] DEFAULT '{}'::uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rol_actual text;
  v_evento_ids uuid[];
  v_primer_evento uuid;
  v_rol_evento text;
BEGIN
  IF NOT public.rpe_is_admin() THEN
    RAISE EXCEPTION 'Solo un administrador puede configurar accesos';
  END IF;

  IF p_nuevo_rol NOT IN ('admin', 'organizador', 'user', 'externo') THEN
    RAISE EXCEPTION 'Rol inválido: %', p_nuevo_rol;
  END IF;

  SELECT p.rol
  INTO v_rol_actual
  FROM public.perfiles p
  WHERE p.id = p_usuario_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Usuario no encontrado';
  END IF;

  SELECT COALESCE(
    array_agg(ids.evento_id ORDER BY ids.primera_posicion),
    '{}'::uuid[]
  )
  INTO v_evento_ids
  FROM (
    SELECT entrada.evento_id, min(entrada.orden) AS primera_posicion
    FROM unnest(COALESCE(p_evento_ids, '{}'::uuid[]))
      WITH ORDINALITY AS entrada(evento_id, orden)
    WHERE entrada.evento_id IS NOT NULL
    GROUP BY entrada.evento_id
  ) ids;

  IF p_nuevo_rol IN ('admin', 'organizador') THEN
    v_evento_ids := '{}'::uuid[];
  ELSIF p_nuevo_rol = 'externo' AND cardinality(v_evento_ids) < 1 THEN
    RAISE EXCEPTION 'Debe seleccionar al menos un evento para el usuario externo';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM unnest(v_evento_ids) AS eid
    WHERE NOT EXISTS (SELECT 1 FROM public.eventos e WHERE e.id = eid)
  ) THEN
    RAISE EXCEPTION 'Uno o más eventos no existen';
  END IF;

  IF p_nuevo_rol = 'externo' AND EXISTS (
    SELECT 1
    FROM public.eventos e
    WHERE e.id = ANY(v_evento_ids)
      AND public.rpe_fecha_termino_evento(e.fecha, e.duracion_dias)
            < CURRENT_DATE
  ) THEN
    RAISE EXCEPTION 'Los externos solo pueden usar eventos no finalizados';
  END IF;

  v_primer_evento := v_evento_ids[1];
  v_rol_evento := CASE
    WHEN p_nuevo_rol = 'externo' THEN 'externo'
    ELSE 'vendedor'
  END;

  DELETE FROM public.usuarios_eventos ue
  WHERE ue.usuario_id = p_usuario_id;

  IF p_nuevo_rol IN ('user', 'externo') AND cardinality(v_evento_ids) > 0 THEN
    INSERT INTO public.usuarios_eventos (usuario_id, evento_id, rol_evento)
    SELECT p_usuario_id, eid, v_rol_evento
    FROM unnest(v_evento_ids) AS eid;
  END IF;

  -- Los pins no autorizan acceso, pero sí ocupan el límite del usuario y
  -- podrían reaparecer si el evento vuelve a ser visible. Se limpian en la
  -- misma transacción al reducir el alcance; pins de campañas no se tocan.
  IF to_regclass('public.usuarios_eventos_fijados') IS NOT NULL
     AND p_nuevo_rol IN ('user', 'externo') THEN
    DELETE FROM public.usuarios_eventos_fijados f
    WHERE f.usuario_id = p_usuario_id
      AND NOT (f.evento_id = ANY(v_evento_ids));
  END IF;

  UPDATE public.perfiles p
  SET rol = p_nuevo_rol,
      evento_asignado_id = CASE
        WHEN p_nuevo_rol = 'externo' THEN v_primer_evento
        ELSE NULL
      END
  WHERE p.id = p_usuario_id;
END;
$$;

-- Reemplaza asignaciones sin cambiar el rol.
CREATE OR REPLACE FUNCTION public.rpe_sincronizar_eventos_usuario(
  p_usuario_id uuid,
  p_evento_ids uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rol text;
BEGIN
  IF NOT public.rpe_is_admin() THEN
    RAISE EXCEPTION 'Solo un administrador puede sincronizar eventos';
  END IF;

  SELECT p.rol INTO v_rol
  FROM public.perfiles p
  WHERE p.id = p_usuario_id;

  IF v_rol IS NULL THEN
    RAISE EXCEPTION 'Usuario no encontrado';
  END IF;
  IF v_rol NOT IN ('user', 'externo') THEN
    RAISE EXCEPTION 'Solo se asignan eventos a usuarios user o externo';
  END IF;

  PERFORM public.rpe_configurar_acceso_usuario(
    p_usuario_id,
    v_rol,
    COALESCE(p_evento_ids, '{}'::uuid[])
  );
END;
$$;

-- Wrappers compatibles con clientes desplegados previamente.
CREATE OR REPLACE FUNCTION public.rpe_actualizar_rol_usuario(
  usuario_id uuid,
  nuevo_rol text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF nuevo_rol = 'externo' THEN
    RAISE EXCEPTION 'Use rpe_configurar_acceso_usuario para asignar un externo';
  END IF;
  PERFORM public.rpe_configurar_acceso_usuario(
    usuario_id,
    nuevo_rol,
    '{}'::uuid[]
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.rpe_sincronizar_eventos_externo(
  p_usuario_id uuid,
  p_evento_ids uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rol text;
BEGIN
  SELECT p.rol INTO v_rol
  FROM public.perfiles p
  WHERE p.id = p_usuario_id;

  IF v_rol IS DISTINCT FROM 'externo' THEN
    RAISE EXCEPTION 'Solo se pueden sincronizar eventos de usuarios externos';
  END IF;

  PERFORM public.rpe_sincronizar_eventos_usuario(p_usuario_id, p_evento_ids);
END;
$$;

-- Administración atómica del alcance de un evento: qué usuarios `user` y
-- `externo` quedan autorizados. Admin y organizador conservan acceso global
-- y no se materializan en usuarios_eventos.
CREATE OR REPLACE FUNCTION public.rpe_configurar_acceso_evento(
  p_evento_id uuid,
  p_usuario_ids uuid[] DEFAULT '{}'::uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_usuario_ids uuid[];
  v_evento_fecha date;
  r record;
BEGIN
  IF NOT public.rpe_is_admin() THEN
    RAISE EXCEPTION 'Solo un administrador puede configurar accesos';
  END IF;

  SELECT public.rpe_fecha_termino_evento(e.fecha, e.duracion_dias)
  INTO v_evento_fecha
  FROM public.eventos e
  WHERE e.id = p_evento_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Evento no encontrado';
  END IF;

  SELECT COALESCE(array_agg(DISTINCT uid), '{}'::uuid[])
  INTO v_usuario_ids
  FROM unnest(COALESCE(p_usuario_ids, '{}'::uuid[])) AS uid
  WHERE uid IS NOT NULL;

  IF EXISTS (
    SELECT 1
    FROM unnest(v_usuario_ids) AS uid
    WHERE uid = '00000000-0000-0000-0000-000000000001'::uuid
       OR NOT EXISTS (
         SELECT 1
         FROM public.perfiles p
         WHERE p.id = uid
           AND p.rol IN ('user', 'externo')
       )
  ) THEN
    RAISE EXCEPTION 'Solo se puede asignar acceso a usuarios o usuarios externos';
  END IF;

  IF v_evento_fecha < CURRENT_DATE THEN
    IF EXISTS (
      SELECT 1
      FROM unnest(v_usuario_ids) AS uid
      JOIN public.perfiles p ON p.id = uid
      WHERE p.rol = 'externo'
        AND NOT EXISTS (
          SELECT 1
          FROM public.usuarios_eventos ue
          WHERE ue.usuario_id = uid
            AND ue.evento_id = p_evento_id
        )
    ) THEN
      RAISE EXCEPTION 'Los externos solo pueden usar eventos no finalizados';
    END IF;
  END IF;

  FOR r IN
    SELECT p.id, p.nombre_completo, p.rol
    FROM public.usuarios_eventos ue
    JOIN public.perfiles p ON p.id = ue.usuario_id
    WHERE ue.evento_id = p_evento_id
      AND NOT (ue.usuario_id = ANY (v_usuario_ids))
    FOR UPDATE OF p
  LOOP
    IF r.rol = 'externo' AND NOT EXISTS (
      SELECT 1
      FROM public.usuarios_eventos ue
      WHERE ue.usuario_id = r.id
        AND ue.evento_id <> p_evento_id
    ) THEN
      RAISE EXCEPTION
        'No se puede quitar el acceso de %: el usuario externo debe conservar al menos un evento',
        r.nombre_completo;
    END IF;
  END LOOP;

  DELETE FROM public.usuarios_eventos ue
  WHERE ue.evento_id = p_evento_id
    AND NOT (ue.usuario_id = ANY (v_usuario_ids));

  IF to_regclass('public.usuarios_eventos_fijados') IS NOT NULL THEN
    DELETE FROM public.usuarios_eventos_fijados f
    WHERE f.evento_id = p_evento_id
      AND NOT (f.usuario_id = ANY (v_usuario_ids));
  END IF;

  INSERT INTO public.usuarios_eventos (usuario_id, evento_id, rol_evento)
  SELECT
    p.id,
    p_evento_id,
    CASE WHEN p.rol = 'externo' THEN 'externo' ELSE 'vendedor' END
  FROM public.perfiles p
  WHERE p.id = ANY (v_usuario_ids)
  ON CONFLICT (usuario_id, evento_id) DO NOTHING;

  UPDATE public.perfiles p
  SET evento_asignado_id = (
    SELECT ue.evento_id
    FROM public.usuarios_eventos ue
    WHERE ue.usuario_id = p.id
    ORDER BY ue.created_at
    LIMIT 1
  )
  WHERE p.rol = 'externo'
    AND p.evento_asignado_id = p_evento_id
    AND NOT (p.id = ANY (v_usuario_ids));

  UPDATE public.perfiles p
  SET evento_asignado_id = p_evento_id
  WHERE p.rol = 'externo'
    AND p.id = ANY (v_usuario_ids)
    AND p.evento_asignado_id IS NULL;
END;
$$;

-- Alta/edición atómica de leads. La identidad de captura y la detección de
-- duplicados se resuelven en servidor; las fotos se adjuntan después mediante
-- UPDATE del lead propio. Un p_lead_id inexistente se usa como UUID de alta,
-- lo que hace idempotente el reintento del cliente/offline.
CREATE OR REPLACE FUNCTION public.cl_guardar_lead(
  p_evento_id uuid,
  p_nombre_completo text,
  p_empresa text,
  p_cargo text,
  p_telefono text,
  p_email text,
  p_descripcion text,
  p_lead_id uuid DEFAULT NULL
)
RETURNS TABLE (
  resultado text,
  lead_id uuid,
  primer_capturador_nombre text,
  es_propio boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_usuario_id uuid := auth.uid();
  v_rol text;
  v_activo boolean;
  v_capturador_nombre text;
  v_email text := NULLIF(btrim(p_email), '');
  v_email_normalizado text := NULLIF(lower(btrim(p_email)), '');
  v_telefono text := NULLIF(btrim(p_telefono), '');
  v_lead_id uuid := COALESCE(p_lead_id, gen_random_uuid());
  v_existente public.leads%ROWTYPE;
  v_duplicado public.leads%ROWTYPE;
  v_guardado public.leads%ROWTYPE;
  v_puede_editar_global boolean;
BEGIN
  IF v_usuario_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'No autenticado';
  END IF;

  SELECT
    p.rol,
    p.activo,
    COALESCE(NULLIF(btrim(p.nombre_completo), ''), 'Sin identificar')
  INTO v_rol, v_activo, v_capturador_nombre
  FROM public.perfiles p
  WHERE p.id = v_usuario_id;

  IF NOT FOUND OR v_activo IS NOT TRUE THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Usuario inactivo o sin perfil';
  END IF;

  v_puede_editar_global := v_rol IN ('admin', 'organizador');

  IF NOT EXISTS (
    SELECT 1 FROM public.eventos_leads el WHERE el.id = p_evento_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'Campaña no encontrada';
  END IF;

  IF NOT public.cl_campana_autorizada(p_evento_id) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Sin acceso a la campaña';
  END IF;

  IF NULLIF(btrim(p_nombre_completo), '') IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'El nombre es obligatorio';
  END IF;

  -- La fila se carga antes de validar el email porque quien no edita de forma
  -- global tampoco puede cambiar el contacto: su email y teléfono se reemplazan
  -- por los ya guardados, y son esos los que se validan y se buscan duplicados.
  IF p_lead_id IS NOT NULL THEN
    SELECT l.* INTO v_existente
    FROM public.leads l
    WHERE l.id = p_lead_id
    FOR UPDATE;

    IF FOUND THEN
      IF v_existente.evento_id <> p_evento_id THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'El lead pertenece a otra campaña';
      END IF;
      IF NOT v_puede_editar_global
         AND v_existente.perfil_id IS DISTINCT FROM v_usuario_id THEN
        RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Solo puedes editar tus propios leads';
      END IF;
      IF NOT v_puede_editar_global THEN
        v_email := NULLIF(btrim(v_existente.email), '');
        v_email_normalizado := NULLIF(lower(btrim(v_existente.email)), '');
        v_telefono := NULLIF(btrim(v_existente.telefono), '');
      END IF;
    END IF;
  END IF;

  IF v_email IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'El email es obligatorio';
  END IF;

  IF v_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'El email no es válido';
  END IF;

  -- Serializa por campaña+email. El índice único sigue siendo la última línea
  -- de defensa para escrituras directas y clientes concurrentes.
  IF v_email_normalizado IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(
      hashtextextended(p_evento_id::text || ':' || v_email_normalizado, 0)
    );
  END IF;

  IF v_email_normalizado IS NOT NULL THEN
    SELECT l.* INTO v_duplicado
    FROM public.leads l
    WHERE l.evento_id = p_evento_id
      AND l.id IS DISTINCT FROM v_lead_id
      AND NULLIF(lower(btrim(l.email)), '') = v_email_normalizado
    ORDER BY l.created_at NULLS LAST, l.id
    LIMIT 1;

    IF FOUND THEN
      RETURN QUERY SELECT
        'duplicado'::text,
        v_duplicado.id,
        v_duplicado.capturador_nombre,
        v_duplicado.perfil_id = v_usuario_id;
      RETURN;
    END IF;
  END IF;

  IF v_existente.id IS NOT NULL THEN
    UPDATE public.leads l
    SET nombre_completo = btrim(p_nombre_completo),
        empresa = NULLIF(btrim(p_empresa), ''),
        cargo = NULLIF(btrim(p_cargo), ''),
        telefono = v_telefono,
        email = v_email,
        descripcion = NULLIF(btrim(p_descripcion), '')
    WHERE l.id = v_existente.id
    RETURNING l.* INTO v_guardado;

    RETURN QUERY SELECT
      'actualizado'::text,
      v_guardado.id,
      v_guardado.capturador_nombre,
      v_guardado.perfil_id = v_usuario_id;
    RETURN;
  END IF;

  INSERT INTO public.leads (
    id,
    evento_id,
    nombre_completo,
    empresa,
    cargo,
    telefono,
    email,
    descripcion,
    perfil_id,
    capturador_nombre
  ) VALUES (
    v_lead_id,
    p_evento_id,
    btrim(p_nombre_completo),
    NULLIF(btrim(p_empresa), ''),
    NULLIF(btrim(p_cargo), ''),
    v_telefono,
    v_email,
    NULLIF(btrim(p_descripcion), ''),
    v_usuario_id,
    v_capturador_nombre
  )
  RETURNING * INTO v_guardado;

  RETURN QUERY SELECT
    'creado'::text,
    v_guardado.id,
    v_guardado.capturador_nombre,
    true;
  RETURN;
EXCEPTION
  WHEN unique_violation THEN
    SELECT l.* INTO v_duplicado
    FROM public.leads l
    WHERE l.evento_id = p_evento_id
      AND l.id IS DISTINCT FROM v_lead_id
      AND NULLIF(lower(btrim(l.email)), '') = v_email_normalizado
    ORDER BY l.created_at NULLS LAST, l.id
    LIMIT 1;

    IF FOUND THEN
      RETURN QUERY SELECT
        'duplicado'::text,
        v_duplicado.id,
        v_duplicado.capturador_nombre,
        v_duplicado.perfil_id = v_usuario_id;
      RETURN;
    END IF;
    RAISE;
END;
$$;

-- Conteos de campaña para quien puede abrirla. No expone filas, pero conserva
-- exactamente el mismo alcance por evento que el catálogo y los leads.
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

  IF NOT public.cl_campana_autorizada(p_evento_id) THEN
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

-- Lookup de duplicado al escanear: misma normalización que cl_guardar_lead.
CREATE OR REPLACE FUNCTION public.cl_buscar_lead_por_email(
  p_evento_id uuid,
  p_email text
)
RETURNS TABLE (
  lead_id uuid,
  capturador_nombre text,
  es_propio boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_usuario_id uuid := auth.uid();
  v_rol text;
  v_activo boolean;
  v_email_normalizado text := NULLIF(lower(btrim(p_email)), '');
  v_existente public.leads%ROWTYPE;
BEGIN
  IF v_usuario_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'No autenticado';
  END IF;

  SELECT p.rol, p.activo
  INTO v_rol, v_activo
  FROM public.perfiles p
  WHERE p.id = v_usuario_id;

  IF NOT FOUND OR v_activo IS NOT TRUE THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Usuario inactivo o sin perfil';
  END IF;

  IF p_evento_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.eventos_leads el WHERE el.id = p_evento_id
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'Campaña no encontrada';
  END IF;

  IF NOT public.cl_campana_autorizada(p_evento_id) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'Sin acceso a la campaña';
  END IF;

  IF v_email_normalizado IS NULL THEN
    RETURN;
  END IF;

  SELECT l.* INTO v_existente
  FROM public.leads l
  WHERE l.evento_id = p_evento_id
    AND NULLIF(lower(btrim(l.email)), '') = v_email_normalizado
  ORDER BY l.created_at NULLS LAST, l.id
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  lead_id := v_existente.id;
  capturador_nombre := v_existente.capturador_nombre;
  es_propio := v_existente.perfil_id = v_usuario_id;
  RETURN NEXT;
END;
$$;

-- Perfil sistema al que se reasignan las acreditaciones cuando se
-- elimina al usuario que las hizo. UUID fijo; no aparece en la UI
-- de gestión (activo=false). Ver RPC rpe_eliminar_usuario más abajo.
INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, is_super_admin, is_sso_user, is_anonymous,
  banned_until, confirmation_token, recovery_token,
  email_change_token_new, email_change
)
VALUES (
  '00000000-0000-0000-0000-000000000001'::uuid,
  '00000000-0000-0000-0000-000000000000'::uuid,
  'authenticated', 'authenticated',
  'sistema.usuario.eliminado@internal.local',
  crypt(gen_random_uuid()::text, gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"nombre_completo":"Usuario eliminado"}'::jsonb,
  now(), now(), false, false, false, 'infinity'::timestamptz,
  '', '', '', ''
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.perfiles (id, nombre_completo, rol, activo, cambiar_pass)
VALUES (
  '00000000-0000-0000-0000-000000000001'::uuid,
  'Usuario eliminado', 'user', false, false
)
ON CONFLICT (id) DO NOTHING;

-- Evita el RAISE del trigger anti-escalación al fijar activo=false
-- desde el SQL Editor (sin JWT de admin).
ALTER TABLE public.perfiles
  DISABLE TRIGGER trg_perfiles_prevent_role_escalation;
UPDATE public.perfiles
SET nombre_completo = 'Usuario eliminado', activo = false, cambiar_pass = false, rol = 'user'
WHERE id = '00000000-0000-0000-0000-000000000001'::uuid;
ALTER TABLE public.perfiles
  ENABLE TRIGGER trg_perfiles_prevent_role_escalation;

-- Elimina por completo la cuenta de un usuario. Debe ser un RPC
-- SECURITY DEFINER porque el cliente (anon key) no tiene permisos sobre
-- auth.users.
--
-- Regla de negocio: todas las FKs históricas (acreditado_por,
-- ingresado_por, creado_por, leads.perfil_id, eventos_leads.perfil_id,
-- lead_comentarios.autor_id) se reasignan al perfil sistema "Usuario
-- eliminado" (uuid fijo). No deben quedar NULL. Si otra tabla ajena
-- bloquea el DELETE de auth.users, se degrada a ban permanente
-- ('desactivado').
--
-- Devuelve 'eliminado' o 'desactivado' según el resultado.
DROP FUNCTION IF EXISTS public.rpe_eliminar_usuario(uuid);
CREATE FUNCTION public.rpe_eliminar_usuario(usuario_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

  -- Reasignar historial al perfil "Usuario eliminado" (sin NULL).
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'registrados'
      AND column_name = 'acreditado_por'
  ) THEN
    UPDATE public.registrados
    SET acreditado_por = v_sentinel
    WHERE acreditado_por = usuario_id;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'registrados' AND column_name = 'ingresado_por'
  ) THEN
    UPDATE public.registrados
    SET ingresado_por = v_sentinel
    WHERE ingresado_por = usuario_id;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'eventos' AND column_name = 'creado_por'
  ) THEN
    UPDATE public.eventos
    SET creado_por = v_sentinel
    WHERE creado_por = usuario_id;
  END IF;

  IF to_regclass('public.usuarios_eventos') IS NOT NULL THEN
    DELETE FROM public.usuarios_eventos ue
      WHERE ue.usuario_id = v_usuario_id;
  END IF;

  IF to_regclass('public.eventos_leads') IS NOT NULL THEN
    UPDATE public.eventos_leads
    SET perfil_id = v_sentinel
    WHERE perfil_id = usuario_id;
  END IF;
  IF to_regclass('public.leads') IS NOT NULL THEN
    UPDATE public.leads
    SET perfil_id = v_sentinel
    WHERE perfil_id = usuario_id;
  END IF;
  IF to_regclass('public.lead_comentarios') IS NOT NULL THEN
    UPDATE public.lead_comentarios
    SET autor_id = v_sentinel
    WHERE autor_id = usuario_id;
  END IF;
  IF to_regclass('public.inscripciones_subevento') IS NOT NULL THEN
    UPDATE public.inscripciones_subevento
    SET inscrito_por = v_sentinel
    WHERE inscrito_por = usuario_id;
    UPDATE public.inscripciones_subevento
    SET asistio_por = v_sentinel
    WHERE asistio_por = usuario_id;
  END IF;
  IF to_regclass('public.envios_qr') IS NOT NULL THEN
    UPDATE public.envios_qr
    SET solicitado_por = v_sentinel
    WHERE solicitado_por = usuario_id;
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

-- Permisos para que la app (rol authenticated) pueda invocar RPCs vía PostgREST.
-- Sin estos GRANT, signUp/login funcionan pero las llamadas .rpc() fallan con
-- "permission denied for function ...".
GRANT EXECUTE ON FUNCTION public.rpe_is_admin() TO authenticated;
REVOKE ALL ON FUNCTION public.rpe_is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marcar_recuperacion_pass(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.verificar_usuario_registrado(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpe_actualizar_rol_usuario(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpe_eliminar_usuario(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpe_obtener_email_usuario(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpe_sincronizar_eventos_externo(uuid, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpe_configurar_acceso_usuario(uuid, text, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpe_sincronizar_eventos_usuario(uuid, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpe_configurar_acceso_evento(uuid, uuid[]) TO authenticated;
REVOKE ALL ON FUNCTION public.rpe_existe_email_registrado(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpe_existe_email_registrado(uuid, text)
  TO authenticated;
REVOKE ALL ON FUNCTION public.rpe_actualizar_rol_usuario(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpe_sincronizar_eventos_externo(uuid, uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpe_configurar_acceso_usuario(uuid, text, uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpe_sincronizar_eventos_usuario(uuid, uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpe_configurar_acceso_evento(uuid, uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cl_guardar_lead(
  uuid, text, text, text, text, text, text, uuid
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cl_guardar_lead(
  uuid, text, text, text, text, text, text, uuid
) TO authenticated;
REVOKE ALL ON FUNCTION public.cl_resumen_campana(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cl_resumen_campana(uuid) TO authenticated;
-- Helpers legacy retirados: no son API y el fallback por nombre ya no debe
-- poder usarse ni siquiera como oráculo para sondear campañas.
REVOKE ALL ON FUNCTION public.cl_externo_evento_origen_autorizado(uuid)
  FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION public.cl_externo_campana_autorizada(uuid)
  FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION public.cl_externo_nombre_campana_autorizado(text)
  FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION public.cl_campana_autorizada(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cl_campana_autorizada(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.cl_buscar_lead_por_email(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cl_buscar_lead_por_email(uuid, text) TO authenticated;

-- ----------------------------------------------------------------
-- 5. RLS
-- ----------------------------------------------------------------
ALTER TABLE public.perfiles         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eventos          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.registrados      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usuarios_eventos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eventos_leads    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.leads            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lead_comentarios ENABLE ROW LEVEL SECURITY;

-- --- perfiles ---
DROP POLICY IF EXISTS "Acceso total perfiles" ON public.perfiles;
DROP POLICY IF EXISTS "Perfiles visibles para usuarios autenticados" ON public.perfiles;
DROP POLICY IF EXISTS "Usuarios editan su propio perfil" ON public.perfiles;
DROP POLICY IF EXISTS rpe_perfiles_select ON public.perfiles;
CREATE POLICY rpe_perfiles_select ON public.perfiles
  FOR SELECT TO authenticated
  USING (id = auth.uid() OR public.rpe_can_manage_users());

DROP POLICY IF EXISTS rpe_perfiles_insert_own ON public.perfiles;
CREATE POLICY rpe_perfiles_insert_own ON public.perfiles
  FOR INSERT TO authenticated WITH CHECK (id = auth.uid());

-- La escalación de privilegios (rol/activo) queda bloqueada por el trigger
-- rpe_prevent_role_self_escalation, no por esta policy. Esta policy solo
-- decide QUÉ FILA se puede tocar (propia, o cualquiera si eres admin).
DROP POLICY IF EXISTS rpe_perfiles_update ON public.perfiles;
CREATE POLICY rpe_perfiles_update ON public.perfiles
  FOR UPDATE TO authenticated
  USING (id = auth.uid() OR public.rpe_is_admin())
  WITH CHECK (id = auth.uid() OR public.rpe_is_admin());

-- --- eventos: admin/organizador globales; user/externo solo asignados.
DROP POLICY IF EXISTS "Acceso total a eventos para autenticados" ON public.eventos;
DROP POLICY IF EXISTS "Acceso total eventos" ON public.eventos;
DROP POLICY IF EXISTS "Permitir lectura pública de eventos" ON public.eventos;
DROP POLICY IF EXISTS anon_select_eventos ON public.eventos;
DROP POLICY IF EXISTS rpe_eventos_all ON public.eventos;
DROP POLICY IF EXISTS rpe_eventos_select ON public.eventos;
CREATE POLICY rpe_eventos_select ON public.eventos
  FOR SELECT TO authenticated
  USING (public.rpe_puede_operar_evento(id));

DROP POLICY IF EXISTS rpe_eventos_insert ON public.eventos;
CREATE POLICY rpe_eventos_insert ON public.eventos
  FOR INSERT TO authenticated
  WITH CHECK (public.rpe_can_create_content());

DROP POLICY IF EXISTS rpe_eventos_update ON public.eventos;
CREATE POLICY rpe_eventos_update ON public.eventos
  FOR UPDATE TO authenticated
  USING (public.rpe_can_create_content())
  WITH CHECK (public.rpe_can_create_content());

DROP POLICY IF EXISTS rpe_eventos_delete ON public.eventos;
CREATE POLICY rpe_eventos_delete ON public.eventos
  FOR DELETE TO authenticated
  USING (public.rpe_is_admin());

-- El anónimo ya no lee eventos: usa las RPC rpe_publico_*.
DROP POLICY IF EXISTS rpe_eventos_select_publico ON public.eventos;

-- --- registrados: acceso acotado al evento; externo continúa limitado por el
-- trigger de actualización a la acreditación y no puede insertar.
DROP POLICY IF EXISTS "Acceso total a registrados para autenticados" ON public.registrados;
DROP POLICY IF EXISTS "Permitir registro público anónimo" ON public.registrados;
DROP POLICY IF EXISTS anon_insert_registrados ON public.registrados;
DROP POLICY IF EXISTS rpe_registrados_all ON public.registrados;
DROP POLICY IF EXISTS rpe_registrados_select ON public.registrados;
CREATE POLICY rpe_registrados_select ON public.registrados
  FOR SELECT TO authenticated
  USING (public.rpe_puede_operar_evento(evento_id));

-- INSERT de registrados solo por RPC (D3).
DROP POLICY IF EXISTS rpe_registrados_insert ON public.registrados;

DROP POLICY IF EXISTS rpe_registrados_update ON public.registrados;
CREATE POLICY rpe_registrados_update ON public.registrados
  FOR UPDATE TO authenticated
  USING (public.rpe_puede_operar_evento(evento_id))
  WITH CHECK (public.rpe_puede_operar_evento(evento_id));

DROP POLICY IF EXISTS rpe_registrados_delete ON public.registrados;
CREATE POLICY rpe_registrados_delete ON public.registrados
  FOR DELETE TO authenticated
  USING (public.rpe_is_admin());

DROP POLICY IF EXISTS rpe_registrados_insert_publico ON public.registrados;
DROP POLICY IF EXISTS "Permitir registro público anónimo" ON public.registrados;
DROP POLICY IF EXISTS anon_insert_registrados ON public.registrados;

REVOKE INSERT ON TABLE public.registrados FROM PUBLIC, anon, authenticated;

-- La vigencia la marca el rango de fechas: se deja de usar eventos.activo.
ALTER TABLE public.eventos DROP COLUMN IF EXISTS activo;

-- --- usuarios_eventos ---
DROP POLICY IF EXISTS rpe_usuarios_eventos_select ON public.usuarios_eventos;
CREATE POLICY rpe_usuarios_eventos_select ON public.usuarios_eventos
  FOR SELECT TO authenticated
  USING (usuario_id = auth.uid() OR public.rpe_is_admin());

DROP POLICY IF EXISTS rpe_usuarios_eventos_write ON public.usuarios_eventos;
CREATE POLICY rpe_usuarios_eventos_write ON public.usuarios_eventos
  FOR ALL TO authenticated
  USING (public.rpe_is_admin())
  WITH CHECK (public.rpe_is_admin());

-- --- eventos_leads / leads (módulo Capturador; prefijo cl_ para no chocar
-- con las políticas rpe_ del módulo de registro) ---
DROP POLICY IF EXISTS cl_eventos_leads_select ON public.eventos_leads;
CREATE POLICY cl_eventos_leads_select ON public.eventos_leads
  FOR SELECT TO authenticated
  USING (
    (
      evento_origen_id IS NULL
      AND (
        public.rpe_is_internal_user()
        OR public.rpe_is_externo()
      )
    )
    OR (
      evento_origen_id IS NOT NULL
      AND public.rpe_puede_operar_evento(evento_origen_id)
    )
  );

-- INSERT: admin/organizador pueden crear actividades independientes; user y
-- externo solo pueden materializar la actividad interna de un evento asignado.
DROP POLICY IF EXISTS cl_eventos_leads_insert ON public.eventos_leads;
CREATE POLICY cl_eventos_leads_insert ON public.eventos_leads
  FOR INSERT TO authenticated
  WITH CHECK (
    (
      public.rpe_can_create_content()
      OR (
        evento_origen_id IS NOT NULL
        AND public.rpe_puede_operar_evento(evento_origen_id)
      )
    )
    AND (perfil_id IS NULL OR perfil_id = auth.uid())
  );

DROP POLICY IF EXISTS cl_eventos_leads_update ON public.eventos_leads;
CREATE POLICY cl_eventos_leads_update ON public.eventos_leads
  FOR UPDATE TO authenticated
  USING (public.rpe_can_create_content())
  WITH CHECK (public.rpe_can_create_content());

DROP POLICY IF EXISTS cl_eventos_leads_delete ON public.eventos_leads;
CREATE POLICY cl_eventos_leads_delete ON public.eventos_leads
  FOR DELETE TO authenticated
  USING (public.rpe_is_admin());

-- Todo acceso a leads hereda el alcance de su actividad. Ser el capturador de
-- una fila no conserva acceso después de que se revoca el evento.
DROP POLICY IF EXISTS cl_leads_select ON public.leads;
CREATE POLICY cl_leads_select ON public.leads
  FOR SELECT TO authenticated
  USING (public.cl_campana_autorizada(evento_id));

DROP POLICY IF EXISTS cl_leads_insert ON public.leads;
CREATE POLICY cl_leads_insert ON public.leads
  FOR INSERT TO authenticated
  WITH CHECK (
    perfil_id = auth.uid()
    AND public.cl_campana_autorizada(evento_id)
  );

DROP POLICY IF EXISTS cl_leads_update ON public.leads;
CREATE POLICY cl_leads_update ON public.leads
  FOR UPDATE TO authenticated
  USING (
    public.rpe_can_create_content()
    OR (
      perfil_id = auth.uid()
      AND public.cl_campana_autorizada(evento_id)
    )
  )
  WITH CHECK (
    public.rpe_can_create_content()
    OR (
      perfil_id = auth.uid()
      AND public.cl_campana_autorizada(evento_id)
    )
  );

DROP POLICY IF EXISTS cl_leads_delete ON public.leads;
CREATE POLICY cl_leads_delete ON public.leads
  FOR DELETE TO authenticated
  USING (public.rpe_is_admin());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.eventos_leads TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.leads TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.lead_comentarios TO authenticated;

DROP POLICY IF EXISTS cl_lead_comentarios_select ON public.lead_comentarios;
CREATE POLICY cl_lead_comentarios_select ON public.lead_comentarios
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.leads l
      WHERE l.id = lead_id
    )
  );

DROP POLICY IF EXISTS cl_lead_comentarios_insert ON public.lead_comentarios;
CREATE POLICY cl_lead_comentarios_insert ON public.lead_comentarios
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.leads l
      WHERE l.id = lead_id
    )
  );

DROP POLICY IF EXISTS cl_lead_comentarios_delete ON public.lead_comentarios;
CREATE POLICY cl_lead_comentarios_delete ON public.lead_comentarios
  FOR DELETE TO authenticated
  USING (
    autor_id = auth.uid()
    OR public.rpe_is_admin()
    OR public.rpe_is_organizador()
  );

DROP POLICY IF EXISTS cl_lead_comentarios_update ON public.lead_comentarios;
CREATE POLICY cl_lead_comentarios_update ON public.lead_comentarios
  FOR UPDATE TO authenticated
  USING (autor_id = auth.uid())
  WITH CHECK (autor_id = auth.uid());

-- ----------------------------------------------------------------
-- 5a. Fijados personales (eventos y campañas por usuario)
-- ----------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.usuarios_eventos_fijados (
  usuario_id  uuid NOT NULL REFERENCES public.perfiles (id) ON DELETE CASCADE,
  evento_id   uuid NOT NULL REFERENCES public.eventos (id) ON DELETE CASCADE,
  fijado_en   timestamptz NOT NULL DEFAULT timezone('utc', now()),
  PRIMARY KEY (usuario_id, evento_id)
);

CREATE TABLE IF NOT EXISTS public.usuarios_eventos_leads_fijados (
  usuario_id      uuid NOT NULL REFERENCES public.perfiles (id) ON DELETE CASCADE,
  evento_lead_id  uuid NOT NULL REFERENCES public.eventos_leads (id) ON DELETE CASCADE,
  fijado_en       timestamptz NOT NULL DEFAULT timezone('utc', now()),
  PRIMARY KEY (usuario_id, evento_lead_id)
);

CREATE INDEX IF NOT EXISTS idx_usuarios_eventos_fijados_usuario
  ON public.usuarios_eventos_fijados (usuario_id);

CREATE INDEX IF NOT EXISTS idx_usuarios_eventos_leads_fijados_usuario
  ON public.usuarios_eventos_leads_fijados (usuario_id);

ALTER TABLE public.usuarios_eventos_fijados ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usuarios_eventos_leads_fijados ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rpe_usuarios_eventos_fijados_select ON public.usuarios_eventos_fijados;
CREATE POLICY rpe_usuarios_eventos_fijados_select ON public.usuarios_eventos_fijados
  FOR SELECT TO authenticated USING (
    usuario_id = auth.uid()
    AND public.rpe_puede_operar_evento(evento_id)
  );

DROP POLICY IF EXISTS rpe_usuarios_eventos_fijados_insert ON public.usuarios_eventos_fijados;
CREATE POLICY rpe_usuarios_eventos_fijados_insert ON public.usuarios_eventos_fijados
  FOR INSERT TO authenticated WITH CHECK (
    usuario_id = auth.uid()
    AND public.rpe_puede_operar_evento(evento_id)
  );

DROP POLICY IF EXISTS rpe_usuarios_eventos_fijados_delete ON public.usuarios_eventos_fijados;
CREATE POLICY rpe_usuarios_eventos_fijados_delete ON public.usuarios_eventos_fijados
  FOR DELETE TO authenticated USING (usuario_id = auth.uid());

DROP POLICY IF EXISTS rpe_usuarios_eventos_leads_fijados_select ON public.usuarios_eventos_leads_fijados;
CREATE POLICY rpe_usuarios_eventos_leads_fijados_select ON public.usuarios_eventos_leads_fijados
  FOR SELECT TO authenticated USING (
    usuario_id = auth.uid()
    AND public.cl_campana_autorizada(evento_lead_id)
  );

DROP POLICY IF EXISTS rpe_usuarios_eventos_leads_fijados_insert ON public.usuarios_eventos_leads_fijados;
CREATE POLICY rpe_usuarios_eventos_leads_fijados_insert ON public.usuarios_eventos_leads_fijados
  FOR INSERT TO authenticated WITH CHECK (
    usuario_id = auth.uid()
    AND public.cl_campana_autorizada(evento_lead_id)
  );

DROP POLICY IF EXISTS rpe_usuarios_eventos_leads_fijados_delete ON public.usuarios_eventos_leads_fijados;
CREATE POLICY rpe_usuarios_eventos_leads_fijados_delete ON public.usuarios_eventos_leads_fijados
  FOR DELETE TO authenticated USING (usuario_id = auth.uid());

GRANT SELECT, INSERT, DELETE ON public.usuarios_eventos_fijados TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.usuarios_eventos_leads_fijados TO authenticated;

-- ----------------------------------------------------------------
-- 5b. Notificaciones (inbox + tokens FCM)
-- Webhook INSERT → Edge Function enviar-push.
-- ----------------------------------------------------------------
-- `destinatario_id IS NULL` = aviso global (registro, hitos). Con valor, el
-- aviso es para una sola persona y solo ella lo ve (comentarios de lead).
CREATE TABLE IF NOT EXISTS public.notificaciones (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo              text NOT NULL DEFAULT 'registro',
  titulo            text NOT NULL,
  cuerpo            text NOT NULL,
  registrado_id     uuid REFERENCES public.registrados (id) ON DELETE SET NULL,
  evento_id         uuid REFERENCES public.eventos (id) ON DELETE SET NULL,
  destinatario_id   uuid REFERENCES public.perfiles (id) ON DELETE CASCADE,
  lead_id           uuid REFERENCES public.leads (id) ON DELETE CASCADE,
  evento_lead_id    uuid REFERENCES public.eventos_leads (id) ON DELETE CASCADE,
  nombre_registrado text NOT NULL,
  nombre_evento     text NOT NULL,
  created_at        timestamptz NOT NULL DEFAULT timezone('utc', now())
);

-- Instalaciones previas: CREATE TABLE IF NOT EXISTS no agrega columnas.
ALTER TABLE public.notificaciones
  ADD COLUMN IF NOT EXISTS destinatario_id uuid,
  ADD COLUMN IF NOT EXISTS lead_id uuid,
  ADD COLUMN IF NOT EXISTS evento_lead_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'notificaciones_destinatario_id_fkey'
  ) THEN
    ALTER TABLE public.notificaciones
      ADD CONSTRAINT notificaciones_destinatario_id_fkey
      FOREIGN KEY (destinatario_id)
      REFERENCES public.perfiles (id) ON DELETE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'notificaciones_lead_id_fkey'
  ) THEN
    ALTER TABLE public.notificaciones
      ADD CONSTRAINT notificaciones_lead_id_fkey
      FOREIGN KEY (lead_id)
      REFERENCES public.leads (id) ON DELETE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'notificaciones_evento_lead_id_fkey'
  ) THEN
    ALTER TABLE public.notificaciones
      ADD CONSTRAINT notificaciones_evento_lead_id_fkey
      FOREIGN KEY (evento_lead_id)
      REFERENCES public.eventos_leads (id) ON DELETE CASCADE;
  END IF;
END;
$$;

ALTER TABLE public.notificaciones
  DROP CONSTRAINT IF EXISTS notificaciones_tipo_check;
ALTER TABLE public.notificaciones
  ADD CONSTRAINT notificaciones_tipo_check CHECK (tipo = ANY (ARRAY[
    'registro',
    'acreditacion_20',
    'acreditacion_50',
    'acreditacion_80',
    'acreditacion_100',
    'lead_comentario'
  ]));

CREATE TABLE IF NOT EXISTS public.evento_hitos_acreditacion (
  evento_id     uuid NOT NULL REFERENCES public.eventos (id) ON DELETE CASCADE,
  umbral        int  NOT NULL CHECK (umbral = ANY (ARRAY[20, 50, 80, 100])),
  notificado_at timestamptz NOT NULL DEFAULT timezone('utc', now()),
  PRIMARY KEY (evento_id, umbral)
);

CREATE TABLE IF NOT EXISTS public.notificaciones_leidas (
  usuario_id       uuid NOT NULL REFERENCES public.perfiles (id) ON DELETE CASCADE,
  notificacion_id  uuid NOT NULL REFERENCES public.notificaciones (id) ON DELETE CASCADE,
  leida_at         timestamptz NOT NULL DEFAULT timezone('utc', now()),
  PRIMARY KEY (usuario_id, notificacion_id)
);

CREATE TABLE IF NOT EXISTS public.notificaciones_ocultas (
  usuario_id       uuid NOT NULL REFERENCES public.perfiles (id) ON DELETE CASCADE,
  notificacion_id  uuid NOT NULL REFERENCES public.notificaciones (id) ON DELETE CASCADE,
  oculta_at        timestamptz NOT NULL DEFAULT timezone('utc', now()),
  PRIMARY KEY (usuario_id, notificacion_id)
);

CREATE TABLE IF NOT EXISTS public.device_tokens (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id  uuid NOT NULL REFERENCES public.perfiles (id) ON DELETE CASCADE,
  token       text NOT NULL UNIQUE,
  plataforma  text NOT NULL CHECK (plataforma = ANY (ARRAY['android', 'ios'])),
  updated_at  timestamptz NOT NULL DEFAULT timezone('utc', now())
);

CREATE INDEX IF NOT EXISTS idx_notificaciones_created_at
  ON public.notificaciones (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notificaciones_ocultas_usuario_id
  ON public.notificaciones_ocultas (usuario_id);
CREATE INDEX IF NOT EXISTS idx_notificaciones_destinatario
  ON public.notificaciones (destinatario_id, created_at DESC)
  WHERE destinatario_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_device_tokens_usuario_id
  ON public.device_tokens (usuario_id);

CREATE OR REPLACE FUNCTION public.rpe_notificar_nuevo_registrado()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_nombre_evento text;
BEGIN
  SELECT e.nombre INTO v_nombre_evento
  FROM public.eventos e
  WHERE e.id = NEW.evento_id;

  IF v_nombre_evento IS NULL THEN
    v_nombre_evento := 'Evento';
  END IF;

  INSERT INTO public.notificaciones (
    tipo, titulo, cuerpo, registrado_id, evento_id,
    nombre_registrado, nombre_evento
  ) VALUES (
    'registro',
    'Nuevo registro',
    NEW.nombre_completo || ' se registró a ' || v_nombre_evento,
    NEW.id,
    NEW.evento_id,
    NEW.nombre_completo,
    v_nombre_evento
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_registrados_notificar ON public.registrados;
CREATE TRIGGER trg_registrados_notificar
  AFTER INSERT ON public.registrados
  FOR EACH ROW EXECUTE FUNCTION public.rpe_notificar_nuevo_registrado();

CREATE OR REPLACE FUNCTION public.rpe_notificar_hitos_acreditacion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total           int;
  v_acreditados     int;
  v_old_acreditados int;
  v_old_pct         int;
  v_new_pct         int;
  v_nombre_evento   text;
  v_umbral          int;
  v_tipo            text;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF OLD.acreditado IS NOT DISTINCT FROM NEW.acreditado
       OR NEW.acreditado IS NOT TRUE THEN
      RETURN NEW;
    END IF;
  ELSIF TG_OP = 'INSERT' THEN
    IF NEW.acreditado IS NOT TRUE THEN
      RETURN NEW;
    END IF;
  END IF;

  SELECT count(*)::int,
         count(*) FILTER (WHERE acreditado)::int
  INTO v_total, v_acreditados
  FROM public.registrados
  WHERE evento_id = NEW.evento_id;

  IF v_total = 0 THEN
    RETURN NEW;
  END IF;

  v_new_pct := (v_acreditados * 100) / v_total;
  v_old_acreditados := v_acreditados - 1;
  v_old_pct := (v_old_acreditados * 100) / v_total;

  SELECT e.nombre INTO v_nombre_evento
  FROM public.eventos e
  WHERE e.id = NEW.evento_id;

  IF v_nombre_evento IS NULL THEN
    v_nombre_evento := 'Evento';
  END IF;

  FOREACH v_umbral IN ARRAY ARRAY[20, 50, 80, 100] LOOP
    IF v_old_pct < v_umbral AND v_new_pct >= v_umbral THEN
      INSERT INTO public.evento_hitos_acreditacion (evento_id, umbral)
      VALUES (NEW.evento_id, v_umbral)
      ON CONFLICT DO NOTHING;

      IF NOT FOUND THEN
        CONTINUE;
      END IF;

      v_tipo := 'acreditacion_' || v_umbral::text;

      INSERT INTO public.notificaciones (
        tipo, titulo, cuerpo, registrado_id, evento_id,
        nombre_registrado, nombre_evento
      ) VALUES (
        v_tipo,
        'Hito de acreditación',
        v_nombre_evento || ' alcanzó el ' || v_umbral
          || '% de acreditación (' || v_acreditados || '/' || v_total
          || ' acreditados)',
        NEW.id,
        NEW.evento_id,
        NEW.nombre_completo,
        v_nombre_evento
      );
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_registrados_hitos_acreditacion_insert ON public.registrados;
CREATE TRIGGER trg_registrados_hitos_acreditacion_insert
  AFTER INSERT ON public.registrados
  FOR EACH ROW EXECUTE FUNCTION public.rpe_notificar_hitos_acreditacion();

DROP TRIGGER IF EXISTS trg_registrados_hitos_acreditacion_update ON public.registrados;
CREATE TRIGGER trg_registrados_hitos_acreditacion_update
  AFTER UPDATE OF acreditado ON public.registrados
  FOR EACH ROW EXECUTE FUNCTION public.rpe_notificar_hitos_acreditacion();

CREATE OR REPLACE FUNCTION public.rpe_ocultar_todas_notificaciones()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;
  IF NOT public.rpe_is_internal_user() THEN
    RAISE EXCEPTION 'No tienes acceso a notificaciones';
  END IF;

  INSERT INTO public.notificaciones_ocultas (usuario_id, notificacion_id)
  SELECT v_user_id, n.id
  FROM public.notificaciones n
  WHERE public.rpe_puede_ver_notificacion_row(
    n.evento_id,
    n.destinatario_id,
    n.evento_lead_id
  )
  ON CONFLICT (usuario_id, notificacion_id) DO NOTHING;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpe_ocultar_todas_notificaciones() TO authenticated;

CREATE OR REPLACE FUNCTION public.rpe_puede_ver_notificacion_row(
  p_evento_id uuid,
  p_destinatario_id uuid,
  p_evento_lead_id uuid
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT CASE
    -- Los avisos dirigidos heredan el alcance de la actividad: externas para
    -- todos e internas solo mientras se conserve el evento de origen.
    WHEN p_destinatario_id IS NOT NULL THEN
      p_destinatario_id = auth.uid()
      AND public.rpe_is_internal_user()
      AND p_evento_lead_id IS NOT NULL
      AND public.cl_campana_autorizada(p_evento_lead_id)
    ELSE public.rpe_puede_ver_notificacion(p_evento_id)
  END;
$$;

REVOKE ALL ON FUNCTION public.rpe_puede_ver_notificacion_row(
  uuid, uuid, uuid
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpe_puede_ver_notificacion_row(
  uuid, uuid, uuid
)
  TO authenticated;

ALTER TABLE public.notificaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notificaciones_leidas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notificaciones_ocultas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rpe_notificaciones_select ON public.notificaciones;
CREATE POLICY rpe_notificaciones_select ON public.notificaciones
  FOR SELECT TO authenticated
  USING (
    public.rpe_puede_ver_notificacion_row(
      evento_id,
      destinatario_id,
      evento_lead_id
    )
  );

DROP POLICY IF EXISTS rpe_notificaciones_leidas_select ON public.notificaciones_leidas;
CREATE POLICY rpe_notificaciones_leidas_select ON public.notificaciones_leidas
  FOR SELECT TO authenticated
  USING (
    usuario_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.notificaciones n
      WHERE n.id = notificacion_id
        AND public.rpe_puede_ver_notificacion_row(
          n.evento_id,
          n.destinatario_id,
          n.evento_lead_id
        )
    )
  );

DROP POLICY IF EXISTS rpe_notificaciones_leidas_insert ON public.notificaciones_leidas;
CREATE POLICY rpe_notificaciones_leidas_insert ON public.notificaciones_leidas
  FOR INSERT TO authenticated
  WITH CHECK (
    usuario_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.notificaciones n
      WHERE n.id = notificacion_id
        AND public.rpe_puede_ver_notificacion_row(
          n.evento_id,
          n.destinatario_id,
          n.evento_lead_id
        )
    )
  );

DROP POLICY IF EXISTS rpe_notificaciones_leidas_update ON public.notificaciones_leidas;
CREATE POLICY rpe_notificaciones_leidas_update ON public.notificaciones_leidas
  FOR UPDATE TO authenticated
  USING (
    usuario_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.notificaciones n
      WHERE n.id = notificacion_id
        AND public.rpe_puede_ver_notificacion_row(
          n.evento_id,
          n.destinatario_id,
          n.evento_lead_id
        )
    )
  )
  WITH CHECK (
    usuario_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.notificaciones n
      WHERE n.id = notificacion_id
        AND public.rpe_puede_ver_notificacion_row(
          n.evento_id,
          n.destinatario_id,
          n.evento_lead_id
        )
    )
  );

DROP POLICY IF EXISTS rpe_notificaciones_ocultas_select ON public.notificaciones_ocultas;
CREATE POLICY rpe_notificaciones_ocultas_select ON public.notificaciones_ocultas
  FOR SELECT TO authenticated
  USING (
    usuario_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.notificaciones n
      WHERE n.id = notificacion_id
        AND public.rpe_puede_ver_notificacion_row(
          n.evento_id,
          n.destinatario_id,
          n.evento_lead_id
        )
    )
  );

DROP POLICY IF EXISTS rpe_notificaciones_ocultas_insert ON public.notificaciones_ocultas;
CREATE POLICY rpe_notificaciones_ocultas_insert ON public.notificaciones_ocultas
  FOR INSERT TO authenticated
  WITH CHECK (
    usuario_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.notificaciones n
      WHERE n.id = notificacion_id
        AND public.rpe_puede_ver_notificacion_row(
          n.evento_id,
          n.destinatario_id,
          n.evento_lead_id
        )
    )
  );

DROP POLICY IF EXISTS rpe_notificaciones_ocultas_delete ON public.notificaciones_ocultas;
CREATE POLICY rpe_notificaciones_ocultas_delete ON public.notificaciones_ocultas
  FOR DELETE TO authenticated
  USING (
    usuario_id = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM public.notificaciones n
      WHERE n.id = notificacion_id
        AND public.rpe_puede_ver_notificacion_row(
          n.evento_id,
          n.destinatario_id,
          n.evento_lead_id
        )
    )
  );

DROP POLICY IF EXISTS rpe_device_tokens_select ON public.device_tokens;
CREATE POLICY rpe_device_tokens_select ON public.device_tokens
  FOR SELECT TO authenticated
  USING (usuario_id = auth.uid() AND public.rpe_is_internal_user());

DROP POLICY IF EXISTS rpe_device_tokens_insert ON public.device_tokens;
CREATE POLICY rpe_device_tokens_insert ON public.device_tokens
  FOR INSERT TO authenticated
  WITH CHECK (usuario_id = auth.uid() AND public.rpe_is_internal_user());

DROP POLICY IF EXISTS rpe_device_tokens_update ON public.device_tokens;
CREATE POLICY rpe_device_tokens_update ON public.device_tokens
  FOR UPDATE TO authenticated
  USING (usuario_id = auth.uid() AND public.rpe_is_internal_user())
  WITH CHECK (usuario_id = auth.uid() AND public.rpe_is_internal_user());

DROP POLICY IF EXISTS rpe_device_tokens_delete ON public.device_tokens;
CREATE POLICY rpe_device_tokens_delete ON public.device_tokens
  FOR DELETE TO authenticated
  USING (usuario_id = auth.uid());

GRANT SELECT ON public.notificaciones TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.notificaciones_leidas TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.notificaciones_ocultas TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.device_tokens TO authenticated;

-- Aviso de comentario en un lead: al capturador y a quienes ya participaron
-- del hilo, nunca al propio autor.
CREATE OR REPLACE FUNCTION public.cl_notificar_comentario_lead()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sentinel constant uuid := '00000000-0000-0000-0000-000000000001';
  v_lead              public.leads%ROWTYPE;
  v_nombre_campana    text;
  v_evento_origen_id  uuid;
  v_cuerpo            text;
  v_destinatarios     uuid[];
BEGIN
  SELECT * INTO v_lead FROM public.leads l WHERE l.id = NEW.lead_id;
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  SELECT el.nombre, el.evento_origen_id
  INTO v_nombre_campana, v_evento_origen_id
  FROM public.eventos_leads el
  WHERE el.id = v_lead.evento_id;

  v_nombre_campana := COALESCE(v_nombre_campana, 'Actividad de captura');

  -- En actividades externas cualquier user participante puede recibir el
  -- aviso. En internas debe conservar la asignación del evento de origen.
  SELECT ARRAY(
    SELECT p.id
    FROM public.perfiles p
    WHERE p.activo = true
      AND p.rol IN ('admin', 'organizador', 'user')
      AND p.id <> v_sentinel
      AND p.id IS DISTINCT FROM NEW.autor_id
      AND (
        p.rol IN ('admin', 'organizador')
        OR (
          p.rol = 'user'
          AND (
            v_evento_origen_id IS NULL
            OR EXISTS (
              SELECT 1
              FROM public.usuarios_eventos ue
              WHERE ue.usuario_id = p.id
                AND ue.evento_id = v_evento_origen_id
            )
          )
        )
      )
      AND (
        p.id = v_lead.perfil_id
        OR EXISTS (
          SELECT 1
          FROM public.lead_comentarios c
          WHERE c.lead_id = NEW.lead_id
            AND c.autor_id = p.id
        )
      )
  ) INTO v_destinatarios;

  IF v_destinatarios IS NULL OR cardinality(v_destinatarios) = 0 THEN
    RETURN NEW;
  END IF;

  v_cuerpo := NEW.autor_nombre || ' comentó sobre ' || v_lead.nombre_completo
    || ' (' || v_nombre_campana || ')';

  INSERT INTO public.notificaciones (
    tipo, titulo, cuerpo, destinatario_id,
    lead_id, evento_lead_id, evento_id,
    nombre_registrado, nombre_evento
  )
  SELECT
    'lead_comentario',
    'Nuevo comentario',
    v_cuerpo,
    d.destinatario_id,
    v_lead.id,
    v_lead.evento_id,
    v_evento_origen_id,
    v_lead.nombre_completo,
    v_nombre_campana
  FROM unnest(v_destinatarios) AS d(destinatario_id);

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_lead_comentarios_notificar ON public.lead_comentarios;
CREATE TRIGGER trg_lead_comentarios_notificar
  AFTER INSERT ON public.lead_comentarios
  FOR EACH ROW EXECUTE FUNCTION public.cl_notificar_comentario_lead();

-- Acreditaciones propias con historia completa: `rpe_registrados_select` acota
-- a `rpe_puede_operar_evento`, así que sin este RPC a un `user` al que le
-- retiraron un evento le desaparecerían acreditaciones que sí hizo.
CREATE OR REPLACE FUNCTION public.rpe_mis_acreditados()
RETURNS TABLE (
  evento_id       uuid,
  evento_nombre   text,
  evento_fecha    date,
  registrado_id   uuid,
  nombre_completo text,
  empresa         text,
  cargo           text,
  acreditado_en   timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT
    r.evento_id,
    COALESCE(e.nombre, 'Evento eliminado'),
    e.fecha,
    r.id,
    r.nombre_completo,
    r.empresa,
    r.cargo,
    r.acreditado_en
  FROM public.registrados r
  LEFT JOIN public.eventos e ON e.id = r.evento_id
  WHERE auth.uid() IS NOT NULL
    AND r.acreditado_por = auth.uid()
  ORDER BY e.fecha DESC NULLS LAST, r.acreditado_en DESC NULLS LAST;
$$;

REVOKE ALL ON FUNCTION public.rpe_mis_acreditados() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpe_mis_acreditados() TO authenticated;

-- Realtime del inbox: sin esto el badge no se actualiza en vivo
-- (notificacionesRealtimeSubscriptionProvider escucha INSERT).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime'
         AND schemaname = 'public'
         AND tablename = 'notificaciones'
     ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notificaciones;
  END IF;
END;
$$;

-- ----------------------------------------------------------------
-- 6. Storage buckets (ejecutar una vez; el dashboard de Supabase también
--    permite crearlos manualmente). Se listan acá para que quede
--    versionado junto con sus políticas.
-- ----------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('imagenes', 'imagenes', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('plantillas', 'plantillas', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('leads-privados', 'leads-privados', false)
ON CONFLICT (id) DO UPDATE SET public = false;

-- La ruta del objeto también es parte de la autorización. Sin esta barrera,
-- cualquier cuenta autenticada podría usar `upsert` sobre
-- `leads/<uuid>.jpg` y reemplazar la fotografía de otro capturador.
CREATE OR REPLACE FUNCTION public.rpe_puede_escribir_imagen(
  p_object_name text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
DECLARE
  v_carpeta text := split_part(COALESCE(p_object_name, ''), '/', 1);
  v_archivo text := split_part(COALESCE(p_object_name, ''), '/', 2);
  v_id_text text := split_part(v_archivo, '.', 1);
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL
    OR p_object_name !~* '^(eventos|perfiles|leads)/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|jpeg|png|webp|heic|heif)$'
  THEN
    RETURN false;
  END IF;

  v_id := v_id_text::uuid;
  CASE v_carpeta
    WHEN 'eventos' THEN
      RETURN public.rpe_can_create_content();
    WHEN 'perfiles' THEN
      RETURN v_id = auth.uid() OR public.rpe_is_admin();
    WHEN 'leads' THEN
      RETURN public.rpe_can_create_content() OR EXISTS (
        SELECT 1
        FROM public.leads l
        WHERE l.id = v_id
          AND l.perfil_id = auth.uid()
          AND public.cl_campana_autorizada(l.evento_id)
      );
    ELSE
      RETURN false;
  END CASE;
EXCEPTION
  WHEN invalid_text_representation THEN
    RETURN false;
END;
$$;

REVOKE ALL ON FUNCTION public.rpe_puede_escribir_imagen(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpe_puede_escribir_imagen(text)
  TO authenticated;

DROP POLICY IF EXISTS rpe_storage_imagenes_read ON storage.objects;
CREATE POLICY rpe_storage_imagenes_read ON storage.objects
  FOR SELECT USING (bucket_id = 'imagenes');

DROP POLICY IF EXISTS "Permitir subidas a imagenes" ON storage.objects;
DROP POLICY IF EXISTS rpe_storage_imagenes_write ON storage.objects;
CREATE POLICY rpe_storage_imagenes_write ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'imagenes'
    AND split_part(name, '/', 1) <> 'leads'
    AND public.rpe_puede_escribir_imagen(name)
  );

DROP POLICY IF EXISTS "Permitir actualizar imagenes" ON storage.objects;
DROP POLICY IF EXISTS rpe_storage_imagenes_update ON storage.objects;
CREATE POLICY rpe_storage_imagenes_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'imagenes'
    AND split_part(name, '/', 1) <> 'leads'
    AND public.rpe_puede_escribir_imagen(name)
  )
  WITH CHECK (
    bucket_id = 'imagenes'
    AND split_part(name, '/', 1) <> 'leads'
    AND public.rpe_puede_escribir_imagen(name)
  );

DROP POLICY IF EXISTS rpe_storage_leads_read ON storage.objects;
CREATE POLICY rpe_storage_leads_read ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'leads-privados'
    AND public.rpe_puede_escribir_imagen(name)
  );

DROP POLICY IF EXISTS rpe_storage_leads_write ON storage.objects;
CREATE POLICY rpe_storage_leads_write ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'leads-privados'
    AND split_part(name, '/', 1) = 'leads'
    AND public.rpe_puede_escribir_imagen(name)
  );

DROP POLICY IF EXISTS rpe_storage_leads_update ON storage.objects;
CREATE POLICY rpe_storage_leads_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'leads-privados'
    AND public.rpe_puede_escribir_imagen(name)
  )
  WITH CHECK (
    bucket_id = 'leads-privados'
    AND public.rpe_puede_escribir_imagen(name)
  );

DROP POLICY IF EXISTS rpe_storage_plantillas_read ON storage.objects;
CREATE POLICY rpe_storage_plantillas_read ON storage.objects
  FOR SELECT USING (bucket_id = 'plantillas');

-- storage.prefixes: las versiones nuevas de Storage guardan acá una fila por
-- carpeta del path, con RLS propio. La app sube SIEMPRE dentro de una carpeta
-- (`imagenes/eventos/...`, `imagenes/leads/...`), así que sin estas políticas
-- toda subida falla con "new row violates row-level security policy" aunque
-- las de storage.objects estén bien — cuesta de diagnosticar porque el error
-- señala a objects.
--
-- Va dentro de un DO porque la tabla no existe en instalaciones de Storage
-- anteriores, y ahí este bloque simplemente no hace nada.
DO $$
BEGIN
  IF to_regclass('storage.prefixes') IS NULL THEN
    RAISE NOTICE 'storage.prefixes no existe: no hace falta crear políticas.';
    RETURN;
  END IF;

  DROP POLICY IF EXISTS rpe_storage_prefixes_read ON storage.prefixes;
  CREATE POLICY rpe_storage_prefixes_read ON storage.prefixes
    FOR SELECT USING (bucket_id IN ('imagenes', 'plantillas', 'leads-privados'));

  DROP POLICY IF EXISTS rpe_storage_prefixes_write ON storage.prefixes;
  CREATE POLICY rpe_storage_prefixes_write ON storage.prefixes
    FOR INSERT TO authenticated
    WITH CHECK (bucket_id IN ('imagenes', 'leads-privados'));

  DROP POLICY IF EXISTS rpe_storage_prefixes_update ON storage.prefixes;
  CREATE POLICY rpe_storage_prefixes_update ON storage.prefixes
    FOR UPDATE TO authenticated
    USING (bucket_id IN ('imagenes', 'leads-privados'));
END $$;


-- ----------------------------------------------------------------
-- 7. Basura de Storage
--
-- Borrar una fila nunca tocaba el archivo: cada evento eliminado, cada lead
-- borrado y **cada edición de portada** (la app sube un UUID nuevo en vez de
-- sobrescribir) dejaba un objeto huérfano ocupando cuota para siempre.
--
-- El registro lo hacen triggers, porque son lo único que ve también los
-- borrados en cascada, que nunca pasan por la app. El borrado real lo hace la
-- Edge Function `limpiar-storage` con la service role: quitar la fila de
-- `storage.objects` a mano dejaría el archivo físico igual de presente.
--
-- Idéntico a supabase/migrations/202608211200_storage_basura.sql.
-- ----------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- 7.1 Cola
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.storage_basura (
  id         uuid NOT NULL DEFAULT gen_random_uuid(),
  bucket     text NOT NULL,
  path       text NOT NULL,
  creado_at  timestamptz NOT NULL DEFAULT timezone('utc', now()),
  CONSTRAINT storage_basura_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS idx_storage_basura_creado
  ON public.storage_basura (creado_at);

-- Sin políticas a propósito: RLS activo y ninguna regla = solo la service role
-- (que las omite) puede leerla o vaciarla.
ALTER TABLE public.storage_basura ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- 7.2 Normalización de rutas
-- ---------------------------------------------------------------------------
-- La base guarda tres formas de la misma imagen según de dónde venga: el path
-- canónico (`leads/<uuid>.jpg`), la URL pública del bucket `imagenes` y la URL
-- firmada de `leads-privados`. Espejo exacto de `pathFotoStorageLead` en
-- lib/data/repositories/storage_repository.dart.
CREATE OR REPLACE FUNCTION public.rpe_storage_path(p_url text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_valor text := COALESCE(p_url, '');
  v_marca text;
  v_pos   int;
BEGIN
  IF v_valor = '' THEN
    RETURN NULL;
  END IF;

  -- El `?v=` de invalidación de caché no forma parte del objeto.
  v_valor := split_part(v_valor, '?', 1);

  FOREACH v_marca IN ARRAY ARRAY[
    '/object/public/imagenes/',
    '/object/sign/leads-privados/',
    '/object/public/leads-privados/'
  ] LOOP
    v_pos := position(v_marca IN v_valor);
    IF v_pos > 0 THEN
      RETURN NULLIF(
        replace(
          substring(v_valor FROM v_pos + length(v_marca)),
          '%20', ' '
        ),
        ''
      );
    END IF;
  END LOOP;

  -- Ya venía canónico (`leads/<uuid>.jpg`, `eventos/…`, `perfiles/…`).
  IF v_valor ~ '^(eventos|perfiles|leads)/' THEN
    RETURN v_valor;
  END IF;

  -- Cualquier otra cosa (URL externa, dato viejo) no es nuestra: no se encola.
  RETURN NULL;
END;
$$;

-- ---------------------------------------------------------------------------
-- 7.3 Encolado
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpe_encolar_storage(
  p_bucket text,
  p_url    text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_path text := public.rpe_storage_path(p_url);
BEGIN
  IF v_path IS NULL THEN
    RETURN;
  END IF;
  INSERT INTO public.storage_basura (bucket, path) VALUES (p_bucket, v_path);
END;
$$;

-- Portadas de eventos y actividades: bucket `imagenes`.
--
-- La actividad de captura **interna** hereda `imagen_url` del evento ligado
-- (ver `rpe_sync_actividad_interna_desde_evento`), así que su path puede seguir
-- en uso por el evento. No se filtra acá: el filtro definitivo vive en
-- `rpe_storage_basura_tomar`, que corre con la transacción ya cerrada y ve la
-- base consistente —a mitad de un borrado en cascada, en cambio, una fila que
-- está a punto de irse todavía se vería viva.
CREATE OR REPLACE FUNCTION public.rpe_storage_basura_portada()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.rpe_encolar_storage('imagenes', OLD.imagen_url);
    RETURN OLD;
  END IF;

  IF NEW.imagen_url IS DISTINCT FROM OLD.imagen_url THEN
    PERFORM public.rpe_encolar_storage('imagenes', OLD.imagen_url);
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.rpe_storage_basura_foto_perfil()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.rpe_encolar_storage('imagenes', OLD.foto_url);
    RETURN OLD;
  END IF;

  IF NEW.foto_url IS DISTINCT FROM OLD.foto_url THEN
    PERFORM public.rpe_encolar_storage('imagenes', OLD.foto_url);
  END IF;
  RETURN NEW;
END;
$$;

-- Fotos de leads: bucket privado `leads-privados`, y son un array.
CREATE OR REPLACE FUNCTION public.rpe_storage_basura_fotos_lead()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_url text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    FOREACH v_url IN ARRAY COALESCE(OLD.fotos_urls, '{}'::text[]) LOOP
      PERFORM public.rpe_encolar_storage('leads-privados', v_url);
    END LOOP;
    RETURN OLD;
  END IF;

  -- Solo las que dejaron de estar referenciadas por esta fila.
  FOREACH v_url IN ARRAY COALESCE(OLD.fotos_urls, '{}'::text[]) LOOP
    IF NOT (v_url = ANY (COALESCE(NEW.fotos_urls, '{}'::text[]))) THEN
      PERFORM public.rpe_encolar_storage('leads-privados', v_url);
    END IF;
  END LOOP;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_eventos_storage_basura ON public.eventos;
CREATE TRIGGER trg_eventos_storage_basura
  AFTER UPDATE OF imagen_url OR DELETE ON public.eventos
  FOR EACH ROW EXECUTE FUNCTION public.rpe_storage_basura_portada();

DROP TRIGGER IF EXISTS trg_eventos_leads_storage_basura ON public.eventos_leads;
CREATE TRIGGER trg_eventos_leads_storage_basura
  AFTER UPDATE OF imagen_url OR DELETE ON public.eventos_leads
  FOR EACH ROW EXECUTE FUNCTION public.rpe_storage_basura_portada();

DROP TRIGGER IF EXISTS trg_perfiles_storage_basura ON public.perfiles;
CREATE TRIGGER trg_perfiles_storage_basura
  AFTER UPDATE OF foto_url OR DELETE ON public.perfiles
  FOR EACH ROW EXECUTE FUNCTION public.rpe_storage_basura_foto_perfil();

DROP TRIGGER IF EXISTS trg_leads_storage_basura ON public.leads;
CREATE TRIGGER trg_leads_storage_basura
  AFTER UPDATE OF fotos_urls OR DELETE ON public.leads
  FOR EACH ROW EXECUTE FUNCTION public.rpe_storage_basura_fotos_lead();

-- ---------------------------------------------------------------------------
-- 7.4 Drenaje
-- ---------------------------------------------------------------------------
-- ¿Queda alguna fila viva apuntando a este objeto? Cubre el caso de la
-- actividad interna, que comparte portada con su evento, y el de una foto de
-- lead reutilizada.
CREATE OR REPLACE FUNCTION public.rpe_storage_en_uso(
  p_bucket text,
  p_path   text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
DECLARE
  v_en_uso boolean := false;
BEGIN
  IF p_bucket = 'imagenes' THEN
    v_en_uso := EXISTS (
      SELECT 1 FROM public.eventos
      WHERE public.rpe_storage_path(imagen_url) = p_path
    );
    IF NOT v_en_uso AND EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'eventos' AND column_name = 'banner_url'
    ) THEN
      EXECUTE 'SELECT EXISTS (SELECT 1 FROM public.eventos WHERE public.rpe_storage_path(banner_url) = $1)'
        INTO v_en_uso USING p_path;
    END IF;
    IF NOT v_en_uso AND to_regclass('public.subeventos') IS NOT NULL THEN
      EXECUTE 'SELECT EXISTS (SELECT 1 FROM public.subeventos WHERE public.rpe_storage_path(imagen_url) = $1)'
        INTO v_en_uso USING p_path;
    END IF;
    RETURN v_en_uso OR EXISTS (
      SELECT 1 FROM public.eventos_leads
      WHERE public.rpe_storage_path(imagen_url) = p_path
    ) OR EXISTS (
      SELECT 1 FROM public.perfiles
      WHERE public.rpe_storage_path(foto_url) = p_path
    );
  END IF;

  IF p_bucket = 'leads-privados' THEN
    RETURN EXISTS (
      SELECT 1
      FROM public.leads l, unnest(l.fotos_urls) AS u(url)
      WHERE public.rpe_storage_path(u.url) = p_path
    );
  END IF;

  -- Bucket desconocido: no se toca.
  RETURN true;
END;
$$;

-- Entrega el siguiente lote realmente huérfano y descarta de la cola lo que
-- resultó seguir en uso. Lo llama `limpiar-storage` con la service role.
--
-- El `DELETE` va en un CTE: Postgres ejecuta los CTE que modifican datos
-- siempre y exactamente una vez, lea o no la consulta principal su salida.
CREATE OR REPLACE FUNCTION public.rpe_storage_basura_tomar(p_limite int DEFAULT 200)
RETURNS TABLE (id uuid, bucket text, path text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH lote AS (
    SELECT b.id, b.bucket, b.path
      FROM public.storage_basura b
     ORDER BY b.creado_at
     LIMIT GREATEST(COALESCE(p_limite, 200), 1)
  ),
  vivas AS (
    SELECT l.id
      FROM lote l
     WHERE public.rpe_storage_en_uso(l.bucket, l.path)
  ),
  descartadas AS (
    DELETE FROM public.storage_basura b
     WHERE b.id IN (SELECT v.id FROM vivas v)
    RETURNING b.id
  )
  SELECT l.id, l.bucket, l.path
    FROM lote l
   WHERE l.id NOT IN (SELECT v.id FROM vivas v);
$$;

REVOKE ALL ON FUNCTION public.rpe_storage_basura_tomar(int) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpe_storage_en_uso(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpe_encolar_storage(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rpe_storage_basura_tomar(int) TO service_role;
