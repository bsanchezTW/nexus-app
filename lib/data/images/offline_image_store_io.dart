// Implementación de disco del almacén de imágenes offline, para las
// plataformas con `dart:io`.
//
// Se importa condicionalmente desde `offline_image_store.dart`; en web se usa
// `offline_image_store_stub.dart`, porque `dart:io` ni siquiera compila allí.

import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import '../offline/directorio_persistente_io.dart';

const _carpeta = 'imagenes_offline';

bool get almacenamientoDisponible => true;

Future<Directory> _directorio() async {
  final base = await directorioPersistente();
  final dir = Directory('${base.path}${Platform.pathSeparator}$_carpeta');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

Future<String> rutaDe(String nombre) async {
  final dir = await _directorio();
  return '${dir.path}${Platform.pathSeparator}$nombre';
}

Future<bool> existe(String ruta) => File(ruta).exists();

Future<void> escribir(String ruta, Uint8List bytes) async {
  await File(ruta).writeAsBytes(bytes, flush: true);
}

Future<void> borrarTodo() async {
  try {
    final dir = await _directorio();
    if (await dir.exists()) await dir.delete(recursive: true);
  } catch (e) {
    developer.log(
      'No se pudieron borrar las imágenes offline: $e',
      name: 'OfflineImageStore',
    );
  }
}

/// Borra del directorio todo lo que no esté en [nombres].
///
/// Es la contraparte del snapshot: sin esto, la portada de cada evento vivido
/// se quedaba en Documentos para siempre. Silenciosa a propósito —liberar
/// espacio nunca puede tumbar una sincronización— y devuelve cuántos archivos
/// se fueron solo para el log.
Future<int> borrarSalvo(Set<String> nombres) async {
  try {
    final dir = await _directorio();
    if (!await dir.exists()) return 0;
    var borrados = 0;
    await for (final entidad in dir.list(followLinks: false)) {
      if (entidad is! File) continue;
      final nombre = entidad.uri.pathSegments.last;
      if (nombres.contains(nombre)) continue;
      await entidad.delete();
      borrados++;
    }
    return borrados;
  } catch (e) {
    developer.log(
      'No se pudieron purgar las imágenes offline: $e',
      name: 'OfflineImageStore',
    );
    return 0;
  }
}
