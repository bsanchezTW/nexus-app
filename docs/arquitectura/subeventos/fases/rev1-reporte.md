# Revisión 1 — reporte

Trabajo en `main`. El punto de partida de las correcciones es `50e177e` (`[f5-f8] Registro con talleres, asistencia, KPIs y Excel`).

## Commits

| Corrección | Commit | Qué quedó |
|---|---|---|
| C1 | `16edf08` | El escáner, la edición y el filtro observan las inscripciones y esperan la carga. |
| C2 | `3af92da` | Un rechazo online no parchea la caché. La cola marca la fila que ya existía. |
| C3 | `9ef5455` | Migración `202609281200_subeventos_correcciones.sql`. Se aplicó dos veces en NEXUS. |
| C4 | `1b11be4` | `schema.sql` incluye el modelo. La verificación de nombres no imprimió `FALTA` (53 nombres). |
| C5 | `2009030` | El mensaje usa la etiqueta del campo, el JSON de `details` y el hint. |
| C6 | `31edf33` | El primer intento de inscribir va sin sobrecupo. Si está lleno, se pregunta. |
| C7 | `b89d8a0` | Google Calendar lleva `ctz`. El SMS queda en GSM-7. El error de Brevo guarda estado y cuerpo. |
| C8 | `da766a7` | Al abrir el escáner sin `?subevento=` se sugiere el taller en curso, sin cambiar el modo. |
| C9 | `e034a96` | El selector de la cámara usa `TwColors.cameraScrim`, `cameraMenu` y `onCamera`. |
| C10 | `035aa75` | El correo recupera botones de calendario, el bloque de consultas y los márgenes. |

## SQL

`supabase db query --linked -f supabase/tests/subeventos_test.sql` terminó con código 0 después de aplicar la migración y, otra vez, después de aplicar `schema.sql`. La Management API no devuelve `RAISE NOTICE`, así que el texto no salió en la respuesta. Como ningún caso lanzó excepción, estos avisos se ejecutaron:

- OK caso 1 slug
- OK caso 2 codigo_qr
- OK caso 3 cupo evento
- OK caso 4 cupo taller
- OK caso 5 solape en la solicitud
- OK caso 6 reinscripcion
- OK caso 7 solape con inscripcion
- OK caso 8 asistencia externo
- OK caso 9 acreditado_en
- OK caso 10 rango y solape
- OK caso 11 anon
- OK caso 12 sin uuid
- OK caso 13 envio limitado
- OK caso 14 registro cerrado
- PENDIENTE caso 15 concurrencia manual (dos sesiones)
- OK caso 16 email repetido
- OK caso 17 ya inscrito
- OK caso 18 permiso antes de existencia
- OK caso 19 rut k
- OK caso 20 talleres ocultos
- OK caso 21 importacion certificacion

Para que el script pudiera correr contra la base real hubo que ajustar el propio test, no el contrato:

- los códigos de taller de la fixture pasaron a 6 caracteres (`tlr001`–`tlr004`);
- el caso 6 pide los dos talleres en la segunda llamada, que es lo que llena `ya_inscrito_en`, y atrasa el primer envío para que la ventana de 10 minutos no bloquee el segundo dentro de la misma transacción;
- el caso 10 inscribe a la misma persona en los dos talleres antes de mover el horario;
- el caso 11 acepta que `anon` no tenga `GRANT` sobre las tablas;
- al reaplicar `schema.sql`, el backfill de `updated_at` en comentarios se hace con el trigger de comentarios apagado. Si no, la base ya instalada rechaza el `UPDATE`.

## deno test

`npx -y deno test --node-modules-dir=auto supabase/functions/_shared/`

```
ok | 9 passed | 0 failed
```

Plantillas 5, QR 2, zona horaria 2.

## Flutter

`flutter analyze`: sin issues.
`flutter test`: 593 pruebas, todas pasaron.

## TODO(arquitectura)

Ninguno nuevo.
