import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tw_tokens.dart';
import 'app_image_skeleton.dart';
import 'tw_detail_scaffold.dart';

/// Esqueletos de pantalla completa: calcan las tarjetas reales (listas,
/// menús de evento, formularios, KPI) para que la primera carga se lea como
/// la pantalla que viene y el contenido no salte al llegar.
///
/// Las piezas sueltas ([AppSkeletonBox], [AppSkeletonText]) viven en
/// `app_image_skeleton.dart` y comparten el mismo reloj de brillo.

/// Lo que va a la izquierda de cada fila de una lista.
enum TwSkeletonLeading {
  /// Bloque de fecha de [EventRow] y de los talleres.
  fecha,

  /// Avatar redondo (usuarios, leads, registrados).
  avatar,

  /// Caja de icono de 42 (notificaciones).
  icono,
}

/// Anchos del título por fila: listas parejas se leen como relleno, no como
/// datos que vienen.
const _anchosTitulo = [0.78, 0.6, 0.86, 0.52, 0.7, 0.64];

/// Fila de lista: tarjeta blanca con su elemento a la izquierda, título,
/// línea secundaria y, si la fila real la tiene, una píldora de estado.
class TwRowSkeleton extends StatelessWidget {
  const TwRowSkeleton({
    super.key,
    this.leading = TwSkeletonLeading.fecha,
    this.anchoTitulo = 0.7,
    this.conPildora = false,
  });

  final TwSkeletonLeading leading;

  /// Fracción del ancho disponible que ocupa la barra del título.
  final double anchoTitulo;
  final bool conPildora;

  @override
  Widget build(BuildContext context) {
    final escala = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
    final izquierda = switch (leading) {
      TwSkeletonLeading.fecha => AppSkeletonBox(
        width: 48 * escala,
        height: 52 * escala,
        radio: TwRadii.iconLg,
      ),
      TwSkeletonLeading.avatar => const AppSkeletonBox(width: 44, height: 44),
      TwSkeletonLeading.icono => const AppSkeletonBox(
        width: 42,
        height: 42,
        radio: TwRadii.iconLg,
      ),
    };

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: TwColors.surface,
        borderRadius: TwRadii.tile,
        border: Border.all(color: TwColors.border07),
        boxShadow: TwShadows.card,
      ),
      child: Row(
        children: [
          izquierda,
          const SizedBox(width: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final ancho = constraints.maxWidth;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSkeletonText(
                      muestra: 'Nombre',
                      style: TwText.tileTitle.copyWith(
                        fontSize: 14,
                        height: 1.35,
                      ),
                      width: ancho * anchoTitulo,
                    ),
                    const SizedBox(height: 4),
                    AppSkeletonText(
                      muestra: 'Detalle',
                      style: TwText.tileSubtitle.copyWith(fontSize: 12),
                      width: ancho * anchoTitulo * 0.62,
                    ),
                    if (conPildora) ...[
                      const SizedBox(height: 8),
                      const AppSkeletonBox(width: 76, height: 20),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Columna de [TwRowSkeleton]s con el hueco de las listas reales.
class TwListSkeleton extends StatelessWidget {
  const TwListSkeleton({
    super.key,
    this.leading = TwSkeletonLeading.fecha,
    this.filas = 6,
    this.conPildora = false,
    this.gap = 10,
  });

  final TwSkeletonLeading leading;
  final int filas;
  final bool conPildora;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Cargando',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < filas; i++) ...[
              if (i > 0) SizedBox(height: gap),
              TwRowSkeleton(
                leading: leading,
                anchoTitulo: _anchosTitulo[i % _anchosTitulo.length],
                conPildora: conPildora,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// [TwListSkeleton] dentro de un `CustomScrollView`, con el gutter de 20 de
/// las listas del shell.
class TwSliverListSkeleton extends StatelessWidget {
  const TwSliverListSkeleton({
    super.key,
    this.leading = TwSkeletonLeading.fecha,
    this.filas = 6,
    this.conPildora = false,
  });

  final TwSkeletonLeading leading;
  final int filas;
  final bool conPildora;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      sliver: SliverToBoxAdapter(
        child: TwListSkeleton(
          leading: leading,
          filas: filas,
          conPildora: conPildora,
        ),
      ),
    );
  }
}

/// [TwListSkeleton] como cuerpo de una pantalla: no se desplaza, solo llena.
class TwListSkeletonView extends StatelessWidget {
  const TwListSkeletonView({
    super.key,
    this.leading = TwSkeletonLeading.fecha,
    this.filas = 6,
    this.conPildora = false,
    this.padding = const EdgeInsets.fromLTRB(
      TwSpacing.screenH,
      8,
      TwSpacing.screenH,
      32,
    ),
    this.gap = 10,
  });

  final TwSkeletonLeading leading;
  final int filas;
  final bool conPildora;
  final EdgeInsets padding;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      child: TwListSkeleton(
        leading: leading,
        filas: filas,
        conPildora: conPildora,
        gap: gap,
      ),
    );
  }
}

/// Fila de acción de los menús ([TwActionTile]): caja de icono, título y
/// subtítulo.
class TwActionTileSkeleton extends StatelessWidget {
  const TwActionTileSkeleton({super.key, this.anchoTitulo = 0.6});

  final double anchoTitulo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
      decoration: BoxDecoration(
        color: TwColors.surface,
        borderRadius: TwRadii.tile,
        border: Border.all(color: TwColors.border07),
        boxShadow: TwShadows.card,
      ),
      child: Row(
        children: [
          const AppSkeletonBox(width: 42, height: 42, radio: TwRadii.iconLg),
          const SizedBox(width: 13),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final ancho = constraints.maxWidth;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppSkeletonText(
                      muestra: 'Acción',
                      style: TwText.tileTitle,
                      width: ancho * anchoTitulo,
                    ),
                    const SizedBox(height: 4),
                    AppSkeletonText(
                      muestra: 'Detalle',
                      style: TwText.tileSubtitle,
                      width: ancho * anchoTitulo * 0.8,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Rótulo de sección ([TwSectionLabel]) en blanco: mismo ritmo vertical.
class TwSectionLabelSkeleton extends StatelessWidget {
  const TwSectionLabelSkeleton({super.key, this.top = 24, this.ancho = 120});

  final double top;
  final double ancho;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 11, left: 3),
      child: AppSkeletonText(
        muestra: 'SECCIÓN',
        style: TwText.sectionLabel,
        width: ancho,
      ),
    );
  }
}

/// Relleno del contenido sobre el navy del hero.
const _rellenoHero = TwColors.whiteA14;

/// Píldora vacía con el padding y el texto de la real, para que mida lo
/// mismo con cualquier escala de fuente.
Widget _pildoraHero(String muestra, TextStyle style, EdgeInsets padding) {
  return Container(
    padding: padding,
    decoration: BoxDecoration(
      color: _rellenoHero,
      borderRadius: TwRadii.pill,
      border: Border.all(color: Colors.transparent),
    ),
    child: Text(
      muestra,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
      style: style.copyWith(color: Colors.transparent),
    ),
  );
}

/// Hero a sangre de los menús de evento ([TwEventHero]) mientras llega el
/// evento: píldoras, título, lugar, métricas y el botón principal.
class TwEventHeroSkeleton extends StatelessWidget {
  const TwEventHeroSkeleton({
    super.key,
    required this.padding,
    this.conCta = true,
    this.maxContentWidth = 560,
  });

  final EdgeInsets padding;
  final bool conCta;
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    Widget texto(String muestra, TextStyle style, double ancho) =>
        AppSkeletonText(
          muestra: muestra,
          style: style,
          width: ancho,
          color: _rellenoHero,
        );

    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: TwGradients.hero),
        child: Padding(
          padding: padding,
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final ancho = constraints.maxWidth;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          _pildoraHero(
                            '•  ACTIVO',
                            TwText.statusPill,
                            const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 6,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: _pildoraHero(
                              'martes 25 · agosto 2026',
                              TwText.datePill,
                              const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 7,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      texto(
                        'Nombre',
                        TwText.heroTitle.copyWith(
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                        ancho * 0.78,
                      ),
                      const SizedBox(height: 8),
                      texto('Lugar', TwText.heroMeta, ancho * 0.45),
                      Padding(
                        padding: const EdgeInsets.only(top: 20, bottom: 16),
                        child: Row(
                          children: [
                            for (var i = 0; i < 3; i++)
                              Expanded(
                                child: Column(
                                  children: [
                                    texto('00', TwText.statValue, 32),
                                    const SizedBox(height: 6),
                                    texto('REGISTRADOS', TwText.statLabel, 62),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (conCta)
                        const AppSkeletonBox(
                          height: 52,
                          radio: TwRadii.heroBtn,
                          color: _rellenoHero,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hero en tarjeta (el del usuario externo): mismo contenido que
/// [TwEventHeroSkeleton] en una card navy de radio 22, con dos botones.
class TwHeroCardSkeleton extends StatelessWidget {
  const TwHeroCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: const BoxDecoration(
        gradient: TwGradients.hero,
        borderRadius: TwRadii.hero,
        boxShadow: TwShadows.hero,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final ancho = constraints.maxWidth;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: _pildoraHero(
                      'martes 25 · agosto 2026',
                      TwText.datePill,
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _pildoraHero(
                    '•  ACTIVO',
                    TwText.statusPill,
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AppSkeletonText(
                muestra: 'Nombre',
                style: TwText.heroTitle,
                width: ancho * 0.78,
                color: _rellenoHero,
              ),
              const SizedBox(height: 7),
              AppSkeletonText(
                muestra: 'Lugar',
                style: TwText.heroMeta,
                width: ancho * 0.45,
                color: _rellenoHero,
              ),
              const SizedBox(height: 18),
              const Row(
                children: [
                  Expanded(
                    child: AppSkeletonBox(
                      height: 52,
                      radio: TwRadii.heroBtn,
                      color: _rellenoHero,
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: AppSkeletonBox(
                      height: 52,
                      radio: TwRadii.heroBtn,
                      color: _rellenoHero,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Menú de evento o de actividad cargando: la misma pantalla con su barra
/// (el atrás funciona desde el primer frame), el hero y las acciones vacías.
class TwEventMenuSkeleton extends StatelessWidget {
  const TwEventMenuSkeleton({
    super.key,
    required this.eyebrow,
    required this.onBack,
    this.acciones = const [3, 3],
  });

  final String eyebrow;
  final VoidCallback onBack;

  /// Filas por sección: una sección por elemento.
  final List<int> acciones;

  @override
  Widget build(BuildContext context) {
    var fila = 0;
    return Semantics(
      label: 'Cargando',
      child: TwDetailScaffold(
        eyebrow: eyebrow,
        title: '',
        onBack: onBack,
        heroBuilder: (padding) =>
            ExcludeSemantics(child: TwEventHeroSkeleton(padding: padding)),
        children: [
          for (final filas in acciones) ...[
            const TwSectionLabelSkeleton(),
            for (var i = 0; i < filas; i++) ...[
              if (i > 0) const SizedBox(height: TwSpacing.tileGap),
              TwActionTileSkeleton(
                anchoTitulo: _anchosTitulo[fila++ % _anchosTitulo.length],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Tarjeta de KPI ([TwKpiCard]) vacía: caja de icono, valor y etiqueta.
class TwKpiCardSkeleton extends StatelessWidget {
  const TwKpiCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: const BoxDecoration(
        color: TwColors.surface,
        borderRadius: TwRadii.card,
        border: Border.fromBorderSide(BorderSide(color: TwColors.border07)),
        boxShadow: TwShadows.card,
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSkeletonBox(width: 38, height: 38, radio: TwRadii.field),
          SizedBox(height: 14),
          AppSkeletonText(muestra: '000', style: TwText.kpiValue, width: 48),
          SizedBox(height: 5),
          AppSkeletonText(
            muestra: 'Etiqueta',
            style: TwText.kpiLabel,
            width: 90,
          ),
        ],
      ),
    );
  }
}

/// Dos [TwKpiCardSkeleton] lado a lado, como las filas de métricas.
class TwKpiRowSkeleton extends StatelessWidget {
  const TwKpiRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: TwKpiCardSkeleton()),
        SizedBox(width: 12),
        Expanded(child: TwKpiCardSkeleton()),
      ],
    );
  }
}

/// Campo de formulario vacío: etiqueta y caja del alto de un `TextField`.
class TwFieldSkeleton extends StatelessWidget {
  const TwFieldSkeleton({super.key, this.anchoEtiqueta = 96});

  final double anchoEtiqueta;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 7),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AppSkeletonText(
              muestra: 'Etiqueta',
              style: TwText.checkboxLabel.copyWith(fontSize: 13),
              width: anchoEtiqueta,
            ),
          ),
        ),
        const AppSkeletonBox(height: 52, radio: TwRadii.field),
      ],
    );
  }
}

/// Sección de formulario ([FormSection]) vacía: cabecera con icono y sus
/// campos.
class TwFormSectionSkeleton extends StatelessWidget {
  const TwFormSectionSkeleton({super.key, this.campos = 3});

  final int campos;

  static const _anchosEtiqueta = [96.0, 124.0, 80.0, 110.0];

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
              const AppSkeletonBox(
                width: 34,
                height: 34,
                radio: TwRadii.iconSm,
              ),
              const SizedBox(width: 12),
              AppSkeletonText(
                muestra: 'Sección',
                style: TwText.tileTitle.copyWith(fontWeight: FontWeight.w700),
                width: 130,
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < campos; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            TwFieldSkeleton(
              anchoEtiqueta: _anchosEtiqueta[i % _anchosEtiqueta.length],
            ),
          ],
        ],
      ),
    );
  }
}

/// Formulario cargando: secciones vacías una bajo otra, con el ancho y el
/// gutter de los formularios reales.
class TwFormSkeleton extends StatelessWidget {
  const TwFormSkeleton({
    super.key,
    this.secciones = const [3, 2],
    this.padding = const EdgeInsets.fromLTRB(
      TwSpacing.screenH,
      14,
      TwSpacing.screenH,
      32,
    ),
    this.encabezado,
  });

  /// Campos por sección: una sección por elemento.
  final List<int> secciones;
  final EdgeInsets padding;

  /// Lo que va antes de las secciones (p. ej. el avatar de un perfil).
  final Widget? encabezado;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Cargando',
      child: ExcludeSemantics(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: padding,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?encabezado,
                  for (var i = 0; i < secciones.length; i++) ...[
                    if (i > 0 || encabezado != null) const SizedBox(height: 14),
                    TwFormSectionSkeleton(campos: secciones[i]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
