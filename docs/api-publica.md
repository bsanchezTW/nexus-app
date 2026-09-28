# API pública de eventos

Contrato para la web Node. La app de staff no llama estas funciones.

Transporte: `POST {SUPABASE_URL}/rest/v1/rpc/<nombre>` con `apikey` publishable `eventos_web` y `Content-Type: application/json`. La web debe llamarlas desde el servidor, con Turnstile y límite por IP antes de registrar.

Ninguna respuesta incluye UUID. Un código de taller es `subeventos.codigo` (6 caracteres). El QR del asistente no sale en estas respuestas.

## `rpe_publico_calendario`

Entrada: `{"p_desde":"2026-01-01","p_hasta":"2026-12-31"}`. Si se omiten, el rango es un año atrás y un año adelante. Más de 800 días responde `RPE_DATOS_INVALIDOS`.

Salida: arreglo ordenado por `fecha_inicio` y `slug`.

```json
[{
  "slug": "transworld-connect-k3f9",
  "nombre": "Transworld Connect",
  "tematica": "Telecom",
  "pais": "Chile",
  "fecha_inicio": "2026-11-12",
  "fecha_fin": "2026-11-13",
  "hora_inicio": "09:00",
  "hora_fin": "18:00",
  "zona_horaria": "America/Santiago",
  "lugar": "Hotel X",
  "direccion": "Av. Y 123",
  "imagen_url": "https://…",
  "banner_url": "https://…",
  "estado": "proximo",
  "registro_abierto": true,
  "tiene_subeventos": true,
  "agotado": false
}]
```

`estado` es `proximo`, `en_curso` o `finalizado`. `agotado` es verdadero cuando hay cupo y no quedan lugares.

## `rpe_publico_evento`

Entrada: `{"p_slug":"transworld-connect-k3f9"}`.

Salida: los campos del calendario más estos.

```json
{
  "descripcion": "…",
  "mapa_url": "https://maps…",
  "inscripciones_cierre": "2026-11-11T23:59:00",
  "cupo": {"limitado": true, "disponibles": 42},
  "formulario": {"campos": ["nombre_completo", "email", "empresa", "cargo", "telefono"]},
  "subeventos": [{
    "codigo": "a7k2mq",
    "nombre": "Taller IA",
    "descripcion": "…",
    "dia": "2026-11-12",
    "hora_inicio": "10:00",
    "hora_fin": "11:30",
    "sala": "Salón B",
    "expositor": "Ana Pérez",
    "imagen_url": null,
    "cupo": {"limitado": true, "disponibles": 0},
    "agotado": true
  }]
}
```

Solo entran talleres visibles y con día de hoy en adelante, ordenados por día, hora y orden. `disponibles` es `null` si el cupo es ilimitado y nunca baja de 0. Si el slug no existe, PostgREST responde 400 con `message` `RPE_EVENTO_NO_ENCONTRADO`.

## `rpe_publico_registrar`

```json
{
  "p_slug": "transworld-connect-k3f9",
  "p_datos": {
    "nombre_completo": "Ana Pérez",
    "email": "ana@x.cl",
    "empresa": "X",
    "cargo": "CTO",
    "telefono": "+56 9 1234 5678",
    "utm_source": "linkedin",
    "utm_medium": null,
    "utm_campaign": null,
    "utm_content": null
  },
  "p_subeventos": ["a7k2mq", "b8m3np"]
}
```

Si se escribe:

```json
{
  "ok": true,
  "resultado": "inscrito",
  "agregados": ["a7k2mq"],
  "ya_inscrito_en": ["b8m3np"],
  "envio": "programado"
}
```

`resultado` también puede ser `actualizado` o `sin_cambios`. `envio` puede ser `programado` o `limitado`.

Si no se escribe nada:

```json
{
  "ok": false,
  "motivo": "registro_cerrado",
  "rechazados": [{"codigo": "a7k2mq", "motivo": "sin_cupo"}]
}
```

`motivo` del rechazo general: `registro_cerrado`, `sin_cupo_evento` o `subeventos_rechazados`. Motivo de cada taller: `sin_cupo`, `superpuesto`, `superpuesto_con_inscripcion`, `no_disponible` o `no_existe`.

Reglas:

1. El mismo email en el mismo evento suma talleres. No pisa nombre, empresa ni teléfono.
2. El público no puede forzar cupo ni saltar un horario que se solapa.
3. Como máximo 20 códigos de taller. Los repetidos se ignoran.
4. `resultado` dice si ese email ya estaba inscrito.

Errores que se lanzan (no van en `ok: false`): `RPE_EVENTO_NO_ENCONTRADO` y `RPE_DATOS_INVALIDOS`. El detalle de datos inválidos es JSON `{campo, regla}`. Cualquier otro error se muestra como fallo genérico.

La página del evento es `{PUBLIC_WEB_BASE_URL}/eventos/{slug}`. Por defecto la base es `https://eventos.transworld.cl`.

La imagen del QR, aparte de estas RPC, es `GET {SUPABASE_URL}/functions/v1/qr-imagen?c=TW1-…` y no consulta la base.
