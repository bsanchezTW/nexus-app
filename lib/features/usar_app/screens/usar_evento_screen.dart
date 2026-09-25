import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/offline_guard.dart';
import '../../../core/router/refresh_on_visible.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/browser_theme_color.dart';
import '../../../core/theme/tw_tokens.dart';
import '../../../core/utils/registro_asistente.dart';
import '../../../core/widgets/action_lock.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/event_back_navigation_guard.dart';
import '../../../core/widgets/evento_hero_banner.dart';
import '../../../core/widgets/tw_components.dart';
import '../../../core/widgets/tw_detail_scaffold.dart';
import '../../../core/widgets/tw_offline_notice_card.dart';
import '../../../core/widgets/tw_toast.dart';
import '../../../data/models/evento.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../auth/providers/auth_providers.dart';
import '../../capturador/providers/capturador_providers.dart';
import '../../capturador/services/evento_lead_interno_service.dart';
import '../../eventos/providers/eventos_providers.dart';
import '../../registrados/providers/registrados_providers.dart';

/// Menú operativo de un evento — rediseño §8 de la guía de componentes.
///
/// Hero con métricas y CTA de escaneo, seguido de dos grupos de acciones.
/// Sin barra inferior: se llega desde la lista y se vuelve con el botón atrás.
class UsarEventoScreen extends ConsumerStatefulWidget {
  const UsarEventoScreen({super.key, required this.eventoId});

  final String eventoId;

  @override
  ConsumerState<UsarEventoScreen> createState() => _UsarEventoScreenState();
}

class _UsarEventoScreenState extends ConsumerState<UsarEventoScreen>
    with RefreshOnVisible {
  @override
  String get refreshWhenLocation => RoutePaths.usarEvento(widget.eventoId);

  bool _creandoEventoLead = false;
  bool _abriendoRegistrados = false;

  /// Al volver al menú (tras registrar, editar, eliminar o acreditar) se
  /// recarga la lista para que las tarjetas no queden con los conteos viejos.
  @override
  void onBecomeVisible() {
    ref.invalidate(eventoByIdProvider(widget.eventoId));
    ref.invalidate(registradosPorEventoProvider(widget.eventoId));
    ref.invalidate(eventoLeadInternoProvider(widget.eventoId));
  }

  /// Crea la actividad de captura interna de este evento y la abre. La otra
  /// vía es capturar un lead desde los registrados: ambas resuelven al mismo id.
  Future<void> _crearEventoLead(Evento evento) async {
    if (_creandoEventoLead) return;
    if (!requireOnline(context, ref)) return;
    ActionLock.instance.deferUnlock();
    setState(() => _creandoEventoLead = true);
    try {
      final eventoLead = await obtenerOCrearEventoLeadInterno(ref, evento);
      ref.invalidate(eventoLeadInternoProvider(widget.eventoId));
      if (!mounted) return;
      context.push(RoutePaths.usarEventoLead(eventoLead.id));
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          'No se pudo crear la actividad de captura.',
          isError: true,
        );
      }
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ActionLock.instance.finishIfNoNav();
      });
      if (mounted) setState(() => _creandoEventoLead = false);
    }
  }

  /// El indicador se apaga cuando la ruta empujada vuelve, no cuando
  /// [onBecomeVisible] decide correr: si el refresco fallara, el tile quedaría
  /// girando para siempre y sin forma de reabrir la lista.
  ///
  /// La espera va por [pushYEsperarSalida] y no por el futuro de
  /// `context.push`: en web el atrás del navegador no hace pop y ese futuro
  /// nunca resuelve, que era justo el spinner eterno que se veía al volver.
  Future<void> _abrirRegistrados() async {
    if (_abriendoRegistrados) return;
    ActionLock.instance.deferUnlock();
    setState(() => _abriendoRegistrados = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final navegacion = pushYEsperarSalida(
        context,
        RoutePaths.verRegistrados(widget.eventoId),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ActionLock.instance.finishIfNoNav();
      });
      await navegacion;
    } finally {
      if (mounted) setState(() => _abriendoRegistrados = false);
    }
  }

  Future<void> _compartir(String nombreEvento) async {
    if (!requireOnline(context, ref)) return;
    final evento = ref.read(eventoByIdProvider(widget.eventoId)).valueOrNull;
    final link = RoutePaths.urlPublicaEvento(evento?.slug ?? '');
    final esMovil =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (esMovil) {
      await SharePlus.instance.share(
        ShareParams(text: '¡Regístrate al evento "$nombreEvento" aquí!\n$link'),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    TwToast.link(context, 'Enlace del evento copiado');
  }

  Future<bool> _volverConBotonAndroid() async {
    if (!mounted) return false;
    if (currentLocationOf(context) != RoutePaths.usarEvento(widget.eventoId)) {
      return false;
    }
    volverALista(context, RoutePaths.eventos);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final eventoAsync = ref.watch(eventoByIdProvider(widget.eventoId));
    final puedeEditar = ref.watch(canCreateContentProvider);
    final puedeExportar = ref.watch(canExportDataProvider);
    final esAdmin = ref.watch(isAdminProvider);
    final resumen = ref.watch(registradosResumenProvider(widget.eventoId));
    final eventoLead = ref
        .watch(eventoLeadInternoProvider(widget.eventoId))
        .valueOrNull;

    final contenido = BrowserThemeColor(
      color: TwColors.bg,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: TwColors.bg,
          body: eventoAsync.when(
            // Al volver (gesto iOS o atrás) RefreshOnVisible invalida
            // el evento: sin esto el menú se desmonta un frame.
            skipLoadingOnReload: true,
            loading: () => const LoadingView(),
            error: (e, _) =>
                const ErrorView(message: 'No se pudo cargar el evento.'),
            data: (evento) => TwDetailScaffold(
              eyebrow: 'Detalle del evento',
              title: evento.nombre,
              onBack: () => volverAtras(context),
              onRefresh: () => refrescarLecturas(
                ref,
                invalidar: () {
                  ref.invalidate(eventoByIdProvider(widget.eventoId));
                  ref.invalidate(registradosPorEventoProvider(widget.eventoId));
                  ref.invalidate(eventoLeadInternoProvider(widget.eventoId));
                },
                pendientes: () => [
                  ref.read(eventoByIdProvider(widget.eventoId).future),
                  ref.read(
                    registradosPorEventoProvider(widget.eventoId).future,
                  ),
                  ref.read(eventoLeadInternoProvider(widget.eventoId).future),
                ],
              ),
              actions: [
                if (puedeEditar)
                  NexusHeaderAction(
                    icon: Symbols.edit_rounded,
                    tooltip: 'Editar evento',
                    sfSymbol: 'pencil',
                    onTap: () =>
                        context.push(RoutePaths.editarEvento(widget.eventoId)),
                  ),
                NexusHeaderAction(
                  icon: Symbols.ios_share_rounded,
                  variant: TwIconButtonStyle.brand,
                  tooltip: 'Compartir enlace de registro',
                  sfSymbol: 'square.and.arrow.up',
                  onTap: () => _compartir(evento.nombre),
                ),
              ],
              children: [
                _hero(context, evento, resumen),
                const TwOfflineNoticeCard(topGap: 20),
                const TwSectionLabel('Acciones del evento'),
                TwActionTile(
                  icon: Symbols.person_add_rounded,
                  iconStyle: TwIconBoxStyle.brand,
                  title: 'Registrar asistente',
                  subtitle: 'Inscribir a alguien en el evento',
                  onTap: () {
                    if (!requireOnline(context, ref)) return;
                    if (evento.yaOcurrio) {
                      TwToast.info(context, kMensajeEventoFinalizado);
                      return;
                    }
                    context.push(RoutePaths.registrar(widget.eventoId));
                  },
                ),
                const SizedBox(height: TwSpacing.tileGap),
                TwActionTile(
                  icon: Symbols.contacts_rounded,
                  title: 'Lista de asistentes registrados',
                  subtitle: _subtituloAsistentes(resumen?.total),
                  loading: _abriendoRegistrados,
                  onTap: _abrirRegistrados,
                ),
                if (eventoLead != null) ...[
                  const SizedBox(height: TwSpacing.tileGap),
                  TwActionTile(
                    icon: Symbols.person_search_rounded,
                    title: 'Ver actividad de captura',
                    subtitle: 'Captura de oportunidades de este evento',
                    onTap: () => abrirOVolverA(
                      context,
                      RoutePaths.usarEventoLead(eventoLead.id),
                    ),
                  ),
                ] else if (puedeEditar) ...[
                  const SizedBox(height: TwSpacing.tileGap),
                  TwActionTile(
                    icon: Symbols.person_search_rounded,
                    title: 'Crear actividad de captura',
                    subtitle: _creandoEventoLead
                        ? 'Creando…'
                        : 'Capturar oportunidades en este evento',
                    onTap: () => _crearEventoLead(evento),
                  ),
                ],
                if (puedeEditar) ...[
                  const SizedBox(height: TwSpacing.tileGap),
                  TwActionTile(
                    icon: Symbols.calendar_view_day_rounded,
                    title: 'Subeventos',
                    subtitle: 'Talleres de este evento',
                    onTap: () =>
                        context.push(RoutePaths.subeventos(widget.eventoId)),
                  ),
                ],
                const TwSectionLabel('Administración'),
                if (esAdmin) ...[
                  TwActionTile(
                    icon: Symbols.groups_rounded,
                    title: 'Gestionar acceso',
                    subtitle: 'Acreditar y controlar la entrada',
                    onTap: () {
                      if (!requireOnline(context, ref)) return;
                      context.push(RoutePaths.accesoEvento(widget.eventoId));
                    },
                  ),
                  const SizedBox(height: TwSpacing.tileGap),
                ],
                TwActionTile(
                  icon: Symbols.bar_chart_rounded,
                  iconStyle: TwIconBoxStyle.purpleTint,
                  title: 'KPI del evento',
                  subtitle: 'Métricas y acreditación en vivo',
                  onTap: () => context.push(RoutePaths.kpi(widget.eventoId)),
                ),
                if (puedeExportar) ...[
                  const SizedBox(height: TwSpacing.tileGap),
                  TwActionTile(
                    icon: Symbols.table_chart_rounded,
                    iconStyle: TwIconBoxStyle.excel,
                    excel: true,
                    badge: 'XLSX',
                    title: 'Importar o exportar',
                    subtitle: _subtituloExcel(resumen?.total),
                    onTap: () {
                      if (!requireOnline(context, ref)) return;
                      context.push(RoutePaths.exportar(widget.eventoId));
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return EventBackNavigationGuard(
      onAndroidBack: _volverConBotonAndroid,
      child: contenido,
    );
  }

  Widget _hero(
    BuildContext context,
    Evento evento,
    RegistradosResumen? resumen,
  ) {
    final lugar = [
      if (evento.lugar != null && evento.lugar!.isNotEmpty) evento.lugar,
      if (evento.pais != null && evento.pais!.isNotEmpty) evento.pais,
    ].join(' · ');
    final imagenUrl = evento.imagenUrl;

    return TwHeroCard(
      dateText: formatearFechaActividad(evento.fecha, evento.duracionDias),
      status: evento.yaOcurrio ? TwStatus.finalizado : TwStatus.activo,
      title: evento.nombre,
      location: lugar,
      photo: imagenUrl == null || imagenUrl.isEmpty
          ? null
          // El velo lo pinta la propia TwHeroCard (heroScrim).
          : EventoHeroFoto(imagenUrl: imagenUrl, velo: 0),
      stats: [
        TwStat(
          _valor(resumen?.acreditados),
          'Acreditados',
          valueColor: TwColors.statusActive,
        ),
        TwStat(_valor(resumen?.pendientes), 'Pendientes'),
        TwStat(_valor(resumen?.total), 'Registrados'),
      ],
      ctaLabel: 'Escanear QR',
      ctaIcon: Symbols.qr_code_scanner_rounded,
      mostrarCta: evento.accesoQr,
      onCta: () => context.push(RoutePaths.acreditarQr(widget.eventoId)),
    );
  }

  static String _valor(int? n) => n?.toString() ?? '—';

  static String _subtituloAsistentes(int? total) {
    if (total == null) return 'Ver el listado completo';
    return total == 1 ? '1 asistente' : '$total asistentes';
  }

  static String _subtituloExcel(int? total) {
    if (total == null) return 'Carga masiva o descarga de asistentes';
    final filas = total == 1 ? '1 fila' : '$total filas';
    return 'Carga masiva o descarga · $filas';
  }
}
