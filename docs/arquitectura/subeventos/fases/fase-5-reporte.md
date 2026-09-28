# Fase 5 — reporte

Trabajo en `main`, sin commit.

## Qué hay

- Al registrar se eligen talleres. Si el correo ya existe, se ofrece abrir ese registro. Si un taller está lleno y el rol puede forzar, se pregunta antes de guardar en sobrecupo.
- La lista de registrados se filtra por taller. La ficha del QR muestra los talleres de esa persona y el botón "Editar talleres" (apagado sin conexión o si el registro solo está en la cola).
- Al editar, los talleres nuevos se inscriben y los que se quitan se dan de baja. Si uno falla, el resto y los datos personales quedan guardados.

## Cómo se probó

`flutter analyze` y `flutter test` de las pantallas tocadas. El alta real contra la base no se recorrió en el navegador: hace falta una sesión iniciada.
