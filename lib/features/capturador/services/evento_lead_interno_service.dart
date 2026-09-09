import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/connectivity_service.dart';
import '../../../core/network/offline_guard.dart';
import '../../../data/models/evento.dart';
import '../../../data/models/evento_lead.dart';
import '../../../data/offline/offline_cache_tables.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/repositories/eventos_leads_repository.dart';
import '../providers/capturador_providers.dart';

/// Actividad de captura interna de [evento]: la existente, o una nueva.
///
/// Crear una actividad **nunca** ocurre sin red. El id lo asigna el servidor y
/// todos los leads capturados cuelgan de él: inventar uno local dejaría las
/// capturas huérfanas y sin forma de reconciliarlas. Por eso sin conexión solo
/// se resuelve contra lo que el snapshot ya guardó, y si no está se dice
/// claramente en vez de fallar de forma opaca.
Future<EventoLead> obtenerOCrearEventoLeadInterno(
  WidgetRef ref,
  Evento evento,
) async {
  final repo = ref.read(eventosLeadsRepositoryProvider);
  final isOnline = ref.read(isOnlineProvider);

  EventoLead? existente;
  if (isOnline) {
    existente = await repo.buscarPorEventoOrigen(evento.id);
  } else {
    // Se lee el disco directamente y no `eventosLeadsListProvider`: ese
    // provider es autoDispose y puede no haberse construido en esta pantalla.
    final vinculo = ref
        .read(offlineReadCacheProvider)
        .leerLocal(
          tabla: OfflineCacheTables.eventoLeadPorOrigen,
          eventoId: evento.id,
          desdeFila: EventoLead.fromMap,
        );
    existente = vinculo?.firstOrNull;
    existente ??= (ref.read(eventosLeadsListProvider).valueOrNull ?? [])
        .where((e) => e.eventoOrigenId == evento.id)
        .firstOrNull;
  }

  if (existente != null) return existente;

  if (!isOnline) {
    throw Exception(kMensajeSinConexion);
  }

  final creado = await repo.crear(
    EventoLead.internoDesdeEvento(
      eventoOrigenId: evento.id,
      nombre: evento.nombre,
      fecha: evento.fecha,
      duracionDias: evento.duracionDias,
      pais: evento.pais,
      tematica: evento.tematica,
      certificacionCapacitacion: evento.certificacionCapacitacion,
      imagenUrl: evento.imagenUrl,
    ),
  );
  ref.invalidate(eventosLeadsListProvider);
  return creado;
}
