# Despliegue de subeventos, cupos y QR único

Versión de la app: `1.8.0+34`. En Android y Windows la actualización forzada sale al publicar el release de GitHub con el tag `v1.8.0` y la línea `[FORCE_UPDATE]` en el cuerpo. El `pubspec.yaml` ya está en esa versión; el release todavía no se publica desde aquí.

Orden:

1. Backup de la base NEXUS (`evjocwzmlsyjixzihxep`). No tocar el proyecto INTRANET.
2. Aplicar `supabase/migrations/202609251200_subeventos_cupos_ids_opacos.sql` en el SQL Editor. No usar `db push` de migraciones viejas. La migración ya se aplicó en NEXUS durante la fase 1; volver a correrla es idempotente, pero el backup va primero.
3. Desplegar `enviar-qr` y `qr-imagen`.
4. Crear el Database Webhook de `envios_qr` INSERT hacia `enviar-qr` con la apikey secreta. Detalle en `docs/ENVIO_QR.md`.
5. Publicar la app en las plataformas, con el release `v1.8.0` y `[FORCE_UPDATE]`.
6. Mover la web del staff a su subdominio. Lo hace quien opera el dominio.
7. Avisar a la web Node con `docs/api-publica.md`.

## Recorrido manual

No se ejecutó: no hay un entorno de staging con sesión ni una captura de correo en esta pasada. La lista queda para hacerlo antes de dar la versión por cerrada.

1. Crear un evento con cupo 3 y 3 talleres: dos a la misma hora y uno con cupo 1.
2. `rpe_publico_evento` por slug y confirmar que la respuesta no trae UUID.
3. `rpe_publico_registrar` con los dos talleres solapados: rechazo.
4. Registrar a 2 personas, una en el taller de cupo 1.
5. Otra persona pide ese taller: `sin_cupo`.
6. El mismo email suma un taller nuevo: `actualizado`.
7. El correo trae un solo QR, la tabla de talleres y el PNG adjunto.
8. El SMS trae el link a `qr-imagen`.
9. Escanear en Entrada y en un taller.
10. Alguien no inscrito: inscribir y marcar.
11. Un usuario sin permiso de crear ve solo el aviso de sobrecupo.
12. KPIs y Excel: columnas de talleres, sin `codigo_qr` y sin UUID.
13. Regenerar el QR: el anterior deja de servir.
14. Sin red, marcar asistencia en un taller y ver que sube al volver la conexión.
