import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/supabase_tables.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../data/offline/offline_cache_tables.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/offline/sync_queue_item.dart';
import '../../../data/offline/sync_queue_service.dart';
import '../../../data/repositories/leads_repository.dart';
import '../../auth/providers/auth_providers.dart';

class ExternoDashboardData {
  const ExternoDashboardData({
    required this.eventosAutorizados,
    required this.leadsCapturados,
    this.esResumenParcial = false,
  });

  final int eventosAutorizados;
  final int leadsCapturados;
  final bool esResumenParcial;
}

/// Cuenta eventos sin duplicar el evento preferido legado. Algunos perfiles
/// antiguos solo conservan `evento_asignado_id` y todavía no tienen filas en
/// `usuarios_eventos`; para ellos el acceso vigente debe seguir contando.
int contarEventosConAcceso(
  Iterable<String> eventosAutorizadosIds, {
  String? eventoAsignadoId,
}) {
  final ids = eventosAutorizadosIds.where((id) => id.isNotEmpty).toSet();
  final asignado = eventoAsignadoId?.trim();
  if (asignado != null && asignado.isNotEmpty) ids.add(asignado);
  return ids.length;
}

/// Cuenta inserts locales que todavía no pueden estar reflejados en el
/// servidor. Los ítems `syncing` se excluyen para no contar dos veces durante
/// la pequeña ventana entre el INSERT remoto y su retiro de la cola.
int contarLeadsPendientesPorPerfil(
  Iterable<SyncQueueItem> items,
  String perfilId,
) {
  return items.where((item) {
    final pendienteLocal =
        item.status == SyncStatus.pending || item.status == SyncStatus.failed;
    final serverLeadId = item.payload['_server_lead_id']?.toString().trim();
    return item.table == SupabaseTables.leads &&
        item.operation == SyncOperation.insert &&
        pendienteLocal &&
        (serverLeadId == null || serverLeadId.isEmpty) &&
        item.payload['perfil_id'] == perfilId;
  }).length;
}

/// Resumen estrictamente personal para la vista operativa del usuario externo.
///
/// El total remoto de leads está acotado por `perfil_id`; a ese valor se suman
/// únicamente inserts offline del mismo perfil que aún no comenzaron a
/// sincronizarse.
final externoDashboardProvider =
    FutureProvider.autoDispose<ExternoDashboardData>((ref) async {
      final queueItems = ref.watch(syncQueueServiceProvider);
      final leadsRepository = ref.watch(leadsRepositoryProvider);
      final perfil = await ref.watch(currentPerfilProvider.future);
      final estaOnline = ref.watch(usaServidorProvider);

      if (perfil == null || !perfil.isExterno) {
        return const ExternoDashboardData(
          eventosAutorizados: 0,
          leadsCapturados: 0,
        );
      }

      final eventosAsync = ref.watch(externoEventosAutorizadosProvider);
      final leadsPendientes = contarLeadsPendientesPorPerfil(
        queueItems,
        perfil.id,
      );
      final cache = ref.watch(offlineReadCacheProvider);
      var leadsRemotos = 0;
      var esResumenParcial = !estaOnline;

      if (estaOnline) {
        try {
          leadsRemotos = await leadsRepository.contarPorPerfil(perfil.id);
          await cache.guardarGlobal(OfflineCacheTables.externoResumen, [
            {'leads': leadsRemotos},
          ]);
        } catch (_) {
          // El dashboard sigue siendo útil sin red: muestra el mínimo conocido
          // por la cola local y señala que el resumen es parcial.
          esResumenParcial = true;
        }
      }

      if (leadsRemotos == 0) {
        // Sin red, el último total conocido es mejor que un cero que parece
        // "no has capturado nada". Sigue marcándose como parcial porque la
        // cola local puede tener capturas que el servidor aún no vio.
        final local = cache.leerGlobal(
          tabla: OfflineCacheTables.externoResumen,
          desdeFila: (fila) => (fila['leads'] as num?)?.toInt() ?? 0,
        );
        if (local != null && local.isNotEmpty) leadsRemotos = local.first;
      }

      final eventos = eventosAsync.valueOrNull ?? const [];

      return ExternoDashboardData(
        eventosAutorizados: contarEventosConAcceso(
          eventos.map((evento) => evento.id),
          eventoAsignadoId: perfil.eventoAsignadoId,
        ),
        leadsCapturados: leadsRemotos + leadsPendientes,
        esResumenParcial: esResumenParcial,
      );
    });
