-- Acceso con QR obligatorio en los eventos.
--
-- Desde octubre de 2026 todo evento acredita con QR: la app ya no ofrece el
-- interruptor "Acceso con QR" y guarda siempre acceso_qr = true. Esta
-- migración:
-- 1. Deja el valor por defecto en true (altas que no lo manden).
-- 2. Activa el QR en los eventos existentes que lo tenían apagado. Solo
--    cambia lo que se envíe de aquí en adelante (correos y SMS de
--    confirmación con QR); no reenvía nada.
--
-- Idempotente: también vive en supabase/schema.sql.

ALTER TABLE public.eventos
  ALTER COLUMN acceso_qr SET DEFAULT true;

UPDATE public.eventos
  SET acceso_qr = true
  WHERE acceso_qr IS DISTINCT FROM true;
