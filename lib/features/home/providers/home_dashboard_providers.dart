import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/connectivity_service.dart';
import '../../../data/models/evento.dart';
import '../../../data/models/evento_lead.dart';
import '../../../data/offline/offline_cache_tables.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/repositories/registrados_repository.dart';
import '../../capturador/providers/capturador_providers.dart';
import '../../eventos/providers/eventos_providers.dart';

class HomeDashboardData {
  const HomeDashboardData({
    required this.eventos,
    this.actividades = const [],
    required this.totalRegistrados,
    required this.totalAcreditados,
  });

  final List<Evento> eventos;
  final List<EventoLead> actividades;
  final int totalRegistrados;
  final int totalAcreditados;

  /// No finalizados. La fecha (y la duración en actividades) cierra el evento.
  int get eventosActivos =>
      eventos.where((e) => !e.yaOcurrio).length +
      actividades.where((a) => !a.yaOcurrio).length;

  int get eventosEsteMes {
    final hoy = DateTime.now();
    return eventos.where((e) => e.cubreMes(hoy)).length;
  }

  double get porcentajeAcreditacion =>
      totalRegistrados == 0 ? 0 : totalAcreditados / totalRegistrados;

  List<Evento> get proximosEventos {
    final lista = eventos.where((e) => !e.yaOcurrio).toList()
      ..sort((a, b) => a.fecha.compareTo(b.fecha));
    return lista;
  }

  Evento? get proximoEvento =>
      proximosEventos.isEmpty ? null : proximosEventos.first;

  List<Evento> eventosEnMes(DateTime mes) {
    return eventos.where((e) => e.cubreMes(mes)).toList();
  }

  List<Evento> eventosEnDia(DateTime dia) {
    return eventos.where((e) => e.cubreDia(dia)).toList();
  }
}

/// Conteos globales de registrados/acreditados, cacheados aparte del catálogo.
class _ResumenGlobal {
  const _ResumenGlobal({required this.total, required this.acreditados});

  final int total;
  final int acreditados;

  factory _ResumenGlobal.fromMap(Map<String, dynamic> map) {
    return _ResumenGlobal(
      total: (map['total'] as num?)?.toInt() ?? 0,
      acreditados: (map['acreditados'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toCacheMap() => {
    'total': total,
    'acreditados': acreditados,
  };
}

/// Home del interno. Reutiliza [eventosListProvider] —que ya respalda el
/// catálogo en disco— en vez de repetir la llamada, y cachea aparte el
/// resumen global. Sin esto el home mostraba error sin red aunque el catálogo
/// estuviera guardado.
final homeDashboardProvider = FutureProvider.autoDispose<HomeDashboardData>((
  ref,
) async {
  final eventos = await ref.watch(eventosListProvider.future);
  final actividades = await ref.watch(eventosLeadsListProvider.future);
  final isOnline = ref.read(isOnlineProvider);
  final repo = ref.watch(registradosRepositoryProvider);

  var resumen = const _ResumenGlobal(total: 0, acreditados: 0);
  try {
    final filas = await leerCacheFirstConRef(
      ref: ref,
      tabla: OfflineCacheTables.homeResumen,
      desdeServidor: () async {
        final remoto = await repo.obtenerResumenGlobal();
        return [
          _ResumenGlobal(total: remoto.total, acreditados: remoto.acreditados),
        ];
      },
      aFila: (r) => r.toCacheMap(),
      desdeFila: _ResumenGlobal.fromMap,
    );
    if (filas.isNotEmpty) resumen = filas.first;
  } catch (error) {
    // El catálogo ya se resolvió: mejor un home con eventos y contadores en
    // cero que una pantalla de error entera.
    if (isOnline && !isNetworkTransportError(error)) rethrow;
  }

  return HomeDashboardData(
    eventos: eventos,
    actividades: actividades,
    totalRegistrados: resumen.total,
    totalAcreditados: resumen.acreditados,
  );
});
