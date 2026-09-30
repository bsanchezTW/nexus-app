import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/constants/app_role.dart';
import '../../../core/theme/tw_tokens.dart';
import '../../../core/widgets/tw_components.dart';

/// Qué puede hacer cada rol, en una línea. Es lo que faltaba en el desplegable:
/// quien crea el usuario tenía que saber de memoria la diferencia.
String descripcionRol(AppRole rol) => switch (rol) {
  AppRole.admin => 'Acceso total: usuarios, eventos y exportaciones.',
  AppRole.organizador => 'Crea y edita eventos y actividades, y exporta datos.',
  AppRole.user => 'Registra y acredita solo en los eventos que se le asignen.',
  AppRole.externo => 'Vista reducida, limitada a sus eventos asignados.',
};

IconData iconoRol(AppRole rol) => switch (rol) {
  AppRole.admin => Symbols.admin_panel_settings_rounded,
  AppRole.organizador => Symbols.event_available_rounded,
  AppRole.user => Symbols.badge_rounded,
  AppRole.externo => Symbols.person_pin_rounded,
};

/// Lista de roles con su descripción; se elige uno tocando la fila.
class SelectorRolUsuario extends StatelessWidget {
  const SelectorRolUsuario({
    super.key,
    required this.roles,
    required this.value,
    required this.onChanged,
    this.error = false,
  });

  final List<AppRole> roles;
  final AppRole? value;

  /// `null` deja el rol fijo.
  final ValueChanged<AppRole>? onChanged;

  /// Se intentó guardar sin elegir.
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: TwRadii.field,
        border: Border.all(
          color: error ? TwColors.danger : TwColors.border10,
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < roles.length; i++)
            _Opcion(
              rol: roles[i],
              elegido: roles[i] == value,
              primero: i == 0,
              onTap: onChanged == null ? null : () => onChanged!(roles[i]),
            ),
        ],
      ),
    );
  }
}

class _Opcion extends StatelessWidget {
  const _Opcion({
    required this.rol,
    required this.elegido,
    required this.primero,
    required this.onTap,
  });

  final AppRole rol;
  final bool elegido;
  final bool primero;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: elegido,
      button: true,
      child: TwPressable(
        scale: 0.99,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: elegido ? TwColors.blueTint : TwColors.surface,
            border: primero
                ? null
                : const Border(top: BorderSide(color: TwColors.border07)),
          ),
          child: Opacity(
            opacity: onTap == null && !elegido ? 0.5 : 1,
            child: Row(
              children: [
                Icon(
                  iconoRol(rol),
                  size: 22,
                  color: elegido ? TwColors.hero700 : TwColors.iconInk,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rol.label,
                        style: TwText.tileTitle.copyWith(
                          fontSize: 14,
                          fontWeight: elegido
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        descripcionRol(rol),
                        style: TwText.tileSubtitle.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  elegido
                      ? Symbols.radio_button_checked_rounded
                      : Symbols.radio_button_unchecked_rounded,
                  size: 20,
                  fill: elegido ? 1 : 0,
                  color: elegido ? TwColors.hero700 : TwColors.chevron,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
