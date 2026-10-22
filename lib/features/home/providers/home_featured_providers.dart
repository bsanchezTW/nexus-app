import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/evento.dart';
import '../../../data/models/evento_lead.dart';
import '../../../data/offline/offline_cache_tables.dart';
import '../../../data/offline/offline_read_cache.dart';

import '../../../data/repositories/eventos_leads_repository.dart';
import '../../../data/repositories/eventos_repository.dart';
import '../../../data/repositories/fijados_repository.dart';
import '../../../data/repositories/leads_repository.dart';
import '../../../data/repositories/registrados_repository.dart';
import '../../auth/providers/auth_providers.dart';
import '../../capturador/providers/capturador_providers.dart';
import '../../fijados/providers/fijados_providers.dart';
import '../models/home_featured_item.dart';
import 'home_dashboard_providers.dart';

/// Ítems del header del home: fijados primero; el próximo evento y la próxima
/// actividad al final.
///
/// El resultado ya ensamblado se respalda en disco: son media docena de
/// consultas encadenadas y sin red no hay forma de rehacerlas, así que el
/// slider se serviría vacío justo en la pantalla de entrada.
///
/// Las dependencias (fijados, catálogo, actividades) se resuelven aquí, en el
/// build, y la consulta al servidor solo recibe valores y repositorios. Antes
/// la consulta hacía `ref.watch` por su cuenta: si el provider se reconstruía
/// mientras corría —lo normal al abrir la app, cuando el catálogo cambia— usaba
/// un `ref` ya destruido, fallaba en silencio y el carrusel quedaba congelado
/// en la copia del disco ("Todo tranquilo por aquí" con eventos en curso).
final homeFeaturedItemsProvider =
    FutureProvider.autoDispose<List<HomeFeaturedItem>>((ref) async {
      ref.watch(authStateChangesProvider);
      final perfil = await ref.watch(currentPerfilProvider.future);
      if (perfil == null) return const [];

      // Dependencias para refrescar al fijar/desfijar.
      await ref.watch(eventosFijadosProvider.future);
      await ref.watch(campanasFijadasProvider.future);
      final dashboard = await ref.watch(homeDashboardProvider.future);
      final campanas = await ref.watch(eventosLeadsListProvider.future);
      final repos = _ReposDestacados(
        fijados: ref.watch(fijadosRepositoryProvider),
        eventos: ref.watch(eventosRepositoryProvider),
        campanas: ref.watch(eventosLeadsRepositoryProvider),
        registrados: ref.watch(registradosRepositoryProvider),
        leads: ref.watch(leadsRepositoryProvider),
      );

      final items = await leerCacheFirstConRef(
        ref: ref,
        tabla: OfflineCacheTables.homeDestacados,
        desdeServidor: () => _construirDestacados(
          repos: repos,
          proximoEvento: dashboard.proximoEvento,
          campanas: campanas,
        ),
        aFila: (item) => item.toCacheMap(),
        desdeFila: HomeFeaturedItem.fromCacheMap,
      );
      if (!perfil.requiresEventAssignment) return items;

      final campanasAutorizadas = campanas
          .map((actividad) => actividad.id)
          .toSet();
      final visibles = items
          .where(
            (item) =>
                !item.esActividadCaptura ||
                campanasAutorizadas.contains(item.id),
          )
          .toList();
      if (visibles.length != items.length) {
        await ref
            .read(offlineReadCacheProvider)
            .guardarGlobal(
              OfflineCacheTables.homeDestacados,
              visibles.map((item) => item.toCacheMap()).toList(),
            );
      }
      return visibles;
    });

class _ReposDestacados {
  const _ReposDestacados({
    required this.fijados,
    required this.eventos,
    required this.campanas,
    required this.registrados,
    required this.leads,
  });

  final FijadosRepository fijados;
  final EventosRepository eventos;
  final EventosLeadsRepository campanas;
  final RegistradosRepository registrados;
  final LeadsRepository leads;
}

/// Ensamblado contra el servidor. No toca `ref`: corre también por detrás,
/// cuando el provider que la lanzó puede ya no existir.
Future<List<HomeFeaturedItem>> _construirDestacados({
  required _ReposDestacados repos,
  required Evento? proximoEvento,
  required List<EventoLead> campanas,
}) async {
  final (eventoIds, campanaIds) = await (
    repos.fijados.listarEventosFijadosOrdenados(),
    repos.fijados.listarCampanasFijadasOrdenadas(),
  ).wait;
  final proximos = elegirProximosDestacados(
    evento: proximoEvento,
    actividad: proximaActividadVigente(campanas),
  );

  // En paralelo y en orden: cada fijado inaccesible (borrado o sin permiso)
  // se omite sin frenar a los demás.
  final fijados = (await Future.wait([
    for (final id in eventoIds)
      repos.eventos
          .obtenerPorId(id)
          .then<HomeFeaturedItem?>(HomeFeaturedItem.eventoFijado)
          .catchError((Object _) => null),
    for (final id in campanaIds)
      repos.campanas
          .obtenerPorId(id)
          .then<HomeFeaturedItem?>(HomeFeaturedItem.campanaFijada)
          .catchError((Object _) => null),
  ])).whereType<HomeFeaturedItem>().toList();

  final items = ensamblarHomeFeaturedItems(
    fijados: fijados,
    proximos: proximos,
  );

  if (items.isEmpty) return items;

  return Future.wait(
    items.map(
      (item) => _conMetricas(
        item: item,
        registradosRepo: repos.registrados,
        campanasRepo: repos.campanas,
        leadsRepo: repos.leads,
      ),
    ),
  );
}

Future<HomeFeaturedItem> _conMetricas({
  required HomeFeaturedItem item,
  required RegistradosRepository registradosRepo,
  required EventosLeadsRepository campanasRepo,
  required LeadsRepository leadsRepo,
}) async {
  try {
    if (item.esActividadCaptura) {
      final resumen = await leadsRepo.obtenerResumenCampana(item.id);
      return item.copyWith(leads: resumen.total, empresas: resumen.empresas);
    }

    final resumen = await registradosRepo.obtenerResumenPorEvento(item.id);
    var leads = 0;
    try {
      // El homónimo solo cubre los eventos de leads anteriores al vínculo por
      // id, que no tienen `evento_origen_id`.
      final eventoLead =
          await campanasRepo.buscarPorEventoOrigen(item.id) ??
          await campanasRepo.buscarPorNombre(item.nombre);
      if (eventoLead != null) {
        leads = (await leadsRepo.obtenerResumenCampana(eventoLead.id)).total;
      }
    } catch (_) {
      // Sin evento de leads asociado o sin permiso: leads queda en 0.
    }
    return item.copyWith(
      registrados: resumen.total,
      acreditados: resumen.acreditados,
      leads: leads,
    );
  } catch (_) {
    return item;
  }
}
