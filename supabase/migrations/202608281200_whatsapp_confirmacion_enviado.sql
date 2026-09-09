-- Constancia de envío del QR por WhatsApp, espejo de email_confirmacion_enviado.

ALTER TABLE public.registrados
  ADD COLUMN IF NOT EXISTS whatsapp_confirmacion_enviado boolean NOT NULL DEFAULT false;
