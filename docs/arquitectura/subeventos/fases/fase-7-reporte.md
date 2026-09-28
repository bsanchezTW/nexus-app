# Fase 7 — reporte

Trabajo en `main`, sin commit.

## Qué hay

- Los KPI de cada taller salen de las listas en caché: inscritos, asistentes, cupo, porcentaje de asistencia y cuántos van en sobrecupo. La pantalla los muestra en tarjetas.
- El Excel de registrados agrega "Acreditado en", "Sobrecupo" y una columna por taller (`Inscrito` o `Asistió`). Hay una hoja "Talleres" con el resumen de las personas exportadas. No se escribe `codigo_qr` ni ningún UUID.

## Revisión

- El archivo generado no contiene el QR ni los UUID de prueba. Los conteos recorren las inscripciones una vez y después consultan un mapa.
- Se comprobó abriendo el `.xlsx` con el lector del propio paquete, no en Excel de escritorio ni en Google Sheets.
- La pantalla de KPI no se recorrió con sesión iniciada.

## Cómo se probó

`flutter analyze` y `flutter test` (581 pruebas).
