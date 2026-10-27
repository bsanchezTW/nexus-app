import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/tw_tokens.dart';
import 'ios_native_chrome.dart';
import 'tw_components.dart';

/// Medidas de la cabecera fija de las pantallas-menú.
abstract final class TwDetailBarMetrics {
  /// Aire sobre y bajo la fila de botones. **El mismo valor a propósito**: al
  /// colapsar, el fondo difuminado ocupa todo el alto de la barra y la fila
  /// tiene que leerse centrada. Con menos aire arriba que abajo los botones
  /// y el título quedaban visiblemente altos.
  ///
  /// El aire de arriba también hace falta en web y Windows, donde no hay notch
  /// ni barra de estado que empuje el contenido.
  static const double gapVertical = 14;

  /// Alto de la fila de botones (mínimo táctil).
  static const double rowHeight = 44;

  /// Scroll en el que el fondo y el título compacto terminan de aparecer.
  static const double collapseFadeRange = 20;

  static double height(double topInset) =>
      topInset + gapVertical * 2 + rowHeight;

  /// Cuánto se monta la hoja de acciones sobre el hero a sangre.
  static const double sheetOverlap = 24;

  /// Radio superior de esa hoja.
  static const double sheetRadius = 28;

  /// Inset superior estable para la barra.
  ///
  /// En la PWA de iOS el gesto de atrás mueve el visual viewport y
  /// [MediaQuery.padding] puede caer a 0 un frame (el notch se cuenta como
  /// `viewInsets`). [viewPadding] no se mueve: sin esto la cabecera —y con
  /// ella el menú de acciones— salta al volver deslizando.
  static double topInsetOf(BuildContext context) {
    final mq = MediaQuery.of(context);
    return mq.viewPadding.top > mq.padding.top
        ? mq.viewPadding.top
        : mq.padding.top;
  }

  static double bottomInsetOf(BuildContext context) {
    final mq = MediaQuery.of(context);
    return mq.viewPadding.bottom > mq.padding.bottom
        ? mq.viewPadding.bottom
        : mq.padding.bottom;
  }
}

/// Pantalla-menú con cabecera fija que colapsa al hacer scroll.
///
/// Mismo comportamiento que el home y las listas: la barra vive en un `Stack`
/// sobre el contenido, así el botón atrás y las acciones **nunca se pierden**
/// al desplazarse. Al colapsar aparece el fondo difuminado con hairline y el
/// eyebrow deja paso al título compacto.
class TwDetailScaffold extends StatefulWidget {
  const TwDetailScaffold({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.onBack,
    required this.children,
    this.actions = const [],
    this.onRefresh,
    this.maxContentWidth = 560,
    this.bottomPadding = 40,
    this.backIcon = Symbols.arrow_back_rounded,
    this.backTooltip = 'Volver',
    this.backKey,
    this.leading,
    this.heroBuilder,
  });

  /// Cabecera a sangre (menús de evento): ocupa todo el ancho desde el borde
  /// superior, la barra flota encima y [children] van en una hoja redondeada
  /// que se monta sobre su borde inferior. El builder recibe el relleno que
  /// deja libre la barra arriba y el solape de la hoja abajo.
  final Widget Function(EdgeInsets padding)? heroBuilder;

  /// Rótulo en reposo ("Detalle del evento").
  final String eyebrow;

  /// Título compacto que aparece al colapsar (el nombre del evento).
  final String title;

  final VoidCallback onBack;

  /// El usuario externo no navega hacia atrás, así que el icono, el tooltip y
  /// la key son configurables.
  final IconData backIcon;
  final String backTooltip;
  final Key? backKey;

  /// Reemplaza el chip izquierdo por un widget propio. El externo pone ahí su
  /// foto de perfil, igual que los internos en el home: su cabecera es de
  /// cuenta, no de navegación, porque no tiene a dónde volver.
  final Widget? leading;

  final List<Widget> actions;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final double maxContentWidth;
  final double bottomPadding;

  @override
  State<TwDetailScaffold> createState() => _TwDetailScaffoldState();
}

class _TwDetailScaffoldState extends State<TwDetailScaffold> {
  final ScrollController _controller = ScrollController();
  final ValueNotifier<double> _scrollY = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    _scrollY.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final y = _controller.offset;
    // Umbral bajo: el fade se siente fluido a 120 Hz sin repintar de más.
    if ((y - _scrollY.value).abs() <= 0.1) return;
    _scrollY.value = y;
  }

  @override
  Widget build(BuildContext context) {
    return _contenido(context);
  }

  Widget _contenido(BuildContext context) {
    final topInset = TwDetailBarMetrics.topInsetOf(context);
    final headerHeight = TwDetailBarMetrics.height(topInset);
    final bottomPad =
        widget.bottomPadding + TwDetailBarMetrics.bottomInsetOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final minBody = math.max(
          0.0,
          constraints.maxHeight - headerHeight - bottomPad,
        );
        final columna = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: widget.children,
        );
        final heroBuilder = widget.heroBuilder;
        Widget scroll = heroBuilder == null
            ? SingleChildScrollView(
                controller: _controller,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                  TwSpacing.screenH,
                  headerHeight,
                  TwSpacing.screenH,
                  bottomPad,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: widget.maxContentWidth,
                      minHeight: minBody,
                    ),
                    child: columna,
                  ),
                ),
              )
            : SingleChildScrollView(
                controller: _controller,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                padding: EdgeInsets.only(bottom: bottomPad),
                child: Column(
                  children: [
                    heroBuilder(
                      EdgeInsets.fromLTRB(
                        TwSpacing.screenH,
                        headerHeight + 4,
                        TwSpacing.screenH,
                        TwDetailBarMetrics.sheetOverlap + 22,
                      ),
                    ),
                    // La hoja sube sobre el hero; lo que deja abajo es del
                    // mismo color que el fondo.
                    Transform.translate(
                      offset: const Offset(0, -TwDetailBarMetrics.sheetOverlap),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: TwSpacing.screenH,
                        ),
                        decoration: const BoxDecoration(
                          color: TwColors.bg,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(
                              TwDetailBarMetrics.sheetRadius,
                            ),
                          ),
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: widget.maxContentWidth,
                            ),
                            child: columna,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
        if (widget.onRefresh != null) {
          scroll = RefreshIndicator(
            color: TwColors.brand700,
            edgeOffset: headerHeight,
            displacement: 40,
            onRefresh: widget.onRefresh!,
            child: scroll,
          );
        }
        return Stack(
          children: [
            scroll,
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: RepaintBoundary(
                child: ValueListenableBuilder<double>(
                  valueListenable: _scrollY,
                  builder: (context, scrollY, _) => _TwDetailBar(
                    scrollOffset: scrollY,
                    sobreHero: widget.heroBuilder != null,
                    topInset: topInset,
                    eyebrow: widget.eyebrow,
                    title: widget.title,
                    onBack: widget.onBack,
                    backIcon: widget.backIcon,
                    backTooltip: widget.backTooltip,
                    backKey: widget.backKey,
                    leading: widget.leading,
                    actions: widget.actions,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TwDetailBar extends StatelessWidget {
  const _TwDetailBar({
    required this.scrollOffset,
    required this.sobreHero,
    required this.topInset,
    required this.eyebrow,
    required this.title,
    required this.onBack,
    required this.backIcon,
    required this.backTooltip,
    required this.backKey,
    required this.leading,
    required this.actions,
  });

  final double scrollOffset;

  /// Flota sobre un hero oscuro: sin eyebrow y con la barra de estado clara
  /// hasta colapsar. El contenido del hero arranca justo bajo los botones,
  /// así que colapsa apenas se desplaza, con el mismo vidrio que la cabecera
  /// del inicio.
  final bool sobreHero;
  final double topInset;
  final String eyebrow;
  final String title;
  final VoidCallback onBack;
  final IconData backIcon;
  final String backTooltip;
  final Key? backKey;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = (scrollOffset / TwDetailBarMetrics.collapseFadeRange).clamp(
      0.0,
      1.0,
    );
    final mostrarFondo = t > 0.01;

    final barra = SizedBox(
      height: TwDetailBarMetrics.height(topInset),
      child: Stack(
        children: [
          // Bloquea taps en la zona de la barra: sin esto el scroll recibe
          // toques en las áreas sin widget interactivo.
          const Positioned.fill(child: AbsorbPointer(child: SizedBox.expand())),
          if (mostrarFondo)
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRect(
                  child: sobreHero
                      ? TwFrostedGlass(
                          color: TwColors.bg.withValues(alpha: 0.72 * t),
                        )
                      : TwGlassFilter(
                          sigma: 18,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: TwColors.bg.withValues(alpha: 0.72 * t),
                              border: Border(
                                bottom: BorderSide(
                                  color: TwColors.border07.withValues(
                                    alpha: TwColors.border07.a * t,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          Positioned(
            top: topInset + TwDetailBarMetrics.gapVertical,
            left: TwSpacing.screenH,
            right: TwSpacing.screenH,
            height: TwDetailBarMetrics.rowHeight,
            child: Row(
              children: [
                leading ??
                    TwIosGlassIconButton(
                      key: backKey,
                      icon: backIcon,
                      iconSize: 22,
                      tooltip: backTooltip,
                      onTap: onBack,
                      sfSymbol: 'chevron.left',
                    ),
                const SizedBox(width: 10),
                // El eyebrow deja paso al título compacto con un cross-fade,
                // sin mover ni ocultar los botones de los extremos.
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Opacity(
                          opacity: sobreHero ? 0 : 1 - t,
                          child: Text(
                            eyebrow.toUpperCase(),
                            style: TwText.eyebrow,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(0, (1 - t) * 6),
                            child: Text(
                              title,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TwText.tileTitle.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                for (final a in actions) ...[const SizedBox(width: 10), a],
              ],
            ),
          ),
        ],
      ),
    );

    if (!sobreHero) return barra;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: t < 0.5 ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: barra,
    );
  }
}
