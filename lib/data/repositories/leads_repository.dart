import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_tables.dart';
import '../models/lead.dart';
import '../models/lead_existente.dart';
import '../models/lead_write_result.dart';
import '../offline/pending_photo_store.dart';
import '../offline/sync_queue_item.dart';
import '../offline/sync_queue_service.dart';
import '../supabase/supabase_client_provider.dart';
import 'storage_repository.dart';

/// CRUD de leads capturados (`public.leads`) + sync offline de inserts.
class LeadsRepository implements SyncExecutor {
  LeadsRepository(this._client, this._storage, this._fotosPendientes);

  final SupabaseClient _client;
  final StorageRepository _storage;
  final PendingPhotoStore _fotosPendientes;

  @override
  String get table => SupabaseTables.leads;

  static const _selectLead = '*';
  static const _guardarLeadRpc = SupabaseRpc.guardarLead;
  static const _resumenCampanaRpc = SupabaseRpc.resumenCampana;

  List<Lead> _mapRows(List<dynamic> rows) {
    return rows
        .map((row) => Lead.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<List<Lead>> listarPorEvento(String eventoId) async {
    final rows = await _client
        .from(SupabaseTables.leads)
        .select(_selectLead)
        .eq('evento_id', eventoId)
        .order('created_at', ascending: false);
    return _mapRows(rows);
  }

  /// Leads capturados por un perfil concreto (más recientes primero).
  Future<List<Lead>> listarPorPerfil(String perfilId) async {
    final rows = await _client
        .from(SupabaseTables.leads)
        .select(_selectLead)
        .eq('perfil_id', perfilId)
        .order('created_at', ascending: false);
    return _mapRows(rows);
  }

  Future<List<Lead>> listarPorEventoYPerfil(
    String eventoId,
    String perfilId,
  ) async {
    final rows = await _client
        .from(SupabaseTables.leads)
        .select(_selectLead)
        .eq('evento_id', eventoId)
        .eq('perfil_id', perfilId)
        .order('created_at', ascending: false);
    return _mapRows(rows);
  }

  Future<int> contarPorPerfil(String perfilId) async {
    return _client
        .from(SupabaseTables.leads)
        .count(CountOption.exact)
        .eq('perfil_id', perfilId);
  }

  /// Conteos del evento de leads para roles internos. No devuelve filas.
  Future<({int total, int empresas})> obtenerResumenCampana(
    String eventoId,
  ) async {
    final raw = await _client.rpc(
      _resumenCampanaRpc,
      params: {'p_evento_id': eventoId},
    );
    final row = _primeraFilaRpc(raw, _resumenCampanaRpc);
    return (total: _asInt(row['total']), empresas: _asInt(row['empresas']));
  }

  static Map<String, dynamic> _primeraFilaRpc(Object? raw, String rpc) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return Map<String, dynamic>.from(raw.first as Map);
    }
    throw FormatException('Respuesta vacía de $rpc.');
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<Lead> obtenerPorId(String id) async {
    final row = await _client
        .from(SupabaseTables.leads)
        .select(_selectLead)
        .eq('id', id)
        .single();
    return Lead.fromMap(Map<String, dynamic>.from(row));
  }

  /// Lead ya capturado en la campaña con ese email, o `null`.
  Future<LeadExistente?> buscarPorEmail({
    required String eventoId,
    required String email,
  }) async {
    final normalizado = emailLeadNormalizado(email);
    if (normalizado == null) return null;

    final raw = await _client.rpc(
      SupabaseRpc.buscarLeadPorEmail,
      params: {'p_evento_id': eventoId, 'p_email': email},
    );
    if (raw == null) return null;
    if (raw is List) {
      if (raw.isEmpty) return null;
      final first = raw.first;
      if (first is! Map) return null;
      final existente = LeadExistente.fromRpc(Map<String, dynamic>.from(first));
      if (existente.leadId.isEmpty) return null;
      return existente;
    }
    if (raw is Map) {
      final existente = LeadExistente.fromRpc(Map<String, dynamic>.from(raw));
      if (existente.leadId.isEmpty) return null;
      return existente;
    }
    return null;
  }

  Future<LeadWriteResult> crear(Lead lead) async {
    final result = await _guardarConRpc(lead);
    if (!result.guardado || lead.fotosUrls.isEmpty) return result;

    try {
      final fotos = await _subirFotosPendientes(lead.fotosUrls, result.leadId);
      await _client
          .from(SupabaseTables.leads)
          .update({'fotos_urls': fotos.urls})
          .eq('id', result.leadId);
      await fotos.limpiarLocales();
    } catch (error) {
      throw LeadPhotoPendingException(
        result: result,
        fotosPendientes: lead.fotosUrls,
        cause: error,
      );
    }
    return result;
  }

  Future<void> adjuntarFotoBytes(String leadId, Uint8List bytes) async {
    final path = await _storage.subirFotoLeadParaId(bytes, leadId);
    await _client
        .from(SupabaseTables.leads)
        .update({
          'fotos_urls': [path],
        })
        .eq('id', leadId);
  }

  Future<LeadWriteResult> _guardarConRpc(Lead lead, {String? leadId}) async {
    final raw = await _client.rpc(
      _guardarLeadRpc,
      params: {
        'p_evento_id': lead.eventoId,
        'p_nombre_completo': lead.nombreCompleto.trim(),
        'p_empresa': _nullable(lead.empresa),
        'p_cargo': _nullable(lead.cargo),
        'p_telefono': _nullable(lead.telefono),
        'p_email': lead.email?.trim().toLowerCase(),
        'p_descripcion': _nullable(lead.descripcion),
        'p_lead_id': leadId,
      },
    );
    return LeadWriteResult.fromRpc(raw);
  }

  String? _nullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<LeadWriteResult> actualizar(
    String id,
    Map<String, dynamic> changes,
  ) async {
    final canonicalChanges = Map<String, dynamic>.from(changes);
    if (canonicalChanges['fotos_urls'] is List) {
      canonicalChanges['fotos_urls'] = _fotosDe(canonicalChanges)
          .map((url) => esFotoStorageLead(url) ? pathFotoStorageLead(url) : url)
          .toList();
    }
    final actual = await obtenerPorId(id);
    final editado = actual.conCambiosPendientes(canonicalChanges);
    final result = await _guardarConRpc(editado, leadId: id);
    if (!result.guardado || !canonicalChanges.containsKey('fotos_urls')) {
      return result;
    }

    try {
      final fotos = await _subirFotosPendientes(_fotosDe(canonicalChanges), id);
      await _client
          .from(SupabaseTables.leads)
          .update({'fotos_urls': fotos.urls})
          .eq('id', id);
      await fotos.limpiarLocales();
    } catch (error) {
      throw LeadPhotoPendingException(
        result: result,
        fotosPendientes: _fotosDe(canonicalChanges),
        cause: error,
      );
    }
    return result;
  }

  /// Borrado lógico (`cl_eliminar_lead`): el lead deja de verse en listas,
  /// conteos y Excel, pero la fila queda para que el admin pueda recuperarla.
  /// La base lo permite al admin y a quien lo capturó; la ventana de tiempo
  /// la decide la app (ver `permisosLead`).
  Future<void> eliminar(String id) async {
    await _client.rpc(SupabaseRpc.eliminarLead, params: {'p_lead_id': id});
  }

  @override
  Future<void> onInsert(Map<String, dynamic> payload) async {
    final data = Map<String, dynamic>.from(payload);
    final currentUserId = _client.auth.currentUser?.id;
    final payloadOwner = data['perfil_id']?.toString();
    if (currentUserId == null || payloadOwner != currentUserId) {
      throw const TerminalSyncConflictException(
        SyncConflict(
          code: 'owner_mismatch',
          message: 'La captura pertenece a otra sesión y no se sincronizó.',
        ),
      );
    }
    final localId = data.remove('id')?.toString();
    final serverId = data.remove('_server_lead_id')?.toString();
    final requestedId =
        serverId ?? data.remove('_requested_lead_id')?.toString();
    final localFotos = _fotosDe(data);
    final lead = Lead.fromMap({
      ...data,
      'id': requestedId ?? localId ?? '',
      'fotos_urls': const <String>[],
    });

    final result = await _guardarConRpc(lead, leadId: requestedId);
    if (result.esDuplicado) {
      // El lead ya existe en el servidor: no hay nada que resolver, se omite
      // esta captura y la cola sigue con el resto.
      throw SyncDiscardedException(result.mensajeDuplicado);
    }

    try {
      if (localFotos.isNotEmpty) {
        final fotos = await _subirFotosPendientes(localFotos, result.leadId);
        await _client
            .from(SupabaseTables.leads)
            .update({'fotos_urls': fotos.urls})
            .eq('id', result.leadId);
        await fotos.limpiarLocales();
      }
    } catch (e) {
      throw RetryableSyncException(
        e.toString(),
        payloadPatch: {'_server_lead_id': result.leadId},
      );
    }
  }

  @override
  Future<void> onUpdate(Map<String, dynamic> payload) async {
    if (_client.auth.currentUser == null) {
      throw const RetryableSyncException('No hay una sesión activa.');
    }
    final id = payload['id'] as String;
    final changes = Map<String, dynamic>.from(payload['changes'] as Map);
    // Un borrado hecho sin red: lo demás que se haya editado ya no importa.
    if (changes[campoLeadEliminadoAt] != null) {
      await eliminar(id);
      return;
    }
    final result = await actualizar(id, changes);
    if (result.esDuplicado) {
      throw SyncDiscardedException(result.mensajeDuplicado);
    }
  }

  List<String> _fotosDe(Map<String, dynamic> fila) {
    final valor = fila['fotos_urls'];
    if (valor is! List) return const [];
    return valor.map((e) => e.toString()).toList();
  }

  /// Sube a Storage las fotos que quedaron en disco por falta de red y
  /// devuelve la lista con las URLs públicas ya resueltas.
  ///
  /// Los archivos locales se borran recién cuando la fila llegó al servidor
  /// ([_FotosResueltas.limpiarLocales]): si el INSERT falla, la cola vuelve a
  /// intentarlo más tarde y la foto tiene que seguir ahí.
  Future<_FotosResueltas> _subirFotosPendientes(
    List<String> urls,
    String leadId,
  ) async {
    final resueltas = <String>[];
    final consumidas = <String>[];
    for (final url in urls) {
      if (!esFotoLocal(url)) {
        // Nunca persistir el token temporal de una URL firmada. Las URLs
        // públicas legacy se preservan hasta migrar físicamente sus blobs.
        resueltas.add(esFotoStorageLead(url) ? pathFotoStorageLead(url) : url);
        continue;
      }
      final bytes = await _fotosPendientes.leer(url);
      if (bytes == null) {
        // El archivo ya no está (datos limpiados, o el sistema recuperó
        // espacio). Se sincroniza el lead sin la foto en vez de dejar la
        // cola atascada: processPending no tiene tope de reintentos, así que
        // una excepción permanente acá bloquearía toda la sincronización.
        developer.log(
          'Foto pendiente perdida, el lead se sube sin ella: $url',
          name: 'LeadsRepository',
        );
        continue;
      }
      resueltas.add(await _storage.subirFotoLeadParaId(bytes, leadId));
      consumidas.add(url);
    }
    return _FotosResueltas(resueltas, consumidas, _fotosPendientes);
  }
}

class _FotosResueltas {
  const _FotosResueltas(this.urls, this._consumidas, this._store);

  final List<String> urls;
  final List<String> _consumidas;
  final PendingPhotoStore _store;

  Future<void> limpiarLocales() async {
    for (final marcador in _consumidas) {
      await _store.borrar(marcador);
    }
  }
}

final leadsRepositoryProvider = Provider<LeadsRepository>((ref) {
  return LeadsRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(storageRepositoryProvider),
    ref.watch(pendingPhotoStoreProvider),
  );
});
