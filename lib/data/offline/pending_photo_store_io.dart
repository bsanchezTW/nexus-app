// Implementación de disco del store de fotos pendientes, para las
// plataformas con `dart:io` (Android, iOS, Windows, macOS, Linux).
//
// Se importa condicionalmente desde `pending_photo_store.dart`; en web se usa
// `pending_photo_store_stub.dart`, porque `dart:io` ni siquiera compila allí.

import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import 'directorio_persistente_io.dart';

const _carpeta = 'leads_pendientes';
const _uuid = Uuid();

bool get almacenamientoDisponible => true;

Future<String> guardarFoto(Uint8List bytes) async {
  final base = await directorioPersistente();
  final dir = Directory('${base.path}${Platform.pathSeparator}$_carpeta');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final archivo = File('${dir.path}${Platform.pathSeparator}${_uuid.v4()}.jpg');
  await archivo.writeAsBytes(bytes, flush: true);
  return archivo.path;
}

Future<Uint8List?> leerFoto(String ruta) async {
  try {
    final archivo = File(ruta);
    if (!await archivo.exists()) return null;
    return await archivo.readAsBytes();
  } catch (e) {
    developer.log(
      'No se pudo leer la foto pendiente $ruta: $e',
      name: 'PendingPhotoStore',
    );
    return null;
  }
}

Future<void> borrarFoto(String ruta) async {
  try {
    final archivo = File(ruta);
    if (await archivo.exists()) await archivo.delete();
  } catch (e) {
    developer.log(
      'No se pudo borrar la foto pendiente $ruta: $e',
      name: 'PendingPhotoStore',
    );
  }
}
