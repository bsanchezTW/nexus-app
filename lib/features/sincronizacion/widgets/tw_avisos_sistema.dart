import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/avisos/aviso_sistema.dart';
import '../../../core/network/offline_policy.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/tw_tokens.dart';
import '../../../core/widgets/app_modals.dart';
import '../../../core/widgets/sync_conflict_listener.dart';
import '../../../core/widgets/tw_components.dart';
import '../../../core/widgets/tw_notice_card.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/offline/sync_coordinator.dart';
import '../../updates/widgets/update_notice_card.dart';
import '../providers/avisos_sistema_provider.dart';

/// Zona de avisos de las pantallas principales (Inicio, Usar evento, Usar
/// actividad, Externo).
///
/// Muestra como mucho dos tarjetas: el estado de la conexión y, debajo, lo
/// que la app está haciendo con los datos (ver [avisosDelSistema]). Si no hay
/// nada de esto último, ese lugar lo ocupa el aviso de actualización.
///
/// Reemplaza a las tres tarjetas hermanas que había antes —sin conexión,
/// sincronización y actualización—, que podían apilarse de a tres y repetían
/// la misma lógica de visibilidad en cada pantalla.
class TwAvisosSistema extends ConsumerWidget {
  const TwAvisosSistema({
    super.key,
    this.topGap = 0,
    this.bottomGap = 0,
    this.incluirActualizacion = true,
  });

  /// Aire sobre cada tarjeta visible.
  final double topGap;

  /// Aire bajo cada tarjeta visible.
  final double bottomGap;

  /// En la hoja del indicador la actualización sobra: tiene su propio lugar.
  final bool incluirActualizacion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avisos = ref.watch(avisosSistemaProvider);
    AvisoSistema? de(RanuraAviso ranura) =>
        avisos.where((a) => a.ranura == ranura).firstOrNull;
    final conexion = de(RanuraAviso.conexion);
    final actividad = de(RanuraAviso.actividad);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TwNoticeSlot(
          visible: conexion != null,
          topGap: topGap,
          bottomGap: bottomGap,
          child: conexion == null
              ? const SizedBox.shrink()
              : TarjetaAvisoSistema(aviso: conexion),
        ),
        TwNoticeSlot(
          visible: actividad != null,
          topGap: topGap,
          bottomGap: bottomGap,
          child: actividad == null
              ? const SizedBox.shrink()
              : TarjetaAvisoSistema(aviso: actividad),
        ),
        if (actividad == null && incluirActualizacion)
          UpdateNoticeCard(topGap: topGap, bottomGap: bottomGap),
      ],
    );
  }
}

/// Un aviso con el molde de [TwNoticeCard].
class TarjetaAvisoSistema extends ConsumerWidget {
  const TarjetaAvisoSistema({super.key, required this.aviso});

  final AvisoSistema aviso;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TwNoticeCard(
      key: Key('aviso_${aviso.tipo.name}'),
      icon: iconoAviso(aviso.tipo),
      title: aviso.titulo,
      subtitle: aviso.detalle,
      palette: aviso.esProblema
          ? TwNoticePalette.offline
          : TwNoticePalette.update,
      progress: aviso.progreso,
      onTap: accionAviso(context, ref, aviso.accion),
    );
  }
}

IconData iconoAviso(TipoAviso tipo) => switch (tipo) {
  TipoAviso.sinInternet => Symbols.cloud_off_rounded,
  TipoAviso.sinBackend => Symbols.database_off_rounded,
  TipoAviso.inestable => Symbols.network_check_rounded,
  TipoAviso.copiaLocal => Symbols.history_rounded,
  TipoAviso.conflictos => Symbols.sync_problem_rounded,
  TipoAviso.subiendo || TipoAviso.pendientes => Symbols.cloud_upload_rounded,
  TipoAviso.descargando => Symbols.cloud_download_rounded,
  TipoAviso.descargaIncompleta => Symbols.cloud_off_rounded,
};

/// Qué hace tocar un aviso. `null` si no tiene acción.
VoidCallback? accionAviso(
  BuildContext context,
  WidgetRef ref,
  AccionAviso accion,
) {
  return switch (accion) {
    AccionAviso.ninguna => null,
    AccionAviso.revisarConflictos => () => showSyncConflictsSheet(context, ref),
    AccionAviso.reintentar =>
      () => ref.read(syncCoordinatorProvider).sincronizarAhora(),
    AccionAviso.abrirSincronizacion => () => context.push(
      RoutePaths.sincronizacion,
    ),
    // Igual que una recarga a mano: no esperar la ventana de "servidor
    // inalcanzable" y volver a preguntar en todas las lecturas vivas.
    AccionAviso.recargar => () {
      ref.read(offlineReadCacheProvider)
        ..olvidarServidorInalcanzable()
        ..olvidarCopiasServidas();
      exigirLecturaDelServidor(ref.read(epocaServidorProvider.notifier));
    },
  };
}

/// Indicador compacto para las pantallas sin zona de avisos (listas, escáner).
///
/// Solo aparece cuando hay algo que contar. Toma el ícono del aviso más
/// urgente, se tiñe si es un problema y lleva la cantidad de cambios en
/// espera. Al tocarlo abre una hoja con las mismas tarjetas de
/// [TwAvisosSistema].
class TwIndicadorConexion extends ConsumerWidget {
  const TwIndicadorConexion({super.key, this.sobreOscuro = false});

  /// Para la cámara del escáner: ícono blanco sobre vidrio.
  final bool sobreOscuro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avisos = ref.watch(avisosSistemaProvider);
    if (avisos.isEmpty) return const SizedBox.shrink();

    final principal = avisos.first;
    final cantidad = avisos
        .where((a) => a.ranura == RanuraAviso.actividad)
        .map((a) => a.cantidad)
        .firstOrNull;
    final tooltip = principal.titulo;
    void abrir() => mostrarAvisosSistema(context);

    if (sobreOscuro) {
      return Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          key: const Key('indicador_conexion'),
          onTap: abrir,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: TwRadii.pill,
              color: principal.esProblema
                  ? TwColors.danger.withValues(alpha: 0.85)
                  : Colors.white.withValues(alpha: 0.18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(iconoAviso(principal.tipo), size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    principal.titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return TwIconButton(
      key: const Key('indicador_conexion'),
      icon: iconoAviso(principal.tipo),
      onTap: abrir,
      tooltip: tooltip,
      danger: principal.esProblema,
      badgeCount: cantidad == null || cantidad == 0 ? null : cantidad,
    );
  }
}

/// Hoja con los avisos vigentes y, donde hay copia local, el acceso a
/// Sincronización.
Future<void> mostrarAvisosSistema(BuildContext context) {
  return showAppModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: TwColors.bg,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Conexión y datos', style: TwText.tileTitle),
            const TwAvisosSistema(topGap: 12, incluirActualizacion: false),
            if (supportsOfflineCacheAqui) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  context.push(RoutePaths.sincronizacion);
                },
                icon: const Icon(Symbols.sync_rounded),
                label: const Text('Ver sincronización'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
