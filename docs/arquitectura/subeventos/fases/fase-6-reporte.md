# Fase 6 — reporte

Trabajo en `main`, sin commit.

## Qué hay

- El escáner elige Entrada o un taller. La ruta acepta `?subevento=`.
- En un taller, el mismo QR marca asistencia, avisa si ya estaba, o solo avisa cuando no se puede inscribir (externo, o sin red y sin permiso de crear). Con permiso ofrece inscribir y marcar, y si choca el horario pregunta "Mover desde {taller}".
- La lista manual tiene el mismo selector. En un taller solo aparecen los inscritos y el botón marca asistencia. Sin red, esa marca queda en la cola.

## Cómo se probó

`flutter analyze`, `flutter test` y la decisión de escaneo en `decidir_accion_escaneo_test`. El escáner con cámara no se recorrió en el navegador.
