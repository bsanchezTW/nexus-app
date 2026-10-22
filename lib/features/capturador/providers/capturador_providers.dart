import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/supabase_tables.dart';
import '../../../data/models/evento_lead.dart';
import '../../../data/models/lead.dart';
import '../../../data/models/lead_comentario.dart';
import '../../../data/models/perfil.dart';
import '../../../data/offline/offline_cache_tables.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/offline/sync_queue_item.dart';
import '../../../data/offline/sync_queue_service.dart';
import '../../../data/repositories/eventos_leads_repository.dart';
import '../../../data/repositories/lead_comentarios_repository.dart';
import '../../../data/repositories/leads_repository.dart';
import '../../auth/providers/auth_providers.dart';

class _AlcanceActividadesCaptura {
  const _AlcanceActividadesCaptura.global()
    : sinRestriccion = true,
      eventosAutorizados = const {};

  const _AlcanceActividadesCaptura.restringido(this.eventosAutorizados)
    : sinRestriccion = false;

  final bool sinRestriccion;
  final Set<String> eventosAutorizados;

  bool permite(EventoLead actividad) {
    if (sinRestriccion) return true;
    final origen = actividad.eventoOrigenId;
    return origen == null || eventosAutorizados.contains(origen);
  }
}

/// Segunda barrera de la app para no pintar datos antiguos del disco antes de
/// que Supabase revalide. Las actividades externas son globales; solo las
/// internas se autorizan por `evento_origen_id`. El nombre no otorga acceso.
List<EventoLead> filtrarActividadesCapturaAutorizadas({
  required Perfil? perfil,
  required Set<String> eventosAutorizados,
  required Iterable<EventoLead> actividades,
}) {
  if (perfil == null) return const [];
  if (!perfil.requiresEventAssignment) return actividades.toList();
  return actividades.where((actividad) {
    final origen = actividad.eventoOrigenId;
    return origen == null || eventosAutorizados.contains(origen);
  }).toList();
}

Future<_AlcanceActividadesCaptura> _resolverAlcanceCaptura(Ref ref) async {
  final perfil = await ref.watch(currentPerfilProvider.future);
  if (perfil == null) {
    return const _AlcanceActividadesCaptura.restringido({});
  }
  if (!perfil.requiresEventAssignment) {
    return const _AlcanceActividadesCaptura.global();
  }
  if (perfil.rol.isUsuario) {
    final ids = await ref.watch(usuarioEventosAutorizadosProvider.future);
    return _AlcanceActividadesCaptura.restringido(ids);
  }
  final eventos = await ref.watch(externoEventosAutorizadosProvider.future);
  return _AlcanceActividadesCaptura.restringido(
    eventos.map((evento) => evento.id).toSet(),
  );
}

Future<void> _purgarActividadesSinAcceso({
  required OfflineReadCache cache,
  required List<EventoLead> visibles,
}) async {
  final campanas = visibles.map((actividad) => actividad.id).toSet();
  final origenes = visibles
      .map((actividad) => actividad.eventoOrigenId)
      .whereType<String>()
      .toSet();
  await cache.retenerEventos(OfflineCacheTables.eventoLeadDetalle, campanas);
  await cache.retenerEventos(leadsCacheTabla(true), campanas);
  await cache.retenerEventos(leadsCacheTabla(false), campanas);
  await cache.retenerEventos(leadsResumenCacheTabla, campanas);
  await cache.retenerEventos(OfflineCacheTables.eventoLeadPorOrigen, origenes);
}

/// Catálogo de actividades de captura, con respaldo en disco.
final eventosLeadsListProvider = FutureProvider.autoDispose<List<EventoLead>>((
  ref,
) async {
  final cache = ref.watch(offlineReadCacheProvider);
  final repo = ref.watch(eventosLeadsRepositoryProvider);
  final perfil = await ref.watch(currentPerfilProvider.future);
  final alcance = await _resolverAlcanceCaptura(ref);

  final actividades = await leerCacheFirstConRef(
    ref: ref,
    tabla: OfflineCacheTables.eventosLeads,
    desdeServidor: () async {
      final remotas = await repo.listarTodos();
      final visibles = filtrarActividadesCapturaAutorizadas(
        perfil: perfil,
        eventosAutorizados: alcance.eventosAutorizados,
        actividades: remotas,
      );
      for (final actividad in visibles) {
        await cache.guardar(
          OfflineCacheTables.eventoLeadDetalle,
          actividad.id,
          [actividad.toCacheMap()],
        );
        final origen = actividad.eventoOrigenId;
        if (origen != null && origen.isNotEmpty) {
          await cache.guardar(OfflineCacheTables.eventoLeadPorOrigen, origen, [
            actividad.toCacheMap(),
          ]);
        }
      }
      return visibles;
    },
    aFila: (actividad) => actividad.toCacheMap(),
    desdeFila: EventoLead.fromMap,
  );

  final visibles = filtrarActividadesCapturaAutorizadas(
    perfil: perfil,
    eventosAutorizados: alcance.eventosAutorizados,
    actividades: actividades,
  );
  if (!alcance.sinRestriccion) {
    if (visibles.length != actividades.length) {
      await cache.guardarGlobal(
        OfflineCacheTables.eventosLeads,
        visibles.map((actividad) => actividad.toCacheMap()).toList(),
      );
    }
    await _purgarActividadesSinAcceso(cache: cache, visibles: visibles);
  }
  return visibles;
});

final eventoLeadByIdProvider = FutureProvider.autoDispose
    .family<EventoLead, String>((ref, id) async {
      final repo = ref.watch(eventosLeadsRepositoryProvider);
      final cache = ref.watch(offlineReadCacheProvider);
      final alcance = await _resolverAlcanceCaptura(ref);

      final filas = await leerCacheFirstConRef(
        ref: ref,
        tabla: OfflineCacheTables.eventoLeadDetalle,
        eventoId: id,
        desdeServidor: () async => [await repo.obtenerPorId(id)],
        aFila: (actividad) => actividad.toCacheMap(),
        desdeFila: EventoLead.fromMap,
      );
      if (filas.isEmpty) throw Exception('No se pudo cargar la actividad.');
      final actividad = filas.first;
      if (!alcance.permite(actividad)) {
        await cache.eliminarEvento(OfflineCacheTables.eventoLeadDetalle, id);
        await cache.eliminarEvento(leadsCacheTabla(true), id);
        await cache.eliminarEvento(leadsCacheTabla(false), id);
        await cache.eliminarEvento(leadsResumenCacheTabla, id);
        throw Exception('No tienes acceso a esta actividad.');
      }
      return actividad;
    });

/// Evento de leads interno de un evento de registro, o `null` si todavía no se
/// ha creado. El menú de Evento lo usa para ofrecer crearlo o abrirlo.
///
/// El vínculo se cachea porque sin red **no se puede crear** la actividad: si
/// el snapshot no la guardó, capturar un lead desde ese evento es imposible y
/// hay que decirlo, no fallar en silencio.
final eventoLeadInternoProvider = FutureProvider.autoDispose
    .family<EventoLead?, String>((ref, eventoOrigenId) async {
      final repo = ref.watch(eventosLeadsRepositoryProvider);
      final cache = ref.watch(offlineReadCacheProvider);
      final alcance = await _resolverAlcanceCaptura(ref);
      if (!alcance.sinRestriccion &&
          !alcance.eventosAutorizados.contains(eventoOrigenId)) {
        await cache.eliminarEvento(
          OfflineCacheTables.eventoLeadPorOrigen,
          eventoOrigenId,
        );
        return null;
      }

      final filas = await leerCacheFirstConRef(
        ref: ref,
        tabla: OfflineCacheTables.eventoLeadPorOrigen,
        eventoId: eventoOrigenId,
        desdeServidor: () async {
          final actividad = await repo.buscarPorEventoOrigen(eventoOrigenId);
          return actividad == null ? <EventoLead>[] : [actividad];
        },
        aFila: (actividad) => actividad.toCacheMap(),
        desdeFila: EventoLead.fromMap,
      );
      return filas.isEmpty ? null : filas.first;
    });

Iterable<SyncQueueItem> leadQueueItemsForOverlay(
  Iterable<SyncQueueItem> items,
) {
  return items.where(
    (item) =>
        item.table == SupabaseTables.leads &&
        item.status != SyncStatus.conflict &&
        item.status != SyncStatus.synced,
  );
}

List<Lead> fusionarLeadsConCola({
  required List<Lead> servidor,
  required Iterable<SyncQueueItem> colaDeLeads,
  required String eventoId,
}) {
  final inserts = colaDeLeads
      .where(
        (item) =>
            item.operation == SyncOperation.insert &&
            item.payload['evento_id'] == eventoId,
      )
      .map(
        (i) => Lead.fromMap({
          ...i.payload,
          'id': i.id,
        }).copyWith(pendienteDeSincronizar: true),
      )
      .toList();

  final cambiosPorId = <String, Map<String, dynamic>>{};
  for (final item in colaDeLeads) {
    if (item.operation != SyncOperation.update) continue;
    final id = item.payload['id'] as String;
    cambiosPorId[id] = {
      ...?cambiosPorId[id],
      ...Map<String, dynamic>.from(item.payload['changes'] as Map),
    };
  }

  final servidorConCambios = servidor
      // Borrado sin red: desaparece ya, aunque el servidor aún no lo sepa.
      .where((lead) => cambiosPorId[lead.id]?[campoLeadEliminadoAt] == null)
      .map((lead) {
        final cambios = cambiosPorId[lead.id];
        return cambios == null ? lead : lead.conCambiosPendientes(cambios);
      })
      .toList();

  return [...inserts, ...servidorConCambios];
}

class LeadsResumen {
  const LeadsResumen({required this.total, required this.empresas});

  final int total;
  final int empresas;

  factory LeadsResumen.fromMap(Map<String, dynamic> map) {
    return LeadsResumen(
      total: (map['total'] as num?)?.toInt() ?? 0,
      empresas: (map['empresas'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toCacheMap() => {'total': total, 'empresas': empresas};
}

String leadsCacheTabla(bool canViewAllLeads) =>
    '${SupabaseTables.leads}__${canViewAllLeads ? 'all' : 'own'}';

const leadsResumenCacheTabla = '${SupabaseTables.leads}__campana_resumen';

LeadsResumen resumenDesdeLeads(Iterable<Lead> leads) {
  return LeadsResumen(
    total: leads.length,
    empresas: leads
        .where((lead) => (lead.empresa ?? '').trim().isNotEmpty)
        .length,
  );
}

LeadsResumen aplicarColaAResumen({
  required LeadsResumen base,
  required Iterable<SyncQueueItem> cola,
  required String eventoId,
}) {
  final inserts = leadQueueItemsForOverlay(cola).where(
    (item) =>
        item.operation == SyncOperation.insert &&
        item.payload['evento_id'] == eventoId,
  );
  var extraTotal = 0;
  var extraEmpresas = 0;
  for (final item in inserts) {
    extraTotal++;
    if ((item.payload['empresa'] as String? ?? '').trim().isNotEmpty) {
      extraEmpresas++;
    }
  }
  if (extraTotal == 0) return base;
  return LeadsResumen(
    total: base.total + extraTotal,
    empresas: base.empresas + extraEmpresas,
  );
}

/// RPC de conteos del evento de leads. Lo puede pedir todo el que lo abre
/// —incluido el externo autorizado—, porque devuelve conteos y no filas: el
/// recorte a "mis leads" es de la lista, no del resumen. Se cachea sin PII.
final leadsResumenRemotoProvider = FutureProvider.autoDispose
    .family<LeadsResumen, String>((ref, eventoId) async {
      await ref.watch(eventoLeadByIdProvider(eventoId).future);
      final perfil = await ref.watch(currentPerfilProvider.future);
      if (perfil == null) {
        return const LeadsResumen(total: 0, empresas: 0);
      }
      final repo = ref.watch(leadsRepositoryProvider);
      final filas = await leerCacheFirstConRef(
        ref: ref,
        tabla: leadsResumenCacheTabla,
        eventoId: eventoId,
        desdeServidor: () async {
          final remoto = await repo.obtenerResumenCampana(eventoId);
          return [LeadsResumen(total: remoto.total, empresas: remoto.empresas)];
        },
        aFila: (resumen) => resumen.toCacheMap(),
        desdeFila: LeadsResumen.fromMap,
      );
      return filas.isEmpty
          ? const LeadsResumen(total: 0, empresas: 0)
          : filas.first;
    });

/// Conteos del hub: RPC del evento de leads para internos, con cola local.
final leadsResumenLocalProvider = Provider.autoDispose
    .family<LeadsResumen?, String>((ref, eventoId) {
      final perfil = ref.watch(currentPerfilProvider).valueOrNull;
      if (perfil == null) return null;

      final cola = leadQueueItemsForOverlay(
        ref.watch(syncQueueServiceProvider),
      );
      final cache = ref.watch(offlineReadCacheProvider);

      final remoto = ref
          .watch(leadsResumenRemotoProvider(eventoId))
          .valueOrNull;
      final cacheados = cache.leerLocal(
        tabla: leadsResumenCacheTabla,
        eventoId: eventoId,
        desdeFila: LeadsResumen.fromMap,
      );
      final cacheado = cacheados == null || cacheados.isEmpty
          ? null
          : cacheados.first;
      if (remoto != null) {
        return aplicarColaAResumen(
          base: remoto,
          cola: cola,
          eventoId: eventoId,
        );
      }

      // Un resumen remoto ya pasó por el RPC autorizado. Para reconstruirlo
      // desde datos del disco, en cambio, los roles acotados deben haber
      // validado primero la actividad contra su evento asignado.
      if (perfil.requiresEventAssignment) {
        final actividad = ref.watch(eventoLeadByIdProvider(eventoId));
        if (!actividad.hasValue) return null;
      }

      if (cacheado != null) {
        return aplicarColaAResumen(
          base: cacheado,
          cola: cola,
          eventoId: eventoId,
        );
      }

      // Sin resumen del servidor se cuenta la caché de leads de la campaña.
      // Todos los roles ven ese listado; el externo queda acotado por RLS.
      if (!perfil.canViewAllLeads) return null;

      final local = cache.leerLocal(
        tabla: leadsCacheTabla(true),
        eventoId: eventoId,
        desdeFila: Lead.fromMap,
      );
      final fusionados = fusionarLeadsConCola(
        servidor: local ?? const [],
        colaDeLeads: cola,
        eventoId: eventoId,
      );
      if (local == null && fusionados.isEmpty) return null;
      return resumenDesdeLeads(fusionados);
    });

/// Combina los leads del servidor con lo que sigue pendiente en la cola
/// offline (inserts y updates). Si el servidor no responde se sirve la última
/// copia en caché, para que la lista y el detalle funcionen sin conexión.
final leadsPorEventoProvider = FutureProvider.autoDispose
    .family<List<Lead>, String>((ref, eventoId) async {
      await ref.watch(eventoLeadByIdProvider(eventoId).future);
      final repo = ref.watch(leadsRepositoryProvider);
      final perfil = await ref.watch(currentPerfilProvider.future);
      if (perfil == null) return const [];
      final cacheTabla = leadsCacheTabla(perfil.canViewAllLeads);

      final cache = ref.watch(offlineReadCacheProvider);
      final servidor = await leerCacheFirstConRef(
        ref: ref,
        tabla: cacheTabla,
        eventoId: eventoId,
        desdeServidor: () => perfil.canViewAllLeads
            ? repo.listarPorEvento(eventoId)
            : repo.listarPorEventoYPerfil(eventoId, perfil.id),
        aFila: (lead) => lead.toCacheMap(),
        desdeFila: Lead.fromMap,
      );
      final servidorVisible = perfil.canViewAllLeads
          ? servidor
          : servidor.where((lead) => lead.perfilId == perfil.id).toList();
      if (!perfil.canViewAllLeads &&
          servidorVisible.length != servidor.length) {
        await cache.guardar(
          cacheTabla,
          eventoId,
          servidorVisible.map((lead) => lead.toCacheMap()).toList(),
        );
      }

      return fusionarLeadsConCola(
        servidor: servidorVisible,
        colaDeLeads: leadQueueItemsForOverlay(
          ref.watch(syncQueueServiceProvider),
        ),
        eventoId: eventoId,
      );
    });

final comentariosPorLeadProvider = FutureProvider.autoDispose
    .family<List<LeadComentario>, String>((ref, leadId) async {
      return ref.watch(leadComentariosRepositoryProvider).listar(leadId);
    });
