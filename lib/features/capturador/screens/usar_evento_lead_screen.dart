import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/router/refresh_on_visible.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/network/offline_guard.dart';
import '../../../core/theme/browser_theme_color.dart';
import '../../../core/theme/tw_tokens.dart';
import '../../../core/widgets/action_lock.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/evento_hero_banner.dart';
import '../../../core/widgets/sync_conflict_listener.dart';
import '../../../core/widgets/tw_components.dart';
import '../../../core/widgets/tw_detail_scaffold.dart';
import '../../../core/widgets/tw_offline_notice_card.dart';
import '../../../data/models/evento_lead.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/offline/sync_queue_service.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/capturador_providers.dart';

/// Hub operativo de un evento de captura de leads — rediseño §9.
///
/// Misma estructura que el menú de Evento, con tres diferencias: la cabecera
/// no lleva botón compartir, el hero muestra 2 métricas y el CTA es
/// "Capturar lead".
class UsarEventoLeadScreen extends ConsumerStatefulWidget {
  const UsarEventoLeadScreen({super.key, required this.eventoId});

  final String eventoId;

  @override
  ConsumerState<UsarEventoLeadScreen> createState() =>
      _UsarEventoLeadScreenState();
}

class _UsarEventoLeadScreenState extends ConsumerState<UsarEventoLeadScreen>
    with RefreshOnVisible {
  @override
  String get refreshWhenLocation => RoutePaths.usarEventoLead(widget.eventoId);

  bool _abriendoLeads = false;

  @override
  void onBecomeVisible() {
    ref.invalidate(eventoLeadByIdProvider(widget.eventoId));
    ref.invalidate(leadsResumenRemotoProvider(widget.eventoId));
  }

  /// Ver la nota de `_abrirRegistrados` en el menú de evento: el indicador se
  /// apaga al volver de la ruta, no desde [onBecomeVisible].
  Future<void> _abrirLeads() async {
    if (_abriendoLeads) return;
    ActionLock.instance.deferUnlock();
    setState(() => _abriendoLeads = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final navegacion = pushYEsperarSalida(
        context,
        RoutePaths.verLeads(widget.eventoId),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ActionLock.instance.finishIfNoNav();
      });
      await navegacion;
    } finally {
      if (mounted) setState(() => _abriendoLeads = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventoAsync = ref.watch(eventoLeadByIdProvider(widget.eventoId));
    final puedeEditar = ref.watch(canCreateContentProvider);
    final puedeExportar = ref.watch(canExportDataProvider);
    final conflictos = ref.watch(syncConflictsProvider).length;
    final resumen = ref.watch(leadsResumenLocalProvider(widget.eventoId));

    return BrowserThemeColor(
      color: TwColors.bg,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: TwColors.bg,
          body: eventoAsync.when(
            skipLoadingOnReload: true,
            loading: () => const LoadingView(),
            error: (e, _) =>
                const ErrorView(message: 'No se pudo cargar la actividad.'),
            data: (evento) => TwDetailScaffold(
              eyebrow: 'Detalle de la actividad',
              title: evento.nombre,
              onBack: () => volverAtras(context),
              onRefresh: () => refrescarLecturas(
                ref,
                invalidar: () {
                  ref.invalidate(eventoLeadByIdProvider(widget.eventoId));
                  ref.invalidate(leadsResumenRemotoProvider(widget.eventoId));
                },
                pendientes: () => [
                  ref.read(eventoLeadByIdProvider(widget.eventoId).future),
                  ref.read(leadsResumenRemotoProvider(widget.eventoId).future),
                ],
              ),
              actions: [
                // Sin botón compartir: la actividad de captura no tiene
                // formulario público que enlazar (§9).
                if (puedeEditar)
                  NexusHeaderAction(
                    icon: Symbols.edit_rounded,
                    tooltip: evento.esInterno
                        ? 'Ver datos de la actividad'
                        : 'Editar actividad',
                    sfSymbol: 'pencil',
                    onTap: () => context.push(
                      RoutePaths.editarEventoLead(widget.eventoId),
                    ),
                  ),
              ],
              children: [
                _hero(context, evento, resumen),
                const TwOfflineNoticeCard(topGap: 20),
                const TwSectionLabel('Acciones del evento'),
                TwActionTile(
                  icon: Symbols.contacts_rounded,
                  title: 'Ver leads',
                  subtitle: 'Listado de clientes capturados',
                  loading: _abriendoLeads,
                  onTap: _abrirLeads,
                ),
                if (evento.esInterno && evento.eventoOrigenId != null) ...[
                  const SizedBox(height: TwSpacing.tileGap),
                  TwActionTile(
                    icon: Symbols.event_rounded,
                    title: 'Ver evento de registro',
                    subtitle: 'Abrir el evento del que nació esta actividad',
                    onTap: () => abrirOVolverA(
                      context,
                      RoutePaths.usarEvento(evento.eventoOrigenId!),
                    ),
                  ),
                ],
                if (conflictos > 0) ...[
                  const SizedBox(height: TwSpacing.tileGap),
                  TwActionTile(
                    icon: Symbols.warning_rounded,
                    iconStyle: TwIconBoxStyle.amberTint,
                    title: 'Conflictos de sincronización',
                    subtitle: conflictos == 1
                        ? '1 pendiente de revisar'
                        : '$conflictos pendientes de revisar',
                    onTap: () => showSyncConflictsSheet(context, ref),
                  ),
                ],
                // §9 lista además un tile "KPI del evento"; no se monta
                // porque `KpiScreen` solo sabe leer `eventos`/
                // `registrados` y un evento de leads la haría fallar.
                // Queda pendiente su pantalla propia.
                if (puedeExportar) ...[
                  const TwSectionLabel('Administración'),
                  TwActionTile(
                    icon: Symbols.table_chart_rounded,
                    iconStyle: TwIconBoxStyle.excel,
                    excel: true,
                    badge: 'XLSX',
                    title: 'Importar o exportar',
                    subtitle: _subtituloExcel(resumen?.total),
                    onTap: () {
                      if (!requireOnline(context, ref)) return;
                      context.push(RoutePaths.exportarLeads(widget.eventoId));
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hero(BuildContext context, EventoLead evento, LeadsResumen? resumen) {
    final meta = [
      if (evento.pais != null && evento.pais!.isNotEmpty) evento.pais,
      if (evento.tematica != null && evento.tematica!.isNotEmpty)
        evento.tematica,
    ].join(' · ');

    return TwHeroCard(
      dateText: formatearFechaActividad(evento.fecha, evento.duracionDias),
      status: evento.yaOcurrio ? TwStatus.finalizado : TwStatus.activo,
      title: evento.nombre,
      titleHeight: 1.22,
      location: meta,
      photo: evento.tieneImagen
          ? EventoHeroFoto(imagenUrl: evento.imagenUrl!, velo: 0)
          : null,
      stats: [
        TwStat(_valor(resumen?.total), 'Leads capturados'),
        TwStat(_valor(resumen?.empresas), 'Empresas'),
      ],
      ctaLabel: 'Capturar lead',
      ctaIcon: Symbols.person_add_rounded,
      onCta: () => context.push(RoutePaths.capturarLead(widget.eventoId)),
    );
  }

  static String _valor(int? n) => n?.toString() ?? '—';

  static String _subtituloExcel(int? total) {
    if (total == null) return 'Leads de la actividad';
    final filas = total == 1 ? '1 fila' : '$total filas';
    return 'Leads de la actividad · $filas';
  }
}
