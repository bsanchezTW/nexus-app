import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_tables.dart';
import '../../core/errors/rpe_exception.dart';
import '../models/ocupacion_evento.dart';
import '../models/subevento.dart';
import '../supabase/supabase_client_provider.dart';

class SubeventosRepository {
  SubeventosRepository(this._client);

  final SupabaseClient _client;

  Future<List<Subevento>> listarPorEvento(String eventoId) {
    return conErroresRpe(() async {
      final rows = await _client
          .from(SupabaseTables.subeventos)
          .select()
          .eq('evento_id', eventoId)
          .order('dia')
          .order('hora_inicio')
          .order('orden');
      return rows.map(Subevento.fromMap).toList();
    });
  }

  Future<Subevento> obtener(String id) {
    return conErroresRpe(() async {
      final row = await _client
          .from(SupabaseTables.subeventos)
          .select()
          .eq('id', id)
          .single();
      return Subevento.fromMap(row);
    });
  }

  Future<Subevento> crear(Subevento subevento) {
    return conErroresRpe(() async {
      final datos = subevento.toInsertMap();
      if ((datos['codigo'] as String?)?.isEmpty ?? true) datos.remove('codigo');
      final row = await _client
          .from(SupabaseTables.subeventos)
          .insert(datos)
          .select()
          .single();
      return Subevento.fromMap(row);
    });
  }

  Future<void> actualizar(String id, Map<String, dynamic> cambios) {
    return conErroresRpe(
      () => _client.from(SupabaseTables.subeventos).update(cambios).eq('id', id),
    );
  }

  Future<void> eliminar(String id) {
    return conErroresRpe(
      () => _client.from(SupabaseTables.subeventos).delete().eq('id', id),
    );
  }

  Future<OcupacionEvento> ocupacion(String eventoId) {
    return conErroresRpe(() async {
      final raw = await _client.rpc(
        SupabaseRpc.ocupacionEvento,
        params: {'p_evento_id': eventoId},
      );
      if (raw is! Map) throw const RpeException(RpeErrorCode.desconocido);
      return ocupacionDesdeJson(Map<String, dynamic>.from(raw));
    });
  }
}

OcupacionEvento ocupacionDesdeJson(Map<String, dynamic> json) {
  final evento = Map<String, dynamic>.from(json['evento'] as Map);
  final lista = json['subeventos'];
  return OcupacionEvento(
    evento: OcupacionItem(
      cupoMaximo: evento['cupo_maximo'] as int?,
      inscritos: (evento['inscritos'] as num?)?.toInt() ?? 0,
      asistentes: (evento['acreditados'] as num?)?.toInt() ?? 0,
      sobrecupo: (evento['sobrecupo'] as num?)?.toInt() ?? 0,
    ),
    subeventos: {
      for (final item in lista is List ? lista : const [])
        if (item is Map)
          item['subevento_id'].toString(): OcupacionItem(
            cupoMaximo: item['cupo_maximo'] as int?,
            inscritos: (item['inscritos'] as num?)?.toInt() ?? 0,
            asistentes: (item['asistentes'] as num?)?.toInt() ?? 0,
            sobrecupo: (item['sobrecupo'] as num?)?.toInt() ?? 0,
          ),
    },
  );
}

final subeventosRepositoryProvider = Provider<SubeventosRepository>((ref) {
  return SubeventosRepository(ref.watch(supabaseClientProvider));
});
