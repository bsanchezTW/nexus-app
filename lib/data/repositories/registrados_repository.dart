import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/rpe_exception.dart';
import '../../core/constants/supabase_tables.dart';
import '../../core/utils/registro_asistente.dart';
import '../models/mi_acreditacion.dart';
import '../models/registrado.dart';
import '../models/resultado_envio_qr.dart';
import '../models/resultado_registro.dart';
import '../offline/sync_queue_item.dart';
import '../offline/sync_queue_service.dart';
import '../supabase/supabase_client_provider.dart';

class RegistradosRepository implements SyncExecutor {
  RegistradosRepository(this._client);

  final SupabaseClient _client;

  @override
  String get table => SupabaseTables.registrados;

  Future<List<Registrado>> listarPorEvento(String eventoId) async {
    final rows = await _client
        .from(SupabaseTables.registrados)
        .select()
        .eq('evento_id', eventoId)
        .order('created_at', ascending: false);
    return rows.map(Registrado.fromMap).toList();
  }

  Future<Registrado?> obtenerPorIdEnEvento(String id, String eventoId) async {
    final row = await _client
        .from(SupabaseTables.registrados)
        .select()
        .eq('id', id)
        .eq('evento_id', eventoId)
        .maybeSingle();
    if (row == null) return null;
    return Registrado.fromMap(row);
  }

  Future<Registrado?> obtenerPorCodigoQrEnEvento(
    String codigo,
    String eventoId,
  ) async {
    final row = await conErroresRpe(
      () => _client
          .from(SupabaseTables.registrados)
          .select()
          .eq('codigo_qr', codigo)
          .eq('evento_id', eventoId)
          .maybeSingle(),
    );
    if (row == null) return null;
    return Registrado.fromMap(row);
  }

  Future<ResultadoRegistro> registrar({
    required String eventoId,
    required Map<String, dynamic> datos,
    List<String> subeventoIds = const [],
    bool acreditar = false,
    bool forzarSobrecupo = false,
    bool enviarQr = true,
  }) async {
    final raw = await conErroresRpe(
      () => _client.rpc(
        SupabaseRpc.registrarAsistente,
        params: {
          'p_evento_id': eventoId,
          'p_datos': datos,
          'p_subevento_ids': subeventoIds,
          'p_acreditar': acreditar,
          'p_forzar_sobrecupo': forzarSobrecupo,
          'p_enviar_qr': enviarQr,
        },
      ),
    );
    return _resultadoRegistro(raw);
  }

  Future<ResultadoImportacion> importar({
    required String eventoId,
    required List<Map<String, dynamic>> filas,
    bool forzarSobrecupo = false,
  }) async {
    final raw = await conErroresRpe(
      () => _client.rpc(
        SupabaseRpc.importarRegistrados,
        params: {
          'p_evento_id': eventoId,
          'p_filas': filas,
          'p_forzar_sobrecupo': forzarSobrecupo,
        },
      ),
    );
    if (raw is! Map) {
      throw const RpeException(RpeErrorCode.desconocido);
    }
    return ResultadoImportacion.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<String> regenerarCodigoQr(String registradoId, {bool reenviar = true}) async {
    final raw = await conErroresRpe(
      () => _client.rpc(
        SupabaseRpc.regenerarCodigoQr,
        params: {'p_registrado_id': registradoId, 'p_reenviar': reenviar},
      ),
    );
    if (raw is Map && raw['codigo_qr'] is String) return raw['codigo_qr'] as String;
    throw const RpeException(RpeErrorCode.desconocido);
  }

  Future<ResultadoEnvioQr> enviarQr(
    String registradoId, {
    required List<String> canales,
  }) async {
    FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        SupabaseFunctions.enviarQr,
        body: {
          'registrado_id': registradoId,
          'canales': canales,
          'motivo': 'reenvio',
        },
      );
    } on FunctionException catch (e) {
      final mapeado = rpeExceptionDesde(e);
      if (mapeado != null) throw mapeado;
      final resultado = ResultadoEnvioQr.fromJson(_mapaRespuesta(e.details));
      if (resultado.email.fallido ||
          resultado.sms.fallido ||
          resultado.email.enviado ||
          resultado.sms.enviado ||
          resultado.email.omitido ||
          resultado.sms.omitido) {
        return resultado;
      }
      throw Exception('No se pudo enviar la confirmación.');
    }
    if (response.status >= 400) {
      throw Exception('No se pudo enviar la confirmación.');
    }
    return ResultadoEnvioQr.fromJson(_mapaRespuesta(response.data));
  }

  Future<void> actualizar(String id, Map<String, dynamic> changes) async {
    await _client.from(SupabaseTables.registrados).update(changes).eq('id', id);
  }

  Future<void> acreditar(String id, {required String acreditadoPorId}) async {
    await actualizar(id, {
      'acreditado': true,
      'acreditado_por': acreditadoPorId,
    });
  }

  Future<void> desacreditar(String id) async {
    await actualizar(id, {'acreditado': false, 'acreditado_por': null});
  }

  /// Solo admin puede eliminar (política `rpe_registrados_delete`).
  Future<void> eliminar(String id) async {
    await _client.from(SupabaseTables.registrados).delete().eq('id', id);
  }

  Map<String, dynamic> _mapaRespuesta(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.isNotEmpty) {
      final decoded = jsonDecode(data);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return {};
  }

  ResultadoRegistro _resultadoRegistro(dynamic raw) {
    if (raw is! Map) throw const RpeException(RpeErrorCode.desconocido);
    final json = Map<String, dynamic>.from(raw);
    if (json['ok'] == true) {
      return RegistroOk(
        registradoId: json['registrado_id'] as String,
        codigoQr: json['codigo_qr'] as String? ?? '',
        sobrecupo: json['sobrecupo'] == true,
        envio: json['envio'] as String? ?? 'no_solicitado',
      );
    }
    final rechazados = json['rechazados'];
    return RegistroRechazado(
      motivo: json['motivo'] as String? ?? 'desconocido',
      registradoIdExistente: json['registrado_id_existente'] as String?,
      puedeForzar: json['puede_forzar'] == true,
      rechazados: rechazados is List
          ? [
              for (final item in rechazados)
                if (item is Map)
                  RechazoSubevento(
                    subeventoId: item['subevento_id']?.toString() ?? '',
                    motivo: item['motivo']?.toString() ?? '',
                  ),
            ]
          : const [],
    );
  }

  // ---- SyncExecutor: puente entre la cola offline y esta tabla ----

  @override
  Future<void> onInsert(Map<String, dynamic> payload) async {
    final eventoId = payload['evento_id'] as String?;
    if (eventoId == null || eventoId.isEmpty) {
      throw TerminalSyncConflictException(
        const SyncConflict(
          code: 'sin_evento',
          message: 'El registro no tiene evento.',
        ),
      );
    }
    final resultado = await registrar(
      eventoId: eventoId,
      datos: payload,
      acreditar: payload['acreditado'] == true,
      enviarQr: false,
    );
    if (resultado is RegistroRechazado) {
      if (resultado.motivo == 'email_duplicado') {
        throw SyncDiscardedException(kMensajeEmailDuplicado);
      }
      throw TerminalSyncConflictException(
        SyncConflict(
          code: resultado.motivo,
          message: 'No se pudo sincronizar el registro.',
        ),
      );
    }
  }

  @override
  Future<void> onUpdate(Map<String, dynamic> payload) async {
    final id = payload['id'] as String;
    final changes = Map<String, dynamic>.from(payload['changes'] as Map);
    await _client.from(SupabaseTables.registrados).update(changes).eq('id', id);
  }

  /// Totales de un evento concreto para la card del home.
  Future<({int total, int acreditados})> obtenerResumenPorEvento(
    String eventoId,
  ) async {
    final resultados = await Future.wait<int>([
      _client
          .from(SupabaseTables.registrados)
          .count(CountOption.exact)
          .eq('evento_id', eventoId),
      _client
          .from(SupabaseTables.registrados)
          .count(CountOption.exact)
          .eq('evento_id', eventoId)
          .eq('acreditado', true),
    ]);
    return (total: resultados[0], acreditados: resultados[1]);
  }

  /// Totales visibles para el dashboard. RLS acota las filas a los eventos
  /// asignados cuando la sesión corresponde al rol `user`.
  Future<({int total, int acreditados})> obtenerResumenGlobal() async {
    final resultados = await Future.wait<int>([
      _client.from(SupabaseTables.registrados).count(CountOption.exact),
      _client
          .from(SupabaseTables.registrados)
          .count(CountOption.exact)
          .eq('acreditado', true),
    ]);
    return (total: resultados[0], acreditados: resultados[1]);
  }

  Future<int> contarPorIngresadoPor(String perfilId) async {
    return _client
        .from(SupabaseTables.registrados)
        .count(CountOption.exact)
        .eq('ingresado_por', perfilId);
  }

  /// Acreditaciones del usuario en sesión, con su evento y ya ordenadas.
  ///
  /// Va por RPC `SECURITY DEFINER` y no por `select` directo: la política
  /// `rpe_registrados_select` acota a `rpe_puede_operar_evento`, así que a un
  /// `user` al que le retiraron un evento le desaparecerían acreditaciones que
  /// sí hizo. Reemplaza también al conteo, para que la tarjeta de "Mi perfil"
  /// y el listado no puedan discrepar.
  Future<List<MiAcreditacion>> listarMisAcreditados() async {
    final filas = await _client.rpc(SupabaseRpc.misAcreditados);
    if (filas is! List) return const [];
    return filas
        .cast<Map<String, dynamic>>()
        .map(MiAcreditacion.fromMap)
        .toList();
  }
}

final registradosRepositoryProvider = Provider<RegistradosRepository>((ref) {
  return RegistradosRepository(ref.watch(supabaseClientProvider));
});
