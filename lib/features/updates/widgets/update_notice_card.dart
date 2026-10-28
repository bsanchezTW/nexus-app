import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/widgets/tw_notice_card.dart';
import '../providers/update_providers.dart';
import '../services/update_platform.dart';
import '../services/update_service.dart';

/// Aviso de versión nueva, con el molde del de "sin conexión" pero en azul.
///
/// Las actualizaciones ya no bloquean la app con un modal: este aviso queda
/// a la vista mientras haya una versión sin instalar y, al tocarlo, abre
/// Actualizaciones con la descarga lista. Durante la descarga muestra el
/// avance, así se puede seguir usando la app y volver a mirar.
class UpdateNoticeCard extends ConsumerWidget {
  const UpdateNoticeCard({super.key, this.topGap = 0, this.bottomGap = 0});

  final double topGap;
  final double bottomGap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateControllerProvider);
    final visible = otaUpdatesSupported && state.hasPendingUpdate;

    return TwNoticeSlot(
      visible: visible,
      topGap: topGap,
      bottomGap: bottomGap,
      child: visible ? _tarjeta(context, state) : const SizedBox.shrink(),
    );
  }

  Widget _tarjeta(BuildContext context, UpdateState state) {
    final version = 'v${state.info!.remoteVersion}';
    final (titulo, bajada, progreso) = switch (state.status) {
      UpdateStatus.downloading => (
        'Descargando actualización',
        'RegisPro $version · '
            '${(state.progress * 100).clamp(0, 100).toStringAsFixed(0)} %',
        state.progress,
      ),
      UpdateStatus.verifying || UpdateStatus.installing => (
        'Instalando actualización',
        otaInstallingLabel,
        0.0,
      ),
      UpdateStatus.awaitingInstallPermission => (
        'Falta un permiso',
        'Toca para permitir que RegisPro se actualice',
        null,
      ),
      UpdateStatus.failed => (
        'No se pudo actualizar',
        'Toca para reintentar la instalación de $version',
        null,
      ),
      _ => (
        'Nueva versión disponible',
        'RegisPro $version está lista para descargar. Toca para actualizar.',
        null,
      ),
    };

    return TwNoticeCard(
      key: const Key('aviso_actualizacion'),
      icon: Symbols.system_update_rounded,
      title: titulo,
      subtitle: bajada,
      palette: TwNoticePalette.update,
      progress: progreso,
      onTap: () => context.push(RoutePaths.actualizaciones),
    );
  }
}
