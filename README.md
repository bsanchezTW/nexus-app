# Transworld Nexus (Flutter)

Reconstrucción en Flutter de **Registro Pro**, ahora bautizada **Transworld
Nexus**, unificando en un solo código
base lo que antes eran dos apps separadas e inconsistentes:
`registro-pro-eventos-master` (Expo/React Native) y `registro-pro-pc-main`
(React + Vite + Electron). Corre en Android, iOS, Web y escritorio
(macOS/Windows/Linux) desde el mismo código.

Este proyecto nace del levantamiento detallado documentado en
`documentacion_zips_registro_pro.md` (ver especialmente las Secciones 8, 17
y 18) y corrige explícitamente los hallazgos críticos ahí identificados.

## Qué se corrigió respecto al proyecto legado

| # | Problema en el proyecto legado | Corrección en este proyecto |
|---|---|---|
| 1 | **Escalación de privilegios**: la policy RLS `rpe_perfiles_update` no tenía `WITH CHECK`, cualquier usuario autenticado podía autoasignarse `rol = 'admin'` llamando directo a la API de Supabase. | `supabase/schema.sql` agrega el trigger `rpe_prevent_role_self_escalation`, que rechaza cualquier `UPDATE` que cambie `rol` o `activo` si quien lo ejecuta no es admin. Además, el cambio de rol desde la app pasa por el RPC `rpe_actualizar_rol_usuario` (`SECURITY DEFINER`), nunca por un `UPDATE` directo. |
| 2 | **Cola offline móvil rota**: `lib/offlineManager.ts` usaba la clave `capturador_leads_cola_offline` (nunca escrita), mientras las pantallas escribían en `registro_pro_cola_offline` (nunca leída). Los registros offline nunca se sincronizaban. | Una única cola (`data/offline/sync_queue_service.dart`), una única clave de `SharedPreferences`, con estado/reintentos/errores por ítem, y un único `SyncCoordinator` que dispara la sincronización al recuperar conexión. |
| 3 | `eventos` y `registrados` con RLS `USING (true) WITH CHECK (true)` para cualquier autenticado: la única barrera era ocultar botones en la UI. | Políticas separadas por operación: cualquier autenticado puede leer/registrar, pero crear/editar/eliminar eventos y eliminar registrados requiere `rol = 'admin'` **a nivel de base de datos**. |
| 4 | Sin constraint de duplicados en `registrados`: la deduplicación era solo a nivel de aplicación. | `UNIQUE (evento_id, email)` en la base de datos, reforzado (no reemplazado) por un chequeo previo en el cliente. |
| 5 | Esquema inconsistente: código y `.env` apuntaban a `registro_eventos`, pero `schema.sql` creaba todo en `public`. | Todo vive explícitamente en `public`, sin variables de esquema configurables que puedan desalinearse. |
| 6 | Base de datos compartida con la app hermana "capturador-leads" sin documentar el impacto. | Captura de leads vive en esta misma app (`features/capturador/`), mismo `auth.users` y esquema `public`; políticas/funciones con prefijo `rpe_` para evitar colisiones (`supabase/schema.sql`). |
| 7 | Formulario público de autoregistro vivía **fuera** de ambos repositorios (`intranet-transworld-dc.onrender.com`), como dependencia oculta e indocumentada. | El formulario público de Flutter se eliminó. El registro público lo hace la web Node con las RPC `rpe_publico_*`. Contrato: [`docs/api-publica.md`](docs/api-publica.md). |
| 8 | Integración con Electron oculta (`window.ipcRenderer`) sin las herramientas de build correspondientes en el ZIP. | Ya no aplica: el mismo Flutter Desktop nativo cubre exportación de archivos sin depender de un runtime externo. |
| 9 | `.env` con credenciales reales incluido en el ZIP pese a `.gitignore`. | `.env` real nunca se versiona; `.env.example` documenta las variables sin valores reales. Ver `.gitignore`. |
| 10 | Control de acceso por rol solo en la UI (`if (rol === 'admin')` repetido en decenas de archivos). | Sigue existiendo en la UI por UX (`RequireAdmin`, `isAdminProvider`), pero ya no es la única barrera: RLS + triggers son la fuente de verdad. |
| 11 | El cambio obligatorio de contraseña (`perfiles.cambiar_pass`, regla 6.1 de la doc) existía como pantalla pero nada lo forzaba: un usuario marcado podía seguir usando la app. | El `redirect` del router fuerza `/recrear-pass` mientras `cambiar_pass = true`; al guardar la nueva contraseña se refresca el perfil y se vuelve al home. |
| 12 | La Edge Function `enviar-qr` estaba declarada pero **nunca se invocaba**, `email_confirmacion_enviado` nunca se marcaba, y ningún flujo mostraba/entregaba el QR del asistente (la pantalla de escaneo leía un QR que nadie tenía). | El QR es `codigo_qr` (`TW1-` + 32 hex). Se muestra en "Ver registrados", se envía por email y SMS, y el escáner lo lee para la entrada y para la asistencia a talleres. Ver [`docs/ENVIO_QR.md`](docs/ENVIO_QR.md). |

## Arquitectura

```
lib/
  core/           # Config, tema, router, constantes, widgets compartidos
  data/
    models/       # Entidades inmutables (Perfil, Evento, Registrado, …)
    repositories/ # Un repositorio por tabla/dominio, hablan con Supabase
    offline/      # Motor de sincronización offline unificado
    supabase/     # Inicialización y provider del cliente Supabase
  features/       # Un folder por pantalla/flujo de negocio
    auth/
    home/
    perfil/           # Mi perfil (nombre, foto)
    eventos/
    usar_app/
    externo/          # Operación acotada a eventos asignados
    capturador/       # Campañas y captura de leads
    registro/
    registrados/
    subeventos/       # Talleres del evento
    acreditacion/
    fijados/          # Eventos/campañas fijados por usuario
    notificaciones/   # Inbox in-app + bootstrap FCM
    kpi/
    exportacion/
    usuarios/
    updates/          # OTA vía GitHub Releases (Android / Windows)
docs/
  NOTIFICACIONES_PUSH.md   # Setup Firebase + webhook Supabase
  ENVIO_QR.md              # Webhook y envío del QR
  api-publica.md           # Contrato de la web Node
  arquitectura/subeventos/ # Fases y despliegue
```

- **Sistema de diseño**: `core/theme/app_theme.dart` define los tokens
  (colores semánticos, espaciado, radios) y el tema Material 3 completo,
  con navegación de línea iOS: transiciones Cupertino (swipe back) en
  todas las plataformas y **sin AppBars de Material** —
  `core/widgets/app_scaffold.dart` integra el título en el contenido con
  una flecha de volver a la izquierda, más el banner offline y el ancho
  máximo de contenido para Web/escritorio. Las pantallas no usan colores
  ni paddings "sueltos": consumen los tokens. En el home, el perfil del
  usuario vive integrado en un encabezado a sangre completa con un menú
  de cuenta colapsable (Mi perfil / Configuraciones / Cerrar sesión) y
  acceso al inbox de notificaciones.
- **Flujo de autenticación**: el login está descompuesto en componentes
  (`features/auth/widgets/login/`: header hero dibujado con CustomPaint,
  formulario, botón con estados y animación de presión, tokens propios en
  `login_theme.dart`). Incluye "Recordarme" (persiste el correo en
  `SharedPreferences`), animaciones de entrada escalonadas (easeOutCubic,
  250–350 ms), colapso del hero al abrir el teclado, layout de dos paneles
  en pantallas ≥900 px y autoregistro de cuenta en `/registro` (el perfil
  lo crea el trigger `rpe_handle_new_user` con rol `user`). Los permisos
  runtime (cámara, mic, fotos, notificaciones) se piden una sola vez por
  usuario en el dispositivo tras autenticarse (`PermissionsBootstrap`).
- **Captura de leads**: `features/capturador/` unifica la app hermana
  (campañas, captura, listado y exportación Excel) sobre el mismo backend
  Supabase.
- **Fijados y home**: cada usuario puede fijar eventos y campañas
  (límite por dominio); el home destaca esos ítems junto al próximo evento.
- **Notificaciones**: inbox in-app (`/notificaciones`) con Realtime
  Supabase; push de sistema vía FCM en Android/iOS (ver
  `docs/NOTIFICACIONES_PUSH.md`). En Web/escritorio solo aplica el inbox.
- **Gestión de estado**: Riverpod (`flutter_riverpod` 2.x), con providers
  simples (`Provider`, `FutureProvider`, `StateNotifierProvider`) — sin
  generación de código, para mantener el build simple y predecible.
- **Navegación**: `go_router`, con `redirect` reactivo a los cambios de
  sesión de Supabase (`GoRouterRefreshStream`).
- **Persistencia offline**: `shared_preferences` como almacenamiento del
  motor de sincronización (`SyncQueueService`), que funciona igual en
  Android, iOS, Web y escritorio.
- **  Backend**: Supabase (Postgres + Auth + Storage + Edge Functions),
  esquema `public`. Ver `supabase/schema.sql` para el modelo completo,
  políticas RLS, triggers y funciones RPC. Es la fuente de verdad
  consolidada; `supabase/migrations/` se mantiene vacío a propósito.

## Cómo correr el proyecto

1. Instala las dependencias:

   ```bash
   flutter pub get
   ```

2. Copia `.env.example` a `.env` y completa con los datos de tu proyecto
   Supabase (y, si usas OTA, las variables `GITHUB_*`):

   ```bash
   cp .env.example .env
   ```

3. Aplica `supabase/schema.sql` en tu proyecto Supabase (SQL Editor).
   Es idempotente: puede ejecutarse varias veces sin duplicar objetos.

4. (Opcional — push FCM) Copia el stub y genera opciones reales:
   `cp lib/firebase_options.stub.dart lib/firebase_options.dart` y luego
   `flutterfire configure`. También coloca `google-services.json` /
   `GoogleService-Info.plist` (gitignored). Sin eso, CI y clones usan el
   stub: inbox in-app con Supabase; FCM desactivado. Para releases con
   push, configura el secret `FIREBASE_OPTIONS_BASE64` en GitHub Actions.

5. Corre la app:

   ```bash
   flutter run                # dispositivo/emulador conectado
   flutter run -d chrome      # Web
   flutter run -d macos       # macOS (requiere Xcode)
   ```

## Verificación realizada

- `flutter analyze` → sin advertencias ni errores.
- `flutter test` → suite en `test/` (modelos, offline, widgets de listas,
  home, notificaciones, storage, etc.). Las pantallas que hablan con
  Supabase deben mockear los repositorios de `data/repositories/`.
- `flutter build web --release` → build exitoso.
- Para build de macOS/iOS/Android nativo hace falta un entorno con
  Xcode/Android SDK completos; el código Dart se valida con `analyze` +
  tests + `build web`.

## Edge Functions (`supabase/functions/`)

| Función | Rol |
|---------|-----|
| `crear-usuario` | Alta por admin + email de credenciales (Brevo) |
| `regenerar-password-usuario` | Nueva password por admin + email |
| `reset-password` | Olvido de contraseña (sin sesión) |
| `enviar-qr` | Confirmación por email y SMS. El staff llama con JWT; el webhook de `envios_qr` usa la apikey secreta. Ver `docs/ENVIO_QR.md`. |
| `qr-imagen` | PNG público del código `TW1-…`, sin base de datos (`verify_jwt = false`) |
| `enviar-push` | Envía FCM al insertar en `notificaciones` (secret `FIREBASE_SERVICE_ACCOUNT_JSON`) |
| `limpiar-storage` | Vacía la cola `storage_basura`: borra los objetos que ya no referencia ninguna fila |

Desplegar con `supabase functions deploy`. El secret `BREVO_API_KEY` lo
comparten las funciones de correo y SMS. Remitentes: `soporte@transworld.cl`
(credenciales / reset) y `contacto@transworld.cl` (QR y comunicaciones
de evento).

Las functions leen `SUPABASE_PUBLISHABLE_KEYS` y `SUPABASE_SECRET_KEYS`
(JSON inyectado por el runtime, keyed por el nombre de cada key). La
secret se toma de `default`. Publishable de la app: `nexus_app`. Del
formulario: `eventos_web`. Si el JSON no está, caen a las JWT legacy.
`verify_jwt` está en `false`: las keys nuevas no son JWT y cada función
autoriza en código (sesión del usuario o `apikey` secret). El webhook de
`enviar-push` debe mandar `apikey: <sb_secret_…>`, no `Authorization: Bearer`
con la secret.

SMS transaccional de QR (eventos con acceso QR) usa además
`BREVO_SMS_SENDER` (nombre alfanumérico, máx. 11 caracteres; por defecto
`Transworld` si el secreto no está). El SMS lleva un enlace a la imagen del
QR. Hace falta crédito SMS en la cuenta Brevo.

Detalle del webhook y Firebase:
[`docs/NOTIFICACIONES_PUSH.md`](docs/NOTIFICACIONES_PUSH.md).
El contrato de la web pública está en
[`docs/api-publica.md`](docs/api-publica.md).
El orden para sacar esta versión está en
[`docs/arquitectura/subeventos/despliegue.md`](docs/arquitectura/subeventos/despliegue.md).

## Pendiente / próximos pasos

- **Push en dashboards**: webhook Database → `enviar-push` y secret
  Firebase (checklist en `docs/NOTIFICACIONES_PUSH.md`). El inbox in-app
  ya funciona sin eso.
- **RLS más granular por evento**: `usuarios_eventos` ya acota al rol
  externo en la app; falta reforzar a nivel de políticas que un usuario
  autenticado genérico no opere eventos ajenos solo vía API.
- Tests de integración con mocks de Supabase (por ejemplo con
  `mocktail` + fakes de `SupabaseClient`) para los repositorios y el motor
  de sincronización offline.
- Configurar íconos/splash screen definitivos (`flutter_launcher_icons`,
  `flutter_native_splash`) — hoy el proyecto usa los assets por defecto de
  `flutter create`.
- Subir `Plantilla_Registro.xlsx` al bucket `plantillas` de Storage (lo
  referencia `StorageRepository.urlPlantillaRegistro`, pero el archivo en
  sí no se genera desde este repo).

## Actualizaciones OTA (Android / Windows / GitHub Releases)

Nexus se distribuye de forma privada vía **GitHub Releases** (sin Play Store
ni Supabase Storage). En **Android** y **Windows**, tras el login la app consulta:

`GET https://api.github.com/repos/{GITHUB_OWNER}/{GITHUB_REPO}/releases/latest`

y ofrece instalar la actualización si el `tag_name` (SemVer) es mayor que la
versión instalada (`package_info_plus` ↔ `pubspec.yaml`).

### Convención de Release

| Elemento | Contrato |
|----------|----------|
| Tag | `vMAJOR.MINOR.PATCH` (ej. `v1.2.0`) |
| `pubspec.yaml` | `version: MAJOR.MINOR.PATCH+BUILD` **debe coincidir** con el tag (sin `v`) |
| Asset Android | `android-regispro-vMAJOR.MINOR.PATCH.apk` |
| Asset Windows | `windows-regispro-vMAJOR.MINOR.PATCH.zip` (contenido de `build/windows/x64/runner/Release/`) |
| Force update | Incluir la línea `[FORCE_UPDATE]` en el body de la Release |

Si el body contiene `[FORCE_UPDATE]`, el diálogo no se puede cerrar ni
posponer hasta instalar.

### Cómo se aplica la actualización

| | Android | Windows |
|---|---|---|
| Asset | `.apk` | `.zip` |
| Mecanismo | Instalador del sistema (`OpenFilex` + permiso *instalar apps desconocidas*) | Script PowerShell *out-of-process* que reemplaza la carpeta de instalación |
| Reinicio | Manual (lo hace el instalador) | Automático (el script relanza Nexus) |

En **Windows** el flujo es: descarga → verificación SHA-256 → la app lanza un
actualizador desacoplado y se cierra (`exit(0)`) → el actualizador espera a que
el proceso libere el `.exe`, extrae el ZIP sobre la carpeta de instalación y
vuelve a abrir Nexus.

Garantías del actualizador (`lib/features/updates/services/windows_installer.dart`):

- **Pre-flight de escritura**: si la carpeta de instalación no es escribible, la
  app **no se cierra** y muestra el error. Nexus debe vivir en una carpeta de
  usuario (ej. `%LOCALAPPDATA%\RegisPro`); en `C:\Program Files` haría falta
  elevación y la OTA no se aplicará.
- **Proceso independiente + handshake**: Explorer lanza PowerShell fuera del
  ciclo de vida de Flutter y Nexus espera una señal real de inicio antes de
  cerrarse. Si el updater no arranca en 10 segundos, la app permanece abierta.
- **Validación del paquete**: si el ZIP no contiene el `.exe`, se aborta sin
  tocar la instalación.
- **Backup + rollback**: se respalda la instalación antes de sobrescribir y se
  restaura si la copia falla.
- **Reintentos**: la copia reintenta ante archivos bloqueados (antivirus,
  indexador) antes de darse por vencida.
- **Nunca deja al usuario sin app**: pase lo que pase, se relanza Nexus.
- **Traza**: cada intento queda registrado en `%TEMP%\nexus-update.log`.

Prueba de integración local (no modifica la instalación real):

```powershell
.\scripts\test-windows-ota.ps1
```

Los archivos ajenos al paquete (config local del usuario) se conservan: la
actualización copia encima, no borra la carpeta.

### Instalador bootstrap (Windows — primera instalación)

En lugar de un `.exe` grande por versión, Nexus usa un **instalador ligero**
que consulta GitHub Releases en runtime e instala siempre la última versión.

| Archivo | Uso |
|---------|-----|
| `scripts/installer_script.iss` | Instalador nativo Inno Setup → `NexusSetup.exe` (UI de Windows, sin PowerShell) |
| `scripts/install-nexus.ps1` | Alternativa CLI (API → descarga ZIP → extrae) |
| `scripts/install-nexus.bat` | Launcher de doble clic del script CLI |
| `scripts/uninstall-regispro.ps1` | Desinstalación (binarios, datos en `%APPDATA%`, accesos directos) |

**Instalación recomendada:** distribuir `NexusSetup.exe` (wizard de Windows).

**Alternativa CLI** (desde el repo clonado):

```powershell
.\scripts\install-nexus.bat
# o con acceso directo en el escritorio:
.\scripts\install-nexus.ps1 -DesktopShortcut
```

**Compilar `NexusSetup.exe`** (requiere [Inno Setup 6.1+](https://jrsoftware.org/isinfo.php)):

```powershell
.\scripts\build-installer.ps1
# Salida: build\windows\installer\NexusSetup.exe
```

Flujo del bootstrap (`NexusSetup.exe`):

1. Wizard Inno consulta `GET /repos/{owner}/{repo}/releases/latest`
2. Descarga `windows-regispro-vX.Y.Z.zip` con barra de progreso nativa
3. Verifica SHA-256 si GitHub expone `digest` en el asset
4. Extrae en `%LOCALAPPDATA%\RegisPro` (compatible con OTA posterior)
5. Crea accesos en el menú Inicio (y escritorio si se pide)
6. Registra desinstalación en *Agregar o quitar programas*

Traza de instalación: `%TEMP%\nexus-install.log`.

El bootstrap **no se recompila por release**; solo hay que volver a publicarlo
si cambia la lógica de instalación. Los binarios vienen siempre del ZIP en GitHub.

### Firma release (obligatoria para upgrades reales)

1. Genera un keystore (una sola vez) y guárdalo fuera de git.
2. Copia `android/key.properties.example` → `android/key.properties` y completa.

Sin keystore, Gradle firma con debug (útil en local; **no** para distribución).

### Publicar una versión

Los paquetes **no** los genera GitHub Actions: se construyen en local y se
suben a mano a la Release.

1. Sube `pubspec.yaml` (`version: X.Y.Z+N`) y haz merge a `main`.
2. Crea y pushea el tag: `git tag vX.Y.Z && git push origin vX.Y.Z`.
3. Construye los paquetes:
   - Android: `flutter build apk --release` → copia a `android-regispro-vX.Y.Z.apk`
   - Windows: `flutter build windows --release` → ZIP de `build/windows/x64/runner/Release/` como `windows-regispro-vX.Y.Z.zip`
4. Crea/edita la GitHub Release del tag y sube esos archivos.
5. Hasta que no queden clientes 1.5.x / 1.4.x, sube también copias con el
   nombre legacy: `android-nexus-vX.Y.Z.apk` y `windows-nexus-vX.Y.Z.zip`
   (mismo archivo, otro nombre). Esas apps solo buscan el prefijo `nexus-`.
6. (Opcional) Edita las notas del Release y agrega `[FORCE_UPDATE]` si aplica.

### Variables `.env`

Ver `.env.example`. Para Supabase: `SUPABASE_URL`, la publishable
`nexus_app` en `SUPABASE_PUBLISHABLE_KEY` o `SUPABASE_ANON_KEY`, y
`eventos_web` en `SUPABASE_PUBLISHABLE_KEY_FORM` (si falta, se reusa la
de la app). OTA: `GITHUB_OWNER`, `GITHUB_REPO`, `UPDATE_CHANNEL`.
