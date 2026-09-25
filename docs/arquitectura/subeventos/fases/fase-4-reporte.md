# Fase 4 — reporte

Trabajo en `main`.

## Qué hay

- El formulario de evento guarda cupo, descripción, horario, cierre, mapa, banner y slug, con el aviso de que cambiar el slug rompe los links.
- Pantallas de talleres: lista por día, alta, edición y borrado con el conteo de inscritos.
- La ocupación se lee online. La lista de talleres queda en la caché del snapshot.
- El acceso con QR es el único que muestra "Escanear QR".

## Cómo se probó

`flutter analyze` y `flutter test` después de estos cambios. El alta real de un taller contra la base no se recorrió en el navegador.
