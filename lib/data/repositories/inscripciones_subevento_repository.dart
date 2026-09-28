import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_tables.dart';
import '../../core/errors/rpe_exception.dart';
import '../models/inscripcion_subevento.dart';
import '../offline/sync_queue_item.dart';
import '../offline/sync_queue_service.dart';
import '../supabase/supabase_client_provider.dart';

class InscripcionesSubeventoRepository implements SyncExecutor {
  InscripcionesSubeventoRepository(this._client);

  final SupabaseClient _client;

  @override
  String get table => SupabaseTables.inscripcionesSubevento;

  Future<List<InscripcionSubevento>> listarPorEvento(String eventoId) {
    return conErroresRpe(() async {
      final rows = await _client
          .from(SupabaseTables.inscripcionesSubevento)
          .select()
          .eq('evento_id', eventoId);
      return rows.map(InscripcionSubevento.fromMap).toList();
    });
  }

  Future<Map<String, dynamic>> inscribir({
    required String registradoId,
    required String subeventoId,
    bool forzarSobrecupo = false,
    bool marcarAsistencia = false,
    bool reemplazarSuperpuestos = false,
  }) {
    return conErroresRpe(() async {
      final raw = await _client.rpc(
        SupabaseRpc.inscribirSubevento,
        params: {
          'p_registrado_id': registradoId,
          'p_subevento_id': subeventoId,
          'p_forzar_sobrecupo': forzarSobrecupo,
          'p_marcar_asistencia': marcarAsistencia,
          'p_reemplazar_superpuestos': reemplazarSuperpuestos,
        },
      );
      if (raw is! Map) throw const RpeException(RpeErrorCode.desconocido);
      return Map<String, dynamic>.from(raw);
    });
  }

  Future<Map<String, dynamic>> marcarAsistencia({
    required String registradoId,
    required String subeventoId,
    bool asistio = true,
  }) {
    return conErroresRpe(() async {
      final raw = await _client.rpc(
        SupabaseRpc.marcarAsistenciaSubevento,
        params: {
          'p_registrado_id': registradoId,
          'p_subevento_id': subeventoId,
          'p_asistio': asistio,
        },
      );
      if (raw is! Map) throw const RpeException(RpeErrorCode.desconocido);
      return Map<String, dynamic>.from(raw);
    });
  }

  Future<void> quitar({
    required String registradoId,
    required String subeventoId,
  }) {
    return conErroresRpe(
      () => _client.rpc(
        SupabaseRpc.quitarInscripcionSubevento,
        params: {
          'p_registrado_id': registradoId,
          'p_subevento_id': subeventoId,
        },
      ),
    );
  }

  @override
  Future<void> onInsert(Map<String, dynamic> payload) async {
    final accion = payload['accion'] as String?;
    final registradoId = payload['registrado_id'] as String?;
    final subeventoId = payload['subevento_id'] as String?;
    if (registradoId == null || subeventoId == null) {
      throw TerminalSyncConflictException(
        const SyncConflict(
          code: 'datos',
          message: 'La asistencia en cola no tiene persona o taller.',
        ),
      );
    }
    final Map<String, dynamic> resultado;
    if (accion == 'inscribir_y_marcar') {
      resultado = await inscribir(
        registradoId: registradoId,
        subeventoId: subeventoId,
        forzarSobrecupo: payload['forzar'] == true,
        marcarAsistencia: true,
        reemplazarSuperpuestos: payload['reemplazar'] == true,
      );
    } else {
      resultado = await marcarAsistencia(
        registradoId: registradoId,
        subeventoId: subeventoId,
      );
    }
    if (resultado['ok'] == false) {
      developer.log(
        'Conflicto de asistencia ${resultado['motivo']}',
        name: 'AsistenciaSubevento',
      );
      throw TerminalSyncConflictException(
        SyncConflict(
          code: resultado['motivo']?.toString() ?? 'rechazo',
          message: 'No se pudo sincronizar la asistencia al taller.',
        ),
      );
    }
  }

  @override
  Future<void> onUpdate(Map<String, dynamic> payload) async {}
}

final inscripcionesSubeventoRepositoryProvider =
    Provider<InscripcionesSubeventoRepository>((ref) {
      return InscripcionesSubeventoRepository(ref.watch(supabaseClientProvider));
    });
