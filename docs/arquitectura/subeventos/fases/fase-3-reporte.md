# Fase 3 — reporte

Rama: `feat/subeventos-f3-nucleo-dart`.

## Archivos

- Modelos `Evento` y `Registrado` con slug, acceso QR, cupo y `codigo_qr`. Caché antigua: `tipo_registro = cliente` sigue leyéndose como acceso QR.
- Modelos sin UI: `Subevento`, `InscripcionSubevento`, `OcupacionEvento`, `ResultadoRegistro`, `EnvioQr`.
- `RegistradosRepository.registrar`, `importar`, `enviarQr(id)`, `obtenerPorCodigoQrEnEvento`, `regenerarCodigoQr`.
- Registro manual, importación Excel, hoja QR, enlaces públicos y escáner de entrada.
- Se eliminó `lib/features/registro_publico/` y las rutas `/registro-forms` y `/r/:eventoId`.

## Cómo se probó

`flutter analyze`: sin issues. `flutter test`: toda la suite en verde.

No se registró a una persona real ni se escaneó un QR en un dispositivo. El parser cubre código válido, minúsculas, UUID antiguo y texto inválido.

## Decisiones menores

- `eventoFinalizado` se conserva: lo usan el externo y el capturador, no solo el formulario público.
- `Env.supabasePublishableKeyForm` sigue en `env.dart` porque sus tests la cubren, aunque ya no hay cliente anónimo.

## TODO(arquitectura)

Ninguno nuevo. La caché lee `tipo_registro` solo como respaldo, tal como pide el §7.5.
