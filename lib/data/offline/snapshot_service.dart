import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/supabase_tables.dart';
import '../../core/network/connectivity_service.dart';
import '../../core/network/offline_policy.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/capturador/providers/capturador_providers.dart';
import '../../features/eventos/providers/eventos_providers.dart';
import '../../features/fijados/providers/fijados_providers.dart';
import '../../features/home/providers/home_dashboard_providers.dart';
import '../../features/home/providers/home_featured_providers.dart';
import '../../features/registrados/providers/registrados_providers.dart';
import '../../features/usuarios/providers/usuarios_providers.dart';
import '../images/offline_image_store.dart';
import '../repositories/storage_cleanup_service.dart';
import '../models/evento.dart';
import '../models/evento_lead.dart';
import 'offline_cache_tables.dart';
import 'offline_read_cache.dart';
import 'offline_retention_policy.dart';
import 'sync_queue_item.dart';
import 'sync_queue_service.dart';

/// Etapas del snapshot, en el orden en que se ejecutan.
enum SnapshotEtapa {
  perfil,
  catalogo,
  actividades,
  usuarios,
  home,
  listas,
  fotos;

  String get titulo => switch (this) {
    SnapshotEtapa.perfil => 'Perfil',
    SnapshotEtapa.catalogo => 'Eventos',
    SnapshotEtapa.actividades => 'Actividades de captura',
    SnapshotEtapa.usuarios => 'Usuarios',
    SnapshotEtapa.home => 'Inicio',
    SnapshotEtapa.listas => 'Asistentes y leads',
    SnapshotEtapa.fotos => 'Imágenes',
  };
}

class SnapshotProgreso {
  const SnapshotProgreso({
    required this.etapa,
    this.completados = 0,
    this.total = 0,
  });

  final SnapshotEtapa etapa;
  final int completados;
  final int total;

  double get fraccion {
    final indice = SnapshotEtapa.values.indexOf(etapa);
    final base = indice / SnapshotEtapa.values.length;
    if (total <= 0) return base;
    return base + (completados / total) / SnapshotEtapa.values.length;
  }
}

class SnapshotEstado {
  const SnapshotEstado({
    this.enCurso = false,
    this.esPrimeraPasada = false,
    this.progreso,
    this.ultimoExito,
    this.errores = const [],
  });

  final bool enCurso;

  /// La pasada en curso arrancó sin ninguna copia en disco. Solo entonces el
  /// splash espera: con caché se entra de inmediato y se refresca por detrás.
  final bool esPrimeraPasada;
  final SnapshotProgreso? progreso;
  final DateTime? ultimoExito;

  /// Etapas que fallaron en la última pasada. Un fallo parcial no invalida el
  /// resto: lo que sí se bajó queda guardado.
  final List<String> errores;

  SnapshotEstado copyWith({
    bool? enCurso,
    bool? esPrimeraPasada,
    SnapshotProgreso? progreso,
    DateTime? ultimoExito,
    List<String>? errores,
    bool limpiarProgreso = false,
  }) {
    return SnapshotEstado(
      enCurso: enCurso ?? this.enCurso,
      esPrimeraPasada: esPrimeraPasada ?? this.esPrimeraPasada,
      progreso: limpiarProgreso ? null : (progreso ?? this.progreso),
      ultimoExito: ultimoExito ?? this.ultimoExito,
      errores: errores ?? this.errores,
    );
  }
}

/// Baja de una pasada todo lo que la app necesita para operar sin red.
///
/// No inventa consultas propias: dispara los mismos providers que usa la UI,
/// que ya saben respaldarse en [OfflineReadCache]. Así no hay dos caminos que
/// puedan divergir —uno para pintar y otro para sincronizar— que es
/// exactamente el error que tenía el proyecto legado con sus dos colas.
class SnapshotService extends StateNotifier<SnapshotEstado> {
  SnapshotService(this._ref) : super(const SnapshotEstado());

  final Ref _ref;

  bool _metadatosRestaurados = false;

  /// Recupera del disco la marca de la última bajada.
  ///
  /// Es perezoso a propósito: leer la caché arrastra `appBootstrapProvider`, y
  /// hacerlo en el constructor obligaría a que cualquiera que solo quiera
  /// *consultar* el estado —el splash, por ejemplo— tenga el bootstrap ya
  /// resuelto. Idempotente: se puede llamar desde un `build`.
  void restaurarMetadatosSiHaceFalta() {
    if (_metadatosRestaurados) return;
    _metadatosRestaurados = true;
    final filas = _ref
        .read(offlineReadCacheProvider)
        .leerGlobal(
          tabla: OfflineCacheTables.syncMeta,
          desdeFila: (fila) => fila['ultimo_exito_at']?.toString(),
        );
    final marca = filas?.firstOrNull;
    if (marca == null) return;
    state = state.copyWith(ultimoExito: DateTime.tryParse(marca));
  }

  /// `true` si ya hay una copia utilizable en disco.
  ///
  /// El splash solo debe bloquearse la primera vez: con caché se entra de
  /// inmediato y el refresco va por detrás.
  bool get hayCacheUtilizable {
    final eventos = _ref
        .read(offlineReadCacheProvider)
        .leerGlobal(
          tabla: OfflineCacheTables.eventos,
          desdeFila: Evento.fromMap,
        );
    return eventos != null;
  }

  /// Eventos que se bajan enteros (listas y fotos).
  ///
  /// Mismo criterio que `eventoExternoOperable`: no finalizado.
  static List<Evento> eventosDelSnapshot(List<Evento> catalogo) {
    return catalogo.where((e) => !e.yaOcurrio).toList();
  }

  /// Actividades de captura que se bajan enteras.
  ///
  /// Las finalizadas dejan de refrescarse aquí, pero su copia no se suelta el
  /// mismo día: de eso se encarga [_purgar] con
  /// [margenRetencionOffline], para no vaciarle la lista en plena feria a
  /// quien siga capturando después de medianoche.
  static List<EventoLead> actividadesDelSnapshot(List<EventoLead> catalogo) {
    return catalogo.where((e) => !e.yaOcurrio).toList();
  }

  /// Campañas que el snapshot pide al servidor.
  ///
  /// El externo solo opera las ligadas a sus eventos de registro. Pedir el
  /// resumen de las demás dispara `42501` ("Sin acceso al resumen de la
  /// campaña") y ensuciaba la etapa de listas aunque los leads sí se
  /// hubieran bajado.
  static List<EventoLead> campanasDelSnapshot({
    required List<EventoLead> actividades,
    required List<Evento> eventosVisibles,
    required bool esExterno,
  }) {
    final vigentes = actividadesDelSnapshot(actividades);
    if (!esExterno) return vigentes;

    final ids = eventosVisibles.map((e) => e.id).toSet();
    final nombres = {
      for (final evento in eventosVisibles) evento.nombre.trim().toLowerCase(),
    };
    return vigentes.where((campana) {
      final origen = campana.eventoOrigenId?.trim();
      if (origen != null && origen.isNotEmpty) return ids.contains(origen);
      return nombres.contains(campana.nombre.trim().toLowerCase());
    }).toList();
  }

  /// El RPC de conteos rechazó la campaña. Los leads de esa actividad ya
  /// pueden estar en disco; no vale marcar toda la etapa como fallida.
  static bool esErrorSinAccesoResumen(Object error) {
    return error.toString().toLowerCase().contains(
      'sin acceso al resumen de la campaña',
    );
  }

  Future<void> ejecutar() async {
    restaurarMetadatosSiHaceFalta();
    if (state.enCurso) return;
    if (!supportsOfflineCacheAqui) return;
    if (!_ref.read(isOnlineProvider)) return;

    state = state.copyWith(
      enCurso: true,
      esPrimeraPasada: !hayCacheUtilizable,
      errores: const [],
    );
    final errores = <String>[];

    Future<T?> etapa<T>(
      SnapshotEtapa etapa,
      Future<T> Function() accion, {
      int completados = 0,
      int total = 0,
    }) async {
      state = state.copyWith(
        progreso: SnapshotProgreso(
          etapa: etapa,
          completados: completados,
          total: total,
        ),
      );
      try {
        return await accion();
      } catch (e) {
        // Un fallo parcial no aborta la pasada: lo ya guardado sigue siendo
        // útil y la etapa se reintenta en la próxima sincronización.
        developer.log('Etapa ${etapa.name} falló: $e', name: 'SnapshotService');
        errores.add('${etapa.titulo}: ${_mensaje(e)}');
        return null;
      }
    }

    try {
      await etapa(SnapshotEtapa.perfil, () async {
        _ref.invalidate(currentPerfilProvider);
        return _ref.read(currentPerfilProvider.future);
      });

      // El resultado nullable se conserva: `null` es "la etapa falló", y la
      // purga no puede confundir eso con "el usuario no tiene nada".
      final catalogoBajado = await etapa(SnapshotEtapa.catalogo, () async {
        _ref.invalidate(eventosListProvider);
        return _ref.read(eventosListProvider.future);
      });
      final catalogo = catalogoBajado ?? const <Evento>[];

      final actividadesBajadas = await etapa(
        SnapshotEtapa.actividades,
        () async {
          _ref.invalidate(eventosLeadsListProvider);
          return _ref.read(eventosLeadsListProvider.future);
        },
      );
      final actividades = actividadesBajadas ?? const <EventoLead>[];

      await etapa(SnapshotEtapa.usuarios, () async {
        _ref.invalidate(usuariosListProvider);
        return _ref.read(usuariosListProvider.future);
      });

      await etapa(SnapshotEtapa.home, () async {
        _ref.invalidate(eventosFijadosProvider);
        _ref.invalidate(campanasFijadasProvider);
        _ref.invalidate(homeDashboardProvider);
        _ref.invalidate(homeFeaturedItemsProvider);
        await _ref.read(homeDashboardProvider.future);
        return _ref.read(homeFeaturedItemsProvider.future);
      });

      // Los registrados cuelgan de un evento y los leads de una actividad de
      // captura: son tablas distintas y hay que recorrer ambas listas.
      final perfil = _ref.read(currentPerfilProvider).valueOrNull;
      final eventos = eventosDelSnapshot(catalogo);
      final campanas = campanasDelSnapshot(
        actividades: actividades,
        eventosVisibles: catalogo,
        esExterno: perfil?.isExterno ?? false,
      );
      final total = eventos.length + campanas.length;
      var hechos = 0;

      for (final evento in eventos) {
        await etapa(
          SnapshotEtapa.listas,
          () async {
            _ref.invalidate(registradosPorEventoProvider(evento.id));
            await _ref.read(registradosPorEventoProvider(evento.id).future);
          },
          completados: hechos,
          total: total,
        );
        hechos++;
      }

      for (final campana in campanas) {
        await etapa(
          SnapshotEtapa.listas,
          () async {
            _ref.invalidate(leadsPorEventoProvider(campana.id));
            await _ref.read(leadsPorEventoProvider(campana.id).future);
            try {
              _ref.invalidate(leadsResumenRemotoProvider(campana.id));
              await _ref.read(leadsResumenRemotoProvider(campana.id).future);
            } catch (e) {
              if (!esErrorSinAccesoResumen(e)) rethrow;
            }
          },
          completados: hechos,
          total: total,
        );
        hechos++;
      }

      // Las fotos van al final a propósito: si fallan, las listas ya están
      // guardadas y la app opera igual, solo con placeholders.
      await etapa(SnapshotEtapa.fotos, () async {
        final store = _ref.read(offlineImageStoreProvider);
        if (!store.disponible) return;

        final urls = <String>{
          ...eventos.map((e) => e.imagenUrl ?? ''),
          ...campanas.map((c) => c.imagenUrl ?? ''),
          ...(_ref.read(usuariosListProvider).valueOrNull ?? const []).map(
            (p) => p.fotoUrl ?? '',
          ),
        }..removeWhere((url) => url.isEmpty);

        var descargadas = 0;
        for (final url in urls) {
          await store.prefetch(url);
          descargadas++;
          state = state.copyWith(
            progreso: SnapshotProgreso(
              etapa: SnapshotEtapa.fotos,
              completados: descargadas,
              total: urls.length,
            ),
          );
        }
      });

      await _purgar(catalogo: catalogoBajado, actividades: actividadesBajadas);
      await _guardarMarca();
    } finally {
      state = state.copyWith(
        enCurso: false,
        esPrimeraPasada: false,
        errores: errores,
        limpiarProgreso: true,
      );
    }
  }

  /// Purga con lo que ya hay en disco, sin pedirle nada al servidor.
  ///
  /// La decisión solo depende de la fecha del catálogo cacheado, así que puede
  /// —y debe— correr también sin red: si no, un teléfono que pasa semanas en
  /// modo avión nunca liberaría nada.
  Future<void> purgarConCacheLocal() async {
    if (!supportsOfflineCacheAqui) return;
    final cache = _ref.read(offlineReadCacheProvider);

    final catalogo = cache.leerGlobal(
      tabla: OfflineCacheTables.eventos,
      desdeFila: Evento.fromMap,
    );
    final actividades = cache.leerGlobal(
      tabla: OfflineCacheTables.eventosLeads,
      desdeFila: EventoLead.fromMap,
    );
    if (catalogo == null && actividades == null) return;

    await _purgar(catalogo: catalogo, actividades: actividades);
  }

  /// Suelta del disco lo que ya no está activo.
  ///
  /// Sin esto el snapshot solo crecía: bajaba el set vigente y dejaba intacto
  /// todo lo de las ferias anteriores. Cubre las tres capas —listas por evento,
  /// detalles y portadas— y respeta dos reglas:
  ///
  /// * [margenRetencionOffline] de gracia tras la fecha del evento.
  /// * Nada con escrituras pendientes en la cola se toca, aunque haya
  ///   caducado: esa copia es lo único que sostiene lo capturado sin red.
  ///
  /// [catalogo] y [actividades] en `null` significan "no se pudo saber" —la
  /// etapa del snapshot falló— y ahí esa familia de tablas no se toca. Una
  /// lista vacía sí es una respuesta (el usuario no tiene nada) y purga.
  Future<void> _purgar({
    required List<Evento>? catalogo,
    required List<EventoLead>? actividades,
  }) async {
    if (!supportsOfflineCacheAqui) return;
    if (catalogo == null && actividades == null) return;

    try {
      final cache = _ref.read(offlineReadCacheProvider);
      final protegidos = _idsConEscriturasPendientes();

      if (catalogo != null) {
        final eventos = eventosAConservar(catalogo, protegidos: protegidos);

        await cache.retenerEventos(OfflineCacheTables.eventoDetalle, eventos);
        await cache.retenerEventos(SupabaseTables.registrados, eventos);
      }

      if (actividades != null) {
        final campanas = actividadesAConservar(
          actividades,
          protegidos: protegidos,
        );
        final origenes = origenesAConservar(actividades, campanas);

        await cache.retenerEventos(
          OfflineCacheTables.eventoLeadDetalle,
          campanas,
        );
        // Las dos variantes por rol: un cambio de permisos deja atrás la tabla
        // que ya no se lee y nadie más la limpia.
        await cache.retenerEventos(leadsCacheTabla(true), campanas);
        await cache.retenerEventos(leadsCacheTabla(false), campanas);
        await cache.retenerEventos(leadsResumenCacheTabla, campanas);
        await cache.retenerEventos(
          OfflineCacheTables.eventoLeadPorOrigen,
          origenes,
        );
      }

      // Las portadas solo se pueden podar sabiéndolo todo: con medio catálogo
      // se borrarían imágenes que siguen en uso.
      if (catalogo != null && actividades != null) {
        await _purgarImagenes(catalogo: catalogo, actividades: actividades);
      }
    } catch (e) {
      // Liberar espacio jamás puede tumbar una sincronización que ya trajo
      // datos buenos: se reintenta en la próxima pasada.
      developer.log('Purga de caché pospuesta: $e', name: 'SnapshotService');
    }
  }

  Future<void> _purgarImagenes({
    required List<Evento> catalogo,
    required List<EventoLead> actividades,
  }) async {
    final store = _ref.read(offlineImageStoreProvider);
    if (!store.disponible) return;

    final vigentes = <String>{
      ...eventosDelSnapshot(catalogo).map((e) => e.imagenUrl ?? ''),
      ...actividadesDelSnapshot(actividades).map((c) => c.imagenUrl ?? ''),
      ...(_ref.read(usuariosListProvider).valueOrNull ?? const []).map(
        (p) => p.fotoUrl ?? '',
      ),
    }..removeWhere((url) => url.isEmpty);

    final borradas = await store.retener(vigentes);
    if (borradas > 0) {
      developer.log(
        '$borradas portadas liberadas del disco',
        name: 'SnapshotService',
      );
    }
  }

  Set<String> _idsConEscriturasPendientes() =>
      idsConEscriturasPendientes(_ref.read(syncQueueServiceProvider));

  /// Eventos y campañas con escrituras que todavía no llegaron al servidor.
  ///
  /// Su caché es la única prueba de lo capturado sin red: purgarla borraría el
  /// contexto de una fila que aún está por subir.
  static Set<String> idsConEscriturasPendientes(List<SyncQueueItem> cola) {
    return {
      for (final item in cola)
        if (item.status != SyncStatus.synced)
          item.payload['evento_id']?.toString() ?? '',
    }..removeWhere((id) => id.isEmpty);
  }

  /// Eventos cuya copia local se conserva: los vigentes más los [protegidos].
  static Set<String> eventosAConservar(
    List<Evento> catalogo, {
    Set<String> protegidos = const {},
    DateTime? ahora,
  }) {
    return idsVigentes(
      catalogo,
      id: (Evento e) => e.id,
      fecha: (Evento e) => e.fechaFin,
      ahora: ahora,
    )..addAll(protegidos);
  }

  static Set<String> actividadesAConservar(
    List<EventoLead> actividades, {
    Set<String> protegidos = const {},
    DateTime? ahora,
  }) {
    return idsVigentes(
      actividades,
      id: (EventoLead e) => e.id,
      fecha: (EventoLead e) => e.fechaFin,
      ahora: ahora,
    )..addAll(protegidos);
  }

  /// Claves a conservar en `eventoLeadPorOrigen`, que se indexa **por el id del
  /// evento de origen**, no por el de la actividad.
  static Set<String> origenesAConservar(
    List<EventoLead> actividades,
    Set<String> campanasVigentes,
  ) {
    return {
      for (final actividad in actividades)
        if (campanasVigentes.contains(actividad.id))
          actividad.eventoOrigenId ?? '',
    }..removeWhere((id) => id.isEmpty);
  }

  Future<void> _guardarMarca() async {
    final ahora = DateTime.now();
    await _ref.read(offlineReadCacheProvider).guardarGlobal(
      OfflineCacheTables.syncMeta,
      [
        {'ultimo_exito_at': ahora.toIso8601String()},
      ],
    );
    state = state.copyWith(ultimoExito: ahora);
  }

  static String _mensaje(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }
}

final snapshotServiceProvider =
    StateNotifierProvider<SnapshotService, SnapshotEstado>((ref) {
      return SnapshotService(ref);
    });

/// `true` mientras la **primera** bajada completa sigue en curso.
///
/// Es lo único que justifica retener el splash: sin copia previa la app no
/// tiene nada que mostrar. En aperturas siguientes se entra con disco y el
/// refresco va por detrás.
final esperandoPrimerSnapshotProvider = Provider<bool>((ref) {
  final estado = ref.watch(snapshotServiceProvider);
  return estado.enCurso && estado.esPrimeraPasada;
});

/// Mantiene vivo el disparo automático del snapshot. Se lee una vez cerca de
/// la raíz (ver `app.dart`).
final snapshotAutoStartProvider = Provider<void>((ref) {
  void lanzar() {
    if (ref.read(currentPerfilProvider).valueOrNull == null) return;
    final servicio = ref.read(snapshotServiceProvider.notifier);
    // Sin red `ejecutar` sale de inmediato, así que la purga va aparte: la
    // decisión solo mira la fecha del catálogo que ya está en disco.
    servicio.purgarConCacheLocal();
    servicio.ejecutar();
    // Drena también lo que encolaron otros dispositivos: la cola vive en el
    // servidor y nadie más la vacía.
    ref.read(storageCleanupServiceProvider).drenar();
  }

  // Perfil resuelto: primera bajada (o refresco) de la sesión.
  ref.listen(currentPerfilProvider, (_, next) {
    if (next.valueOrNull != null) lanzar();
  });

  // Al recuperar la red se vuelve a bajar el set activo.
  ref.listen(connectivityStreamProvider, (previous, next) {
    if (previous?.valueOrNull == false && next.valueOrNull == true) lanzar();
  });

  if (ref.read(currentPerfilProvider).valueOrNull != null) lanzar();
});
