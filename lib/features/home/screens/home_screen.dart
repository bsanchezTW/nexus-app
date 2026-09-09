import 'dart:io' show exit;
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/browser_theme_color.dart';
import '../../../core/theme/tw_tokens.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/collapsing_nav.dart';
import '../../../core/widgets/cuenta_identity_header.dart';
import '../../../core/widgets/cuenta_settings_sheet.dart';
import '../../../core/widgets/shell_tab_scroll.dart';
import '../../../core/widgets/tw_offline_notice_card.dart';
import '../../../data/models/perfil.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../auth/providers/auth_providers.dart';
import '../../capturador/providers/capturador_providers.dart';
import '../../fijados/providers/fijados_providers.dart';
import '../../notificaciones/providers/notificaciones_providers.dart';
import '../../updates/services/update_platform.dart';
import '../../updates/services/windows_uninstaller.dart';
import '../../updates/widgets/update_checker.dart';
import '../models/home_featured_item.dart';
import '../providers/home_dashboard_providers.dart';
import '../providers/home_featured_providers.dart';
import '../widgets/home_dashboard_section.dart';
import '../widgets/proximo_evento_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  bool _desinstalando = false;
  final _scrollTop = ValueNotifier<double>(0);
  final _scrollController = ScrollController();
  List<HomeFeaturedItem> _ultimosDestacados = const [];
  late final AnimationController _enterCtrl;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(vsync: this, duration: AppMotion.screenIn)
      ..forward();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _scrollTop.dispose();
    _enterCtrl.dispose();
    super.dispose();
  }

  Future<void> _desinstalar() async {
    if (_desinstalando || !canUninstallApp) return;

    final ok = await confirmDialog(
      context,
      title: 'Desinstalar RegisPro',
      message:
          'Se eliminarán la aplicación, los accesos directos y los datos '
          'locales de RegisPro en este equipo. Esta acción no se puede deshacer.',
      confirmLabel: 'Desinstalar',
      destructive: true,
    );
    if (!ok || !mounted) return;

    setState(() => _desinstalando = true);
    final result = await WindowsUninstaller().uninstall();
    if (!mounted) return;

    if (result.outcome == WindowsUninstallOutcome.launched) {
      Future.delayed(const Duration(milliseconds: 800), () => exit(0));
      return;
    }

    setState(() => _desinstalando = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.message ?? 'No se pudo iniciar la desinstalación.',
        ),
      ),
    );
  }

  String _firstName(Perfil? perfil) {
    final nombre = perfil?.nombreCompleto.trim() ?? '';
    if (nombre.isEmpty) return '';
    return nombre.split(RegExp(r'\s+')).first;
  }

  Future<void> _mostrarAjustes() {
    return showCuentaSettingsSheet(
      context: context,
      onMiPerfil: () => context.push(RoutePaths.perfil),
      onSincronizacion: () => context.push(RoutePaths.sincronizacion),
      onActualizaciones: () => context.push(RoutePaths.actualizaciones),
      onDesinstalar: canUninstallApp ? _desinstalar : null,
      onCerrarSesion: () => ref.read(authRepositoryProvider).cerrarSesion(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final perfilAsync = ref.watch(currentPerfilProvider);
    final perfil = perfilAsync.valueOrNull;
    final featuredAsync = ref.watch(homeFeaturedItemsProvider);
    var featuredItems = featuredAsync.valueOrNull ?? _ultimosDestacados;
    if (featuredAsync.hasValue) {
      _ultimosDestacados = featuredAsync.requireValue;
    }
    if (perfil == null) {
      featuredItems = featuredItems
          .where((item) => !item.esActividadCaptura)
          .toList();
    } else if (perfil.requiresEventAssignment) {
      final autorizadas = ref
          .watch(eventosLeadsListProvider)
          .valueOrNull
          ?.map((actividad) => actividad.id)
          .toSet();
      // Mientras el alcance se resuelve, las cards de captura fallan cerradas
      // en vez de reutilizar `_ultimosDestacados` de una asignación revocada.
      featuredItems = featuredItems
          .where(
            (item) =>
                !item.esActividadCaptura ||
                (autorizadas?.contains(item.id) ?? false),
          )
          .toList();
    }
    ref.listen<int>(shellTabEpochProvider(ShellTabBranch.inicio), (prev, next) {
      if (prev == next) return;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      _scrollTop.value = 0;
    });
    final noLeidas = ref.watch(notificacionesNoLeidasProvider);
    final first = _firstName(perfil);
    final saludo = first.isEmpty ? 'Hola 👋' : 'Hola, $first 👋';
    final reduce = AppMotion.reduceMotion(context);
    final safeTop = MediaQuery.paddingOf(context).top;
    final contentTop = safeTop + _HomeHeaderMetrics.topGap(safeTop);
    final collapseStart = contentTop - safeTop;
    final bottomPad = math.max(
      120.0,
      GlassNavTokens.contentBottomInset(context),
    );

    final body = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis != Axis.vertical) return false;
        _scrollTop.value = math.max(0, notification.metrics.pixels);
        return false;
      },
      child: RefreshIndicator(
        color: TwColors.brand700,
        edgeOffset: safeTop,
        displacement: 40,
        onRefresh: () => refrescarLecturas(
          ref,
          invalidar: () {
            ref.invalidate(homeDashboardProvider);
            ref.invalidate(homeFeaturedItemsProvider);
            ref.invalidate(eventosFijadosProvider);
            ref.invalidate(campanasFijadasProvider);
            ref.invalidate(currentPerfilProvider);
          },
          pendientes: () => [
            ref.read(homeDashboardProvider.future),
            ref.read(homeFeaturedItemsProvider.future),
            ref.read(eventosFijadosProvider.future),
            ref.read(campanasFijadasProvider.future),
            ref.read(currentPerfilProvider.future),
          ],
        ),
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          padding: EdgeInsets.fromLTRB(0, contentTop, 0, bottomPad),
          children: [
            _HomeColumn(
              child: CuentaIdentityHeader(
                perfil: perfil,
                noLeidas: noLeidas,
                onNotificaciones: () => context.push(RoutePaths.notificaciones),
                onAjustes: _mostrarAjustes,
                onMiPerfil: () => context.push(RoutePaths.perfil),
              ),
            ),
            const SizedBox(height: 18),
            ProximoEventoCard(items: featuredItems),
            const SizedBox(height: 20),
            _HomeColumn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const TwOfflineNoticeCard(bottomGap: 20),
                  perfilAsync.when(
                    skipLoadingOnReload: true,
                    skipLoadingOnRefresh: true,
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: LoadingView(),
                    ),
                    error: (e, _) => ErrorView(
                      message: 'No se pudo cargar tu perfil.',
                      onRetry: () => ref.invalidate(currentPerfilProvider),
                    ),
                    data: (_) => const HomeDashboardSection(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final enter = reduce
        ? body
        : FadeTransition(
            opacity: CurvedAnimation(parent: _enterCtrl, curve: AppMotion.ease),
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 0.024),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: _enterCtrl, curve: AppMotion.ease),
                  ),
              child: body,
            ),
          );

    return BrowserThemeColor(
      color: TwColors.bg,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: UpdateChecker(
          child: Scaffold(
            backgroundColor: TwColors.bg,
            body: Stack(
              children: [
                enter,
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ValueListenableBuilder<double>(
                    valueListenable: _scrollTop,
                    builder: (context, t, _) {
                      return _HomeCollapseBar(
                        scrollTop: t,
                        title: saludo,
                        collapseStart: collapseStart,
                      );
                    },
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

/// Columna del home con el gutter de pantalla. El carrusel de eventos se
/// sale de este wrapper para poder deslizar hasta el borde.
class _HomeColumn extends StatelessWidget {
  const _HomeColumn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: TwSpacing.screenH),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.contentMax),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
  }
}

/// Medidas del header de identidad: el avatar vive a [topGap] bajo el safe area.
abstract final class _HomeHeaderMetrics {
  static const topGapWithSafeArea = 12.0;
  static const topGapWithoutSafeArea = 16.0;

  static double topGap(double safeTop) {
    return safeTop > 0 ? topGapWithSafeArea : topGapWithoutSafeArea;
  }
}

class _HomeCollapseBar extends StatelessWidget {
  const _HomeCollapseBar({
    required this.scrollTop,
    required this.title,
    required this.collapseStart,
  });

  final double scrollTop;
  final String title;

  /// Scroll en el que el avatar toca el borde superior (bajo el safe area).
  final double collapseStart;

  static List<double> _saturationMatrix(double s) {
    const r = 0.213;
    const g = 0.715;
    const b = 0.072;
    final inv = 1 - s;
    return [
      inv * r + s,
      inv * g,
      inv * b,
      0,
      0,
      inv * r,
      inv * g + s,
      inv * b,
      0,
      0,
      inv * r,
      inv * g,
      inv * b + s,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    final barHeight = safeTop + 52;
    final start = collapseStart < 0 ? 0.0 : collapseStart;
    final opacity =
        ((scrollTop - start) / CollapsingNavMetrics.collapseFadeRange).clamp(
          0.0,
          1.0,
        );
    final titleOpacity = opacity;
    final titleTranslateY = (1 - titleOpacity) * 6;
    final visible = opacity > 0.01;

    return IgnorePointer(
      ignoring: opacity < 0.45,
      child: SizedBox(
        height: barHeight,
        child: Stack(
          children: [
            if (visible)
              Positioned.fill(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.compose(
                      inner: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      outer: ColorFilter.matrix(_saturationMatrix(1.8)),
                    ),
                    child: ColoredBox(
                      color: TwColors.bg.withValues(alpha: 0.72 * opacity),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: safeTop,
              left: TwSpacing.screenH,
              right: TwSpacing.screenH,
              bottom: 0,
              child: Opacity(
                opacity: titleOpacity,
                child: Transform.translate(
                  offset: Offset(0, titleTranslateY),
                  child: Align(
                    alignment: Alignment.center,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TwText.greeting.copyWith(fontSize: 16),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
