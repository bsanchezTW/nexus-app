import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../network/connectivity_service.dart';
import '../theme/tw_tokens.dart';
import 'tw_components.dart';

const kTwOfflineNoticeTitle = 'Sin conexión a internet';
const kTwOfflineNoticeSubtitle =
    'Se han limitado las funciones de la aplicación hasta que recuperes la conexión';

/// Aviso de modo local: naranjo pálido, sin chevron ni tap.
///
/// Solo aparece cuando [isOnlineProvider] es `false`. Pendientes y conflictos
/// no lo disparan.
class TwOfflineNoticeCard extends ConsumerWidget {
  const TwOfflineNoticeCard({super.key, this.topGap = 0, this.bottomGap = 0});

  /// Aire sobre la card (p. ej. respecto al hero del menú de acciones).
  final double topGap;

  /// Espacio bajo la card cuando está visible (0 si el label de sección ya
  /// aporta aire).
  final double bottomGap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hayRed = ref.watch(isOnlineProvider);
    return TwNoticeSlot(
      visible: !hayRed,
      topGap: topGap,
      bottomGap: bottomGap,
      child: const TwNoticeCard(
        icon: Symbols.warning_amber_rounded,
        title: kTwOfflineNoticeTitle,
        subtitle: kTwOfflineNoticeSubtitle,
        palette: TwNoticePalette.offline,
      ),
    );
  }
}

/// Hueco animado de un aviso: se abre y cierra con [AnimatedSize] y solo
/// aporta [topGap]/[bottomGap] mientras el aviso está a la vista.
class TwNoticeSlot extends StatelessWidget {
  const TwNoticeSlot({
    super.key,
    required this.visible,
    required this.child,
    this.topGap = 0,
    this.bottomGap = 0,
  });

  final bool visible;
  final Widget child;
  final double topGap;
  final double bottomGap;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: visible
          ? Padding(
              padding: EdgeInsets.only(top: topGap, bottom: bottomGap),
              child: child,
            )
          : const SizedBox(width: double.infinity),
    );
  }
}

/// Colores de un [TwNoticeCard].
class TwNoticePalette {
  const TwNoticePalette({
    required this.bg,
    required this.border,
    required this.iconBg,
    required this.ink,
    required this.muted,
  });

  final Color bg;
  final Color border;
  final Color iconBg;
  final Color ink;
  final Color muted;

  static const offline = TwNoticePalette(
    bg: TwColors.offlineNoticeBg,
    border: TwColors.offlineNoticeBorder,
    iconBg: TwColors.offlineNoticeIconBg,
    ink: TwColors.offlineNoticeInk,
    muted: TwColors.offlineNoticeMuted,
  );

  static const update = TwNoticePalette(
    bg: TwColors.updateNoticeBg,
    border: TwColors.updateNoticeBorder,
    iconBg: TwColors.updateNoticeIconBg,
    ink: TwColors.updateNoticeInk,
    muted: TwColors.updateNoticeMuted,
  );
}

/// Tarjeta de aviso del sistema (sin conexión, actualización): caja de icono,
/// título y bajada. Con [onTap] lleva chevron y es tocable; con [progress]
/// suma una barra fina bajo el texto.
class TwNoticeCard extends StatelessWidget {
  const TwNoticeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.palette,
    this.onTap,
    this.progress,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final TwNoticePalette palette;
  final VoidCallback? onTap;

  /// 0…1, o `null` sin barra. Un 0 exacto pinta la barra indeterminada.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final tarjeta = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: TwRadii.tile,
        border: Border.all(color: palette.border),
        boxShadow: TwShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.iconBg,
              borderRadius: TwRadii.iconLg,
            ),
            child: Icon(icon, size: 21, color: palette.ink),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TwText.tileTitle.copyWith(color: palette.ink),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TwText.tileSubtitle.copyWith(color: palette.muted),
                ),
                if (progress != null) ...[
                  const SizedBox(height: 9),
                  ClipRRect(
                    borderRadius: TwRadii.pill,
                    child: LinearProgressIndicator(
                      value: progress! > 0 ? progress : null,
                      minHeight: 4,
                      backgroundColor: palette.iconBg,
                      color: palette.ink,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            Icon(Symbols.chevron_right_rounded, size: 22, color: palette.muted),
          ],
        ],
      ),
    );

    if (onTap == null) return tarjeta;
    return Semantics(
      button: true,
      child: TwPressable(onTap: onTap, child: tarjeta),
    );
  }
}
