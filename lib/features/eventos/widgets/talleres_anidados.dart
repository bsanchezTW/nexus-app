import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/tw_tokens.dart';
import '../../../core/widgets/tw_components.dart';
import '../../../data/models/evento.dart';
import '../../../data/models/subevento.dart';

/// Talleres de un evento principal, como pestaña al pie de su tarjeta.
///
/// Va dentro de la misma tarjeta del evento (`EventRow.footer`): una franja a
/// todo el ancho con el resumen ("3 talleres") que, al tocarla, despliega los
/// talleres hacia abajo. Así se leen como parte del evento y no como otro.
class TalleresAnidados extends StatelessWidget {
  const TalleresAnidados({
    super.key,
    required this.principal,
    required this.talleres,
    required this.abierto,
    required this.onToggle,
    required this.onTallerTap,
    this.deshabilitado = false,
  });

  final Evento principal;
  final List<Subevento> talleres;
  final bool abierto;
  final VoidCallback onToggle;
  final ValueChanged<Subevento> onTallerTap;

  /// Sin red y sin copia local: se puede ver el resumen, no entrar.
  final bool deshabilitado;

  @override
  Widget build(BuildContext context) {
    final total = talleres.length;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final duracion = reduce ? Duration.zero : const Duration(milliseconds: 200);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: abierto,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            child: AnimatedContainer(
              duration: duracion,
              padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
              decoration: BoxDecoration(
                color: abierto ? TwColors.blueTint : TwColors.surfaceTint,
                border: const Border(
                  top: BorderSide(color: TwColors.border07),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Symbols.account_tree_rounded,
                    size: 17,
                    color: TwColors.blueInk,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      total == 1 ? '1 taller' : '$total talleres',
                      style: TwText.tileSubtitle.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: TwColors.blueInk,
                      ),
                    ),
                  ),
                  Text(
                    abierto ? 'Ocultar' : 'Ver',
                    style: TwText.tileSubtitle.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: TwColors.blueInk,
                    ),
                  ),
                  const SizedBox(width: 2),
                  AnimatedRotation(
                    turns: abierto ? 0.5 : 0,
                    duration: duracion,
                    child: const Icon(
                      Symbols.expand_more_rounded,
                      size: 20,
                      color: TwColors.blueInk,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: duracion,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !abierto
              ? const SizedBox(width: double.infinity)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final taller in talleres)
                      _FilaTaller(
                        taller: taller,
                        mostrarDia: principal.esMultiDia,
                        deshabilitado: deshabilitado,
                        onTap: () => onTallerTap(taller),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _FilaTaller extends StatelessWidget {
  const _FilaTaller({
    required this.taller,
    required this.mostrarDia,
    required this.deshabilitado,
    required this.onTap,
  });

  final Subevento taller;
  final bool mostrarDia;
  final bool deshabilitado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final terminado = taller.yaTermino(DateTime.now());
    final meta = [
      if (mostrarDia)
        DateFormat('EEE d MMM', 'es').format(taller.dia).replaceAll('.', ''),
      if ((taller.sala ?? '').trim().isNotEmpty) taller.sala!.trim(),
      if ((taller.expositor ?? '').trim().isNotEmpty) taller.expositor!.trim(),
    ].join(' · ');

    return Opacity(
      opacity: deshabilitado ? 0.55 : 1,
      child: TwPressable(
        scale: 0.99,
        onTap: deshabilitado ? null : onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
          decoration: const BoxDecoration(
            color: TwColors.surface,
            border: Border(top: BorderSide(color: TwColors.border07)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _hora(taller.horaInicio),
                      style: TwText.tileTitle.copyWith(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: terminado ? TwColors.muted : TwColors.hero700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _hora(taller.horaFin),
                      style: TwText.tileSubtitle.copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 30,
                margin: const EdgeInsets.only(right: 12),
                color: TwColors.border10,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      taller.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TwText.tileTitle.copyWith(
                        fontSize: 13.5,
                        height: 1.3,
                        color: terminado ? TwColors.secondary : TwColors.ink,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TwText.tileSubtitle.copyWith(fontSize: 11.5),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Symbols.chevron_right_rounded,
                size: 20,
                color: TwColors.chevron,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _hora(TimeOfDay hora) {
    final h = hora.hour.toString().padLeft(2, '0');
    final m = hora.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
