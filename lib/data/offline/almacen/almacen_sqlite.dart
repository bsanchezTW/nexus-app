import 'dart:developer' as developer;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/offline_policy.dart';
import 'almacen_copia_local.dart';
import 'copia_local_db.dart';

/// Copia local en SQLite (drift), para las plataformas con modo sin conexión.
///
/// Al abrir carga todo en el espejo de memoria de [AlmacenCopiaLocal]; desde
/// ahí cada cambio se escribe en una transacción, fila por fila. Las
/// escrituras se encadenan para llegar al disco en el mismo orden en que se
/// hicieron, y la base corre en un isolate aparte: la interfaz no espera al
/// disco.
class AlmacenSqlite extends AlmacenCopiaLocal {
  AlmacenSqlite._(this._db) : super.enMemoria();

  final CopiaLocalDb _db;
  Future<void> _cola = Future<void>.value();

  /// Abre la base en la carpeta de datos de la app y carga su contenido.
  static Future<AlmacenSqlite> abrir() async {
    final db = CopiaLocalDb(
      driftDatabase(
        name: 'copia_local',
        native: const DriftNativeOptions(
          databaseDirectory: getApplicationSupportDirectory,
        ),
      ),
    );
    return deBase(db);
  }

  /// Carga una base ya abierta. Para los tests, que usan una en memoria.
  static Future<AlmacenSqlite> deBase(CopiaLocalDb db) async {
    final almacen = AlmacenSqlite._(db);
    await almacen._cargar();
    return almacen;
  }

  Future<void> _cargar() async {
    final entradas = await _db.select(_db.entradasCopia).get();
    final filas =
        await (_db.select(_db.filasCopia)..orderBy([
              (f) => OrderingTerm.asc(f.owner),
              (f) => OrderingTerm.asc(f.tabla),
              (f) => OrderingTerm.asc(f.evento),
              (f) => OrderingTerm.asc(f.orden),
            ]))
            .get();

    String clave(String owner, String tabla, String evento) =>
        '$owner\u0000$tabla\u0000$evento';
    final porEntrada = <String, List<FilaCopiaLocal>>{};
    for (final fila in filas) {
      porEntrada
          .putIfAbsent(clave(fila.owner, fila.tabla, fila.evento), () => [])
          .add(
            FilaCopiaLocal(
              id: fila.filaId,
              orden: fila.orden,
              datos: fila.datos,
            ),
          );
    }
    for (final e in entradas) {
      cargarEntrada(
        e.owner,
        e.tabla,
        e.evento,
        porEntrada[clave(e.owner, e.tabla, e.evento)] ?? const [],
        actualizadaEn: e.actualizadaEn,
      );
    }
  }

  @override
  Future<void> persistir(CambioCopiaLocal cambio) {
    final escritura = _cola.then((_) => _escribir(cambio));
    // Un fallo no corta la cadena: la siguiente escritura igual tiene que
    // llegar. Pero sí le llega a quien esperaba esta: la cola de pendientes no
    // puede decir "guardado" si el ítem no quedó en disco.
    _cola = escritura.then(
      (_) {},
      onError: (Object e) {
        developer.log(
          'No se pudo guardar ${cambio.tabla}/${cambio.evento}: $e',
          name: 'AlmacenSqlite',
        );
      },
    );
    return escritura;
  }

  @override
  Future<void> esperarEscrituras() => _cola;

  Future<void> _escribir(CambioCopiaLocal c) {
    return _db.transaction(() async {
      final deLaEntrada =
          _db.filasCopia.owner.equals(c.owner) &
          _db.filasCopia.tabla.equals(c.tabla) &
          _db.filasCopia.evento.equals(c.evento);

      if (c.borrarEntrada) {
        await (_db.delete(_db.filasCopia)..where((_) => deLaEntrada)).go();
        await (_db.delete(_db.entradasCopia)..where(
              (e) =>
                  e.owner.equals(c.owner) &
                  e.tabla.equals(c.tabla) &
                  e.evento.equals(c.evento),
            ))
            .go();
        return;
      }

      await _db
          .into(_db.entradasCopia)
          .insertOnConflictUpdate(
            // Sin hora nueva la columna se omite: el UPSERT no pisa la que
            // ya había.
            EntradasCopiaCompanion.insert(
              owner: c.owner,
              tabla: c.tabla,
              evento: c.evento,
              actualizadaEn: Value.absentIfNull(c.actualizadaEn),
            ),
          );
      if (c.idsBorrados.isNotEmpty) {
        await (_db.delete(
          _db.filasCopia,
        )..where((f) => deLaEntrada & f.filaId.isIn(c.idsBorrados))).go();
      }
      if (c.filasNuevas.isNotEmpty) {
        await _db.batch((b) {
          b.insertAllOnConflictUpdate(_db.filasCopia, [
            for (final fila in c.filasNuevas)
              FilasCopiaCompanion.insert(
                owner: c.owner,
                tabla: c.tabla,
                evento: c.evento,
                filaId: fila.id,
                orden: fila.orden,
                datos: fila.datos,
              ),
          ]);
        });
      }
    });
  }
}

/// El almacén que corresponde a esta plataforma: SQLite donde hay modo sin
/// conexión; en memoria en la web y Linux, que siempre trabajan en línea.
Future<AlmacenCopiaLocal> abrirAlmacenCopiaLocal() async {
  if (!supportsOfflineCacheAqui) return AlmacenCopiaLocal.enMemoria();
  return AlmacenSqlite.abrir();
}
