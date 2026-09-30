import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/tw_tokens.dart';
import 'nexus_components.dart';
import 'tw_components.dart';

/// Piezas de los formularios largos (evento, taller, actividad de captura).
///
/// Un formulario se arma con [FormSection]es: cada una agrupa los campos de un
/// mismo tema bajo un título con icono, en una tarjeta blanca. Así el usuario
/// sabe en qué parte está y qué le falta, en vez de enfrentarse a una columna
/// de veinte campos iguales.

/// Tarjeta de una sección del formulario.
class FormSection extends StatelessWidget {
  const FormSection({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Acción o estado a la derecha del título (p. ej. un contador).
  final Widget? trailing;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: const BoxDecoration(
        color: TwColors.surface,
        borderRadius: TwRadii.card,
        border: Border.fromBorderSide(BorderSide(color: TwColors.border07)),
        boxShadow: TwShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: TwColors.blueTint,
                  borderRadius: TwRadii.iconSm,
                ),
                child: Icon(icon, size: 19, color: TwColors.blueInk),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: TwText.tileTitle.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle!, style: TwText.tileSubtitle),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
          const SizedBox(height: 16),
          ..._espaciados(children),
        ],
      ),
    );
  }

  static List<Widget> _espaciados(List<Widget> hijos) {
    return [
      for (var i = 0; i < hijos.length; i++) ...[
        if (i > 0) const SizedBox(height: FormSection.fieldGap),
        hijos[i],
      ],
    ];
  }

  /// Aire entre campos dentro de una sección.
  static const fieldGap = 16.0;

  /// Aire entre secciones.
  static const gap = 14.0;
}

/// Etiqueta de un campo, en tipo oración. Los campos opcionales lo dicen; los
/// obligatorios no llevan asterisco (son mayoría y el asterisco ensucia).
class FormFieldLabel extends StatelessWidget {
  const FormFieldLabel(this.text, {super.key, this.opcional = false});

  final String text;
  final bool opcional;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 7),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: text),
            if (opcional)
              TextSpan(
                text: '  Opcional',
                style: TwText.tileSubtitle.copyWith(
                  fontSize: 11.5,
                  color: TwColors.muted,
                ),
              ),
          ],
        ),
        style: TwText.checkboxLabel.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: TwColors.labelInk,
        ),
      ),
    );
  }
}

/// Etiqueta + campo, con una ayuda opcional debajo.
class FormLabeledField extends StatelessWidget {
  const FormLabeledField({
    super.key,
    required this.label,
    required this.child,
    this.opcional = false,
    this.ayuda,
  });

  final String label;
  final Widget child;
  final bool opcional;
  final String? ayuda;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormFieldLabel(label, opcional: opcional),
        child,
        if (ayuda != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              ayuda!,
              style: TwText.tileSubtitle.copyWith(fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }
}

/// Dos campos en la misma fila cuando hay ancho; uno bajo el otro si no.
class FormFieldRow extends StatelessWidget {
  const FormFieldRow({
    super.key,
    required this.left,
    required this.right,
    this.minWidth = 300,
  });

  final Widget left;
  final Widget right;

  /// Ancho mínimo para ir lado a lado.
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < minWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: FormSection.fieldGap), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

/// Una opción de [FormChoiceCards].
class FormChoice<T> {
  const FormChoice({
    required this.value,
    required this.icon,
    required this.title,
    required this.description,
  });

  final T value;
  final IconData icon;
  final String title;
  final String description;
}

/// Elección entre pocas opciones que necesitan explicarse (p. ej. evento
/// principal o taller). Cada opción es una tarjeta con su descripción.
class FormChoiceCards<T> extends StatelessWidget {
  const FormChoiceCards({
    super.key,
    required this.choices,
    required this.value,
    required this.onChanged,
  });

  final List<FormChoice<T>> choices;
  final T value;

  /// `null` deja la elección fija (sin red, guardando).
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < choices.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: _tarjeta(choices[i])),
          ],
        ],
      ),
    );
  }

  Widget _tarjeta(FormChoice<T> opcion) {
    final elegida = opcion.value == value;
    final habilitada = onChanged != null;
    return Semantics(
      button: true,
      selected: elegida,
      label: opcion.title,
      child: TwPressable(
        onTap: !habilitada ? null : () => onChanged!(opcion.value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(13, 12, 12, 13),
          decoration: BoxDecoration(
            color: elegida ? TwColors.blueTint : TwColors.surface,
            borderRadius: TwRadii.tile,
            border: Border.all(
              color: elegida ? TwColors.fieldBorderActive : TwColors.border10,
              width: elegida ? 1.5 : 1,
            ),
            boxShadow: elegida ? null : TwShadows.card,
          ),
          child: Opacity(
            opacity: habilitada || elegida ? 1 : 0.55,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      opcion.icon,
                      size: 22,
                      color: elegida ? TwColors.hero700 : TwColors.iconInk,
                    ),
                    const Spacer(),
                    Icon(
                      elegida
                          ? Symbols.check_circle_rounded
                          : Symbols.radio_button_unchecked_rounded,
                      size: 20,
                      fill: elegida ? 1 : 0,
                      color: elegida ? TwColors.hero700 : TwColors.chevron,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  opcion.title,
                  style: TwText.tileTitle.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  opcion.description,
                  style: TwText.tileSubtitle.copyWith(
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Interruptor con título y explicación, para usar dentro de una sección.
class FormToggleRow extends StatelessWidget {
  const FormToggleRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;

  /// `null` lo deja fijo.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final habilitado = onChanged != null;
    return Semantics(
      toggled: value,
      child: TwPressable(
        scale: 0.99,
        onTap: habilitado ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: habilitado ? 1 : 0.55,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 21, color: TwColors.iconInk),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TwText.tileTitle.copyWith(fontSize: 14),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          style: TwText.tileSubtitle.copyWith(fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                IgnorePointer(
                  ignoring: !habilitado,
                  child: NexusToggle(
                    value: value,
                    onChanged: (v) => onChanged?.call(v),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Línea divisoria entre filas de una sección.
class FormDivider extends StatelessWidget {
  const FormDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, thickness: 1, color: TwColors.border07);
  }
}

/// Campo que abre un selector (hora, fecha y hora…). Sin valor muestra el
/// [placeholder]; con [onClear] ofrece vaciarlo.
class FormPickerField extends StatelessWidget {
  const FormPickerField({
    super.key,
    required this.valor,
    required this.placeholder,
    required this.icon,
    this.onTap,
    this.onClear,
    this.enabled = true,
    this.error = false,
  });

  final String? valor;
  final String placeholder;
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final bool enabled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final editable = enabled && onTap != null;
    final tieneValor = valor != null && valor!.isNotEmpty;
    final Color borde;
    if (error) {
      borde = TwColors.danger;
    } else {
      borde = editable ? TwColors.fieldBorderActive : TwColors.fieldBorder;
    }
    return Material(
      color: editable ? TwColors.fieldBg : TwColors.bg,
      borderRadius: TwRadii.field,
      child: InkWell(
        onTap: editable ? onTap : null,
        borderRadius: TwRadii.field,
        child: Container(
          height: 52,
          padding: const EdgeInsets.only(left: 14, right: 6),
          decoration: BoxDecoration(
            borderRadius: TwRadii.field,
            border: Border.all(color: borde),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 19,
                color: editable ? TwColors.brand700 : TwColors.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tieneValor ? valor! : placeholder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TwText.input.copyWith(
                    fontSize: 14.5,
                    fontWeight: tieneValor ? FontWeight.w600 : FontWeight.w500,
                    color: tieneValor
                        ? (editable ? TwColors.ink : TwColors.secondary)
                        : TwColors.muted,
                  ),
                ),
              ),
              if (tieneValor && onClear != null && editable)
                IconButton(
                  onPressed: onClear,
                  tooltip: 'Quitar',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Symbols.close_rounded,
                    size: 18,
                    color: TwColors.iconIdle,
                  ),
                )
              else
                const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aviso en línea dentro de una sección (validación cruzada, contexto).
class FormNotice extends StatelessWidget {
  const FormNotice(this.text, {super.key, this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: error ? TwColors.dangerTint : TwColors.surfaceTint,
        borderRadius: TwRadii.field,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error ? Symbols.error_rounded : Symbols.info_rounded,
            size: 17,
            color: error ? TwColors.danger : TwColors.blueInk,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TwText.tileSubtitle.copyWith(
                fontSize: 12.5,
                height: 1.35,
                color: error ? TwColors.danger : TwColors.labelInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra fija al pie con la acción principal del formulario. Queda visible
/// mientras se recorre el formulario, en vez de esperar al final de la lista.
class FormActionBar extends StatelessWidget {
  const FormActionBar({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.maxWidth = 760,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final inferior = MediaQuery.viewPaddingOf(context).bottom;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: TwColors.bg,
        border: Border(top: BorderSide(color: TwColors.border07)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          TwSpacing.screenH,
          12,
          TwSpacing.screenH,
          12 + inferior,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth - 40),
            child: Opacity(
              opacity: onPressed == null && !loading ? 0.5 : 1,
              child: TwPrimaryButton(
                label: label,
                loading: loading,
                onTap: onPressed,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
