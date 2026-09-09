import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/supabase_tables.dart';
import '../../core/utils/registro_asistente.dart';
import '../models/mi_acreditacion.dart';
import '../models/registrado.dart';
import '../models/resultado_envio_qr.dart';
import '../offline/sync_queue_service.dart';
import '../supabase/supabase_client_provider.dart';

/// Código de error de Postgres para violación de constraint UNIQUE.
const _uniqueViolation = '23505';

class RegistradosRepository implements SyncExecutor {
  RegistradosRepository(this._client);

  final SupabaseClient _client;

  @override
  String get table => SupabaseTables.registrados;

  /// Incluye el join a `evento_bloques` para resolver la etiqueta del bloque
  /// (el Excel y la UI no deben mostrar el UUID de `bloque_id`).
  static const _selectConBloque =
      '*, ${SupabaseTables.eventoBloques}(etiqueta)';

  Future<List<Registrado>> listarPorEvento(String eventoId) async {
    final rows = await _client
        .from(SupabaseTables.registrados)
        .select(_selectConBloque)
        .eq('evento_id', eventoId)
        .order('created_at', ascending: false);
    return rows.map(Registrado.fromMap).toList();
  }

  /// Busca un asistente por id dentro de un evento concreto. Lo usa el
  /// escáner QR como respaldo cuando la lista cacheada aún no está lista
  /// o quedó desactualizada.
  Future<Registrado?> obtenerPorIdEnEvento(String id, String eventoId) async {
    final row = await _client
        .from(SupabaseTables.registrados)
        .select(_selectConBloque)
        .eq('id', id)
        .eq('evento_id', eventoId)
        .maybeSingle();
    if (row == null) return null;
    return Registrado.fromMap(row);
  }

  /// Antes de insertar, revisa si ya existe alguien con ese correo en el
  /// evento. Compara en minúsculas porque el email es el identificador
  /// irrepetible y en producción hay filas históricas con distinta capitalización.
  ///
  /// Refuerza (no reemplaza) el `UNIQUE(evento_id, email)` de la base: la
  /// constraint es la última línea de defensa ante doble click / carrera;
  /// este chequeo evita el viaje redondo con error en el caso común.
  Future<bool> existeEmailEnEvento(String eventoId, String email) async {
    final normalizado = email.trim().toLowerCase();
    if (normalizado.isEmpty) return false;
    try {
      final result = await _client.rpc(
        SupabaseRpc.existeEmailRegistrado,
        params: {'p_evento_id': eventoId, 'p_email': normalizado},
      );
      return result == true;
    } catch (_) {
      // Fallback si el RPC aún no está desplegado. `ilike` sin comodines
      // equivale a igualdad case-insensitive. El rol `anon` no puede leer
      // la tabla: en ese caso devolvemos false y `crear` se apoya en UNIQUE.
      final escaped = normalizado
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      try {
        final rows = await _client
            .from(SupabaseTables.registrados)
            .select('id')
            .eq('evento_id', eventoId)
            .ilike('email', escaped)
            .limit(1);
        return rows.isNotEmpty;
      } catch (_) {
        return false;
      }
    }
  }

  Future<Registrado> crear(Registrado registrado) async {
    try {
      final row = await _client
          .from(SupabaseTables.registrados)
          .insert(registrado.toInsertMap())
          .select()
          .single();
      return Registrado.fromMap(row);
    } on PostgrestException catch (e) {
      if (e.code == _uniqueViolation) {
        throw Exception(kMensajeEmailDuplicado);
      }
      rethrow;
    }
  }

  /// Inserción masiva (carga por Excel). Filtra localmente los correos que
  /// ya existen en el evento y los duplicados internos del propio archivo,
  /// y deja que el `UNIQUE(evento_id, email)` de la base de datos actúe
  /// como respaldo final.
  Future<({int insertados, int omitidos})> importarLote(
    String eventoId,
    List<Registrado> registros,
  ) async {
    final vistos = <String>{};
    final unicosDelArchivo = <Registrado>[];
    for (final r in registros) {
      final email = r.email.trim().toLowerCase();
      if (email.isEmpty || vistos.contains(email)) continue;
      vistos.add(email);
      unicosDelArchivo.add(r);
    }

    if (unicosDelArchivo.isEmpty) {
      return (insertados: 0, omitidos: registros.length);
    }

    final existentesRows = await _client
        .from(SupabaseTables.registrados)
        .select('email')
        .eq('evento_id', eventoId)
        .inFilter(
          'email',
          unicosDelArchivo.map((r) => r.email.trim().toLowerCase()).toList(),
        );

    final emailsExistentes = existentesRows
        .map((r) => (r['email'] as String).trim().toLowerCase())
        .toSet();

    final aInsertar = unicosDelArchivo
        .where((r) => !emailsExistentes.contains(r.email.trim().toLowerCase()))
        .toList();

    if (aInsertar.isEmpty) {
      return (insertados: 0, omitidos: registros.length);
    }

    await _client
        .from(SupabaseTables.registrados)
        .insert(aInsertar.map((r) => r.toInsertMap()).toList());

    return (
      insertados: aInsertar.length,
      omitidos: registros.length - aInsertar.length,
    );
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

  /// Envía el QR de acreditación (UUID de `registrados.id`) por email y/o
  /// SMS a través de la Edge Function `enviar-qr`.
  ///
  /// [canales] es `email`, `sms` o ambos. La función responde por canal
  /// (`sent` / `skipped` / `failed`) y acá solo se marcan los flags de los
  /// que realmente salieron. Eventos comerciales omiten SMS.
  ///
  /// El body va envuelto en `{ record: {...}, canales: [...] }` con las
  /// columnas de `public.registrados`, como lo invocaba el legado.
  Future<ResultadoEnvioQr> enviarQr(
    Registrado registrado, {
    String? nombreEvento,
    required List<String> canales,
  }) async {
    final record = <String, dynamic>{
      'id': registrado.id,
      'evento_id': registrado.eventoId,
      'nombre_completo': registrado.nombreCompleto,
      'email': registrado.email,
      'acreditado': registrado.acreditado,
      'rut': registrado.rut,
      'patente': registrado.patente,
      'empresa': registrado.empresa,
      'cargo': registrado.cargo,
      'telefono': registrado.telefono,
      'ingresado_por': registrado.ingresadoPor,
      'email_confirmacion_enviado': registrado.emailConfirmacionEnviado,
      'sms_confirmacion_enviado': registrado.smsConfirmacionEnviado,
      'evento': ?nombreEvento,
    };
    FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        SupabaseFunctions.enviarQr,
        body: {'record': record, 'canales': canales},
      );
    } on FunctionException catch (e) {
      final resultado = ResultadoEnvioQr.fromJson(_mapaRespuesta(e.details));
      if (resultado.email.fallido ||
          resultado.sms.fallido ||
          resultado.email.enviado ||
          resultado.sms.enviado ||
          resultado.email.omitido ||
          resultado.sms.omitido) {
        return resultado;
      }
      final details = e.details;
      throw Exception(
        details is Map && details['error'] != null
            ? details['error'].toString()
            : 'No se pudo enviar el QR.',
      );
    }
    if (response.status >= 400) {
      final data = response.data;
      final message = data is Map && data['error'] != null
          ? data['error'].toString()
          : 'No se pudo enviar el QR.';
      throw Exception(message);
    }
    final resultado = ResultadoEnvioQr.fromJson(_mapaRespuesta(response.data));
    final pideEmail = canales.contains(CanalesEnvioQr.email);
    final pideSms = canales.contains(CanalesEnvioQr.sms);
    final cambios = <String, dynamic>{};
    if (pideEmail && resultado.email.enviado) {
      cambios['email_confirmacion_enviado'] = true;
    }
    if (pideSms && resultado.sms.enviado) {
      cambios['sms_confirmacion_enviado'] = true;
    }
    if (cambios.isNotEmpty) {
      await actualizar(registrado.id, cambios);
    }
    return resultado;
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

  // ---- SyncExecutor: puente entre la cola offline y esta tabla ----

  @override
  Future<void> onInsert(Map<String, dynamic> payload) async {
    final data = Map<String, dynamic>.from(payload)
      ..remove('id')
      ..remove('acreditado_en');
    try {
      await _client.from(SupabaseTables.registrados).insert(data);
    } on PostgrestException catch (e) {
      // Si mientras estuvo offline alguien más registró el mismo correo,
      // el UNIQUE(evento_id, email) rechaza el insert. Se descarta el
      // duplicado en vez de reintentarlo por siempre.
      if (e.code == _uniqueViolation) return;
      rethrow;
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

final registradosRepositoryPublicoProvider = Provider<RegistradosRepository>((
  ref,
) {
  return RegistradosRepository(ref.watch(supabasePublicClientProvider));
});
