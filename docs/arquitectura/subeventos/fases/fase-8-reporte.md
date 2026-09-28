# Fase 8 — reporte

Trabajo en `main`, sin commit.

## Qué hay

- `pubspec.yaml` quedó en `1.8.0+34`.
- El README apunta a la tabla de funciones, `docs/ENVIO_QR.md`, `docs/api-publica.md` y el despliegue.
- `docs/api-publica.md` copia el contrato de las tres RPC públicas.
- `docs/arquitectura/subeventos/despliegue.md` deja el orden de salida y el recorrido manual.

## Revisión

- La actualización forzada no está publicada. Hace falta el release `v1.8.0` con `[FORCE_UPDATE]` en el cuerpo.
- El recorrido manual de la fase 8 no se hizo: no hay staging con sesión ni capturas de correo. La lista está en el documento de despliegue, marcada como pendiente.
- `docs/api-publica.md` sale de la especificación. No se contrastó con un `curl` a la base.

## Cómo se probó

`flutter analyze` y `flutter test` (581 pruebas).
