import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tw_tokens.dart';
import 'pressable.dart';
import 'tw_components.dart';

class TwNavItemData {
  const TwNavItemData({
    required this.icon,
    required this.label,
    required this.sfSymbol,
    this.sfSymbolActive,
  });

  final IconData icon;
  final String label;

  /// Nombre SF Symbol para la tab bar nativa de iOS (p. ej. `house`).
  final String sfSymbol;

  /// Variante rellena del SF Symbol; si falta se usa [sfSymbol].
  final String? sfSymbolActive;
}

/// Barra inferior estilo Android (Material 3): anclada al borde, en el mismo
/// vidrio esmerilado que la cabecera colapsable del home, con la píldora
/// 64×32 bajo el icono activo (en FILL 1) e inactivos en slate oscuro.
///
/// Los ítems siguen la columna del contenido: el gutter de pantalla y el
/// ancho máximo. La píldora del primero cae en el margen izquierdo, la del
/// último en el derecho, y cada celda completa sigue siendo tocable.
///
/// El vidrio baja también detrás de la navegación del sistema; los ítems
/// quedan por encima de ella.
///
/// La navegación real queda fuera: este widget solo pinta y reporta el índice.
class TwBottomNavBar extends StatelessWidget {
  const TwBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final List<TwNavItemData> items;

  @override
  Widget build(BuildContext context) {
    assert(items.isNotEmpty, 'TwBottomNavBar requiere al menos un ítem');

    return RepaintBoundary(
      child: ClipRect(
        // El velo es opaco al tacto: un toque entre ítems no llega a la fila
        // del contenido que pasa por debajo (`extendBody`).
        child: TwFrostedGlass(
          color: GlassNavTokens.glassTint,
          child: Padding(
            padding: EdgeInsets.only(
              left: TwSpacing.screenH,
              right: TwSpacing.screenH,
              bottom: GlassNavTokens.bottomPadding(context),
            ),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppSpacing.contentMax,
                ),
                child: SizedBox(
                  height: GlassNavTokens.height,
                  child: Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: _BottomNavDestination(
                            item: items[i],
                            selected: i == selectedIndex,
                            alignmentX: GlassNavTokens.itemAlignmentX(
                              i,
                              items.length,
                            ),
                            onTap: () => onItemSelected(i),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Destino de la barra inferior: píldora + etiqueta. Al presionar, la
/// píldora muestra la capa de estado de Material 3 aunque el ítem no esté
/// activo.
class _BottomNavDestination extends StatefulWidget {
  const _BottomNavDestination({
    required this.item,
    required this.selected,
    required this.alignmentX,
    required this.onTap,
  });

  final TwNavItemData item;
  final bool selected;
  final double alignmentX;
  final VoidCallback onTap;

  @override
  State<_BottomNavDestination> createState() => _BottomNavDestinationState();
}

class _BottomNavDestinationState extends State<_BottomNavDestination> {
  bool _presionado = false;

  void _presionar(bool valor) {
    if (_presionado != valor) setState(() => _presionado = valor);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.item.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _presionar(true),
        onTapUp: (_) => _presionar(false),
        onTapCancel: () => _presionar(false),
        onTap: widget.onTap,
        child: Align(
          alignment: Alignment(widget.alignmentX, 0),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: widget.selected ? 1 : 0),
            duration: GlassNavTokens.transitionDuration,
            curve: GlassNavTokens.transitionCurve,
            builder: (context, t, _) {
              final fg = Color.lerp(
                GlassNavTokens.inactiveForeground,
                AppColors.primaryDeep,
                t,
              )!;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: GlassNavTokens.indicatorWidth,
                    height: GlassNavTokens.indicatorHeight,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // La píldora crece desde el centro, como en M3.
                        Container(
                          width: GlassNavTokens.indicatorWidth * (0.5 + t / 2),
                          decoration: ShapeDecoration(
                            shape: const StadiumBorder(),
                            color: GlassNavTokens.indicatorColor.withValues(
                              alpha: t,
                            ),
                          ),
                        ),
                        AnimatedOpacity(
                          opacity: _presionado ? 1 : 0,
                          duration: AppMotion.press,
                          child: Container(
                            decoration: ShapeDecoration(
                              shape: const StadiumBorder(),
                              color: AppColors.primary.withValues(alpha: 0.12),
                            ),
                          ),
                        ),
                        Icon(
                          widget.item.icon,
                          size: GlassNavTokens.iconSize,
                          fill: t,
                          color: fg,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.item.label,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    softWrap: false,
                    style: TwText.navLabel.copyWith(
                      fontSize: GlassNavTokens.labelSize,
                      fontWeight: FontWeight.lerp(
                        FontWeight.w600,
                        FontWeight.w800,
                        t,
                      ),
                      color: fg,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Rail izquierdo de escritorio: ítem de chip con borde, sin vidrio
/// flotante, del color del contenedor para calzar con el marco de Windows.
class TwSideNavRail extends StatelessWidget {
  const TwSideNavRail({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.items,
  });

  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final List<TwNavItemData> items;

  @override
  Widget build(BuildContext context) {
    assert(items.isNotEmpty, 'TwSideNavRail requiere al menos un ítem');

    return Material(
      color: TwColors.bg,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: TwColors.border07, width: 1)),
        ),
        child: SizedBox(
          width: GlassNavTokens.sideRailWidth,
          child: Padding(
            padding: GlassNavTokens.sideRailPadding,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const _SideNavSeparator(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _TwNavItem(
                      item: items[i],
                      selected: i == selectedIndex,
                      onTap: () => onItemSelected(i),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SideNavSeparator extends StatelessWidget {
  const _SideNavSeparator();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: GlassNavTokens.sideRailSeparatorHeight,
      thickness: 1,
      indent: GlassNavTokens.sideRailSeparatorIndent,
      endIndent: GlassNavTokens.sideRailSeparatorIndent,
      color: TwColors.border07,
    );
  }
}

class _TwNavItem extends StatelessWidget {
  const _TwNavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final TwNavItemData item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      scale: 0.97,
      onTap: onTap,
      child: Semantics(
        button: true,
        selected: selected,
        label: item.label,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: selected ? 1 : 0),
            duration: GlassNavTokens.transitionDuration,
            curve: GlassNavTokens.transitionCurve,
            builder: (context, t, _) {
              final fg = Color.lerp(TwColors.muted, TwColors.hero700, t)!;
              final chip = Color.lerp(
                TwColors.blueTint.withValues(alpha: 0),
                TwColors.blueTint,
                t,
              )!;
              final ring = Color.lerp(
                TwColors.hero700.withValues(alpha: 0),
                TwColors.hero700,
                t,
              )!;

              return Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 46,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: chip,
                      borderRadius: const BorderRadius.all(Radius.circular(15)),
                      border: Border.all(color: ring, width: 1.5),
                    ),
                    child: Icon(item.icon, size: 20, fill: t, color: fg),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TwText.navLabel.copyWith(color: fg),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
