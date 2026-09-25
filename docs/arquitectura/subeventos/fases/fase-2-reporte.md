# Fase 2 — reporte

Rama: `feat/subeventos-f2-edge-functions`.

## Archivos

- `supabase/functions/_shared/qr.ts`, `plantillas_confirmacion.ts`, `zona_horaria.ts`, `log.ts` y sus tests.
- `supabase/functions/enviar-qr/index.ts`: modos staff (JWT) y webhook (apikey secreta). El cuerpo solo aporta ids, canales y motivo; el contenido sale de la base.
- `supabase/functions/qr-imagen/index.ts`: PNG público, sin base de datos.
- `supabase/config.toml`: `qr-imagen` con `verify_jwt = false`.
- `docs/ENVIO_QR.md` y la tabla de funciones del README.

## Cómo se probó

`deno` no está instalado en esta máquina y no se pudo instalar. `deno test` y `supabase functions serve` no corrieron. No hay captura del correo.

La fase 1 sí se aplicó en el proyecto enlazado NEXUS (`evjocwzmlsyjixzihxep`), dos veces. Quedaron 20 eventos con slug, 1664 registrados con `codigo_qr` y cero políticas de lectura pública o INSERT directo.

## Pendiente para cerrar la fase 2

- `deno test` de `_shared`.
- Servir `qr-imagen` y comprobar el PNG.
- `enviar-qr` sin auth → 401; con JWT de staff, un envío real; webhook sobre una fila `pendiente` → `completado`, y la misma fila → `skipped`.
- Crear el Database Webhook de `envios_qr` (está documentado, no creado).
