import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/tw_tokens.dart';
import 'action_lock.dart';

/// Librería de componentes del rediseño (guía §3 átomos, §4 formularios,
/// §5 superficies).
///
/// Reglas que aplican a todo el archivo:
/// * nada de widgets Material por defecto (`Card`, `ListTile`, `AppBar`…);
/// * sin ripple: los taps van por [GestureDetector];
/// * 1 px del mock = 1 dp, sin redondear a múltiplos de 8.

/// Vidrio de cabeceras y navbar: el mismo [BackdropFilter] en todas las
/// plataformas (web, Windows, Android, iOS).
class TwGlassFilter extends StatelessWidget {
  const TwGlassFilter({super.key, required this.child, this.sigma = 18});

  final Widget child;
  final double sigma;

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// §3 · Átomos
// ---------------------------------------------------------------------------

/// Label de sección en MAYÚSCULAS, con su ritmo vertical incluido
/// (24 arriba / 11 abajo) y 3 px de sangría izquierda.
class TwSectionLabel extends StatelessWidget {
  const TwSectionLabel(this.text, {super.key, this.top = 24});

  final String text;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 11, left: 3),
      child: Text(text.toUpperCase(), style: TwText.sectionLabel),
    );
  }
}

enum TwIconButtonStyle { plain, brand }

/// Botón-icono de cabecera: 44×44, radio 14.
///
/// Es el único botón de acción de las cabeceras (atrás, editar, compartir,
/// eliminar). Admite estado deshabilitado (`onTap` nulo), de carga y
/// destructivo, para que ninguna pantalla tenga que dibujarse el suyo.
class TwIconButton extends StatelessWidget {
  const TwIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.iconSize = 22,
    this.size = 44,
    this.variant = TwIconButtonStyle.plain,
    this.tooltip,
    this.danger = false,
    this.loading = false,
    this.badgeCount,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double iconSize;

  /// Lado del botón. 44 salvo cuando tiene que calzar con otro control (el
  /// buscador fijado de las listas mide 48).
  final double size;

  final TwIconButtonStyle variant;
  final String? tooltip;

  /// Acción destructiva: tiñe el icono de rojo.
  final bool danger;

  final bool loading;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final isBrand = variant == TwIconButtonStyle.brand;
    final habilitado = onTap != null && !loading;

    final Color fg;
    if (isBrand) {
      fg = Colors.white;
    } else if (!habilitado) {
      fg = TwColors.muted;
    } else {
      fg = danger ? TwColors.danger : TwColors.inkSoft;
    }

    Widget boton = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: !habilitado ? null : () => ActionLock.instance.run(onTap!),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isBrand ? null : TwColors.surface,
          gradient: isBrand ? TwGradients.brand : null,
          borderRadius: TwRadii.button,
          border: isBrand ? null : Border.all(color: TwColors.border08),
          boxShadow: isBrand ? TwShadows.brandButton : TwShadows.soft,
        ),
        child: loading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isBrand ? Colors.white : TwColors.brand700,
                ),
              )
            : Icon(icon, size: iconSize, color: fg),
      ),
    );

    if ((badgeCount ?? 0) > 0) {
      final count = badgeCount!;
      boton = Stack(
        clipBehavior: Clip.none,
        children: [
          boton,
          Positioned(
            top: -5,
            right: -7,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: TwColors.danger,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  height: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (tooltip != null) {
      boton = Tooltip(message: tooltip!, child: boton);
    }
    return Semantics(button: true, label: tooltip, child: boton);
  }
}

enum TwIconBoxStyle {
  brand,
  blueTint,
  greenTint,
  purpleTint,
  amberTint,
  excel,
  support,
}

/// Caja de icono de un action tile / tarjeta de soporte.
class TwIconBox extends StatelessWidget {
  const TwIconBox(
    this.icon, {
    super.key,
    this.variant = TwIconBoxStyle.blueTint,
  });

  final IconData icon;
  final TwIconBoxStyle variant;

  @override
  Widget build(BuildContext context) {
    late final double size;
    late final double radius;
    late final double iconSize;
    late final Color fg;
    Color? bg;
    Gradient? grad;
    List<BoxShadow> shadow = const [];

    switch (variant) {
      case TwIconBoxStyle.brand:
        size = 42;
        radius = 13;
        iconSize = 21;
        grad = TwGradients.tileIcon;
        fg = Colors.white;
        shadow = TwShadows.tileIcon;
      case TwIconBoxStyle.blueTint:
        size = 42;
        radius = 13;
        iconSize = 21;
        bg = TwColors.blueTint;
        fg = TwColors.blueInk;
      case TwIconBoxStyle.greenTint:
        size = 42;
        radius = 13;
        iconSize = 21;
        bg = TwColors.greenTint;
        fg = TwColors.greenInk;
      case TwIconBoxStyle.purpleTint:
        size = 42;
        radius = 13;
        iconSize = 21;
        bg = TwColors.purpleTint;
        fg = TwColors.purpleInk;
      case TwIconBoxStyle.amberTint:
        size = 42;
        radius = 13;
        iconSize = 21;
        bg = TwColors.amberTint;
        fg = TwColors.amberInk;
      // El radio del cuadro de Excel es 11, no 13. Es intencional.
      case TwIconBoxStyle.excel:
        size = 42;
        radius = 11;
        iconSize = 21;
        grad = TwGradients.excel;
        fg = Colors.white;
        shadow = TwShadows.excelIcon;
      case TwIconBoxStyle.support:
        size = 38;
        radius = 12;
        iconSize = 20;
        bg = TwColors.surfaceTint;
        fg = TwColors.brand700;
    }

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        gradient: grad,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow,
      ),
      child: Icon(
        icon,
        size: iconSize,
        color: fg,
        fill: variant == TwIconBoxStyle.excel ? 1 : 0,
      ),
    );
  }
}

enum TwStatus { activo, finalizado }

class TwStatusPill extends StatelessWidget {
  const TwStatusPill(this.status, {super.key});

  final TwStatus status;

  @override
  Widget build(BuildContext context) {
    final active = status == TwStatus.activo;
    final fg = active ? TwColors.statusActive : TwColors.statusEnded;
    final bg = active ? TwColors.statusActiveBg : TwColors.statusEndedBg;
    final bd = active ? TwColors.statusActiveBd : TwColors.statusEndedBd;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: TwRadii.pill,
        border: Border.all(color: bd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            active ? 'ACTIVO' : 'FINALIZADO',
            style: TwText.statusPill.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

/// Origen de un evento de leads, con el mismo patrón que [TwStatusPill].
///
/// Interno: nació de un evento organizado por Transworld. Externo: alta manual
/// en la lista de leads, sin evento de registro detrás.
class TwOriginPill extends StatelessWidget {
  const TwOriginPill({super.key, required this.interno});

  final bool interno;

  @override
  Widget build(BuildContext context) {
    final fg = interno ? TwColors.originInternal : TwColors.originExternal;
    final bg = interno ? TwColors.originInternalBg : TwColors.originExternalBg;
    final bd = interno ? TwColors.originInternalBd : TwColors.originExternalBd;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: TwRadii.pill,
        border: Border.all(color: bd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            interno ? 'INTERNO' : 'EXTERNO',
            style: TwText.statusPill.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}

/// Píldora de fecha del hero: `martes 25 · agosto 2026`.
class TwDatePill extends StatelessWidget {
  const TwDatePill(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: TwColors.whiteA16,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: TwColors.whiteA18),
      ),
      child: Text(
        text,
        style: TwText.datePill,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Badge `XLSX` del tile de exportación.
class TwBadge extends StatelessWidget {
  const TwBadge(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: TwColors.excelBadgeBg,
        borderRadius: TwRadii.badge,
        border: Border.all(color: TwColors.excelBadgeBd),
      ),
      child: Text(text, style: TwText.badge),
    );
  }
}

class TwStat {
  const TwStat(this.value, this.label, {this.valueColor});

  final String value;
  final String label;

  /// `null` = blanco.
  final Color? valueColor;
}

/// Fila de métricas del hero: columnas de igual ancho separadas por una línea
/// de 1 px al 14 % de blanco.
class TwStatsRow extends StatelessWidget {
  const TwStatsRow(this.stats, {super.key});

  final List<TwStat> stats;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List.generate(stats.length, (i) {
            final s = stats[i];
            return Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: i == 0
                      ? null
                      : const Border(
                          left: BorderSide(color: TwColors.whiteA14),
                        ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        s.value,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: s.valueColor == null
                            ? TwText.statValue
                            : TwText.statValue.copyWith(color: s.valueColor),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        s.label.toUpperCase(),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: TwText.statLabel,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// §4 · Formularios y botones
// ---------------------------------------------------------------------------

class TwFieldLabel extends StatelessWidget {
  const TwFieldLabel(this.text, {super.key, this.top = 0});

  final String text;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 8, left: 2),
      child: Text(text.toUpperCase(), style: TwText.fieldLabel),
    );
  }
}

/// Campo de texto del rediseño: 52 de alto, radio 12, sin cambio de borde al
/// enfocar (así está en el mock).
class TwTextField extends StatelessWidget {
  const TwTextField({
    super.key,
    required this.controller,
    required this.icon,
    required this.hint,
    this.obscure = false,
    this.enabled = true,
    this.keyboardType,
    this.trailing,
    this.onChanged,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.autofillHints,
    this.inputFormatters,
    this.autocorrect = true,
    this.enableSuggestions = true,
  });

  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final bool obscure;
  final bool enabled;
  final TextInputType? keyboardType;
  final Widget? trailing;
  final ValueChanged<String>? onChanged;
  final TextInputAction textInputAction;
  final VoidCallback? onSubmitted;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final bool autocorrect;
  final bool enableSuggestions;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: enabled ? TwColors.fieldBg : TwColors.bg,
        borderRadius: TwRadii.field,
        border: Border.all(
          color: enabled ? TwColors.fieldBorderActive : TwColors.fieldBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: TwColors.iconIdle),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              obscureText: obscure,
              keyboardType: keyboardType,
              onChanged: onChanged,
              textInputAction: textInputAction,
              onSubmitted: (_) => onSubmitted?.call(),
              autofillHints: autofillHints,
              inputFormatters: inputFormatters,
              autocorrect: autocorrect,
              enableSuggestions: enableSuggestions,
              style: TwText.input,
              cursorColor: TwColors.brand700,
              cursorWidth: 1.6,
              // El `inputDecorationTheme` global rellena y dibuja un
              // `OutlineInputBorder`: sin anular relleno y los cuatro bordes
              // aquí, se ve una caja blanca más chica dentro del campo.
              decoration: InputDecoration(
                isDense: true,
                isCollapsed: true,
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: hint,
                hintStyle: TwText.input.copyWith(color: TwColors.muted),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Ojo de contraseña: se pasa como `trailing` de [TwTextField].
class TwPasswordEye extends StatelessWidget {
  const TwPasswordEye({super.key, required this.visible, required this.onTap});

  final bool visible;

  /// `null` lo deja atenuado y sin respuesta (p. ej. mientras se guarda).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: visible ? 'Ocultar contraseña' : 'Mostrar contraseña',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 30,
          height: 52,
          child: Align(
            alignment: Alignment.centerRight,
            child: Icon(
              visible
                  ? Symbols.visibility_off_rounded
                  : Symbols.visibility_rounded,
              size: 21,
              color: onTap == null ? TwColors.chevron : TwColors.iconEye,
            ),
          ),
        ),
      ),
    );
  }
}

/// Error de validación: siempre debajo del último campo, nunca dentro del
/// input y nunca como toast.
class TwErrorLine extends StatelessWidget {
  const TwErrorLine(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 2),
      child: Row(
        children: [
          const Icon(Symbols.error_rounded, size: 16, color: TwColors.danger),
          const SizedBox(width: 6),
          Expanded(child: Text(message, style: TwText.errorText)),
        ],
      ),
    );
  }
}

/// Fila "Recordarme" + enlace. El checkbox es un icono, no el widget Material.
class TwCheckRow extends StatelessWidget {
  const TwCheckRow({
    super.key,
    required this.checked,
    required this.label,
    required this.onToggle,
    required this.linkText,
    required this.onLink,
  });

  final bool checked;
  final String label;
  final VoidCallback onToggle;
  final String linkText;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 18),
      // Ambos lados son flexibles: con el texto escalado (o una traducción
      // más larga) la fila recorta en vez de desbordar.
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Semantics(
              label: label,
              checked: checked,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggle,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      checked
                          ? Symbols.check_box_rounded
                          : Symbols.check_box_outline_blank_rounded,
                      size: 22,
                      fill: 1,
                      color: checked ? TwColors.brand700 : TwColors.chevron,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: ExcludeSemantics(
                        child: Text(
                          label,
                          style: TwText.checkboxLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onLink,
              child: Text(
                linkText,
                style: TwText.linkText,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Botón primario: 52 de alto, radio 14, gradiente de marca.
class TwPrimaryButton extends StatelessWidget {
  const TwPrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return TwPressable(
      onTap: loading ? null : onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          gradient: TwGradients.brand,
          borderRadius: TwRadii.button,
          boxShadow: TwShadows.primary,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading) ...const [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                  backgroundColor: Color(0x59FFFFFF), // blanco 35 %
                ),
              ),
              SizedBox(width: 9),
            ],
            Text(label, style: TwText.button),
          ],
        ),
      ),
    );
  }
}

/// Botón blanco que vive DENTRO de la hero card.
class TwHeroButton extends StatelessWidget {
  const TwHeroButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TwPressable(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: TwColors.surface,
          borderRadius: TwRadii.heroBtn,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 22, color: TwColors.deepInk),
              const SizedBox(width: 9),
            ],
            Flexible(
              child: Text(
                label,
                style: TwText.buttonDark,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Feedback táctil del diseño: escala 0.98 en 90 ms, sin ripple.
class TwPressable extends StatefulWidget {
  const TwPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.scale = 0.98,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<TwPressable> createState() => _TwPressableState();
}

class _TwPressableState extends State<TwPressable> {
  bool _down = false;

  void _set(bool value) {
    if (_down == value) return;
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final activo = widget.onTap != null || widget.onLongPress != null;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: activo ? (_) => _set(true) : null,
      onTapUp: activo ? (_) => _set(false) : null,
      onTapCancel: activo ? () => _set(false) : null,
      onTap: widget.onTap == null
          ? null
          : () => ActionLock.instance.run(widget.onTap!),
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down && !reduce ? widget.scale : 1,
        duration: reduce ? Duration.zero : const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// §5 · Superficies
// ---------------------------------------------------------------------------

/// Contenedor blanco base: radio 18, borde `border07`, sombra `card`.
class TwCard extends StatelessWidget {
  const TwCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: const BoxDecoration(
        color: TwColors.surface,
        borderRadius: TwRadii.card,
        border: Border.fromBorderSide(BorderSide(color: TwColors.border07)),
        boxShadow: TwShadows.card,
      ),
      child: child,
    );
  }
}

/// Tarjeta de KPI del bloque "Resumen": caja de icono 38, valor 27 y
/// etiqueta 13.5. La usan el home y la vista del usuario externo.
class TwKpiCard extends StatelessWidget {
  const TwKpiCard({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.tint,
    required this.iconColor,
    this.onTap,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color tint;
  final Color iconColor;

  /// Con valor, la tarjeta abre un detalle: se vuelve pulsable y muestra el
  /// chevron para que se lea como navegable y no como un número muerto.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tarjeta = Container(
      padding: const EdgeInsets.all(15),
      decoration: const BoxDecoration(
        color: TwColors.surface,
        borderRadius: TwRadii.card,
        border: Border.fromBorderSide(BorderSide(color: TwColors.border07)),
        boxShadow: TwShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: tint, borderRadius: TwRadii.field),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(
                value,
                key: ValueKey(value),
                maxLines: 1,
                style: TwText.kpiValue,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(child: Text(label, style: TwText.kpiLabel)),
              if (onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: TwColors.muted,
                ),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return tarjeta;
    return TwPressable(onTap: onTap, child: tarjeta);
  }
}

/// Fila de acción de las pantallas-menú (Evento y Evento de leads).
class TwActionTile extends StatelessWidget {
  const TwActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.iconStyle = TwIconBoxStyle.blueTint,
    this.subtitle,
    this.badge,
    this.excel = false,
    this.loading = false,
  });

  final IconData icon;
  final TwIconBoxStyle iconStyle;
  final String title;
  final String? subtitle;

  /// `'XLSX'` o `null`.
  final String? badge;

  /// Borde y sombra verdes de la variante de exportación.
  final bool excel;

  /// Sustituye el chevron por un spinner mientras carga la siguiente pantalla.
  final bool loading;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TwPressable(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
        decoration: BoxDecoration(
          color: TwColors.surface,
          borderRadius: TwRadii.tile,
          border: Border.all(
            color: excel ? TwColors.excelCardBd : TwColors.border07,
          ),
          boxShadow: excel ? TwShadows.excelCard : TwShadows.card,
        ),
        child: Row(
          children: [
            TwIconBox(icon, variant: iconStyle),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: TwText.tileTitle),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: TwText.tileSubtitle),
                  ],
                ],
              ),
            ),
            if (badge != null) ...[const SizedBox(width: 13), TwBadge(badge!)],
            const SizedBox(width: 13),
            if (loading)
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: excel ? TwColors.excel700 : TwColors.brand700,
                ),
              )
            else
              Icon(
                Symbols.chevron_right_rounded,
                size: 22,
                color: excel ? TwColors.chevronGreen : TwColors.chevron,
              ),
          ],
        ),
      ),
    );
  }
}

/// Hero de las pantallas de detalle: fecha + estado, título, ubicación,
/// métricas y CTA. Capas: gradiente base → foto opcional → velo → contenido.
class TwHeroCard extends StatelessWidget {
  const TwHeroCard({
    super.key,
    required this.dateText,
    required this.status,
    required this.title,
    required this.location,
    required this.stats,
    required this.ctaLabel,
    required this.ctaIcon,
    required this.onCta,
    this.mostrarCta = true,
    this.photo,
    this.titleHeight,
  });

  final String dateText;
  final TwStatus status;
  final String title;
  final String location;
  final List<TwStat> stats;
  final String ctaLabel;
  final IconData ctaIcon;
  final VoidCallback onCta;
  final bool mostrarCta;
  final Widget? photo;

  /// El evento de leads usa 1.22 en vez del 1.20 por defecto (§9).
  final double? titleHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        gradient: TwGradients.hero,
        borderRadius: TwRadii.hero,
        boxShadow: TwShadows.hero,
      ),
      child: Stack(
        children: [
          if (photo != null) Positioned.fill(child: photo!),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: TwGradients.heroScrim),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: TwDatePill(dateText)),
                    const SizedBox(width: 8),
                    TwStatusPill(status),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: titleHeight == null
                      ? TwText.heroTitle
                      : TwText.heroTitle.copyWith(height: titleHeight),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (location.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      const Icon(
                        Symbols.location_on_rounded,
                        size: 16,
                        color: TwColors.whiteA66,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          location,
                          style: TwText.heroMeta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                TwStatsRow(stats),
                if (mostrarCta)
                  TwHeroButton(label: ctaLabel, icon: ctaIcon, onTap: onCta),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// La cabecera de detalle (§5 · TwDetailHeader) vive ahora dentro de
// `TwDetailScaffold`: allí va fija sobre el contenido y colapsa con el scroll,
// para que el "atrás" y las acciones no se pierdan al desplazarse.
