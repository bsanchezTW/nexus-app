import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/offline/sync_queue_service.dart';
import '../models/home_featured_item.dart';

const _prefijoClave = 'home_orden_carrusel_v1';

/// Orden del carrusel del inicio elegido en **este** teléfono.
///
/// A diferencia de los fijados (que viven en la base y siguen al usuario),
/// el orden es una preferencia del dispositivo: se guarda en
/// `SharedPreferences` por cuenta y no se sincroniza.
class OrdenCarrusel extends StateNotifier<List<String>> {
  OrdenCarrusel(this._prefs, this._ownerId) : super(const []) {
    state = _leer();
  }

  final SharedPreferences _prefs;
  final String? _ownerId;

  String? get _clave {
    final owner = _ownerId?.trim();
    if (owner == null || owner.isEmpty) return null;
    return '${_prefijoClave}_$owner';
  }

  List<String> _leer() {
    final clave = _clave;
    if (clave == null) return const [];
    final raw = _prefs.getString(clave);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List<dynamic>).map((e) => '$e').toList();
    } catch (e) {
      developer.log('Orden del carrusel ilegible: $e', name: 'OrdenCarrusel');
      return const [];
    }
  }

  /// Guarda el orden de las tarjetas tal como quedaron en la hoja.
  Future<void> guardar(List<HomeFeaturedItem> items) async {
    final ids = items.map((item) => item.id).toList();
    state = ids;
    final clave = _clave;
    if (clave == null) return;
    await _prefs.setString(clave, jsonEncode(ids));
  }

  /// Vuelve al orden por defecto (fijados primero, próximos al final).
  Future<void> restablecer() async {
    state = const [];
    final clave = _clave;
    if (clave == null) return;
    await _prefs.remove(clave);
  }
}

final ordenCarruselProvider =
    StateNotifierProvider<OrdenCarrusel, List<String>>((ref) {
      return OrdenCarrusel(
        ref.watch(sharedPreferencesProvider),
        ref.watch(syncQueueActiveOwnerIdProvider),
      );
    });

/// Aplica el orden del usuario sin desordenar lo que no conoce.
///
/// Las tarjetas que el usuario ya ordenó ocupan, en su orden, los lugares que
/// les tocan por defecto; las nuevas (un fijado o un próximo que no estaba
/// cuando ordenó) se quedan en su lugar por defecto.
List<HomeFeaturedItem> aplicarOrdenCarrusel(
  List<HomeFeaturedItem> porDefecto,
  List<String> orden,
) {
  if (orden.isEmpty || porDefecto.length < 2) return porDefecto;
  final posicion = {for (var i = 0; i < orden.length; i++) orden[i]: i};
  final conocidas =
      porDefecto.where((item) => posicion.containsKey(item.id)).toList()
        ..sort((a, b) => posicion[a.id]!.compareTo(posicion[b.id]!));
  var siguiente = 0;
  return [
    for (final item in porDefecto)
      if (posicion.containsKey(item.id)) conocidas[siguiente++] else item,
  ];
}
