import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync_queue_service.dart';

/// Una fila de la copia local tal como se guarda.
@immutable
class FilaCopiaLocal {
  const FilaCopiaLocal({
    required this.id,
    required this.orden,
    required this.datos,
  });

  /// El `id` de la fila o, si no tiene, su posición (`#3`).
  final String id;

  /// Posición en la lista: las listas se muestran en el orden del servidor.
  final int orden;

  /// La fila en JSON.
  final String datos;
}

/// Lo que cambió en una entrada y hay que llevar al disco.
@immutable
class CambioCopiaLocal {
  const CambioCopiaLocal({
    required this.owner,
    required this.tabla,
    required this.evento,
    this.borrarEntrada = false,
    this.filasNuevas = const [],
    this.idsBorrados = const [],
  });

  final String owner;
  final String tabla;
  final String evento;

  /// La entrada desaparece entera (acceso revocado, evento purgado).
  final bool borrarEntrada;

  /// Filas nuevas o que cambiaron de contenido o de orden.
  final List<FilaCopiaLocal> filasNuevas;

  /// Filas que ya no están.
  final List<String> idsBorrados;
}

class _Entrada {
  _Entrada(this.filas);

  /// Filas en orden, con su JSON.
  List<FilaCopiaLocal> filas;
}

/// Dónde vive la copia local que permite leer sin conexión.
///
/// Guarda **filas**, no listas enteras: cada entrada es `(perfil, tabla,
/// evento)` y contiene sus filas en orden. Al guardar una lista se compara
/// fila a fila con lo que ya había y solo se escribe lo que cambió, así que
/// acreditar a una persona en un evento de 5.000 toca una fila, no 5.000.
///
/// Las lecturas son síncronas, como siempre lo fueron: se sirven de un espejo
/// en memoria que se carga al arrancar. La escritura al disco —SQLite en las
/// plataformas con copia local, ver `AlmacenSqlite`— corre en segundo plano.
/// Antes la copia vivía en `SharedPreferences`, que en Windows reescribe el
/// archivo completo en el hilo de la interfaz en cada escritura: con una feria
/// grande eso congelaba la app 0,3 s por acreditación.
///
/// Esta clase sola es el almacén en memoria: lo usan la web (que no trabaja
/// sin conexión) y los tests.
class AlmacenCopiaLocal {
  AlmacenCopiaLocal.enMemoria();

  final Map<String, _Entrada> _entradas = {};

  static String _clave(String owner, String tabla, String evento) =>
      '$owner\u0000$tabla\u0000$evento';

  /// Filas de una entrada, en orden. `null` si nunca se guardó o está ilegible.
  List<Map<String, dynamic>>? leer(String owner, String tabla, String evento) {
    final entrada = _entradas[_clave(owner, tabla, evento)];
    if (entrada == null) return null;
    try {
      return [
        for (final fila in entrada.filas)
          Map<String, dynamic>.from(jsonDecode(fila.datos) as Map),
      ];
    } catch (e) {
      developer.log(
        'Copia local de $tabla/$evento ilegible, se descarta: $e',
        name: 'AlmacenCopiaLocal',
      );
      return null;
    }
  }

  /// Eventos con copia en [tabla].
  Set<String> eventos(String owner, String tabla) {
    final prefijo = '$owner\u0000$tabla\u0000';
    return {
      for (final clave in _entradas.keys)
        if (clave.startsWith(prefijo)) clave.substring(prefijo.length),
    };
  }

  /// Reemplaza la entrada por [filas] y responde si algo cambió.
  ///
  /// La memoria se actualiza antes de volver, así que una lectura inmediata ya
  /// ve lo nuevo; el disco recibe solo las filas que cambiaron.
  Future<bool> guardar(
    String owner,
    String tabla,
    String evento,
    List<Map<String, dynamic>> filas,
  ) async {
    final clave = _clave(owner, tabla, evento);
    final nuevas = filasDe(filas);
    final anterior = _entradas[clave];

    final anteriores = <String, FilaCopiaLocal>{
      for (final fila in anterior?.filas ?? const <FilaCopiaLocal>[])
        fila.id: fila,
    };
    final cambiadas = [
      for (final fila in nuevas)
        if (anteriores[fila.id]?.datos != fila.datos ||
            anteriores[fila.id]?.orden != fila.orden)
          fila,
    ];
    final idsNuevos = {for (final fila in nuevas) fila.id};
    final borradas = [
      for (final id in anteriores.keys)
        if (!idsNuevos.contains(id)) id,
    ];

    if (anterior != null && cambiadas.isEmpty && borradas.isEmpty) {
      return false;
    }
    _entradas[clave] = _Entrada(nuevas);
    await persistir(
      CambioCopiaLocal(
        owner: owner,
        tabla: tabla,
        evento: evento,
        filasNuevas: cambiadas,
        idsBorrados: borradas,
      ),
    );
    return true;
  }

  /// Quita la entrada entera.
  Future<void> borrar(String owner, String tabla, String evento) async {
    if (_entradas.remove(_clave(owner, tabla, evento)) == null) return;
    await persistir(
      CambioCopiaLocal(
        owner: owner,
        tabla: tabla,
        evento: evento,
        borrarEntrada: true,
      ),
    );
  }

  /// Espera a que todo lo guardado haya llegado al disco.
  Future<void> esperarEscrituras() async {}

  /// Lleva [cambio] al disco. En memoria no hay disco.
  @protected
  Future<void> persistir(CambioCopiaLocal cambio) async {}

  /// Carga una entrada leída del disco, sin volver a escribirla.
  @protected
  void cargarEntrada(
    String owner,
    String tabla,
    String evento,
    List<FilaCopiaLocal> filas,
  ) {
    _entradas[_clave(owner, tabla, evento)] = _Entrada(filas);
  }

  /// Convierte una lista en filas con id y orden.
  ///
  /// Usa el `id` de cada fila; las que no tienen —o lo repiten— se identifican
  /// por su posición.
  @visibleForTesting
  static List<FilaCopiaLocal> filasDe(List<Map<String, dynamic>> filas) {
    final vistos = <String>{};
    return [
      for (var i = 0; i < filas.length; i++)
        FilaCopiaLocal(
          id: switch (filas[i]['id']?.toString()) {
            final id? when vistos.add(id) => id,
            _ => '#$i',
          },
          orden: i,
          datos: jsonEncode(filas[i]),
        ),
    ];
  }
}

AlmacenCopiaLocal? _almacenInstalado;

/// Instala el almacén de disco. Lo llama el arranque de la app (ver
/// `appBootstrapProvider`) antes de que nadie lea la copia local.
void instalarAlmacenCopiaLocal(AlmacenCopiaLocal almacen) {
  _almacenInstalado = almacen;
}

/// Almacén de la copia local.
///
/// En la app es el que instaló el arranque. Sin él —tests— cada contenedor
/// recibe uno en memoria, vacío y propio. Observa [sharedPreferencesProvider]
/// a propósito: en la app ese provider exige el arranque terminado, así que el
/// almacén de disco ya está instalado cuando esto se lee.
final almacenCopiaLocalProvider = Provider<AlmacenCopiaLocal>((ref) {
  ref.watch(sharedPreferencesProvider);
  return _almacenInstalado ?? AlmacenCopiaLocal.enMemoria();
});
