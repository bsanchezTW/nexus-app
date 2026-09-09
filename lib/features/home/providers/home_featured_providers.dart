import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Ítems del header del home: fijados primero; el próximo evento al final.
///
/// El resultado ya ensamblado se respalda en disco: son media docena de
/// consultas encadenadas y sin red no hay forma de rehacerlas, así que el
/// slider se serviría vacío justo en la pantalla de entrada.
///
/// Con copia en disco el carrusel se pinta al instante y el ensamblado va por
/// detrás. Antes ese ensamblado tenía 20 s de presupuesto **antes** de pintar:
/// abrir el home costaba la cadena completa de consultas incluso con la caché
/// llena, y sin red se esperaba el timeout entero para acabar mostrando
/// exactamente lo que ya estaba guardado.
final homeFeaturedItemsProvider =
    FutureProvider.autoDispose<List<HomeFeaturedItem>>((ref) async {
      final items = await leerCacheFirstConRef(
        ref: ref,
        tabla: OfflineCacheTables.homeDestacados,
        desdeServidor: () => _construirDestacados(ref),
        aFila: (item) => item.toCacheMap(),
        desdeFila: HomeFeaturedItem.fromCacheMap,
      );
      final perfil = await ref.watch(currentPerfilProvider.future);
      if (perfil == null) return const [];
      if (!perfil.requiresEventAssignment) return items;

      final campanasAutorizadas = (await ref.watch(
        eventosLeadsListProvider.future,
      )).map((actividad) => actividad.id).toSet();
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

Future<List<HomeFeaturedItem>> _construirDestacados(Ref ref) async {
  ref.watch(authStateChangesProvider);
  // Dependencias para refrescar al fijar/desfijar.
  await ref.watch(eventosFijadosProvider.future);
  await ref.watch(campanasFijadasProvider.future);

  final fijadosRepo = ref.watch(fijadosRepositoryProvider);
  final eventoIds = await fijadosRepo.listarEventosFijadosOrdenados();
  final campanaIds = await fijadosRepo.listarCampanasFijadasOrdenadas();
  final dashboard = await ref.watch(homeDashboardProvider.future);
  final campanas = await ref.watch(eventosLeadsListProvider.future);
  final proximo = elegirProximoDestacado(
    evento: dashboard.proximoEvento,
    actividad: proximaActividadVigente(campanas),
  );
  final fijados = <HomeFeaturedItem>[];

  if (eventoIds.isNotEmpty || campanaIds.isNotEmpty) {
    final eventosRepo = ref.watch(eventosRepositoryProvider);
    final campanasRepo = ref.watch(eventosLeadsRepositoryProvider);

    for (final id in eventoIds) {
      try {
        final evento = await eventosRepo.obtenerPorId(id);
        fijados.add(HomeFeaturedItem.eventoFijado(evento));
      } catch (_) {
        // Evento borrado o inaccesible: omitir.
      }
    }
    for (final id in campanaIds) {
      try {
        final campana = await campanasRepo.obtenerPorId(id);
        fijados.add(HomeFeaturedItem.campanaFijada(campana));
      } catch (_) {
        // Evento de leads borrado o inaccesible: omitir.
      }
    }
  }

  final items = ensamblarHomeFeaturedItems(fijados: fijados, proximo: proximo);

  if (items.isEmpty) return items;

  final registradosRepo = ref.watch(registradosRepositoryProvider);
  final campanasRepo = ref.watch(eventosLeadsRepositoryProvider);
  final leadsRepo = ref.watch(leadsRepositoryProvider);
  return Future.wait(
    items.map(
      (item) => _conMetricas(
        item: item,
        registradosRepo: registradosRepo,
        campanasRepo: campanasRepo,
        leadsRepo: leadsRepo,
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
      return item.copyWith(leads: resumen.total);
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
