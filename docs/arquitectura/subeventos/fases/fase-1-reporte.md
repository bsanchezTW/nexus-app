# Fase 1 — reporte

Rama: `feat/subeventos-f1-base-datos`.

## Archivos

- `supabase/migrations/202609251200_subeventos_cupos_ids_opacos.sql` — migración idempotente del §6.
- `supabase/schema.sql` — deja de recrear `tipo_registro`, el INSERT directo y `evento_bloques`; actualiza `rpe_eliminar_usuario` y `rpe_storage_en_uso`.
- `supabase/tests/subeventos_test.sql` — casos del §11.1, dentro de `BEGIN … ROLLBACK`.

No se tocó Dart.

## Cómo se probó

En esta máquina no hay `psql`, Docker ni la CLI de Supabase. La migración no se aplicó dos veces y el script de tests no se ejecutó. El caso 15 (dos sesiones) queda pendiente de staging.

Salida de NOTICEs: no hay.

## Decisiones menores

- La confirmación encola `email` y `sms`. El §6.8 no fija los canales.
- `rpe_ocupacion_evento.sobrecupo` es la cantidad de filas con `sobrecupo = true`, no un booleano.
- `rpe_eliminar_usuario` también reasigna `envios_qr.solicitado_por`, además de `inscrito_por` y `asistio_por`.
- El país para RUT/RUC viaja en el GUC `rpe.pais_evento`, porque la firma de `rpe_validar_datos_asistente` no lo recibe.
- Un rechazo de talleres después de insertar al asistente se deshace con un sub-bloque `BEGIN/EXCEPTION` (`RPE_INSCRIPCIONES_RECHAZADAS`). La transacción del llamador no conserva esa fila.

## TODO(arquitectura)

- Dart no limita el largo de nombre, empresa ni cargo. El §10 pide 3–120 y 1–120. La SQL sigue a Dart y no aplica tope.
- El teléfono en Dart depende del país. La SQL aplica 8–15 dígitos y guarda el texto recortado.
- El §10 pide `inscripciones_cierre` menor o igual al fin del evento. El §6.2 no lo pone como restricción. No está implementado.
- `imagen_url` y `banner_url` salen en las RPC públicas. Si la URL de Storage trae un UUID, el caso 12 falla aunque el contrato no incluya identificadores propios.
- No hay código `RPE_*` para agotar los 10 intentos de `codigo` de taller. Se usa `RPE_DATOS_INVALIDOS`.

## Revisión contra la checklist de la fase 1

| Ítem | Resultado |
|---|---|
| Idempotencia (aplicar dos veces) | No verificada. El script usa `IF NOT EXISTS`, `CREATE OR REPLACE` y `DROP IF EXISTS`. |
| `SECURITY DEFINER` con `search_path`, `REVOKE` y `GRANT` | Las RPC y los helpers internos sí. Las utilidades `rpe_slug_base`, `rpe_codigo_aleatorio` y `rpe_generar_codigo_qr` no son `SECURITY DEFINER` y no tienen `REVOKE`: las llaman triggers y el `DEFAULT` de `codigo_qr`. |
| RPC públicas sin UUID | Los JSON se arman con slug, código y textos. Siguen saliendo las URLs de imagen, que pueden contener un UUID. |
| Locks ascendentes y todo o nada | `rpe_insertar_inscripciones` bloquea los talleres por uuid ascendente. El cupo del evento se toma antes. Si hay rechazo, no queda fila de registrado. El solape no se fuerza en el alta. |
| Sin políticas INSERT en `registrados` | `DROP` de `rpe_registrados_insert` y `rpe_registrados_insert_publico`, y `REVOKE INSERT` a `anon` y `authenticated`. |
| `DROP` de `rpe_eventos_select_publico` | Hecho, sin recrearla. |
| `acreditado_en` antes del trigger de externo | `trg_registrados_acreditado_en` queda antes de `trg_registrados_restrict_externo_update` por orden alfabético. No hizo falta renombrar el de externo. |
| `schema.sql` y la migración coinciden | No del todo. Las funciones y las tablas nuevas están en la migración. `schema.sql` evita recrear el modelo viejo y actualiza storage y `rpe_eliminar_usuario`. `rpe_storage_en_uso` en el schema consulta `banner_url` y `subeventos` solo si ya existen. |

La fase 1 no está cerrada: faltan la corrida doble de la migración y los 15 casos en staging.
