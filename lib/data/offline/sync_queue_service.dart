import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_bootstrap.dart';
import '../supabase/supabase_client_provider.dart';
import 'sync_queue_item.dart';

/// Ejecuta un ítem de la cola contra el backend real. Cada feature que
/// necesite soporte offline (por ahora, registrados) implementa uno de
/// estos y lo registra en [SyncCoordinator] — así el motor de sincronización
/// no depende directamente de Supabase ni de un dominio en particular.
abstract class SyncExecutor {
  String get table;

  Future<void> onInsert(Map<String, dynamic> payload);

  Future<void> onUpdate(Map<String, dynamic> payload);
}

const _legacyPrefsKey = 'sync_queue_v1';
const _prefsKeyPrefix = 'sync_queue_v2';
const _uuid = Uuid();

/// Prefijo de los ids temporales que [SyncQueueService.enqueueInsert] asigna
/// a las filas que todavía no existen en el servidor.
const syncLocalIdPrefix = 'local_';

/// true si [id] es uno de esos ids temporales, es decir, si la fila vive solo
/// en la cola local.
///
/// Es la pregunta correcta antes de un UPDATE, un DELETE o de generar un QR:
/// distinta de `pendienteDeSincronizar`, que también vale `true` para una fila
/// ya sincronizada que solo tiene una edición esperando en la cola.
bool esIdSoloLocal(String id) => id.startsWith(syncLocalIdPrefix);

/// La captura local ya está siendo enviada con un snapshot inmutable.
/// Permitir una edición en esta ventana haría que el worker eliminara el
/// ítem tras sincronizar la versión anterior y perdiera silenciosamente el
/// cambio más reciente.
class SyncItemInFlightException implements Exception {
  const SyncItemInFlightException();

  @override
  String toString() =>
      'Este lead se está sincronizando. Reintenta en unos segundos.';
}

/// Única cola de sincronización offline de toda la app.
///
/// Corrige el bug crítico documentado en `documentacion_zips_registro_pro.md`
/// (Secciones 3.8, 4.8 y 17.3): en el proyecto legado, la app móvil tenía DOS
/// colas offline desconectadas — una en `lib/offlineManager.ts` (clave
/// `capturador_leads_cola_offline`, jamás escrita) y otra usada por las
/// pantallas directamente (clave `registro_pro_cola_offline`, jamás leída
/// por el motor de sincronización). El resultado era que nada capturado sin
/// conexión llegaba nunca a Supabase.
///
/// Acá solo existe ESTA clase. Ninguna pantalla debe leer/escribir
/// `SharedPreferences` directamente para temas de sincronización: todo pasa
/// por [enqueueInsert] / [enqueueUpdate] / [processPending].
class SyncQueueService extends StateNotifier<List<SyncQueueItem>> {
  SyncQueueService(this._prefs, this.ownerId) : super(const []) {
    _restore();
  }

  final SharedPreferences _prefs;
  final String? ownerId;
  bool _processing = false;

  /// Ítems que el servidor rechazó por duplicados y se retiraron de la cola.
  ///
  /// Vive solo en memoria: es material de un aviso, no un pendiente. Si la app
  /// se cierra, el dato ya está en el servidor y no hay nada que recordar.
  final List<String> _descartes = [];

  List<String> get descartes => List.unmodifiable(_descartes);

  void limpiarDescartes() => _descartes.clear();

  String? get _prefsKey {
    final owner = ownerId?.trim();
    if (owner == null || owner.isEmpty) return null;
    return '${_prefsKeyPrefix}_$owner';
  }

  String _requireOwner() {
    final owner = ownerId?.trim();
    if (owner == null || owner.isEmpty) {
      throw StateError('Se requiere una sesión para guardar datos offline.');
    }
    return owner;
  }

  void _restore() {
    final key = _prefsKey;
    if (key == null) return;
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      state = decoded
          .map((e) => SyncQueueItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      developer.log(
        'No se pudo restaurar la cola offline: $e',
        name: 'SyncQueueService',
      );
    }
  }

  Future<void> _persist() async {
    final key = _prefsKey;
    if (key == null) return;
    final encoded = jsonEncode(state.map((e) => e.toJson()).toList());
    await _prefs.setString(key, encoded);
  }

  List<SyncQueueItem> pendingFor(String table) => state
      .where(
        (i) =>
            i.table == table &&
            i.status != SyncStatus.synced &&
            i.status != SyncStatus.conflict,
      )
      .toList();

  int get pendingCount => state
      .where(
        (i) =>
            i.status == SyncStatus.pending ||
            i.status == SyncStatus.syncing ||
            i.status == SyncStatus.failed,
      )
      .length;

  List<SyncQueueItem> get conflicts =>
      state.where((i) => i.status == SyncStatus.conflict).toList();

  /// La cola v1 no tenía dueño. Adoptarla automáticamente podría enviar datos
  /// de una sesión anterior; solo se adopta si cada fila identifica de forma
  /// inequívoca al usuario actual. El resto queda en cuarentena local.
  Future<int> migrateLegacyIfUnambiguous() async {
    final currentOwner = ownerId?.trim();
    final key = _prefsKey;
    final raw = _prefs.getString(_legacyPrefsKey);
    if (currentOwner == null ||
        currentOwner.isEmpty ||
        key == null ||
        raw == null ||
        raw.isEmpty) {
      return 0;
    }

    try {
      final decoded = (jsonDecode(raw) as List<dynamic>)
          .map((e) => SyncQueueItem.fromJson(e as Map<String, dynamic>))
          .toList();
      final adoptables = decoded.where((item) {
        final changes = item.payload['changes'];
        final owners = <String>{};
        void addOwner(Object? raw) {
          final value = raw?.toString().trim();
          if (value != null && value.isNotEmpty) owners.add(value);
        }

        addOwner(item.ownerId);
        for (final key in const [
          'perfil_id',
          'ingresado_por',
          'acreditado_por',
        ]) {
          addOwner(item.payload[key]);
        }
        if (changes is Map) {
          for (final key in const ['perfil_id', 'acreditado_por']) {
            addOwner(changes[key]);
          }
        }
        return owners.length == 1 && owners.single == currentOwner;
      }).toList();
      final quarantine = decoded.where((item) => !adoptables.contains(item));

      if (adoptables.isNotEmpty) {
        final existingIds = state.map((e) => e.id).toSet();
        state = [
          ...state,
          ...adoptables
              .where((item) => !existingIds.contains(item.id))
              .map((item) => item.copyWith(ownerId: currentOwner)),
        ];
        await _persist();
      }
      if (quarantine.isNotEmpty) {
        await _prefs.setString(
          '${_prefsKeyPrefix}_quarantine',
          jsonEncode(quarantine.map((e) => e.toJson()).toList()),
        );
      }
      await _prefs.remove(_legacyPrefsKey);
      return adoptables.length;
    } catch (e) {
      developer.log(
        'Cola legacy ilegible; se conserva en cuarentena: $e',
        name: 'SyncQueueService',
      );
      await _prefs.setString('${_prefsKeyPrefix}_quarantine_raw', raw);
      await _prefs.remove(_legacyPrefsKey);
      return 0;
    }
  }

  /// Encola un INSERT y devuelve el id local temporal generado, para que la
  /// UI pueda mostrar el registro de inmediato (con `pendienteDeSincronizar
  /// = true`) sin esperar al servidor.
  Future<String> enqueueInsert({
    required String table,
    required Map<String, dynamic> payload,
  }) async {
    final currentOwner = _requireOwner();
    final id = '$syncLocalIdPrefix${_uuid.v4()}';
    final now = DateTime.now();
    final item = SyncQueueItem(
      id: id,
      operation: SyncOperation.insert,
      table: table,
      payload: {...payload, 'id': id},
      createdAt: now,
      updatedAt: now,
      ownerId: currentOwner,
    );
    state = [...state, item];
    await _persist();
    return id;
  }

  /// Encola un UPDATE. Si el `entityId` corresponde a un INSERT todavía
  /// pendiente (empieza con `local_` y sigue en la cola), el cambio se
  /// fusiona directamente en ese ítem en vez de crear una operación nueva
  /// — evita intentar "actualizar" una fila que el servidor todavía no
  /// conoce.
  Future<void> enqueueUpdate({
    required String table,
    required String entityId,
    required Map<String, dynamic> changes,
  }) async {
    final currentOwner = _requireOwner();
    final localInsertIndex = state.indexWhere(
      (i) => i.id == entityId && i.operation == SyncOperation.insert,
    );

    if (localInsertIndex != -1) {
      final current = state[localInsertIndex];
      if (current.status == SyncStatus.syncing) {
        throw const SyncItemInFlightException();
      }
      if (current.status == SyncStatus.conflict) {
        throw StateError(
          'Esta captura tiene un conflicto pendiente. Revísalo antes de editar.',
        );
      }
      final merged = {...current.payload, ...changes};
      state = [
        for (final item in state)
          if (item.id == current.id)
            current.copyWith(payload: merged)
          else
            item,
      ];
      await _persist();
      return;
    }

    // Un identificador local nunca existe en Supabase. Si su INSERT ya salió
    // de la cola, crear un UPDATE separado solo produciría reintentos eternos.
    if (esIdSoloLocal(entityId)) {
      throw StateError(
        'Esta captura local ya no está disponible. Actualiza la lista e intenta de nuevo.',
      );
    }

    final now = DateTime.now();
    final item = SyncQueueItem(
      id: _uuid.v4(),
      operation: SyncOperation.update,
      table: table,
      payload: {'id': entityId, 'changes': changes},
      createdAt: now,
      updatedAt: now,
      ownerId: currentOwner,
    );
    state = [...state, item];
    await _persist();
  }

  /// Procesa toda la cola pendiente usando los [executors] disponibles
  /// (uno por tabla). Devuelve cuántos ítems se sincronizaron con éxito.
  Future<int> processPending(
    Map<String, SyncExecutor> executors, {
    bool Function()? canContinue,
  }) async {
    if (_processing) return 0;
    _processing = true;
    try {
      return await _processPending(executors, canContinue: canContinue);
    } finally {
      _processing = false;
    }
  }

  Future<int> _processPending(
    Map<String, SyncExecutor> executors, {
    bool Function()? canContinue,
  }) async {
    final expectedOwner = ownerId?.trim();
    if (expectedOwner == null || expectedOwner.isEmpty) return 0;
    var syncedCount = 0;
    final pending = state
        .where(
          (i) =>
              i.status == SyncStatus.pending || i.status == SyncStatus.failed,
        )
        .toList();

    for (final item in pending) {
      // Defensa ante un cambio de sesión durante el ciclo: un ítem nunca se
      // ejecuta si su propietario no coincide con el namespace activo.
      if (canContinue?.call() == false) break;
      if (item.ownerId != expectedOwner) {
        // No bloquear ítems válidos que estén más adelante por una fila
        // corrupta o legacy: queda fuera de ejecución y se continúa.
        continue;
      }
      final executor = executors[item.table];
      if (executor == null) continue;

      _updateItem(item.copyWith(status: SyncStatus.syncing));

      try {
        if (item.operation == SyncOperation.insert) {
          await executor.onInsert(item.payload);
        } else {
          await executor.onUpdate(item.payload);
        }
        state = state.where((i) => i.id != item.id).toList();
        syncedCount++;
        await _persist();
      } on SyncDiscardedException catch (e) {
        // El dato ya existe en el servidor: se retira igual que un éxito para
        // no dejar la cola atascada, pero no cuenta como sincronizado y se
        // guarda el motivo para avisar una sola vez.
        state = state.where((i) => i.id != item.id).toList();
        _descartes.add(e.message);
        await _persist();
      } on TerminalSyncConflictException catch (e) {
        _updateItem(
          item.copyWith(
            status: SyncStatus.conflict,
            retries: item.retries,
            lastError: e.conflict.message,
            conflict: e.conflict,
            conflictNotified: false,
          ),
        );
        await _persist();
      } on RetryableSyncException catch (e) {
        _updateItem(
          item.copyWith(
            status: SyncStatus.failed,
            retries: item.retries + 1,
            lastError: e.message,
            payload: {...item.payload, ...e.payloadPatch},
          ),
        );
        await _persist();
      } catch (e) {
        _updateItem(
          item.copyWith(
            status: SyncStatus.failed,
            retries: item.retries + 1,
            lastError: e.toString(),
          ),
        );
        await _persist();
      }
    }

    return syncedCount;
  }

  void _updateItem(SyncQueueItem updated) {
    state = [
      for (final item in state)
        if (item.id == updated.id) updated else item,
    ];
  }

  Future<void> clearSynced() async {
    state = state.where((i) => i.status != SyncStatus.synced).toList();
    await _persist();
  }

  Future<void> markConflictNotified(String itemId) async {
    final matches = state.where((i) => i.id == itemId);
    if (matches.isEmpty) return;
    final item = matches.first;
    if (item.status != SyncStatus.conflict) return;
    _updateItem(item.copyWith(conflictNotified: true));
    await _persist();
  }

  Future<SyncQueueItem?> discardConflict(String itemId) async {
    final matches = state.where(
      (i) => i.id == itemId && i.status == SyncStatus.conflict,
    );
    if (matches.isEmpty) return null;
    final item = matches.first;
    state = state.where((i) => i.id != itemId).toList();
    await _persist();
    return item;
  }
}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  return ref.watch(appBootstrapProvider).requireValue.sharedPreferences;
});

final syncQueueServiceProvider =
    StateNotifierProvider<SyncQueueService, List<SyncQueueItem>>((ref) {
      final ownerId = ref.watch(syncQueueActiveOwnerIdProvider);
      final service = SyncQueueService(
        ref.watch(sharedPreferencesProvider),
        ownerId,
      );
      service.migrateLegacyIfUnambiguous();
      return service;
    });

/// Identidad reactiva de la sesión. Al cambiar de A a B, Riverpod destruye la
/// cola/cache de A y crea instancias que solo leen el namespace de B.
final syncQueueOwnerIdProvider = StreamProvider<String?>((ref) async* {
  final client = ref.watch(supabaseClientProvider);
  yield client.auth.currentUser?.id;
  await for (final state in client.auth.onAuthStateChange) {
    yield state.session?.user.id;
  }
});

final syncQueueActiveOwnerIdProvider = Provider<String?>((ref) {
  return ref.watch(syncQueueOwnerIdProvider).valueOrNull ??
      ref.watch(supabaseClientProvider).auth.currentUser?.id;
});

final pendingSyncCountProvider = Provider<int>((ref) {
  List<SyncQueueItem> items;
  try {
    items = ref.watch(syncQueueServiceProvider);
  } catch (_) {
    // Algunos widgets reutilizables se prueban sin bootstrap de Supabase ni
    // SharedPreferences. En la app real ambos providers se inicializan en main.
    return 0;
  }
  return items
      .where(
        (i) =>
            i.status == SyncStatus.pending ||
            i.status == SyncStatus.syncing ||
            i.status == SyncStatus.failed,
      )
      .length;
});

/// `true` mientras la cola está enviando algo al servidor.
final syncEnCursoProvider = Provider<bool>((ref) {
  try {
    return ref
        .watch(syncQueueServiceProvider)
        .any((i) => i.status == SyncStatus.syncing);
  } catch (_) {
    return false;
  }
});

/// Avisos de capturas omitidas por estar ya en el servidor.
final syncDescartesProvider = Provider<List<String>>((ref) {
  try {
    ref.watch(syncQueueServiceProvider);
    return ref.read(syncQueueServiceProvider.notifier).descartes;
  } catch (_) {
    return const [];
  }
});

final syncConflictsProvider = Provider<List<SyncQueueItem>>((ref) {
  try {
    return ref
        .watch(syncQueueServiceProvider)
        .where((i) => i.status == SyncStatus.conflict)
        .toList();
  } catch (_) {
    return const [];
  }
});
