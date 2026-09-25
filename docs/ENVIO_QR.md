# Envío de confirmaciones

La app y la web no llaman a `enviar-qr` al registrar. La RPC inserta una fila en `envios_qr` con `estado = pendiente`. Un Database Webhook la procesa.

## Webhook

1. Dashboard → Database → Webhooks → Create.
2. Tabla `envios_qr`, evento INSERT.
3. URL: `https://<project-ref>.supabase.co/functions/v1/enviar-qr`.
4. Header `apikey: <sb_secret_…>` (la secret `default`, no la publishable).
5. Método POST. El cuerpo estándar incluye `record.id`.

El staff reenvía en modo síncrono: `Authorization: Bearer <JWT>` y `apikey` publishable, con `{"registrado_id","canales":["email","sms"],"motivo":"reenvio"}`.

`qr-imagen` es pública (`verify_jwt = false`) y no consulta la base: `GET /functions/v1/qr-imagen?c=TW1-…`.

## Consultas

Envíos fallidos de las últimas 24 h:

```sql
SELECT id, registrado_id, evento_id, estado, error, created_at
FROM public.envios_qr
WHERE estado = 'fallido'
  AND created_at > now() - interval '24 hours'
ORDER BY created_at DESC;
```

Atascados en `procesando` por más de 10 minutos:

```sql
SELECT id, registrado_id, evento_id, intentos, created_at
FROM public.envios_qr
WHERE estado = 'procesando'
  AND created_at < now() - interval '10 minutes';
```

Ocupación de un evento (reemplazar el uuid):

```sql
SELECT public.rpe_ocupacion_evento('<evento_id>'::uuid);
```
