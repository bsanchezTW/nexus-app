-- Constancia de envío del QR por SMS, espejo de email_confirmacion_enviado.

ALTER TABLE public.registrados
  ADD COLUMN IF NOT EXISTS sms_confirmacion_enviado boolean NOT NULL DEFAULT false;
