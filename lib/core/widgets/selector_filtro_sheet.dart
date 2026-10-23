import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/tw_tokens.dart';
import 'app_modals.dart';
import 'pressable.dart';
import 'tw_components.dart';

/// Una opción de [showSelectorFiltroSheet].
class OpcionFiltro<T> {
  const OpcionFiltro({
    required this.valor,
    required this.titulo,
    this.detalle,
    this.conteo,
  });

  final T valor;
  final String titulo;

  /// Segunda línea (p. ej. día y hora del taller).
  final String? detalle;

  /// Cuántos registros quedan con esta opción; se muestra a la derecha.
  final int? conteo;
}

/// Hoja para elegir el valor de un filtro desplegable ([FiltroDesplegableChip]).
/// Las opciones van en una tarjeta con separadores, como una lista agrupada.
/// Devuelve la opción tocada, o `null` si se cierra sin elegir.
Future<OpcionFiltro<T>?> showSelectorFiltroSheet<T>(
  BuildContext context, {
  required String titulo,
  required List<OpcionFiltro<T>> opciones,
  required T seleccionado,
}) {
  return showAppModalBottomSheet<OpcionFiltro<T>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: TwColors.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TwSectionLabel(titulo, top: 0),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: TwColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: TwColors.border08),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    children: [
                      for (var i = 0; i < opciones.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            thickness: 1,
                            // Junto a la opción activa (con fondo) va de borde
                            // a borde: con sangría dejaba una muesca blanca.
                            indent:
                                opciones[i - 1].valor == seleccionado ||
                                    opciones[i].valor == seleccionado
                                ? 0
                                : 16,
                            color: TwColors.border08,
                          ),
                        _FilaOpcion(
                          opcion: opciones[i],
                          activa: opciones[i].valor == seleccionado,
                          onTap: () => Navigator.of(context).pop(opciones[i]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _FilaOpcion extends StatelessWidget {
  const _FilaOpcion({
    required this.opcion,
    required this.activa,
    required this.onTap,
  });

  final OpcionFiltro<Object?> opcion;
  final bool activa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final detalle = opcion.detalle;
    final conteo = opcion.conteo;
    return Pressable(
      scale: 0.99,
      onTap: onTap,
      child: Container(
        color: activa ? TwColors.blueTint : TwColors.surface,
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    opcion.titulo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.3,
                      fontWeight: activa ? FontWeight.w700 : FontWeight.w600,
                      color: TwColors.ink,
                    ),
                  ),
                  if (detalle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      detalle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: TwColors.secondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (conteo != null) ...[
              const SizedBox(width: 12),
              Text(
                '$conteo',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: activa ? TwColors.blueInk : TwColors.secondary,
                ),
              ),
            ],
            const SizedBox(width: 12),
            Icon(
              activa
                  ? Symbols.check_circle_rounded
                  : Symbols.radio_button_unchecked_rounded,
              fill: activa ? 1 : 0,
              size: 22,
              color: activa ? TwColors.blueInk : TwColors.chevronSoft,
            ),
          ],
        ),
      ),
    );
  }
}
