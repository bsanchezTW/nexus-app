# Correcciones: revisión 1 (subeventos, cupos y QR único)

> **Para:** Grok (Cursor). **Revisa:** Claude (arquitecto). **Fecha:** 2026-09-28.
>
> Este documento sale de la revisión del trabajo de las fases 1 a 8. Cada corrección tiene: el problema, la causa, el cambio exacto y el criterio de aceptación. **No se decide nada fuera de lo escrito aquí.** Si algo es ambiguo, se deja `// TODO(arquitectura): <pregunta>` y se reporta.

---

## 0. Reglas de trabajo

1. **Rama:** se trabaja directo en `main`, porque la app no está en producción.
2. **Primer commit:** antes de corregir nada, commitear tal cual el trabajo pendiente de las fases 5 a 8 (hoy sin commit), con el mensaje `[f5-f8] Registro con talleres, asistencia, KPIs y Excel`. Así las correcciones quedan en un diff limpio.
3. **Un commit por corrección**, con el prefijo `[rev1-C<N>]`. Ejemplo: `[rev1-C1] Carga las inscripciones antes de decidir en el escáner`.
4. **SQL:**
   - **No se edita** `202609251200_subeventos_cupos_ids_opacos.sql`, porque ya está aplicada.
   - Todo cambio SQL va en una migración nueva: `supabase/migrations/202609281200_subeventos_correcciones.sql`. Tiene que ser idempotente, con `CREATE OR REPLACE` y `DROP … IF EXISTS`.
   - Después se refleja en `supabase/schema.sql` (ver C4).
5. **Base de datos:** el proyecto `evjocwzmlsyjixzihxep` no tiene usuarios. Se puede aplicar ahí la migración nueva y **ejecutar** `supabase/tests/subeventos_test.sql`. El script va entero dentro de `BEGIN … ROLLBACK`, así que no deja datos.
6. **Deno:** si no está instalado, usar `npx -y deno test supabase/functions/_shared/`.
7. **Al terminar:** `flutter analyze` sin issues, `flutter test` en verde y el reporte `docs/arquitectura/subeventos/fases/rev1-reporte.md`. El reporte debe incluir:
   - cada corrección con su commit;
   - la salida de los NOTICE del script SQL;
   - la salida de `deno test`;
   - los TODO que queden.

**Convenciones** (las mismas de siempre):
- Riverpod manual, sin codegen.
- Fakes escritos a mano en los tests, sin mocktail.
- Textos en español.
- Tokens de `app_theme.dart` / `tw_tokens.dart`, nunca colores literales.
- Constantes de tablas y RPC en `supabase_tables.dart`.
- Funciones SQL `SECURITY DEFINER` con `SET search_path = public, pg_temp` y `REVOKE` / `GRANT` explícitos.

---

## Prioridad crítica

### C1. Las inscripciones nunca se cargan en el escáner, la edición y el filtro por taller

**Problema.** `inscripcionesPorEventoProvider` es `FutureProvider.autoDispose.family`. Tres pantallas lo leen con `ref.read(...).valueOrNull` sin que nadie lo tenga en `watch`. Por eso siempre devuelve `null`: el provider arranca en loading y se descarta enseguida. Los tests no lo detectan porque sus overrides devuelven el valor al instante.

| Archivo | Síntoma |
|---|---|
| [acreditar_qr_screen.dart](../../../lib/features/acreditacion/screens/acreditar_qr_screen.dart) `_procesarAsistencia` (~línea 357) y `_resolverRechazoInscripcion` (~454) | En modo taller, todo inscrito aparece como "no inscrito". Externo nunca puede marcar. Admin recibe un error de clave única al intentar "Inscribir y marcar". |
| [editar_registrado_screen.dart](../../../lib/features/registrados/screens/editar_registrado_screen.dart) `_precargar` (~línea 112) | Los talleres de la persona aparecen vacíos. Agregar uno que ya tiene falla. No se puede quitar ninguno. |
| [ver_registrados_screen.dart](../../../lib/features/registrados/screens/ver_registrados_screen.dart) `_filtrarRegistrados` (~línea 139) | Al filtrar por taller, la lista queda vacía. |

**Cambio.**

1. **`acreditar_qr_screen.dart`**
   - En `build`, junto a `ref.watch(registradosPorEventoProvider(...))`, agregar `ref.watch(subeventosPorEventoProvider(widget.eventoId));` y `ref.watch(inscripcionesPorEventoProvider(widget.eventoId));`, con el mismo comentario de precarga.
   - Agregar `Future<List<InscripcionSubevento>> _listaInscripciones()`, calcado de `_listaAsistentes()`: si hay valor lo devuelve; si está cargando, espera `.future`; si falla, devuelve lista vacía **y lo registra con `developer.log(name: 'AsistenciaSubevento')`**.
   - `_procesarAsistencia` y `_resolverRechazoInscripcion` usan `await _listaInscripciones()`. Se elimina el `ref.read(...).valueOrNull` de inscripciones.
   - **Si la lista de inscripciones no se pudo cargar y hay red:** antes de ofrecer "Inscribir y marcar", llamar a `marcarAsistencia` directo. El servidor responde `no_inscrito` si corresponde, y recién ahí se ofrece inscribir. Así nunca se decide "no inscrito" sin datos.
2. **`editar_registrado_screen.dart`**
   - En `build`, hacer `ref.watch(inscripcionesPorEventoProvider(widget.eventoId))`.
   - Sacar la carga de talleres de `_precargar`. Se cargan con un `ref.listen` (o en `build`) **solo cuando el AsyncValue tiene valor** y `_talleresCargados == false`.
   - Mientras no cargue, la sección "Talleres" muestra `LoadingView` compacto y el botón Guardar **no envía cambios de talleres**. Hay que evitar calcular `agregar` / `quitar` contra un conjunto inicial vacío.
   - Si el provider termina con error: la sección muestra "No se pudieron cargar los talleres" con reintento, y el guardado no toca talleres.
3. **`ver_registrados_screen.dart`**
   - En `build` (línea ~218), hacer `ref.watch(inscripcionesPorEventoProvider(widget.eventoId)).valueOrNull ?? const []`.
   - Pasar esa lista a `_filtrarRegistrados` como parámetro, **reutilizando** `filtrarRegistradosPorModo`, que ya existe y usa la lista manual. El método deja de leer providers adentro.
4. **Barrido:** `grep -rn "ref.read(inscripcionesPorEventoProvider\|ref.read(subeventosPorEventoProvider" lib`.
   - Solo se admite `ref.read(...)` en callbacks cuando la misma pantalla hace `watch` del provider en `build`. Documentarlo con un comentario de una línea.
   - `ref.read(...).future` en servicios (snapshot, KPI, export) está bien.

**Tests (obligatorios; deben fallar con el código actual y pasar con el corregido).** En los overrides, usar un provider que **tarde**:

```dart
inscripcionesPorEventoProvider.overrideWith((ref, id) async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
  return [inscripcionDePrueba];
}),
```

- `test/features/registrados/editar_registrado_talleres_test.dart`:
  - tras `pumpAndSettle`, el taller inscrito aparece marcado;
  - guardar sin tocar talleres no llama a `inscribir` ni a `quitar` (verificar con un fake que cuente llamadas).
- `test/features/registrados/ver_registrados_filtro_taller_test.dart`: filtrar por taller muestra solo al inscrito.
- **Escáner:** extraer a una función pura `@visibleForTesting` la resolución `resolverInscripcionParaEscaneo({required Future<List<InscripcionSubevento>> Function() cargar, required String registradoId, required String subeventoId})` y probar que espera la carga diferida.

**Aceptación.**
- Con la app contra la base, en modo taller: un inscrito se marca a la primera, uno ya marcado dice "Ya tenía asistencia" y un no inscrito ofrece inscribir.
- Externo puede marcar a un inscrito.

---

## Prioridad alta

### C2. Asistencia a talleres: resultado ignorado online y marca invisible offline

**Problema.** En [inscripciones_providers.dart](../../../lib/features/subeventos/providers/inscripciones_providers.dart):

- **Online:** `persistirAsistenciaSubevento` ignora `{ok:false, motivo:'no_inscrito'}` de `marcarAsistencia`. Luego parchea la caché como `acreditado: true` y la UI muestra éxito.
- **Offline:** `fusionarInscripcionesConCola` descarta el ítem en cola cuando la inscripción ya existe (`yaEsta → continue`). Esa fila sigue con `asistio=false`, así que la lista y el escáner no muestran la marca hasta sincronizar, y al reescanear se vuelve a encolar.

**Cambio.**

1. **`persistirAsistenciaSubevento`, rama online de `marcar_asistencia`:** si `resultado['ok'] == false`, lanzar `AsistenciaRechazada(resultado['motivo'])` **antes** de tocar la caché.
2. **`fusionarInscripcionesConCola`:** para cada ítem en cola del par `(registrado, taller)`:
   - si la fila del servidor existe → reemplazarla por una copia con `asistio: true` y `pendienteDeSincronizar: true`. Si `InscripcionSubevento` no tiene `copyWith`, agregarlo;
   - si no existe → mantener el comportamiento actual (fila extra).
   - Para `inscribir_y_marcar` con `reemplazar: true`, **no** se simulan en caché los talleres que se quitan; el servidor lo resuelve al sincronizar. Anotarlo en un comentario.
3. **Escáner** (`_procesarAsistencia`, caso `marcarAsistencia`): capturar `AsistenciaRechazada`.
   - Si el motivo es `no_inscrito`: `ref.invalidate(inscripcionesPorEventoProvider(...))` y aplicar el mismo camino que `ofrecerInscribirYMarcar`.
   - Cualquier otro motivo: mostrar el feedback de error.
4. **Lista manual** ([acreditar_confirmado_screen.dart](../../../lib/features/acreditacion/screens/acreditar_confirmado_screen.dart), ~línea 63): capturar `AsistenciaRechazada`.
   - Con `no_inscrito`: mostrar "Esa persona ya no está inscrita en el taller." y refrescar con `_actualizarRegistrados()`.
   - El `catch (_)` genérico queda solo para los demás errores.

**Tests.**
- `fusionarInscripcionesConCola`: una fila existente con `asistio=false` más un ítem en cola da **una sola** fila con `asistio=true` y `pendienteDeSincronizar=true`. Un ítem sin fila en el servidor da una fila extra, como hoy.
- `persistirAsistenciaSubevento` online con un fake que responde `ok:false` lanza `AsistenciaRechazada` y **no** llama a `parchearFila` (fake de `OfflineReadCache`).

**Aceptación.** En modo avión: marcar a un inscrito hace que la lista lo muestre marcado al instante, y al volver la red se sincroniza sin duplicados.

### C3. El SQL debe responder de forma idempotente y ordenada

Todo lo siguiente va en `202609281200_subeventos_correcciones.sql`.

**C3a. `rpe_publico_registrar`: carrera con el mismo email.** Hoy busca el email antes de tomar el lock. Dos envíos simultáneos con el mismo correo terminan en un error `23505` crudo.
- **Cambio:** llamar a `PERFORM public.rpe_lock_cupo_evento(v_evento.id);` **antes** del `SELECT … INTO v_reg` por email (después de validar los datos y los códigos), y quitar el lock que hoy está dentro de la rama `IF NOT FOUND`. Así todos los registros públicos de un mismo evento quedan en fila, lo que es aceptable en volumen.
- **Limpieza:** eliminar la primera consulta muerta que asigna `v_nuevos, v_ya` y se sobrescribe enseguida (líneas ~1903-1910 de la migración original).

**C3b. `rpe_inscribir_subevento`: persona ya inscrita.** Hoy termina en un error de clave única.
- **Cambio:** justo después del chequeo de permisos y de cargar `v_sub`, buscar la inscripción `(p_registrado_id, p_subevento_id)`. Si existe:
  - si `p_marcar_asistencia` y `NOT asistio` → `UPDATE … SET asistio=true, asistio_en=now(), asistio_por=auth.uid()`, y acreditar el principal igual que hoy;
  - devolver `{"ok":true,"inscripcion_id":…,"ya_inscrito":true,"acreditado_principal":<bool>,"reemplazados":[]}`, **sin** consumir cupo.
- En Dart, `ya_inscrito` se trata como éxito. El escáner muestra "Ya estaba inscrito; asistencia marcada."

**C3c. `rpe_marcar_asistencia_subevento`: permiso antes que existencia.** Hoy responde `no_inscrito` antes de validar permisos.
- **Cambio:** cargar primero el registrado (`evento_id`); si no existe → `RPE_REGISTRADO_NO_ENCONTRADO`. Luego `IF NOT rpe_puede_operar_evento(evento_id) THEN RAISE RPE_NO_AUTORIZADO`. Recién después buscar la inscripción.

**C3d. RUT con `k` minúscula.** En `rpe_validar_datos_asistente` (rama Chile), la limpieza borra la `k` antes de pasar a mayúsculas.
- **Cambio:** `v_compacto := regexp_replace(upper(btrim(COALESCE(p_datos->>'rut', ''))), '[^0-9K]', '', 'g');`
- `rpe_validar_datos_asistente` se recrea completa con `CREATE OR REPLACE`, sin otro cambio de lógica salvo C3f.

**C3e. `tiene_subeventos` cuenta talleres ocultos.** En `rpe_publico_calendario` y `rpe_publico_evento`: `EXISTS (… WHERE s.evento_id = e.id AND s.visible_publico)`.

**C3f. Importación Excel en eventos con certificación.** **Decisión del arquitecto:** en `rpe_importar_registrados`, RUT y patente son **opcionales**; si vienen, se valida su formato. En el registro manual (`rpe_registrar_asistente`) siguen siendo obligatorios.
- **Cambio:** agregar a `rpe_validar_datos_asistente` un tercer parámetro, `p_certificacion_opcional boolean DEFAULT false`. Si es `true` y `rut` / `patente` vienen vacíos, se omiten sin error.
- Como cambia la firma:
  - hacer `DROP FUNCTION` de la versión de 2 argumentos y recrear;
  - actualizar los `REVOKE` (sin `GRANT`);
  - actualizar las 3 llamadas (`rpe_registrar_asistente` → `false`, `rpe_importar_registrados` → `true`, `rpe_publico_registrar` → no aplica, porque pasa `p_exigir_certificacion=false`).

**Tests SQL.** Agregar a `supabase/tests/subeventos_test.sql` los casos 16 a 21:

16. Llamar dos veces seguidas a `rpe_publico_registrar` con el mismo email devuelve `inscrito` y luego `sin_cambios`, sin error.
17. `rpe_inscribir_subevento` sobre alguien ya inscrito con `p_marcar_asistencia=true` devuelve `ya_inscrito=true`, marca `asistio` y no cambia el conteo de inscritos.
18. Un user de otro evento que llama a `rpe_marcar_asistencia_subevento` recibe `RPE_NO_AUTORIZADO`, esté o no inscrita la persona.
19. `10.000.013-k` y `10.000.013-K` son válidos y se normalizan a `10000013K`.
20. `tiene_subeventos=false` cuando el evento solo tiene talleres con `visible_publico=false`.
21. Importación en un evento con certificación: una fila sin RUT se inserta; una fila con RUT inválido cae en `invalidos`.

**Aceptación:** la migración se aplica dos veces sin error y el script (casos 1 a 21) imprime todos los `OK`.

### C4. `schema.sql` debe reflejar el modelo completo

**Problema.** `supabase/schema.sql` no tiene `subeventos`, `inscripciones_subevento`, `envios_qr`, las funciones utilitarias, los helpers, las RPC internas y públicas, los triggers, las políticas ni los grants. Además tiene guardas `to_regclass(...)` y "solo si existe", que sirvieron de parche. El README lo define como fuente de verdad.

**Cambio.**
1. Incorporar a `schema.sql` **todo** el contenido de las dos migraciones (la original y la de C3), ya en su versión final, en las secciones que corresponden:
   - utilidades cerca de las demás `rpe_*`;
   - tablas nuevas después de `registrados`;
   - funciones de inscripción y RPC en la zona de funciones;
   - RLS y grants en la sección de políticas;
   - storage en la sección 7.
2. Quitar las guardas `to_regclass('public.subeventos')`, `…envios_qr` e `…inscripciones_subevento` que ya no hacen falta (`rpe_storage_en_uso`, `rpe_eliminar_usuario`, `rpe_eventos_validar_rango_subeventos`).
   - **Ojo con el orden:** `rpe_eventos_validar_rango_subeventos` y el trigger de eventos referencian `subeventos`. La **creación del trigger** debe ir después de `CREATE TABLE subeventos`. La función (plpgsql) se puede crear antes.
3. Actualizar el comentario del encabezado del README sobre `supabase/migrations/`, que hoy dice que está vacía.

**Verificación (incluir su salida en el reporte).** Todos los nombres deben aparecer en `schema.sql`:

```bash
for n in $(grep -hoE "(FUNCTION|TABLE IF NOT EXISTS|POLICY|TRIGGER) public\.[a-z_]+|POLICY [a-z_]+|TRIGGER [a-z_]+" supabase/migrations/202609251200_subeventos_cupos_ids_opacos.sql supabase/migrations/202609281200_subeventos_correcciones.sql | awk '{print $NF}' | sed 's/public\.//' | sort -u); do grep -q "$n" supabase/schema.sql || echo "FALTA: $n"; done
```

Además, **aplicar `schema.sql` completo en el proyecto** (es idempotente) y volver a correr el script de tests: todo `OK`.

---

## Prioridad media

### C5. Mensajes de error por campo

**Problema.** En [rpe_exception.dart](../../../lib/core/errors/rpe_exception.dart), PostgREST entrega `details` como **string** (`'{"campo":"email","regla":"formato"}'`). `_texto` no lo decodifica, así que el mensaje siempre es genérico. Además, cuando sí hubiera campo, se mostraría la clave cruda (`nombre_completo`).

**Cambio.**
- En `rpeExceptionDesde`: si `details is String` y comienza con `{`, hacer `jsonDecode` dentro de un `try` y usar el mapa. Si falla, dejar `details` como está.
- Agregar `const kEtiquetasCampoRpe = {'nombre_completo': 'nombre y apellido', 'email': 'correo', 'empresa': 'empresa', 'cargo': 'cargo', 'telefono': 'teléfono', 'rut': 'RUT/RUC', 'patente': 'patente', 'codigo': 'código', 'subeventos': 'talleres', 'rango': 'rango de fechas'}`.
- Mensaje: `'El campo ${kEtiquetasCampoRpe[campo] ?? campo} no es válido.'`. Para cualquier clave `utm_*`: `'Un parámetro de campaña no es válido.'`.
- Si no hay campo pero `PostgrestException.hint` no está vacío, usar el hint como mensaje. Los hints ya están en español en el SQL.

**Tests.** `test/core/errors/rpe_exception_test.dart`:
- `details` como string JSON da el mensaje con la etiqueta;
- `details` como mapa, igual;
- `details` como string no JSON da el mensaje genérico;
- `utm_source` da el mensaje de campaña;
- solo hint da el hint.

### C6. El escáner avisa antes de usar sobrecupo

**Problema.** Para admin u organizador, "Inscribir y marcar" siempre envía `forzar: true`, así que inscribe en sobrecupo sin decir que el taller está lleno. La decisión del usuario fue: **avisar**, y que admin u organizador puedan sobrepasar.

**Cambio en `acreditar_qr_screen.dart`.**
- **Online:** el primer intento va **siempre** con `forzar: false`. Si la respuesta es `sin_cupo` y `accion.puedeForzar`, mostrar un segundo `confirmDialog`:
  - título "Taller lleno";
  - mensaje "El taller no tiene cupo. ¿Inscribir en sobrecupo?";
  - botón "Inscribir en sobrecupo".
  - Si confirma → reintentar con `forzar: true`.
  - Si no puede forzar → feedback "Sin cupo en este taller."
- **Offline** (solo admin u organizador llegan a este caso): el diálogo inicial dice "Sin conexión no se puede comprobar el cupo. Si el taller está lleno, quedará en sobrecupo." y se encola con `forzar: true`.
- El mensaje del primer diálogo online pasa a ser "Esta persona no está inscrita en {taller}." Se elimina "incluso si el cupo está lleno".
- El mismo flujo de dos pasos aplica a "Mover desde {taller}" (`reemplazar: true`).

**Tests.** Extender `decidir_accion_escaneo_test.dart` si cambia la firma. Si el flujo vive en el widget, extraer `Future<void> inscribirConAvisoDeCupo({required Future<Map<String,dynamic>> Function(bool forzar) intentar, required Future<bool> Function() confirmarSobrecupo, required bool puedeForzar})` como función pura y probar:
- ok a la primera no pregunta;
- con `sin_cupo` y permiso, pregunta y reintenta con `forzar=true`;
- con `sin_cupo` sin permiso, no reintenta.

### C7. Correo y SMS

**C7a. Zona horaria en Google Calendar.**
- En [zona_horaria.ts](../../../supabase/functions/_shared/zona_horaria.ts), agregar `zona: string` a `RangoEvento`.
- Cuando el evento tiene horas, el link de Google agrega `&ctz=${encodeURIComponent(evento.zona)}`.
- `enviar-qr` pasa `zona: zonaDePais(evento.pais)`.
- Outlook queda igual: interpreta la hora local de quien abre el link.
- **Test:** `zona_horaria_test.ts` verifica que con horas el link incluye `ctz=America%2FSantiago`, y que sin horas no lo incluye.

**C7b. SMS solo con caracteres GSM-7.**
- Hoy lleva `á` y `…`, que obligan a codificar el mensaje en UCS-2: 70 caracteres por segmento, unos 3 SMS cobrados por envío.
- **Cambio en [plantillas_confirmacion.ts](../../../supabase/functions/_shared/plantillas_confirmacion.ts):**
  - agregar `export function aGsm7(texto: string): string`, que haga `normalize("NFD")`, quite las marcas diacríticas (`/[̀-ͯ]/g`), reemplace `…` por `...` y reemplace cualquier carácter fuera del alfabeto básico GSM 03.38 por `?`;
  - el texto pasa a ser `"{evento}: registro confirmado{, N talleres}. QR: {url}"`, con `aGsm7` aplicado al nombre del evento;
  - el recorte a 160 caracteres usa `...`.
- **Test:** evento "Conexión Anual Ñuñoa…" da un texto solo GSM, de 160 caracteres o menos, que contiene la URL completa.

**C7c. Detalle del error de Brevo.**
- Cuando `res.ok` es falso, guardar en `reason` el formato `brevo_email:<status>:<primeros 300 caracteres del cuerpo>` (lo mismo para SMS).
- El cuerpo de error de Brevo no trae los datos de la persona, pero **no** debe ir a `log(...)`. Solo se guarda en `envios_qr.resultado`.

**Aceptación (manual, en el proyecto de desarrollo, tras el deploy que hace el usuario):** un correo con evento de hora fija abre Google Calendar a la hora correcta, y un SMS de prueba llega como 1 o 2 segmentos (ver el detalle en Brevo).

---

## Prioridad baja (hacer si todo lo anterior está verde)

- **C8. Sugerir el taller en curso** (spec §14, fase 6). Agregar `Subevento? sugerirSubeventoEnCurso(List<Subevento> talleres, DateTime ahora)` en `lib/features/subeventos/`, usando `Subevento.enCurso`. Si hay varios, gana el de inicio más reciente. Al abrir el escáner sin `?subevento=`, el selector propone ese taller en un `TwToast.info` ("Taller en curso: X. ¿Cambiar?"), **sin cambiar el modo solo**. Con test.
- **C9. Colores del selector del escáner.** Reemplazar `Colors.black54` / `Colors.black87` / `Colors.white` del dropdown por tokens (`TwColors` / `AppColors`). Si no hay un token para overlay oscuro, agregarlo en `tw_tokens.dart`.
- **C10. Diseño del correo.** Recuperar el formato visual del correo anterior (commit `2db541e`, `supabase/functions/enviar-qr/index.ts`): botones de calendario con color (Outlook `#0078D4`, Google `#4285F4`), el bloque "Consultas a contacto@transworld.cl" y los márgenes. Se mantiene el contenido nuevo: el tono, la tabla de talleres, el QR condicional y el escape de HTML. Actualizar los tests de plantillas.

---

## Lo que NO se toca

- El modelo de datos, los contratos públicos (`docs/api-publica.md`) y los permisos, salvo lo indicado en C3.
- Refactors fuera de los archivos de cada corrección.
- El despliegue de funciones, el webhook y el release. Eso lo hace el usuario; ver `despliegue.md`.

## Checklist de revisión (la usa Claude)

- [ ] C1: ningún `ref.read(...).valueOrNull` de inscripciones o talleres sin su `watch` en `build`; tests con provider diferido que fallan con el código viejo.
- [ ] C2: el rechazo online no parchea la caché; la fusión marca la fila existente.
- [ ] C3: migración nueva idempotente; casos SQL 16 a 21 en verde; firma nueva de `rpe_validar_datos_asistente` con `REVOKE` actualizado.
- [ ] C4: el script de verificación no imprime ningún `FALTA`; `schema.sql` aplicado entero sin errores.
- [ ] C5 a C7: tests nuevos en verde; `deno test` en verde.
- [ ] Commits separados `[rev1-C<N>]`, más el reporte `rev1-reporte.md`.
