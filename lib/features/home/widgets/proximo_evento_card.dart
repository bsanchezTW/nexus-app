import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tw_tokens.dart';
import '../../../core/widgets/app_image_skeleton.dart';
import '../../../core/widgets/evento_hero_banner.dart';
import '../../../core/widgets/tw_components.dart';
import '../../acreditacion/destino_escaneo_sheet.dart';
import '../models/home_featured_item.dart';

/// Gutter que alinea la card centrada con el resto del home.
double homeFeaturedSettledInset(double width) {
  final contentWidth = math.min(
    AppSpacing.contentMax,
    math.max(0.0, width - TwSpacing.screenH * 2),
  );
  return (width - contentWidth) / 2;
}

/// Card del home: próximo evento, slider de fijados, o estado vacío.
///
/// Hero navy radio 22 y compacto: métricas separadas por hairline y los dos
/// CTA lado a lado. Una sola card mide lo que su contenido; el slider usa una
/// altura común para que las páginas no salten al deslizar.
class ProximoEventoCard extends StatefulWidget {
  const ProximoEventoCard({
    super.key,
    required this.items,
    this.cargando = false,
    this.onOrdenar,
  });

  final List<HomeFeaturedItem> items;

  /// Abre la hoja "Ordenar". Con una sola tarjeta no se muestra.
  final VoidCallback? onOrdenar;

  /// Primera carga en curso: se muestra el esqueleto en vez del estado vacío,
  /// que antes aparecía ("Todo tranquilo por aquí") mientras el servidor
  /// todavía no contestaba.
  final bool cargando;

  @override
  State<ProximoEventoCard> createState() => _ProximoEventoCardState();
}

class _ProximoEventoCardState extends State<ProximoEventoCard> {
  late final PageController _pageController;
  int _page = 0;

  bool get _esSlider =>
      widget.items.length > 1 ||
      (widget.items.isNotEmpty && widget.items.first.esFijado);

  void _irAPagina(int pagina) {
    if (pagina < 0 || pagina >= widget.items.length) return;
    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      pagina,
      duration: AppMotion.toggle,
      curve: AppMotion.ease,
    );
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void didUpdateWidget(covariant ProximoEventoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length ||
        !_mismaLista(oldWidget.items, widget.items)) {
      _page = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool _mismaLista(List<HomeFeaturedItem> a, List<HomeFeaturedItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].kind != b[i].kind) return false;
    }
    return true;
  }

  /// Altura común del slider: la de su página más alta, **medida** con el
  /// texto real y la escala de fuente del teléfono. Antes se reservaba el
  /// caso peor (título de 2 líneas + lugar) aunque ninguna página lo usara, y
  /// con la letra grande del teléfono quedaba aire bajo el lugar.
  double _alturaSlider(BuildContext context, double anchoCard) {
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.6);
    final base = DefaultTextStyle.of(context).style;
    double alto(String texto, TextStyle style, {int maxLines = 1}) {
      final painter = TextPainter(
        text: TextSpan(text: texto, style: base.merge(style)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: maxLines,
      )..layout(maxWidth: anchoCard - 32);
      return painter.height;
    }

    // Eyebrow: el chip de fecha (texto + 6 de padding y 1 de borde por lado).
    final eyebrow = math.max(15.0, alto('31 OCT', TwText.homeDateChip) + 14);
    final metricas =
        alto('0', TwText.homeStatValue.copyWith(fontSize: 21)) +
        5 +
        alto('LEADS', TwText.homeStatLabel);
    double altoPagina(String titulo, bool conLugar) {
      final lugar = conLugar
          ? 6 + math.max(16.0, alto('Lugar', TwText.heroMeta))
          : 0.0;
      return 16 +
          eyebrow +
          10 +
          alto(titulo, TwText.homeHeroTitle, maxLines: 2) +
          lugar +
          14 +
          metricas +
          14 +
          44 +
          16 +
          2;
    }

    return widget.items
        .map((item) => altoPagina(item.nombre, item.lugar.isNotEmpty))
        .reduce(math.max);
  }

  double _pageValue() {
    if (!_pageController.hasClients) return _page.toDouble();
    return _pageController.page ?? _page.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final settledInset = homeFeaturedSettledInset(width);

        if (widget.items.isEmpty) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: settledInset),
            child: widget.cargando
                ? const _CargandoProximoEventoCard()
                : const _EmptyProximoEventoCard(),
          );
        }

        final cardHeight = _alturaSlider(context, width - settledInset * 2);

        if (!_esSlider) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: settledInset),
            child: _FeaturedSlide(item: widget.items.first, altoFijo: false),
          );
        }

        return Column(
          children: [
            SizedBox(
              height: cardHeight,
              child: AnimatedBuilder(
                animation: _pageController,
                builder: (context, child) {
                  final page = _pageValue();
                  final fractional = (page - page.roundToDouble()).abs();
                  final shadowInset = settledInset * (1 - fractional);
                  return Stack(
                    children: [
                      // La sombra se pinta fuera del PageView: dentro, el
                      // viewport la corta en recto y deja un rectángulo.
                      Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: shadowInset,
                          ),
                          child: const IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: TwRadii.hero,
                                boxShadow: TwShadows.hero,
                              ),
                            ),
                          ),
                        ),
                      ),
                      child!,
                    ],
                  );
                },
                child: _CarruselBordeSuave(
                  child: ScrollConfiguration(
                    // La card ocupa todo el ancho y ya no hay flechas
                    // laterales: en web y Windows el arrastre con mouse es
                    // la única alternativa al swipe.
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: const {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                        PointerDeviceKind.stylus,
                      },
                    ),
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: widget.items.length,
                      onPageChanged: (page) => setState(() => _page = page),
                      itemBuilder: (context, index) {
                        final item = widget.items[index];
                        return AnimatedBuilder(
                          animation: _pageController,
                          builder: (context, child) {
                            final page = _pageValue();
                            final t = (1.0 - (index - page).abs()).clamp(
                              0.0,
                              1.0,
                            );
                            return Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: settledInset * t,
                              ),
                              child: child,
                            );
                          },
                          child: _FeaturedSlide(
                            key: ValueKey('${item.kind.name}-${item.id}'),
                            item: item,
                            conSombra: false,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            if (widget.items.length > 1) ...[
              const SizedBox(height: 12),
              // Fila de viñetas de alto fijo: el botón Ordenar no puede
              // agrandarla, o el aire bajo el carrusel queda mayor que el del
              // resto del inicio.
              Container(
                height: _altoFilaVinetas,
                padding: EdgeInsets.symmetric(horizontal: settledInset),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < widget.items.length; i++)
                          _PuntoCarrusel(
                            key: Key('proximo_evento_punto_$i'),
                            activo: i == _page,
                            posicion: i + 1,
                            total: widget.items.length,
                            onTap: () => _irAPagina(i),
                          ),
                      ],
                    ),
                    if (widget.onOrdenar != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: _BotonOrdenar(onTap: widget.onOrdenar!),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Alto de la fila de viñetas (y del botón Ordenar que vive en ella).
const double _altoFilaVinetas = 24;

/// Acceso a la hoja "Ordenar", discreto junto a las viñetas.
class _BotonOrdenar extends StatelessWidget {
  const _BotonOrdenar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Ordenar tarjetas',
      child: TwPressable(
        key: const Key('proximo_evento_ordenar'),
        onTap: onTap,
        scale: 0.92,
        child: const SizedBox(
          width: 40,
          height: _altoFilaVinetas,
          child: Icon(
            Symbols.swap_vert_rounded,
            size: 18,
            color: TwColors.muted,
          ),
        ),
      ),
    );
  }
}

/// Fade corto en los bordes de la pantalla: la card se disuelve al salir,
/// sin un bloque de blur que corte contra el resto del home.
class _CarruselBordeSuave extends StatelessWidget {
  const _CarruselBordeSuave({required this.child});

  final Widget child;

  static const _fadePx = 16.0;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduceMotion(context)) return child;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final fade = (_fadePx / rect.width).clamp(0.0, 0.12);
        return LinearGradient(
          colors: const [
            Color(0x00FFFFFF),
            Color(0xFFFFFFFF),
            Color(0xFFFFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: [0.0, fade, 1.0 - fade, 1.0],
        ).createShader(rect);
      },
      child: child,
    );
  }
}

/// Viñeta del carrusel. Inactivas con contraste alto para contar cuántas hay.
class _PuntoCarrusel extends StatelessWidget {
  const _PuntoCarrusel({
    super.key,
    required this.activo,
    required this.posicion,
    required this.total,
    required this.onTap,
  });

  final bool activo;
  final int posicion;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: activo,
      label: 'Card $posicion de $total',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: AnimatedContainer(
            duration: AppMotion.toggle,
            curve: AppMotion.ease,
            width: activo ? 20 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: activo
                  ? TwColors.hero700
                  : TwColors.hero700.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hero del home cuando no hay próximo evento ni fijados. Compacto: sin
/// métricas ni botones no hay razón para reservar el alto de una card llena.
class _EmptyProximoEventoCard extends StatelessWidget {
  const _EmptyProximoEventoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('proximo_evento_vacio'),
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: TwGradients.hero,
        borderRadius: TwRadii.hero,
        boxShadow: TwShadows.hero,
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(16),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Eyebrow(icono: Symbols.schedule_rounded, texto: 'PRÓXIMO EVENTO'),
          SizedBox(height: 14),
          Text(
            'Todo tranquilo por aquí',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TwText.homeHeroTitle,
          ),
          SizedBox(height: 6),
          Text(
            'No hay próximos eventos programados por ahora',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TwText.heroMeta,
          ),
        ],
      ),
    );
  }
}

/// Esqueleto del hero mientras llega la primera respuesta del servidor.
///
/// Calca la estructura de [_FeaturedSlide] sin foto (eyebrow con chip de
/// fecha, título de una línea, lugar, métricas y los dos CTA) con barras del
/// mismo alto que cada texto, así la card real llega sin saltar.
class _CargandoProximoEventoCard extends StatelessWidget {
  const _CargandoProximoEventoCard();

  static const _relleno = TwColors.whiteA14;

  @override
  Widget build(BuildContext context) {
    Widget texto(String muestra, TextStyle style, {double? ancho}) =>
        AppSkeletonText(
          muestra: muestra,
          style: style,
          width: ancho,
          color: _relleno,
        );

    return Semantics(
      label: 'Cargando próximo evento',
      child: Container(
        key: const Key('proximo_evento_cargando'),
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: TwGradients.hero,
          borderRadius: TwRadii.hero,
          boxShadow: TwShadows.hero,
        ),
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final ancho = constraints.maxWidth;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    texto('PRÓXIMO EVENTO', TwText.homeEyebrow, ancho: 110),
                    const Spacer(),
                    // Chip de fecha vacío: mismo padding y borde que el real.
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _relleno,
                        borderRadius: TwRadii.pill,
                        border: Border.all(color: Colors.transparent),
                      ),
                      child: Text(
                        '25 NOV',
                        style: TwText.homeDateChip.copyWith(
                          color: Colors.transparent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: texto(
                    'Nombre del evento',
                    TwText.homeHeroTitle,
                    ancho: ancho * 0.75,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: Center(
                        child: AppSkeletonBox(
                          width: 12,
                          height: 12,
                          color: _relleno,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    texto('Lugar', TwText.heroMeta, ancho: ancho * 0.4),
                  ],
                ),
                const SizedBox(height: 14),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < 3; i++)
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: i == 0
                                  ? null
                                  : const Border(
                                      left: BorderSide(color: _relleno),
                                    ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                texto(
                                  '00',
                                  TwText.homeStatValue.copyWith(fontSize: 21),
                                  ancho: 34,
                                ),
                                const SizedBox(height: 5),
                                texto(
                                  'REGISTRADOS',
                                  TwText.homeStatLabel,
                                  ancho: 64,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Row(
                  children: [
                    Expanded(
                      child: AppSkeletonBox(
                        height: 44,
                        radio: TwRadii.button,
                        color: _relleno,
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: AppSkeletonBox(
                        height: 44,
                        radio: TwRadii.button,
                        color: _relleno,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.icono, required this.texto, this.trailing});

  final IconData icono;
  final String texto;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icono, size: 15, fill: 1, color: TwColors.whiteA75),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TwText.homeEyebrow,
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}

const _veloSobreFoto = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0xB808182C),
    Color(0xE6081628),
    Color(0xF5081628),
    Color(0xFA081628),
  ],
  stops: [0.0, 0.35, 0.55, 1.0],
);

class _FeaturedSlide extends StatelessWidget {
  const _FeaturedSlide({
    super.key,
    required this.item,
    this.conSombra = true,
    this.altoFijo = true,
  });

  final HomeFeaturedItem item;

  /// En el carrusel la sombra la pinta el fondo del Stack, no cada slide.
  final bool conSombra;

  /// En el carrusel todas las páginas miden lo mismo y el sobrante queda
  /// entre el título y las métricas. Sola, la card mide su contenido.
  final bool altoFijo;

  @override
  Widget build(BuildContext context) {
    final acciones = item.acciones;

    final contenido = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: altoFijo ? MainAxisSize.max : MainAxisSize.min,
        children: [
          _Eyebrow(
            icono: item.esFijado
                ? Symbols.push_pin_rounded
                : Symbols.schedule_rounded,
            texto: item.etiqueta,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: TwColors.whiteA16,
                borderRadius: TwRadii.pill,
                border: Border.all(color: TwColors.whiteA16),
              ),
              child: Text(
                formatearDiaMesCorto(item.fecha),
                style: TwText.homeDateChip,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // El título abre el evento o la actividad.
          Align(
            alignment: Alignment.centerLeft,
            child: TwPressable(
              key: Key('proximo_evento_titulo_${item.id}'),
              onTap: () => context.push(item.routePath),
              child: Text(
                item.nombre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TwText.homeHeroTitle,
              ),
            ),
          ),
          if (item.lugar.isNotEmpty) ...[
            const SizedBox(height: 6),
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
                    item.lugar,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TwText.heroMeta,
                  ),
                ),
              ],
            ),
          ],
          if (altoFijo) const Spacer() else const SizedBox(height: 14),
          // Una actividad de captura no tiene registrados ni acreditación:
          // sus métricas son las de leads. Cada número abre su lista.
          _HomeStats(
            columnas: item.esActividadCaptura
                ? [
                    _Metrica('${item.leads}', 'LEADS', item.leadsRoutePath),
                    _Metrica('${item.empresas}', 'EMPRESAS'),
                    _Metrica('${item.duracionDias}', 'DÍAS'),
                  ]
                : [
                    _Metrica(
                      '${item.registrados}',
                      'REGISTRADOS',
                      item.registradosRoutePath,
                    ),
                    _Metrica(
                      item.porcentajeAcreditados,
                      'ACREDITADOS',
                      item.kpiRoutePath,
                    ),
                    _Metrica('${item.leads}', 'LEADS', item.leadsRoutePath),
                  ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < acciones.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: _boton(context, acciones[i], filled: i == 0)),
              ],
            ],
          ),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      height: altoFijo ? double.infinity : null,
      decoration: BoxDecoration(
        gradient: TwGradients.hero,
        borderRadius: TwRadii.hero,
        boxShadow: conSombra ? TwShadows.hero : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: altoFijo ? StackFit.expand : StackFit.loose,
        children: [
          // Velo solo sobre la foto, y cerrado: las portadas suelen ser
          // afiches con texto propio, y en la card compacta ese texto caía
          // detrás de las métricas. Sin foto, el texto blanco ya lee sobre
          // el degradado navy y la card queda del mismo tono que su esqueleto.
          if (item.tieneImagen) ...[
            Positioned.fill(
              child: EventoHeroFoto(imagenUrl: item.imagenUrl!, velo: 0),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: _veloSobreFoto),
              ),
            ),
          ],
          contenido,
        ],
      ),
    );
  }

  Widget _boton(
    BuildContext context,
    HomeCardAccion accion, {
    required bool filled,
  }) {
    return switch (accion) {
      HomeCardAccion.verEvento || HomeCardAccion.verActividad => _HeroCta(
        key: Key('proximo_evento_ver_${item.id}'),
        label: accion == HomeCardAccion.verEvento
            ? 'Ver evento'
            : 'Ver actividad',
        filled: filled,
        onTap: () => context.push(item.routePath),
      ),
      // Con talleres, antes de la cámara pregunta dónde se acredita.
      HomeCardAccion.escanearQr => _HeroCta(
        key: Key('proximo_evento_escanear_qr_${item.id}'),
        label: 'Escanear QR',
        icon: Symbols.qr_code_scanner_rounded,
        filled: filled,
        onTap: () => abrirEscanerQr(context, item.id),
      ),
      HomeCardAccion.capturarLead => _HeroCta(
        key: Key('proximo_evento_capturar_lead_${item.id}'),
        label: 'Capturar lead',
        icon: Symbols.person_add_rounded,
        filled: filled,
        onTap: () => context.push(item.capturarLeadRoutePath!),
      ),
    };
  }
}

/// Una columna de [_HomeStats]: valor, etiqueta y, si se puede abrir, la
/// ruta de su lista.
class _Metrica {
  const _Metrica(this.valor, this.etiqueta, [this.ruta]);

  final String valor;
  final String etiqueta;
  final String? ruta;
}

/// Métricas del hero del home: tres columnas de igual ancho separadas por un
/// hairline al 14 % de blanco. Las que tienen ruta se tocan para abrirla.
class _HomeStats extends StatelessWidget {
  const _HomeStats({required this.columnas});

  final List<_Metrica> columnas;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < columnas.length; i++)
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: i == 0
                      ? null
                      : const Border(
                          left: BorderSide(color: TwColors.whiteA14),
                        ),
                ),
                child: _columna(context, columnas[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _columna(BuildContext context, _Metrica metrica) {
    final contenido = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            metrica.valor,
            maxLines: 1,
            style: TwText.homeStatValue.copyWith(fontSize: 21),
          ),
        ),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            metrica.etiqueta,
            maxLines: 1,
            style: TwText.homeStatLabel,
          ),
        ),
      ],
    );
    final ruta = metrica.ruta;
    if (ruta == null) return contenido;
    return TwPressable(
      key: Key('proximo_evento_metrica_${metrica.etiqueta.toLowerCase()}'),
      onTap: () => context.push(ruta),
      child: contenido,
    );
  }
}

/// CTA del hero: blanco (principal) o fantasma sobre el navy.
class _HeroCta extends StatelessWidget {
  const _HeroCta({
    super.key,
    required this.label,
    required this.filled,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = filled ? TwColors.deepInk : Colors.white;

    return TwPressable(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: filled ? TwColors.surface : TwColors.whiteA14,
          borderRadius: TwRadii.button,
          border: filled ? null : Border.all(color: TwColors.whiteA22),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 19, color: color),
                const SizedBox(width: 7),
              ],
              Text(label, style: filled ? TwText.heroCta : TwText.heroCtaGhost),
            ],
          ),
        ),
      ),
    );
  }
}
