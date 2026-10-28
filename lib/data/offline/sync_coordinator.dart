import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/supabase_tables.dart';
import '../../core/conexion/estado_conexion.dart';
import '../../core/conexion/monitor_conexion.dart';
import '../repositories/inscripciones_subevento_repository.dart';
import '../repositories/leads_repository.dart';
import '../repositories/registrados_repository.dart';
import '../repositories/storage_cleanup_service.dart';
import '../supabase/supabase_client_provider.dart';
import 'offline_read_cache.dart';
import 'sync_queue_service.dart';

/// Punto único donde se registran los [SyncExecutor] de cada dominio.
///
/// Esto reemplaza los múltiples listeners sueltos que había en el proyecto
/// legado (`_layout.tsx`, `index.tsx`, `usar-app.tsx`, `ver-registrados.tsx`
/// llamaban `procesarColaOffline()` cada uno por su cuenta, apuntando a una
/// cola que además tenía el bug de la clave equivocada — ver Sección 17.3).
///
/// Cuándo vaciar la cola no lo decide este coordinador sino
/// `orquestadorReconexionProvider`, que lo hace al confirmar una conexión
/// estable. Aquí solo queda el cambio de sesión: la cola nueva puede traer
/// pendientes de una sesión anterior de la misma cuenta.
class SyncCoordinator {
  SyncCoordinator(this._ref) {
    _ref.listen(syncQueueActiveOwnerIdProvider, (previous, next) {
      if (next != null && next.isNotEmpty && next != previous) {
        if (_ref.read(estadoConexionProvider) == EstadoConexion.estable) {
          sincronizarAhora();
        }
      }
    });
  }

  final Ref _ref;

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
        // Lo subido ya es del servidor: las listas tienen que mostrarlo desde
        // ahí y no desde la cola, que acaba de vaciarse.
        exigirLecturaDelServidor(_ref.read(epocaServidorProvider.notifier));
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
/// `app.dart`), para que el listener de sesión quede activo durante toda la
/// vida de la app.
final syncCoordinatorInitializerProvider = Provider<void>((ref) {
  ref.watch(syncCoordinatorProvider);
});
