import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/tw_tokens.dart';
import '../theme/browser_theme_color.dart';
import '../router/refresh_on_visible.dart';
import 'ios_native_chrome.dart';
import 'tw_components.dart';

/// El pop interactivo de iOS (deslizar desde el borde) exige `canPop: true`.
///
/// Un formulario con [hasWillPop] lo apaga en **todas** las plataformas: en
/// iPhone el gesto descartaba lo escrito sin pasar por el diálogo de "descartar
/// cambios" que sí muestra el botón atrás, y perder un registro a medio llenar
/// por un roce en el borde es peor que quedarse sin gesto. Sin [hasWillPop] no
/// hay nada que confirmar y el gesto sigue intacto.
bool scaffoldAllowsInteractivePop({
  required bool hasWillPop,
  bool? isWeb,
  TargetPlatform? platform,
}) {
  return !hasWillPop;
}

/// Caja exacta de la barra de cabecera. Los tests miden por aquí.
const Key appScaffoldHeaderKey = Key('app_scaffold_header');

/// Plantilla push: header sticky (HANDOFF §4.8).
///
/// El cuerpo se ancla arriba, no al centro: un formulario corto
/// arranca igual que crear o editar evento.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.titleWidget,
    this.actions,
    this.headerBottom,
    this.floatingActionButton,
    this.bottomBar,
    this.maxContentWidth = 760,
    this.onWillPop,
  });

  final Widget body;
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? headerBottom;
  final Widget? floatingActionButton;

  /// Barra fija al pie, a todo el ancho (p. ej. `FormActionBar`). Se encarga
  /// de su propio safe area.
  final Widget? bottomBar;

  final double maxContentWidth;

  /// Si no es null, intercepta el botón atrás de la cabecera (y el back
  /// del sistema en Android). En iOS nativo el gesto de deslizar se deja
  /// pasar: `canPop: false` apaga el pop interactivo de [CupertinoPage].
  final Future<bool> Function()? onWillPop;

  Future<void> _intentarVolver(BuildContext context) async {
    if (onWillPop != null) {
      final salir = await onWillPop!();
      if (!salir || !context.mounted) return;
    }
    if (context.mounted) volverAtras(context);
  }

  @override
  Widget build(BuildContext context) {
    final canPop = scaffoldAllowsInteractivePop(hasWillPop: onWillPop != null);

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || onWillPop == null) return;
        final salir = await onWillPop!();
        if (salir && context.mounted) volverAtras(context);
      },
      child: BrowserThemeColor(
        color: TwColors.bg,
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark,
          child: Scaffold(
            backgroundColor: TwColors.bg,
            floatingActionButton: floatingActionButton,
            body: Column(
              children: [
                _PushHeader(
                  title: title,
                  titleWidget: titleWidget,
                  actions: actions,
                  mostrarAtras: onWillPop != null || context.canPop(),
                  onBack: () => _intentarVolver(context),
                ),
                if (headerBottom != null)
                  _constrained(
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: headerBottom!,
                    ),
                  ),
                Expanded(child: _constrained(body)),
                ?bottomBar,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _constrained(Widget child) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxContentWidth),
        child: child,
      ),
    );
  }
}

/// Acción de la cabecera push (atrás, editar, eliminar…).
///
/// En iOS es el botón Liquid Glass nativo; en el resto, el mismo chip
/// [TwIconButton] que los menús de evento, para que la app no tenga dos
/// estilos de cabecera conviviendo.
class NexusHeaderAction extends StatelessWidget {
  const NexusHeaderAction({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.loading = false,
    this.danger = false,
    this.variant = TwIconButtonStyle.plain,
    this.sfSymbol,
  });

  /// Lado del botón. También es el ancho de los huecos que deja la cabecera
  /// cuando no hay botón, para que el título siga centrado.
  static const double size = 44;

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool loading;
  final bool danger;
  final TwIconButtonStyle variant;

  /// SF Symbol nativo (atrás, lápiz, papelera…). Si falta se infiere.
  final String? sfSymbol;

  @override
  Widget build(BuildContext context) {
    return TwIosGlassIconButton(
      icon: icon,
      iconSize: 20,
      size: size,
      variant: variant,
      onTap: onTap,
      tooltip: tooltip,
      loading: loading,
      danger: danger,
      sfSymbol: sfSymbol,
    );
  }
}

class _PushHeader extends StatelessWidget {
  const _PushHeader({
    this.title,
    this.titleWidget,
    this.actions,
    required this.mostrarAtras,
    required this.onBack,
  });

  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final bool mostrarAtras;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    final nativoIos = usesNativeIosChrome;

    // Sin `BackdropFilter`: el cuerpo vive en un `Column` **debajo** de la
    // cabecera, nunca pasa por detrás, así que el blur solo difuminaba el fondo
    // plano del Scaffold —el mismo [TwColors.bg] que ya pinta el contenedor— y
    // el resultado era idéntico. Lo que sí costaba era un `saveLayer` por frame
    // en cada transición de las pantallas push.
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TwColors.bg,
          border: nativoIos
              ? null
              : const Border(
                  bottom: BorderSide(color: TwColors.border07, width: 1),
                ),
        ),
        child: Padding(
          key: appScaffoldHeaderKey,
          padding: EdgeInsets.fromLTRB(
            TwSpacing.screenH,
            top + 14,
            TwSpacing.screenH,
            14,
          ),
          child: Row(
            children: [
              if (mostrarAtras)
                NexusHeaderAction(
                  icon: Symbols.arrow_back_rounded,
                  tooltip: 'Volver',
                  sfSymbol: 'chevron.left',
                  onTap: onBack,
                )
              else
                const SizedBox(width: NexusHeaderAction.size),
              const SizedBox(width: 10),
              Expanded(
                child: DefaultTextStyle(
                  style: TwText.tileTitle.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  child: Semantics(
                    header: true,
                    child:
                        titleWidget ??
                        Text(title ?? '', textAlign: TextAlign.center),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (actions != null && actions!.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < actions!.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      actions![i],
                    ],
                  ],
                )
              else
                const SizedBox(width: NexusHeaderAction.size),
            ],
          ),
        ),
      ),
    );
  }
}
