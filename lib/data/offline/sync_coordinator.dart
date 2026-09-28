import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/supabase_tables.dart';
import '../../core/network/connectivity_service.dart';
import '../repositories/inscripciones_subevento_repository.dart';
import '../repositories/leads_repository.dart';
import '../repositories/registrados_repository.dart';
import '../repositories/storage_cleanup_service.dart';
import '../supabase/supabase_client_provider.dart';
import 'sync_queue_service.dart';

/// Punto único donde se registran los [SyncExecutor] de cada dominio y se
/// dispara `processPending()` automáticamente al recuperar conexión.
///
/// Esto reemplaza los múltiples listeners sueltos que había en el proyecto
/// legado (`_layout.tsx`, `index.tsx`, `usar-app.tsx`, `ver-registrados.tsx`
/// llamaban `procesarColaOffline()` cada uno por su cuenta, apuntando a una
/// cola que además tenía el bug de la clave equivocada — ver Sección 17.3).
/// Acá hay un solo listener de conectividad para toda la app.
class SyncCoordinator {
  SyncCoordinator(this._ref) {
    _ref.listen<AsyncValue<bool>>(connectivityStreamProvider, (_, next) {
      final online = next.valueOrNull;
      if (online != null) _observarConexion(online);
    });
    _ref.listen(syncQueueActiveOwnerIdProvider, (previous, next) {
      if (next != null && next.isNotEmpty && next != previous) {
        final online = _ref.read(connectivityStreamProvider).valueOrNull;
        if (online == true) sincronizarAhora();
      }
    });

    // Si al construirse el estado de red ya estaba resuelto, el listener no
    // volvería a dispararse hasta el próximo cambio.
    final actual = _ref.read(connectivityStreamProvider).valueOrNull;
    if (actual != null) _observarConexion(actual);
  }

  final Ref _ref;

  bool? _ultimoEstadoOnline;

  /// Vacía la cola al recuperar la conexión y también la primera vez que se
  /// conoce el estado de red.
  ///
  /// Ese segundo caso importa: la cola sobrevive al cierre de la app en
  /// `SharedPreferences`, y si el usuario la reabre ya con señal nunca ocurre
  /// la transición offline→online. Sin esto, lo capturado sin conexión se
  /// quedaba esperando indefinidamente — el mismo síntoma que este módulo
  /// existe para evitar (Sección 17.3).
  void _observarConexion(bool online) {
    final esPrimeraLectura = _ultimoEstadoOnline == null;
    final recuperoConexion = _ultimoEstadoOnline == false;
    _ultimoEstadoOnline = online;

    if (online && (esPrimeraLectura || recuperoConexion)) {
      sincronizarAhora();
    }
  }

  Map<String, SyncExecutor> get _executors => {
    SupabaseTables.registrados: _ref.read(registradosRepositoryProvider),
    SupabaseTables.inscripcionesSubevento: _ref.read(
      inscripcionesSubeventoRepositoryProvider,
    ),
    SupabaseTables.leads: _ref.read(leadsRepositoryProvider),
  };

  Future<int> sincronizarAhora() async {
    final queue = _ref.read(syncQueueServiceProvider.notifier);
    final sessionOwner = _ref.read(syncQueueActiveOwnerIdProvider);
    if (sessionOwner == null || sessionOwner != queue.ownerId) return 0;
    try {
      final synced = await queue.processPending(
        _executors,
        canContinue: () =>
            _ref.read(supabaseClientProvider).auth.currentUser?.id ==
            queue.ownerId,
      );
      if (synced > 0) {
        // Una edición offline puede haber quitado o reemplazado la foto de un
        // lead. El trigger recién la encola cuando el UPDATE llega al servidor.
        await _ref.read(storageCleanupServiceProvider).drenar();
        developer.log(
          'Sincronizados $synced ítems pendientes.',
          name: 'SyncCoordinator',
        );
      }
      return synced;
    } catch (e) {
      developer.log(
        'Error sincronizando cola offline: $e',
        name: 'SyncCoordinator',
      );
      return 0;
    }
  }
}

final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  return SyncCoordinator(ref);
});

/// Debe leerse una vez, cerca de la raíz del árbol de widgets (ver
/// `app.dart`), para que el listener de conectividad quede activo durante
/// toda la vida de la app.
final syncCoordinatorInitializerProvider = Provider<void>((ref) {
  ref.watch(syncCoordinatorProvider);
});
