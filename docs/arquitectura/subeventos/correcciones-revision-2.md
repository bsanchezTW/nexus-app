# Correcciones: revisión 2

> **Para:** Grok (Cursor). **Revisa:** Claude. **Fecha:** 2026-09-28.
> Mismas reglas que en `correcciones-revision-1.md` §0:
> - trabajo en `main`, con un commit por corrección (prefijo `[rev2-D<N>]`);
> - migración nueva idempotente si hay SQL;
> - al terminar, `flutter analyze` y `flutter test` en verde, y el reporte `fases/rev2-reporte.md`.

La revisión 1 quedó aprobada salvo lo que sigue.

---

## D1 (media). El SMS reemplaza las letras con tilde por `?`

**Problema.** En [plantillas_confirmacion.ts](../../../supabase/functions/_shared/plantillas_confirmacion.ts), `aGsm7` usa `/̀-ͯ/g`, sin corchetes. Esa expresión busca la secuencia literal "marca + guion + marca", no un rango, así que no quita ninguna tilde. Después de `normalize("NFD")`, cada marca queda suelta y se convierte en `?`. Resultado real, reproducido:

```
"Conexión Anual Ñuñoa…"  →  "Conexio?n Anual N?un?oa..."
```

El test actual no lo detecta: solo verifica que el texto sea "GSM puro", y `?` es un carácter GSM.

**Cambio.** Recorrer el texto **carácter por carácter** (no descomponer todo de una vez):
1. Si el carácter está en el set `GSM7`, se conserva. Así se mantienen `é`, `ñ`, `Ñ`, `ü` y `à`, que sí son GSM.
2. Si no está, aplicar `normalize("NFD")` a ese carácter y quitar las marcas con `/[̀-ͯ]/g`. Si el resultado está en `GSM7`, usarlo (`á` → `a`, `í` → `i`, `ó` → `o`, `ú` → `u`, `Á` → `A`).
3. `…` → `...`.
4. Cualquier otro carácter → `?`.

**Test** (reemplaza las aserciones débiles):

```ts
assertEquals(aGsm7("Conexión Anual Ñuñoa…"), "Conexion Anual Ñuñoa...");
assertEquals(aGsm7("Día único — Perú"), "Dia unico ? Peru");
assertEquals(aGsm7("Café"), "Café");
```

En el test de `textoSms`, además, verificar que el texto **no** contenga `?` cuando el nombre del evento solo tiene letras españolas.

---

## D2 (baja). `schema.sql` define varios objetos dos veces

**Problema.** Para cumplir C4, las dos migraciones se pegaron completas al final de `schema.sql`. El estado final es correcto porque la última definición gana, pero quedaron versiones obsoletas antes de las vigentes:

- `rpe_publico_registrar` y `rpe_inscribir_subevento` aparecen dos veces cada una;
- la versión de 2 argumentos de `rpe_validar_datos_asistente` se crea, se le aplica `REVOKE` y se elimina en cada ejecución.

Quien edite la primera copia no verá ningún efecto.

**Cambio.**
- En `schema.sql`, eliminar los bloques que la migración `202609281200` reemplaza. Queda **una sola definición** de cada función, en su versión final:
  - `rpe_validar_datos_asistente` (3 args)
  - `rpe_registrar_asistente`
  - `rpe_importar_registrados`
  - `rpe_inscribir_subevento`
  - `rpe_marcar_asistencia_subevento`
  - `rpe_publico_calendario`
  - `rpe_publico_evento`
  - `rpe_publico_registrar`
- Conservar `DROP FUNCTION IF EXISTS public.rpe_validar_datos_asistente(jsonb, boolean);`, para las bases antiguas, **antes** de crear la versión de 3 argumentos. Quitar el `REVOKE` de la firma de 2 argumentos.
- No cambiar lógica.

**Verificación (incluir su salida en el reporte).** Cada conteo debe ser `1`:

```bash
for f in rpe_validar_datos_asistente rpe_registrar_asistente rpe_importar_registrados rpe_inscribir_subevento rpe_marcar_asistencia_subevento rpe_publico_calendario rpe_publico_evento rpe_publico_registrar; do printf "%s " $f; grep -c "CREATE OR REPLACE FUNCTION public.$f(" supabase/schema.sql; done
```

Además, **reaplicar `schema.sql`** y correr `supabase/tests/subeventos_test.sql`: sin errores.

---

## D3 (baja). `rpe_inscribir_subevento` revisa "ya inscrito" antes del bloqueo

**Problema.** Si llegan dos llamadas simultáneas para la misma persona y el mismo taller (doble toque, o escáner y lista a la vez), ambas ven "no inscrito" antes del lock. La segunda termina con un error crudo `23505`.

**Cambio.** En una migración nueva, `202609281500_inscribir_lock.sql` (reflejada en `schema.sql` reemplazando la definición, sin duplicar):
- mover `PERFORM public.rpe_lock_cupo_subevento(p_subevento_id);` para que quede **antes** del `SELECT … FROM inscripciones_subevento` que detecta "ya inscrito";
- el resto queda igual.

**Test SQL.** No se puede simular la concurrencia en el script. Basta con que los casos 17 y 3 a 8 sigan en verde.

---

## D4 (baja). El aviso del taller en curso pregunta "¿Cambiar?" sin ofrecer cómo

**Problema.** En [acreditar_qr_screen.dart](../../../lib/features/acreditacion/screens/acreditar_qr_screen.dart), `_programarAvisoDeTaller` muestra `TwToast.info(... '¿Cambiar?')`, pero el toast no tiene ninguna acción.

**Cambio.**
- Si `TwToast` tiene una variante con acción (`TwToast.link` u otra), usarla con el botón "Usar este taller", que hace `setState(() => _subeventoId = sugerido.id)`.
- Si no la tiene, cambiar el texto a `'Taller en curso: ${sugerido.nombre}. Elígelo arriba para pasar asistencia.'`.
- **No** cambiar el modo automáticamente.

---

## D5 (trivial). `deno.lock` sin decidir

Quedó `deno.lock` sin seguimiento en la raíz. Hay que agregarlo a `.gitignore`, porque las funciones se despliegan desde el CLI de Supabase y el lockfile de la raíz no se usa.

---

## Pendiente del usuario (no es de Grok)

- **Caso 15 (concurrencia):**
  1. abrir dos pestañas del SQL Editor en el proyecto;
  2. en ambas, ejecutar `BEGIN;` y un `rpe_publico_registrar` sobre un evento con **1 cupo libre**;
  3. hacer `COMMIT` en las dos.
  - **Resultado esperado:** una responde `ok:true` y la otra queda esperando, hasta que responde `sin_cupo_evento`.
- Desplegar `enviar-qr` y `qr-imagen`, crear el webhook de `envios_qr` y hacer las pruebas manuales de `despliegue.md`.

## Checklist de revisión

- [ ] D1: los tests con valores exactos pasan; `deno test` en verde.
- [ ] D2: el script de conteo imprime `1` en todas las funciones; `schema.sql` reaplicado y tests SQL en verde.
- [ ] D3: migración nueva; el lock va antes del chequeo de "ya inscrito".
- [ ] D4: el aviso no promete una acción que no existe.
- [ ] D5: `deno.lock` ignorado.
