import 'package:drift/drift.dart';

part 'copia_local_db.g.dart';

/// Entradas guardadas: qué `(perfil, tabla, evento)` tiene copia, aunque esté
/// vacía. Sin esto una lista sin filas no se distingue de una nunca bajada.
@DataClassName('EntradaCopia')
class EntradasCopia extends Table {
  TextColumn get owner => text()();
  TextColumn get tabla => text()();
  TextColumn get evento => text()();

  /// Última vez que el servidor confirmó esta entrada, cambiara o no. Es lo
  /// que dice "actualizada hace X" cuando la app muestra la copia. Nula en lo
  /// que vino de SharedPreferences, que no guardaba esa hora.
  DateTimeColumn get actualizadaEn => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {owner, tabla, evento};
}

/// Filas de cada entrada. La clave primaria empieza por la entrada, así que
/// leer o borrar una entrada completa usa ese índice.
@DataClassName('FilaCopia')
class FilasCopia extends Table {
  TextColumn get owner => text()();
  TextColumn get tabla => text()();
  TextColumn get evento => text()();
  TextColumn get filaId => text()();
  IntColumn get orden => integer()();

  /// La fila en JSON, tal como la entrega `toCacheMap`.
  TextColumn get datos => text()();

  @override
  Set<Column<Object>> get primaryKey => {owner, tabla, evento, filaId};
}

/// Base SQLite de la copia local (ver `AlmacenSqlite`).
@DriftDatabase(tables: [EntradasCopia, FilasCopia])
class CopiaLocalDb extends _$CopiaLocalDb {
  CopiaLocalDb(super.executor);

  /// 1: entradas y filas. 2: hora de confirmación de cada entrada.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, desde, hasta) async {
      if (desde < 2) {
        await m.addColumn(entradasCopia, entradasCopia.actualizadaEn);
      }
    },
  );
}
