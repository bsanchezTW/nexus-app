import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/router/route_paths.dart';
import '../../core/theme/tw_tokens.dart';
import '../../core/widgets/app_modals.dart';
import '../../core/widgets/espera_bloqueante.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/tw_components.dart';
import '../../data/models/subevento.dart';
import '../subeventos/providers/subeventos_providers.dart';
import '../subeventos/sugerir_subevento_en_curso.dart';

/// Dónde acredita el escáner: la entrada del evento ([taller] nulo) o un
/// taller. Acreditar un taller también acredita la entrada (lo hace el
/// servidor); la entrada no marca ningún taller.
class DestinoEscaneo {
  const DestinoEscaneo.entrada() : taller = null;
  const DestinoEscaneo.taller(Subevento this.taller);

  final Subevento? taller;
}

/// Abre el escáner del evento. Si el evento tiene talleres, antes pregunta
/// "¿Dónde vas a acreditar?"; sin talleres va directo a la entrada.
///
/// Toma el contenedor de Riverpod del [context] al tocar, así los botones que
/// lo llaman no necesitan ser `Consumer`.
Future<void> abrirEscanerQr(BuildContext context, String eventoId) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final provider = subeventosPorEventoProvider(eventoId);
  // El provider es autoDispose: la suscripción lo mantiene vivo mientras
  // llega la lista.
  final suscripcion = container.listen(provider, (_, _) {});
  List<Subevento> talleres;
  try {
    talleres =
        container.read(provider).valueOrNull ??
        await conEspera(context, () => container.read(provider.future));
  } catch (_) {
    talleres = const [];
  } finally {
    suscripcion.close();
  }
  if (!context.mounted) return;

  if (talleres.isEmpty) {
    context.push(RoutePaths.acreditarQr(eventoId));
    return;
  }
  final destino = await showDestinoEscaneoSheet(
    context,
    talleres: talleres,
    ahora: DateTime.now(),
  );
  if (destino == null || !context.mounted) return;
  context.push(
    RoutePaths.acreditarQr(eventoId, subeventoId: destino.taller?.id),
  );
}

/// Hoja "¿Dónde vas a acreditar?": la entrada arriba, destacada, y debajo los
/// talleres por horario, con el que está en curso marcado. Devuelve `null`
/// si se cierra sin elegir.
Future<DestinoEscaneo?> showDestinoEscaneoSheet(
  BuildContext context, {
  required List<Subevento> talleres,
  required DateTime ahora,
}) {
  final ordenados = [...talleres]
    ..sort((a, b) => _inicio(a).compareTo(_inicio(b)));
  final enCurso = sugerirSubeventoEnCurso(talleres, ahora);

  return showAppModalBottomSheet<DestinoEscaneo>(
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
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            key: const Key('destino_escaneo_sheet'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 3, bottom: 14),
                child: Text(
                  '¿Dónde vas a acreditar?',
                  style: TwText.tileTitle.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _Grupo(
                children: [
                  _Fila(
                    key: const Key('destino_entrada'),
                    icono: Symbols.door_front_rounded,
                    titulo: 'Entrada del evento principal',
                    detalle: 'Acredita la llegada al evento',
                    onTap: () => Navigator.of(
                      context,
                    ).pop(const DestinoEscaneo.entrada()),
                  ),
                ],
              ),
              const TwSectionLabel('Talleres', top: 22),
              _Grupo(
                children: [
                  for (final taller in ordenados)
                    _Fila(
                      key: Key('destino_taller_${taller.id}'),
                      titulo: taller.nombre,
                      detalle: _detalle(taller),
                      enCurso: taller.id == enCurso?.id,
                      apagado: taller.yaTermino(ahora),
                      onTap: () => Navigator.of(
                        context,
                      ).pop(DestinoEscaneo.taller(taller)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

DateTime _inicio(Subevento t) => DateTime(
  t.dia.year,
  t.dia.month,
  t.dia.day,
  t.horaInicio.hour,
  t.horaInicio.minute,
);

String _detalle(Subevento t) {
  String hora(TimeOfDay h) =>
      '${h.hour.toString().padLeft(2, '0')}:${h.minute.toString().padLeft(2, '0')}';
  final dia = DateFormat('EEE d MMM', 'es').format(t.dia);
  final sala = t.sala?.trim();
  return [
    '$dia · ${hora(t.horaInicio)}–${hora(t.horaFin)}',
    if (sala != null && sala.isNotEmpty) sala,
  ].join(' · ');
}

/// Tarjeta blanca con filas separadas por hairlines, como una lista agrupada.
class _Grupo extends StatelessWidget {
  const _Grupo({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: TwColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TwColors.border08),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                const Divider(
                  height: 1,
                  thickness: 1,
                  indent: 16,
                  color: TwColors.border08,
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    super.key,
    required this.titulo,
    required this.detalle,
    required this.onTap,
    this.icono,
    this.enCurso = false,
    this.apagado = false,
  });

  final String titulo;
  final String detalle;
  final VoidCallback onTap;

  /// Solo la entrada lleva icono: la distingue de los talleres.
  final IconData? icono;
  final bool enCurso;

  /// Taller que ya terminó: se puede elegir, pero pasa a segundo plano.
  final bool apagado;

  @override
  Widget build(BuildContext context) {
    final colorTitulo = apagado ? TwColors.secondary : TwColors.ink;

    return Pressable(
      scale: 0.99,
      onTap: onTap,
      child: Container(
        color: TwColors.surface,
        padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
        child: Row(
          children: [
            if (icono != null) ...[
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: TwColors.blueTint,
                  borderRadius: TwRadii.iconLg,
                ),
                child: Icon(icono, size: 21, color: TwColors.hero700),
              ),
              const SizedBox(width: 13),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TwText.tileTitle.copyWith(
                      fontSize: 14.5,
                      color: colorTitulo,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detalle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TwText.tileSubtitle.copyWith(
                      color: TwColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            if (enCurso) ...[
              const SizedBox(width: 10),
              const TwPuntoPill(
                texto: 'EN CURSO',
                color: TwColors.greenInk,
                fondo: TwColors.greenTint,
                borde: Color(0x332F7D43),
              ),
            ],
            const SizedBox(width: 6),
            const Icon(
              Symbols.chevron_right_rounded,
              size: 22,
              color: TwColors.chevron,
            ),
          ],
        ),
      ),
    );
  }
}
