import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/constants/duracion_actividad.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tw_tokens.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/tw_components.dart';
import '../../../data/models/evento.dart';
import '../providers/home_dashboard_providers.dart';

class HomeDashboardSection extends ConsumerWidget {
  const HomeDashboardSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(homeDashboardProvider);

    return dashboardAsync.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: LoadingView(message: 'Cargando resumen...'),
      ),
      error: (e, _) => ErrorView(
        message: 'No se pudo cargar el resumen.',
        onRetry: () => ref.invalidate(homeDashboardProvider),
      ),
      data: (data) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TwSectionLabel('Resumen', top: 0),
          _KpiGrid(data: data),
          const TwSectionLabel('Calendario de eventos'),
          _EventosCalendario(data: data),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.data});

  final HomeDashboardData data;

  @override
  Widget build(BuildContext context) {
    final cards = <TwKpiCard>[
      TwKpiCard(
        value: '${data.eventosActivos}',
        label: 'Activos',
        icon: Symbols.bolt_rounded,
        tint: TwColors.amberTint,
        iconColor: TwColors.amberInk,
      ),
      TwKpiCard(
        value: '${data.totalRegistrados}',
        label: 'Registrados',
        icon: Symbols.groups_rounded,
        tint: TwColors.blueTint,
        iconColor: TwColors.blueInk,
      ),
      TwKpiCard(
        value: '${(data.porcentajeAcreditacion * 100).toStringAsFixed(0)}%',
        label: 'Acreditación',
        icon: Symbols.verified_rounded,
        tint: TwColors.greenTint,
        iconColor: TwColors.greenInk,
      ),
      TwKpiCard(
        value: '${data.eventosEsteMes}',
        label: 'Este mes',
        icon: Symbols.insights_rounded,
        tint: TwColors.purpleTint,
        iconColor: TwColors.purpleInk,
      ),
    ];

    return Column(
      children: [
        for (var row = 0; row * 2 < cards.length; row++) ...[
          if (row > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var col = 0; col < 2; col++) ...[
                  if (col > 0) const SizedBox(width: 12),
                  Expanded(
                    child: row * 2 + col < cards.length
                        ? _HomeCardIn(
                            key: ValueKey(cards[row * 2 + col].label),
                            index: row * 2 + col,
                            child: cards[row * 2 + col],
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _EventosCalendario extends StatefulWidget {
  const _EventosCalendario({required this.data});

  final HomeDashboardData data;

  @override
  State<_EventosCalendario> createState() => _EventosCalendarioState();
}

class _EventosCalendarioState extends State<_EventosCalendario> {
  late DateTime _mesVisible;
  DateTime? _diaSeleccionado;

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _mesVisible = DateTime(hoy.year, hoy.month);
    _diaSeleccionado = DateTime(hoy.year, hoy.month, hoy.day);
  }

  void _cambiarMes(int delta) {
    setState(() {
      _mesVisible = DateTime(_mesVisible.year, _mesVisible.month + delta);
    });
  }

  @override
  Widget build(BuildContext context) {
    final eventosDelMes = widget.data.eventosEnMes(_mesVisible);
    final eventosPorDia = <int, List<Evento>>{};
    for (final evento in eventosDelMes) {
      var dia = fechaCalendario(evento.fecha);
      final mesIni = DateTime(_mesVisible.year, _mesVisible.month, 1);
      final mesFin = DateTime(_mesVisible.year, _mesVisible.month + 1, 0);
      if (dia.isBefore(mesIni)) dia = mesIni;
      final fin = evento.fechaFin;
      while (!dia.isAfter(fin) && !dia.isAfter(mesFin)) {
        eventosPorDia.putIfAbsent(dia.day, () => []).add(evento);
        dia = dia.add(const Duration(days: 1));
      }
    }

    final eventosLista = _diaSeleccionado != null
        ? widget.data.eventosEnDia(_diaSeleccionado!)
        : widget.data.proximosEventos.take(5).toList();

    return TwCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _NavMes(
                icon: Symbols.chevron_left_rounded,
                tooltip: 'Mes anterior',
                onTap: () => _cambiarMes(-1),
              ),
              Expanded(
                child: Text(
                  _capitalize(
                    DateFormat('MMMM yyyy', 'es').format(_mesVisible),
                  ),
                  textAlign: TextAlign.center,
                  style: TwText.supportTitle.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _NavMes(
                icon: Symbols.chevron_right_rounded,
                tooltip: 'Mes siguiente',
                onTap: () => _cambiarMes(1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              _DiaSemanaLabel('L'),
              _DiaSemanaLabel('M'),
              _DiaSemanaLabel('M'),
              _DiaSemanaLabel('J'),
              _DiaSemanaLabel('V'),
              _DiaSemanaLabel('S'),
              _DiaSemanaLabel('D'),
            ],
          ),
          const SizedBox(height: 4),
          AnimatedSize(
            duration: AppMotion.toggle,
            curve: AppMotion.ease,
            alignment: Alignment.topCenter,
            child: _CalendarioGrid(
              mes: _mesVisible,
              eventosPorDia: eventosPorDia,
              diaSeleccionado: _diaSeleccionado,
              onDiaTap: (dia) => setState(() => _diaSeleccionado = dia),
            ),
          ),
          const Divider(height: AppSpacing.xxl, color: TwColors.border07),
          Text(
            _diaSeleccionado != null
                ? 'Eventos del ${_formatDia(_diaSeleccionado!)}'
                : 'Próximos eventos',
            style: TwText.tileSubtitle.copyWith(
              fontSize: 13,
              color: TwColors.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (eventosLista.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'No hay eventos en esta fecha.',
                style: TwText.tileSubtitle,
              ),
            )
          else
            ...eventosLista.map((e) => _EventoCalendarioTile(evento: e)),
        ],
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  String _formatDia(DateTime dia) => DateFormat('d MMM', 'es').format(dia);
}

class _NavMes extends StatelessWidget {
  const _NavMes({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TwPressable(
        onTap: onTap,
        scale: 0.92,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: TwColors.surfaceTint,
            borderRadius: TwRadii.iconSm,
          ),
          child: Icon(icon, size: 18, color: TwColors.iconInk),
        ),
      ),
    );
  }
}

class _DiaSemanaLabel extends StatelessWidget {
  const _DiaSemanaLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: TwText.statLabel.copyWith(
            fontSize: 10.5,
            letterSpacing: 0,
            color: TwColors.muted,
          ),
        ),
      ),
    );
  }
}

class _CalendarioGrid extends StatelessWidget {
  const _CalendarioGrid({
    required this.mes,
    required this.eventosPorDia,
    required this.diaSeleccionado,
    required this.onDiaTap,
  });

  final DateTime mes;
  final Map<int, List<Evento>> eventosPorDia;
  final DateTime? diaSeleccionado;
  final ValueChanged<DateTime> onDiaTap;

  @override
  Widget build(BuildContext context) {
    final primerDia = DateTime(mes.year, mes.month, 1);
    final diasEnMes = DateTime(mes.year, mes.month + 1, 0).day;
    final offset = primerDia.weekday - 1;
    final hoy = DateTime.now();
    final hoySolo = DateTime(hoy.year, hoy.month, hoy.day);

    final celdas = <Widget>[];
    for (var i = 0; i < offset; i++) {
      celdas.add(const _CeldaCalendarioVacia());
    }
    for (var dia = 1; dia <= diasEnMes; dia++) {
      final fecha = DateTime(mes.year, mes.month, dia);
      final tieneEventos = eventosPorDia.containsKey(dia);
      final esHoy = fecha == hoySolo;
      final seleccionado =
          diaSeleccionado != null &&
          diaSeleccionado!.year == fecha.year &&
          diaSeleccionado!.month == fecha.month &&
          diaSeleccionado!.day == fecha.day;
      final esPasado = fecha.isBefore(hoySolo);

      celdas.add(
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onDiaTap(fecha),
          child: SizedBox(
            height: 34,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: esHoy ? TwGradients.hero : null,
                color: !esHoy && seleccionado ? TwColors.blueTint : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    '$dia',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.0,
                      letterSpacing: 0,
                      leadingDistribution: TextLeadingDistribution.even,
                      fontWeight: esHoy || seleccionado
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: esHoy
                          ? Colors.white
                          : esPasado
                          ? TwColors.muted
                          : TwColors.ink,
                    ),
                  ),
                  if (tieneEventos && !esHoy)
                    Positioned(
                      bottom: 4,
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                          color: TwColors.blueInk,
                          shape: BoxShape.circle,
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

    while (celdas.length % 7 != 0) {
      celdas.add(const _CeldaCalendarioVacia());
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var inicio = 0; inicio < celdas.length; inicio += 7) ...[
          if (inicio > 0) const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = inicio; i < inicio + 7; i++) ...[
                if (i > inicio) const SizedBox(width: 2),
                Expanded(child: celdas[i]),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _CeldaCalendarioVacia extends StatelessWidget {
  const _CeldaCalendarioVacia();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 34);
  }
}

class _EventoCalendarioTile extends StatelessWidget {
  const _EventoCalendarioTile({required this.evento});

  final Evento evento;

  @override
  Widget build(BuildContext context) {
    final fecha = evento.esMultiDia
        ? '${DateFormat('dd/MM/yyyy').format(evento.fecha)} – ${DateFormat('dd/MM/yyyy').format(evento.fechaFin)}'
        : DateFormat('dd/MM/yyyy').format(evento.fecha);
    final pasado = evento.yaOcurrio;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TwPressable(
        onTap: () => context.push(RoutePaths.usarEvento(evento.id)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm,
            horizontal: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: pasado ? TwColors.chevron : TwColors.brand700,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      evento.nombre,
                      style: TwText.supportTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$fecha · ${evento.lugar ?? evento.pais ?? ''}',
                      style: TwText.tileSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Symbols.chevron_right_rounded,
                color: TwColors.chevron,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeCardIn extends StatefulWidget {
  const _HomeCardIn({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_HomeCardIn> createState() => _HomeCardInState();
}

class _HomeCardInState extends State<_HomeCardIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: AppMotion.cardIn);
    _fade = CurvedAnimation(parent: _ctrl, curve: AppMotion.ease);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: AppMotion.ease));
    Future<void>.delayed(AppMotion.stagger * widget.index, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduceMotion(context)) return widget.child;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
