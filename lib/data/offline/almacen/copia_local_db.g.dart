// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'copia_local_db.dart';

// ignore_for_file: type=lint
class $EntradasCopiaTable extends EntradasCopia
    with TableInfo<$EntradasCopiaTable, EntradaCopia> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EntradasCopiaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerMeta = const VerificationMeta('owner');
  @override
  late final GeneratedColumn<String> owner = GeneratedColumn<String>(
    'owner',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tablaMeta = const VerificationMeta('tabla');
  @override
  late final GeneratedColumn<String> tabla = GeneratedColumn<String>(
    'tabla',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventoMeta = const VerificationMeta('evento');
  @override
  late final GeneratedColumn<String> evento = GeneratedColumn<String>(
    'evento',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actualizadaEnMeta = const VerificationMeta(
    'actualizadaEn',
  );
  @override
  late final GeneratedColumn<DateTime> actualizadaEn =
      GeneratedColumn<DateTime>(
        'actualizada_en',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [owner, tabla, evento, actualizadaEn];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'entradas_copia';
  @override
  VerificationContext validateIntegrity(
    Insertable<EntradaCopia> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner')) {
      context.handle(
        _ownerMeta,
        owner.isAcceptableOrUnknown(data['owner']!, _ownerMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerMeta);
    }
    if (data.containsKey('tabla')) {
      context.handle(
        _tablaMeta,
        tabla.isAcceptableOrUnknown(data['tabla']!, _tablaMeta),
      );
    } else if (isInserting) {
      context.missing(_tablaMeta);
    }
    if (data.containsKey('evento')) {
      context.handle(
        _eventoMeta,
        evento.isAcceptableOrUnknown(data['evento']!, _eventoMeta),
      );
    } else if (isInserting) {
      context.missing(_eventoMeta);
    }
    if (data.containsKey('actualizada_en')) {
      context.handle(
        _actualizadaEnMeta,
        actualizadaEn.isAcceptableOrUnknown(
          data['actualizada_en']!,
          _actualizadaEnMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {owner, tabla, evento};
  @override
  EntradaCopia map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EntradaCopia(
      owner: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner'],
      )!,
      tabla: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tabla'],
      )!,
      evento: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}evento'],
      )!,
      actualizadaEn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}actualizada_en'],
      ),
    );
  }

  @override
  $EntradasCopiaTable createAlias(String alias) {
    return $EntradasCopiaTable(attachedDatabase, alias);
  }
}

class EntradaCopia extends DataClass implements Insertable<EntradaCopia> {
  final String owner;
  final String tabla;
  final String evento;

  /// Última vez que el servidor confirmó esta entrada, cambiara o no. Es lo
  /// que dice "actualizada hace X" cuando la app muestra la copia. Nula en lo
  /// que vino de SharedPreferences, que no guardaba esa hora.
  final DateTime? actualizadaEn;
  const EntradaCopia({
    required this.owner,
    required this.tabla,
    required this.evento,
    this.actualizadaEn,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner'] = Variable<String>(owner);
    map['tabla'] = Variable<String>(tabla);
    map['evento'] = Variable<String>(evento);
    if (!nullToAbsent || actualizadaEn != null) {
      map['actualizada_en'] = Variable<DateTime>(actualizadaEn);
    }
    return map;
  }

  EntradasCopiaCompanion toCompanion(bool nullToAbsent) {
    return EntradasCopiaCompanion(
      owner: Value(owner),
      tabla: Value(tabla),
      evento: Value(evento),
      actualizadaEn: actualizadaEn == null && nullToAbsent
          ? const Value.absent()
          : Value(actualizadaEn),
    );
  }

  factory EntradaCopia.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EntradaCopia(
      owner: serializer.fromJson<String>(json['owner']),
      tabla: serializer.fromJson<String>(json['tabla']),
      evento: serializer.fromJson<String>(json['evento']),
      actualizadaEn: serializer.fromJson<DateTime?>(json['actualizadaEn']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'owner': serializer.toJson<String>(owner),
      'tabla': serializer.toJson<String>(tabla),
      'evento': serializer.toJson<String>(evento),
      'actualizadaEn': serializer.toJson<DateTime?>(actualizadaEn),
    };
  }

  EntradaCopia copyWith({
    String? owner,
    String? tabla,
    String? evento,
    Value<DateTime?> actualizadaEn = const Value.absent(),
  }) => EntradaCopia(
    owner: owner ?? this.owner,
    tabla: tabla ?? this.tabla,
    evento: evento ?? this.evento,
    actualizadaEn: actualizadaEn.present
        ? actualizadaEn.value
        : this.actualizadaEn,
  );
  EntradaCopia copyWithCompanion(EntradasCopiaCompanion data) {
    return EntradaCopia(
      owner: data.owner.present ? data.owner.value : this.owner,
      tabla: data.tabla.present ? data.tabla.value : this.tabla,
      evento: data.evento.present ? data.evento.value : this.evento,
      actualizadaEn: data.actualizadaEn.present
          ? data.actualizadaEn.value
          : this.actualizadaEn,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EntradaCopia(')
          ..write('owner: $owner, ')
          ..write('tabla: $tabla, ')
          ..write('evento: $evento, ')
          ..write('actualizadaEn: $actualizadaEn')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(owner, tabla, evento, actualizadaEn);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EntradaCopia &&
          other.owner == this.owner &&
          other.tabla == this.tabla &&
          other.evento == this.evento &&
          other.actualizadaEn == this.actualizadaEn);
}

class EntradasCopiaCompanion extends UpdateCompanion<EntradaCopia> {
  final Value<String> owner;
  final Value<String> tabla;
  final Value<String> evento;
  final Value<DateTime?> actualizadaEn;
  final Value<int> rowid;
  const EntradasCopiaCompanion({
    this.owner = const Value.absent(),
    this.tabla = const Value.absent(),
    this.evento = const Value.absent(),
    this.actualizadaEn = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EntradasCopiaCompanion.insert({
    required String owner,
    required String tabla,
    required String evento,
    this.actualizadaEn = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : owner = Value(owner),
       tabla = Value(tabla),
       evento = Value(evento);
  static Insertable<EntradaCopia> custom({
    Expression<String>? owner,
    Expression<String>? tabla,
    Expression<String>? evento,
    Expression<DateTime>? actualizadaEn,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (owner != null) 'owner': owner,
      if (tabla != null) 'tabla': tabla,
      if (evento != null) 'evento': evento,
      if (actualizadaEn != null) 'actualizada_en': actualizadaEn,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EntradasCopiaCompanion copyWith({
    Value<String>? owner,
    Value<String>? tabla,
    Value<String>? evento,
    Value<DateTime?>? actualizadaEn,
    Value<int>? rowid,
  }) {
    return EntradasCopiaCompanion(
      owner: owner ?? this.owner,
      tabla: tabla ?? this.tabla,
      evento: evento ?? this.evento,
      actualizadaEn: actualizadaEn ?? this.actualizadaEn,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (owner.present) {
      map['owner'] = Variable<String>(owner.value);
    }
    if (tabla.present) {
      map['tabla'] = Variable<String>(tabla.value);
    }
    if (evento.present) {
      map['evento'] = Variable<String>(evento.value);
    }
    if (actualizadaEn.present) {
      map['actualizada_en'] = Variable<DateTime>(actualizadaEn.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EntradasCopiaCompanion(')
          ..write('owner: $owner, ')
          ..write('tabla: $tabla, ')
          ..write('evento: $evento, ')
          ..write('actualizadaEn: $actualizadaEn, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FilasCopiaTable extends FilasCopia
    with TableInfo<$FilasCopiaTable, FilaCopia> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FilasCopiaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _ownerMeta = const VerificationMeta('owner');
  @override
  late final GeneratedColumn<String> owner = GeneratedColumn<String>(
    'owner',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tablaMeta = const VerificationMeta('tabla');
  @override
  late final GeneratedColumn<String> tabla = GeneratedColumn<String>(
    'tabla',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventoMeta = const VerificationMeta('evento');
  @override
  late final GeneratedColumn<String> evento = GeneratedColumn<String>(
    'evento',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filaIdMeta = const VerificationMeta('filaId');
  @override
  late final GeneratedColumn<String> filaId = GeneratedColumn<String>(
    'fila_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ordenMeta = const VerificationMeta('orden');
  @override
  late final GeneratedColumn<int> orden = GeneratedColumn<int>(
    'orden',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _datosMeta = const VerificationMeta('datos');
  @override
  late final GeneratedColumn<String> datos = GeneratedColumn<String>(
    'datos',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    owner,
    tabla,
    evento,
    filaId,
    orden,
    datos,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'filas_copia';
  @override
  VerificationContext validateIntegrity(
    Insertable<FilaCopia> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('owner')) {
      context.handle(
        _ownerMeta,
        owner.isAcceptableOrUnknown(data['owner']!, _ownerMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerMeta);
    }
    if (data.containsKey('tabla')) {
      context.handle(
        _tablaMeta,
        tabla.isAcceptableOrUnknown(data['tabla']!, _tablaMeta),
      );
    } else if (isInserting) {
      context.missing(_tablaMeta);
    }
    if (data.containsKey('evento')) {
      context.handle(
        _eventoMeta,
        evento.isAcceptableOrUnknown(data['evento']!, _eventoMeta),
      );
    } else if (isInserting) {
      context.missing(_eventoMeta);
    }
    if (data.containsKey('fila_id')) {
      context.handle(
        _filaIdMeta,
        filaId.isAcceptableOrUnknown(data['fila_id']!, _filaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_filaIdMeta);
    }
    if (data.containsKey('orden')) {
      context.handle(
        _ordenMeta,
        orden.isAcceptableOrUnknown(data['orden']!, _ordenMeta),
      );
    } else if (isInserting) {
      context.missing(_ordenMeta);
    }
    if (data.containsKey('datos')) {
      context.handle(
        _datosMeta,
        datos.isAcceptableOrUnknown(data['datos']!, _datosMeta),
      );
    } else if (isInserting) {
      context.missing(_datosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {owner, tabla, evento, filaId};
  @override
  FilaCopia map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FilaCopia(
      owner: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner'],
      )!,
      tabla: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tabla'],
      )!,
      evento: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}evento'],
      )!,
      filaId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fila_id'],
      )!,
      orden: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}orden'],
      )!,
      datos: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}datos'],
      )!,
    );
  }

  @override
  $FilasCopiaTable createAlias(String alias) {
    return $FilasCopiaTable(attachedDatabase, alias);
  }
}

class FilaCopia extends DataClass implements Insertable<FilaCopia> {
  final String owner;
  final String tabla;
  final String evento;
  final String filaId;
  final int orden;

  /// La fila en JSON, tal como la entrega `toCacheMap`.
  final String datos;
  const FilaCopia({
    required this.owner,
    required this.tabla,
    required this.evento,
    required this.filaId,
    required this.orden,
    required this.datos,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['owner'] = Variable<String>(owner);
    map['tabla'] = Variable<String>(tabla);
    map['evento'] = Variable<String>(evento);
    map['fila_id'] = Variable<String>(filaId);
    map['orden'] = Variable<int>(orden);
    map['datos'] = Variable<String>(datos);
    return map;
  }

  FilasCopiaCompanion toCompanion(bool nullToAbsent) {
    return FilasCopiaCompanion(
      owner: Value(owner),
      tabla: Value(tabla),
      evento: Value(evento),
      filaId: Value(filaId),
      orden: Value(orden),
      datos: Value(datos),
    );
  }

  factory FilaCopia.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FilaCopia(
      owner: serializer.fromJson<String>(json['owner']),
      tabla: serializer.fromJson<String>(json['tabla']),
      evento: serializer.fromJson<String>(json['evento']),
      filaId: serializer.fromJson<String>(json['filaId']),
      orden: serializer.fromJson<int>(json['orden']),
      datos: serializer.fromJson<String>(json['datos']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'owner': serializer.toJson<String>(owner),
      'tabla': serializer.toJson<String>(tabla),
      'evento': serializer.toJson<String>(evento),
      'filaId': serializer.toJson<String>(filaId),
      'orden': serializer.toJson<int>(orden),
      'datos': serializer.toJson<String>(datos),
    };
  }

  FilaCopia copyWith({
    String? owner,
    String? tabla,
    String? evento,
    String? filaId,
    int? orden,
    String? datos,
  }) => FilaCopia(
    owner: owner ?? this.owner,
    tabla: tabla ?? this.tabla,
    evento: evento ?? this.evento,
    filaId: filaId ?? this.filaId,
    orden: orden ?? this.orden,
    datos: datos ?? this.datos,
  );
  FilaCopia copyWithCompanion(FilasCopiaCompanion data) {
    return FilaCopia(
      owner: data.owner.present ? data.owner.value : this.owner,
      tabla: data.tabla.present ? data.tabla.value : this.tabla,
      evento: data.evento.present ? data.evento.value : this.evento,
      filaId: data.filaId.present ? data.filaId.value : this.filaId,
      orden: data.orden.present ? data.orden.value : this.orden,
      datos: data.datos.present ? data.datos.value : this.datos,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FilaCopia(')
          ..write('owner: $owner, ')
          ..write('tabla: $tabla, ')
          ..write('evento: $evento, ')
          ..write('filaId: $filaId, ')
          ..write('orden: $orden, ')
          ..write('datos: $datos')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(owner, tabla, evento, filaId, orden, datos);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FilaCopia &&
          other.owner == this.owner &&
          other.tabla == this.tabla &&
          other.evento == this.evento &&
          other.filaId == this.filaId &&
          other.orden == this.orden &&
          other.datos == this.datos);
}

class FilasCopiaCompanion extends UpdateCompanion<FilaCopia> {
  final Value<String> owner;
  final Value<String> tabla;
  final Value<String> evento;
  final Value<String> filaId;
  final Value<int> orden;
  final Value<String> datos;
  final Value<int> rowid;
  const FilasCopiaCompanion({
    this.owner = const Value.absent(),
    this.tabla = const Value.absent(),
    this.evento = const Value.absent(),
    this.filaId = const Value.absent(),
    this.orden = const Value.absent(),
    this.datos = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FilasCopiaCompanion.insert({
    required String owner,
    required String tabla,
    required String evento,
    required String filaId,
    required int orden,
    required String datos,
    this.rowid = const Value.absent(),
  }) : owner = Value(owner),
       tabla = Value(tabla),
       evento = Value(evento),
       filaId = Value(filaId),
       orden = Value(orden),
       datos = Value(datos);
  static Insertable<FilaCopia> custom({
    Expression<String>? owner,
    Expression<String>? tabla,
    Expression<String>? evento,
    Expression<String>? filaId,
    Expression<int>? orden,
    Expression<String>? datos,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (owner != null) 'owner': owner,
      if (tabla != null) 'tabla': tabla,
      if (evento != null) 'evento': evento,
      if (filaId != null) 'fila_id': filaId,
      if (orden != null) 'orden': orden,
      if (datos != null) 'datos': datos,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FilasCopiaCompanion copyWith({
    Value<String>? owner,
    Value<String>? tabla,
    Value<String>? evento,
    Value<String>? filaId,
    Value<int>? orden,
    Value<String>? datos,
    Value<int>? rowid,
  }) {
    return FilasCopiaCompanion(
      owner: owner ?? this.owner,
      tabla: tabla ?? this.tabla,
      evento: evento ?? this.evento,
      filaId: filaId ?? this.filaId,
      orden: orden ?? this.orden,
      datos: datos ?? this.datos,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (owner.present) {
      map['owner'] = Variable<String>(owner.value);
    }
    if (tabla.present) {
      map['tabla'] = Variable<String>(tabla.value);
    }
    if (evento.present) {
      map['evento'] = Variable<String>(evento.value);
    }
    if (filaId.present) {
      map['fila_id'] = Variable<String>(filaId.value);
    }
    if (orden.present) {
      map['orden'] = Variable<int>(orden.value);
    }
    if (datos.present) {
      map['datos'] = Variable<String>(datos.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FilasCopiaCompanion(')
          ..write('owner: $owner, ')
          ..write('tabla: $tabla, ')
          ..write('evento: $evento, ')
          ..write('filaId: $filaId, ')
          ..write('orden: $orden, ')
          ..write('datos: $datos, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CopiaLocalDb extends GeneratedDatabase {
  _$CopiaLocalDb(QueryExecutor e) : super(e);
  $CopiaLocalDbManager get managers => $CopiaLocalDbManager(this);
  late final $EntradasCopiaTable entradasCopia = $EntradasCopiaTable(this);
  late final $FilasCopiaTable filasCopia = $FilasCopiaTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    entradasCopia,
    filasCopia,
  ];
}

typedef $$EntradasCopiaTableCreateCompanionBuilder =
    EntradasCopiaCompanion Function({
      required String owner,
      required String tabla,
      required String evento,
      Value<DateTime?> actualizadaEn,
      Value<int> rowid,
    });
typedef $$EntradasCopiaTableUpdateCompanionBuilder =
    EntradasCopiaCompanion Function({
      Value<String> owner,
      Value<String> tabla,
      Value<String> evento,
      Value<DateTime?> actualizadaEn,
      Value<int> rowid,
    });

class $$EntradasCopiaTableFilterComposer
    extends Composer<_$CopiaLocalDb, $EntradasCopiaTable> {
  $$EntradasCopiaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tabla => $composableBuilder(
    column: $table.tabla,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get evento => $composableBuilder(
    column: $table.evento,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get actualizadaEn => $composableBuilder(
    column: $table.actualizadaEn,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EntradasCopiaTableOrderingComposer
    extends Composer<_$CopiaLocalDb, $EntradasCopiaTable> {
  $$EntradasCopiaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tabla => $composableBuilder(
    column: $table.tabla,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get evento => $composableBuilder(
    column: $table.evento,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get actualizadaEn => $composableBuilder(
    column: $table.actualizadaEn,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EntradasCopiaTableAnnotationComposer
    extends Composer<_$CopiaLocalDb, $EntradasCopiaTable> {
  $$EntradasCopiaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get owner =>
      $composableBuilder(column: $table.owner, builder: (column) => column);

  GeneratedColumn<String> get tabla =>
      $composableBuilder(column: $table.tabla, builder: (column) => column);

  GeneratedColumn<String> get evento =>
      $composableBuilder(column: $table.evento, builder: (column) => column);

  GeneratedColumn<DateTime> get actualizadaEn => $composableBuilder(
    column: $table.actualizadaEn,
    builder: (column) => column,
  );
}

class $$EntradasCopiaTableTableManager
    extends
        RootTableManager<
          _$CopiaLocalDb,
          $EntradasCopiaTable,
          EntradaCopia,
          $$EntradasCopiaTableFilterComposer,
          $$EntradasCopiaTableOrderingComposer,
          $$EntradasCopiaTableAnnotationComposer,
          $$EntradasCopiaTableCreateCompanionBuilder,
          $$EntradasCopiaTableUpdateCompanionBuilder,
          (
            EntradaCopia,
            BaseReferences<_$CopiaLocalDb, $EntradasCopiaTable, EntradaCopia>,
          ),
          EntradaCopia,
          PrefetchHooks Function()
        > {
  $$EntradasCopiaTableTableManager(_$CopiaLocalDb db, $EntradasCopiaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EntradasCopiaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EntradasCopiaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EntradasCopiaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> owner = const Value.absent(),
                Value<String> tabla = const Value.absent(),
                Value<String> evento = const Value.absent(),
                Value<DateTime?> actualizadaEn = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntradasCopiaCompanion(
                owner: owner,
                tabla: tabla,
                evento: evento,
                actualizadaEn: actualizadaEn,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String owner,
                required String tabla,
                required String evento,
                Value<DateTime?> actualizadaEn = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntradasCopiaCompanion.insert(
                owner: owner,
                tabla: tabla,
                evento: evento,
                actualizadaEn: actualizadaEn,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$EntradasCopiaTable, EntradaCopia>(table),
                  BaseReferences<
                    _$CopiaLocalDb,
                    $EntradasCopiaTable,
                    EntradaCopia
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EntradasCopiaTableProcessedTableManager =
    ProcessedTableManager<
      _$CopiaLocalDb,
      $EntradasCopiaTable,
      EntradaCopia,
      $$EntradasCopiaTableFilterComposer,
      $$EntradasCopiaTableOrderingComposer,
      $$EntradasCopiaTableAnnotationComposer,
      $$EntradasCopiaTableCreateCompanionBuilder,
      $$EntradasCopiaTableUpdateCompanionBuilder,
      (
        EntradaCopia,
        BaseReferences<_$CopiaLocalDb, $EntradasCopiaTable, EntradaCopia>,
      ),
      EntradaCopia,
      PrefetchHooks Function()
    >;
typedef $$FilasCopiaTableCreateCompanionBuilder =
    FilasCopiaCompanion Function({
      required String owner,
      required String tabla,
      required String evento,
      required String filaId,
      required int orden,
      required String datos,
      Value<int> rowid,
    });
typedef $$FilasCopiaTableUpdateCompanionBuilder =
    FilasCopiaCompanion Function({
      Value<String> owner,
      Value<String> tabla,
      Value<String> evento,
      Value<String> filaId,
      Value<int> orden,
      Value<String> datos,
      Value<int> rowid,
    });

class $$FilasCopiaTableFilterComposer
    extends Composer<_$CopiaLocalDb, $FilasCopiaTable> {
  $$FilasCopiaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tabla => $composableBuilder(
    column: $table.tabla,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get evento => $composableBuilder(
    column: $table.evento,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filaId => $composableBuilder(
    column: $table.filaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orden => $composableBuilder(
    column: $table.orden,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get datos => $composableBuilder(
    column: $table.datos,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FilasCopiaTableOrderingComposer
    extends Composer<_$CopiaLocalDb, $FilasCopiaTable> {
  $$FilasCopiaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get owner => $composableBuilder(
    column: $table.owner,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tabla => $composableBuilder(
    column: $table.tabla,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get evento => $composableBuilder(
    column: $table.evento,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filaId => $composableBuilder(
    column: $table.filaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orden => $composableBuilder(
    column: $table.orden,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get datos => $composableBuilder(
    column: $table.datos,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FilasCopiaTableAnnotationComposer
    extends Composer<_$CopiaLocalDb, $FilasCopiaTable> {
  $$FilasCopiaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get owner =>
      $composableBuilder(column: $table.owner, builder: (column) => column);

  GeneratedColumn<String> get tabla =>
      $composableBuilder(column: $table.tabla, builder: (column) => column);

  GeneratedColumn<String> get evento =>
      $composableBuilder(column: $table.evento, builder: (column) => column);

  GeneratedColumn<String> get filaId =>
      $composableBuilder(column: $table.filaId, builder: (column) => column);

  GeneratedColumn<int> get orden =>
      $composableBuilder(column: $table.orden, builder: (column) => column);

  GeneratedColumn<String> get datos =>
      $composableBuilder(column: $table.datos, builder: (column) => column);
}

class $$FilasCopiaTableTableManager
    extends
        RootTableManager<
          _$CopiaLocalDb,
          $FilasCopiaTable,
          FilaCopia,
          $$FilasCopiaTableFilterComposer,
          $$FilasCopiaTableOrderingComposer,
          $$FilasCopiaTableAnnotationComposer,
          $$FilasCopiaTableCreateCompanionBuilder,
          $$FilasCopiaTableUpdateCompanionBuilder,
          (
            FilaCopia,
            BaseReferences<_$CopiaLocalDb, $FilasCopiaTable, FilaCopia>,
          ),
          FilaCopia,
          PrefetchHooks Function()
        > {
  $$FilasCopiaTableTableManager(_$CopiaLocalDb db, $FilasCopiaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FilasCopiaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FilasCopiaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FilasCopiaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> owner = const Value.absent(),
                Value<String> tabla = const Value.absent(),
                Value<String> evento = const Value.absent(),
                Value<String> filaId = const Value.absent(),
                Value<int> orden = const Value.absent(),
                Value<String> datos = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FilasCopiaCompanion(
                owner: owner,
                tabla: tabla,
                evento: evento,
                filaId: filaId,
                orden: orden,
                datos: datos,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String owner,
                required String tabla,
                required String evento,
                required String filaId,
                required int orden,
                required String datos,
                Value<int> rowid = const Value.absent(),
              }) => FilasCopiaCompanion.insert(
                owner: owner,
                tabla: tabla,
                evento: evento,
                filaId: filaId,
                orden: orden,
                datos: datos,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FilasCopiaTable, FilaCopia>(table),
                  BaseReferences<_$CopiaLocalDb, $FilasCopiaTable, FilaCopia>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FilasCopiaTableProcessedTableManager =
    ProcessedTableManager<
      _$CopiaLocalDb,
      $FilasCopiaTable,
      FilaCopia,
      $$FilasCopiaTableFilterComposer,
      $$FilasCopiaTableOrderingComposer,
      $$FilasCopiaTableAnnotationComposer,
      $$FilasCopiaTableCreateCompanionBuilder,
      $$FilasCopiaTableUpdateCompanionBuilder,
      (FilaCopia, BaseReferences<_$CopiaLocalDb, $FilasCopiaTable, FilaCopia>),
      FilaCopia,
      PrefetchHooks Function()
    >;

class $CopiaLocalDbManager {
  final _$CopiaLocalDb _db;
  $CopiaLocalDbManager(this._db);
  $$EntradasCopiaTableTableManager get entradasCopia =>
      $$EntradasCopiaTableTableManager(_db, _db.entradasCopia);
  $$FilasCopiaTableTableManager get filasCopia =>
      $$FilasCopiaTableTableManager(_db, _db.filasCopia);
}
