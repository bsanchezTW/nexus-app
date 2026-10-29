-- Elimina funciones antiguas que solo existían en producción.
--
-- Se crearon a mano antes de que el esquema viviera en el repo. Ni la app,
-- ni la web, ni otra función, trigger o política las usa (revisado en
-- pg_depend, pg_policies y en el código de todas las funciones el
-- 2026-10-29). Tres eran SECURITY DEFINER y ejecutables por anon:
--
-- - verificar_duplicado(evento, email): devolvía el nombre completo del
--   registrado con ese correo. Su reemplazo, rpe_existe_email_registrado,
--   ya no se concede a anon.
-- - preparar_reset_clave(email): devolvía el id de auth del usuario
--   (enumeración de cuentas) y marcaba perfiles.cambiar_pass.
-- - solicitar_reset_clave(email): marcaba perfiles.cambiar_pass, con lo que
--   cualquiera podía obligar a un usuario a cambiar su clave al entrar.
--
-- Además:
-- - validar_bloque_registro(): función de trigger sin trigger asociado.
-- - rpe_puede_ver_notificacion_row(uuid, uuid): sobrecarga vieja; las
--   políticas y rpe_ocultar_todas_notificaciones usan la de tres argumentos.
--
-- Idempotente: también vive en supabase/schema.sql.

DROP FUNCTION IF EXISTS public.verificar_duplicado(uuid, text);
DROP FUNCTION IF EXISTS public.preparar_reset_clave(text);
DROP FUNCTION IF EXISTS public.solicitar_reset_clave(text);
DROP FUNCTION IF EXISTS public.validar_bloque_registro();
DROP FUNCTION IF EXISTS public.rpe_puede_ver_notificacion_row(uuid, uuid);
