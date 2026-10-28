// Carpeta base de los archivos que la app necesita sin red, para las
// plataformas con `dart:io`. Solo la importan las implementaciones `_io`.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Donde viven las fotos pendientes y las portadas offline.
///
/// En el teléfono, los Documentos de la app y no la caché: el sistema puede
/// purgar la caché justo antes de la feria, cuando ya no hay red para volver a
/// bajar nada. En escritorio "Documentos" es la carpeta del usuario, compartida
/// con todo lo demás; ahí se usa la carpeta de datos de la aplicación (AppData
/// en Windows, Application Support en macOS).
///
/// Las fotos pendientes se guardan con su ruta absoluta en la cola, así que
/// las que ya estuvieran en Documentos se siguen encontrando.
Future<Directory> directorioPersistente() {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    return getApplicationSupportDirectory();
  }
  return getApplicationDocumentsDirectory();
}
