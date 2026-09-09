import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Tokens del rediseño "Transworld RegisPro · Eventos & Leads"
/// (guía `Guia Flutter - Libreria de componentes`, §2).
///
/// Regla del diseño: **cero colores libres y cero estilos libres**. Todo lo que
/// pinta o tipografía las pantallas rediseñadas (Login, Home, menú de Evento y
/// menú de Evento de leads) sale de este archivo.
///
/// Convive con [AppColors] (`app_theme.dart`), que sigue vistiendo el resto de
/// la app; no se toca para no arrastrar el rediseño a pantallas fuera de
/// alcance.
class TwColors {
  TwColors._();

  // ---------- Superficies ----------

  /// Fondo de TODA pantalla rediseñada.
  ///
  /// La guía especifica `#EEF1F7`, pero se mantiene el `#F2F5F9` histórico
  /// (= `AppColors.background`, el que siguen usando las listas de eventos y
  /// eventos de leads): en la PWA de iOS la barra del navegador tiene
  /// un color fijo y el contenedor de la app lo iguala para que no se vea la
  /// separación. Cambiar este valor rompe ese calce.
  static const bg = Color(0xFFF2F5F9);
  static const surface = Color(0xFFFFFFFF); // tarjetas y tiles
  static const surfaceTint = Color(0xFFEEF2F9); // caja de icono neutro
  static const silver = Color(0xFFE8ECF2);
  static const fieldBg = Color(0xFFFFFFFF); // fondo de input editable
  static const fieldBorder = Color(0xFFE3EAF4); // borde hairline (no editable)
  static const fieldBorderActive = Color(
    0xFF203E6D,
  ); // marco navy de input editable

  // ---------- Bordes hairline (azul-negro translúcido) ----------
  static const border07 = Color(0x12102340); // rgba(16,35,64,.07) tarjetas
  static const border08 = Color(0x14102340); // rgba(16,35,64,.08) botones icono
  static const border10 = Color(0x1A102340); // rgba(16,35,64,.10) chips

  // ---------- Texto ----------
  static const ink = Color(0xFF16233C); // títulos y texto principal
  static const inkSoft = Color(0xFF1F2B44); // iconos de barra superior
  static const deepInk = Color(0xFF12294A); // texto sobre botón blanco
  static const body = Color(0xFF6B7688); // párrafo de login
  static const secondary = Color(0xFF71809A); // subtítulos de pantalla
  static const muted = Color(0xFF8A95A8); // labels, metadatos
  static const labelInk = Color(0xFF48566E); // "Recordarme"
  static const subtle = Color(0xFF7D8798); // subtítulo tarjeta soporte
  static const footerInk = Color(0xFFA2ABBB); // pie de versión

  // ---------- Iconos ----------
  static const iconIdle = Color(0xFF7F8CA1); // icono dentro de input
  static const iconInk = Color(0xFF40506B); // icono neutro sobre tint
  static const iconEye = Color(0xFF5C6B82); // ojo de contraseña
  static const chevron = Color(0xFFB6C0CF); // chevron de action tile
  static const chevronSoft = Color(0xFF98A2B3); // chevron tarjeta soporte
  static const chevronGreen = Color(0xFF9DC5AE); // chevron tile Excel

  // ---------- Marca ----------
  static const brand700 = Color(0xFF20527F);
  static const brand900 = Color(0xFF0F2B4C);
  static const hero700 = Color(0xFF16385C);
  static const hero900 = Color(0xFF0A1E36);
  static const tile700 = Color(0xFF22548A); // icono destacado de action tile
  static const tile900 = Color(0xFF12314F);

  // ---------- Acentos (fondo tenue + tinta) ----------
  static const blueTint = Color(0xFFE8EEFB);
  static const blueInk = Color(0xFF2B62B8);
  static const greenTint = Color(0xFFE6F4E7);
  static const greenInk = Color(0xFF2F7D43);
  static const purpleTint = Color(0xFFEFEAFC);
  static const purpleInk = Color(0xFF5B46B8);
  static const amberTint = Color(0xFFFDEFE2);
  static const amberInk = Color(0xFFB4691F);
  static const amberInkMuted = Color(0xC7B4691F); // ~78%

  /// Cartel de sin conexión: naranjo pálido + tinta muy oscura (no gris).
  static const offlineNoticeBg = Color(0xFFFBE0C4);
  static const offlineNoticeIconBg = Color(0xFFF3C894);
  static const offlineNoticeInk = Color(0xFF4A1F05);
  static const offlineNoticeMuted = Color(0xFF6B3010);
  static const offlineNoticeBorder = Color(0x66C45E12);

  // ---------- Excel ----------
  static const excel500 = Color(0xFF21A366);
  static const excel700 = Color(0xFF0E7040);
  static const excelBadgeBg = Color(0xFFE7F6EE);
  static const excelBadgeBd = Color(0xFFC7E9D6);
  static const excelCardBd = Color(0xFFD8ECDF);

  // ---------- Estado ----------
  static const danger = Color(0xFFD14343); // error de formulario
  static const dangerTint = Color(0xFFFBEAEA); // fondo de aviso de error
  static const statusActive = Color(0xFF7CE0B0);
  static const statusActiveBg = Color(0x1F7CE0B0); // 12%
  static const statusActiveBd = Color(0x477CE0B0); // 28%
  static const statusEnded = Color(0xFFF3B4B4);
  static const statusEndedBg = Color(0x1FF3B4B4); // 12%
  static const statusEndedBd = Color(0x42F3B4B4); // 26%

  // Origen del evento de leads: lima de marca (interno) y naranjo (externo).
  // Las tintas son las versiones oscuras de ambas familias porque este pill
  // vive sobre tarjeta blanca, no sobre el hero como los de estado.
  static const originInternal = Color(0xFF6B9E14); // lima legible
  static const originInternalBg = Color(0x1F6B9E14); // 12%
  static const originInternalBd = Color(0x476B9E14); // 28%
  static const originExternal = Color(0xFFB4691F); // naranjo
  static const originExternalBg = Color(0x1FB4691F); // 12%
  static const originExternalBd = Color(0x47B4691F); // 28%

  // ---------- Blancos translúcidos (solo sobre hero) ----------
  static const whiteA14 = Color(0x24FFFFFF); // divisores de stats
  static const whiteA16 = Color(0x29FFFFFF); // fondo de pill / botón fantasma
  static const whiteA18 = Color(0x2EFFFFFF); // borde de pill
  static const whiteA22 = Color(0x38FFFFFF); // borde de botón fantasma
  static const whiteA55 = Color(0x8CFFFFFF); // label de stat
  static const whiteA66 = Color(0xA8FFFFFF); // línea de ubicación
  static const whiteA75 = Color(0xBFFFFFFF); // eyebrow sobre hero

  // ---------- Toast ----------
  static const toastBg = Color(0xF20E1E34); // 95%
  static const toastInfo = Color(0xFF8FB6E8);
  static const toastSuccess = Color(0xFF5AD696);
  static const toastError = Color(0xFFF3B4B4);
}

class TwGradients {
  TwGradients._();

  /// CSS `140deg` ≈ topLeft → bottomRight.
  static const brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [TwColors.brand700, TwColors.brand900],
  );

  static const tileIcon = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [TwColors.tile700, TwColors.tile900],
  );

  /// CSS `150deg`: algo más vertical que el de marca.
  static const hero = LinearGradient(
    begin: Alignment(-0.5, -1),
    end: Alignment(0.5, 1),
    colors: [TwColors.hero700, TwColors.hero900],
  );

  /// CSS `160deg`.
  static const excel = LinearGradient(
    begin: Alignment(-0.35, -1),
    end: Alignment(0.35, 1),
    colors: [TwColors.excel500, TwColors.excel700],
  );

  /// Velo de las cards hero (home, menú de evento y menú de actividad).
  /// Arriba 66% / abajo 94%: la portada se lee y el texto blanco también.
  static const heroScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xA808182C), Color(0xF0081628)],
  );
}

class TwShadows {
  TwShadows._();

  /// `0 2px 8px rgba(16,35,64,.05)` — tarjetas y tiles.
  static const card = [
    BoxShadow(color: Color(0x0D102340), blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// `0 2px 6px rgba(16,35,64,.06)` — botones-icono de cabecera.
  static const soft = [
    BoxShadow(color: Color(0x0F102340), blurRadius: 6, offset: Offset(0, 2)),
  ];

  /// `0 10px 22px -12px rgba(14,42,74,.7)` — botón primario.
  static const primary = [
    BoxShadow(
      color: Color(0xB30E2A4A),
      blurRadius: 22,
      offset: Offset(0, 10),
      spreadRadius: -12,
    ),
  ];

  /// `0 14px 30px -16px rgba(10,28,52,.55)` — hero card.
  static const hero = [
    BoxShadow(
      color: Color(0x8C0A1C34),
      blurRadius: 30,
      offset: Offset(0, 14),
      spreadRadius: -16,
    ),
  ];

  /// `0 8px 18px -8px rgba(15,43,76,.8)` — botón compartir.
  static const brandButton = [
    BoxShadow(
      color: Color(0xCC0F2B4C),
      blurRadius: 18,
      offset: Offset(0, 8),
      spreadRadius: -8,
    ),
  ];

  /// `0 8px 16px -8px rgba(18,49,79,.8)` — caja de icono destacada.
  static const tileIcon = [
    BoxShadow(
      color: Color(0xCC12314F),
      blurRadius: 16,
      offset: Offset(0, 8),
      spreadRadius: -8,
    ),
  ];

  /// `0 8px 16px -7px rgba(16,124,65,.7)` — caja de icono Excel.
  static const excelIcon = [
    BoxShadow(
      color: Color(0xB3107C41),
      blurRadius: 16,
      offset: Offset(0, 8),
      spreadRadius: -7,
    ),
  ];

  /// `0 2px 8px rgba(16,80,45,.07)` — tile de Excel.
  static const excelCard = [
    BoxShadow(color: Color(0x1210502D), blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// `0 18px 34px -14px rgba(6,18,36,.8)` — toast.
  static const toast = [
    BoxShadow(
      color: Color(0xCC061224),
      blurRadius: 34,
      offset: Offset(0, 18),
      spreadRadius: -14,
    ),
  ];
}

class TwSpacing {
  TwSpacing._();

  /// Margen lateral de pantalla del rediseño: 16, siempre (§2.3).
  static const screenH = 16.0;

  /// Separación entre action tiles.
  static const tileGap = 10.0;
}

class TwRadii {
  TwRadii._();

  static const hero = BorderRadius.all(Radius.circular(22));
  static const card = BorderRadius.all(Radius.circular(18));
  static const tile = BorderRadius.all(Radius.circular(17));
  static const toast = BorderRadius.all(Radius.circular(16));
  static const heroBtn = BorderRadius.all(Radius.circular(15));
  static const button = BorderRadius.all(Radius.circular(14));
  static const iconLg = BorderRadius.all(Radius.circular(13));
  static const field = BorderRadius.all(Radius.circular(12));
  static const iconSm = BorderRadius.all(Radius.circular(11));
  static const pill = BorderRadius.all(Radius.circular(8));
  static const badge = BorderRadius.all(Radius.circular(6));
}

/// Estilos de texto del rediseño (§2.2).
///
/// No declaran `fontFamily` a propósito: la app carga Plus Jakarta Sans con
/// `google_fonts` y la fija como fuente del `ThemeData`, así que el estilo la
/// hereda del `DefaultTextStyle` de Material. Lo que sí va **siempre**
/// explícito es `height`, `letterSpacing` y `leadingDistribution`: sin ellos el
/// tema base filtra su propio interlineado/tracking y el ritmo vertical se
/// desvía del mock.
class TwText {
  TwText._();

  static const _lead = TextLeadingDistribution.even;

  static const display = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: -0.30,
    color: TwColors.ink,
    leadingDistribution: _lead,
  );

  static const heroTitle = TextStyle(
    fontSize: 23,
    fontWeight: FontWeight.w700,
    height: 1.20,
    letterSpacing: 0,
    color: Colors.white,
    leadingDistribution: _lead,
  );

  static const statValue = TextStyle(
    fontSize: 25,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 0,
    color: Colors.white,
    leadingDistribution: _lead,
  );

  static const statLabel = TextStyle(
    fontSize: 9.5,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 1.14,
    color: TwColors.whiteA55,
    leadingDistribution: _lead,
  );

  static const brandName = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w800,
    height: 1.10,
    letterSpacing: 0.30,
    color: TwColors.ink,
    leadingDistribution: _lead,
  );

  static const brandSub = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    height: 1.10,
    letterSpacing: 1.40,
    color: TwColors.muted,
    leadingDistribution: _lead,
  );

  static const button = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 0,
    color: Colors.white,
    leadingDistribution: _lead,
  );

  static const buttonDark = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 0,
    color: TwColors.deepInk,
    leadingDistribution: _lead,
  );

  static const tileTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.20,
    letterSpacing: 0,
    color: TwColors.ink,
    leadingDistribution: _lead,
  );

  static const tileSubtitle = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    height: 1.20,
    letterSpacing: 0,
    color: TwColors.muted,
    leadingDistribution: _lead,
  );

  static const input = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.20,
    letterSpacing: 0,
    color: TwColors.ink,
    leadingDistribution: _lead,
  );

  static const bodyText = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.45,
    letterSpacing: 0,
    color: TwColors.body,
    leadingDistribution: _lead,
  );

  static const checkboxLabel = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
    height: 1.20,
    letterSpacing: 0,
    color: TwColors.labelInk,
    leadingDistribution: _lead,
  );

  static const linkText = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
    height: 1.0,
    letterSpacing: 0,
    color: TwColors.brand700,
    leadingDistribution: _lead,
  );

  static const supportTitle = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
    height: 1.20,
    letterSpacing: 0,
    color: TwColors.ink,
    leadingDistribution: _lead,
  );

  static const supportSub = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.20,
    letterSpacing: 0,
    color: TwColors.subtle,
    leadingDistribution: _lead,
  );

  static const errorText = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.20,
    letterSpacing: 0,
    color: TwColors.danger,
    leadingDistribution: _lead,
  );

  static const toastText = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: 0,
    color: Colors.white,
    leadingDistribution: _lead,
  );

  static const datePill = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    height: 1.0,
    letterSpacing: 0,
    color: Colors.white,
    leadingDistribution: _lead,
  );

  static const heroMeta = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.20,
    letterSpacing: 0,
    color: TwColors.whiteA66,
    leadingDistribution: _lead,
  );

  static const sectionLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 1.54,
    color: TwColors.muted,
    leadingDistribution: _lead,
  );

  static const eyebrow = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 1.47,
    color: TwColors.muted,
    leadingDistribution: _lead,
  );

  static const fieldLabel = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 1.26,
    color: TwColors.muted,
    leadingDistribution: _lead,
  );

  static const statusPill = TextStyle(
    fontSize: 9.5,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 1.14,
    leadingDistribution: _lead,
  );

  static const badge = TextStyle(
    fontSize: 9.5,
    fontWeight: FontWeight.w800,
    height: 1.0,
    letterSpacing: 0.95,
    color: TwColors.excel700,
    leadingDistribution: _lead,
  );

  static const footer = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 1.05,
    color: TwColors.footerInk,
    leadingDistribution: _lead,
  );

  // ---------- Home (§ prototipo, pantalla de inicio) ----------

  static const greeting = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w700,
    height: 1.10,
    letterSpacing: 0,
    color: TwColors.ink,
    leadingDistribution: _lead,
  );

  static const roleBadge = TextStyle(
    fontSize: 9.5,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 1.14,
    color: TwColors.blueInk,
    leadingDistribution: _lead,
  );

  static const homeHeroTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.20,
    letterSpacing: 0,
    color: Colors.white,
    leadingDistribution: _lead,
  );

  static const homeEyebrow = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 1.40,
    color: TwColors.whiteA75,
    leadingDistribution: _lead,
  );

  static const homeDateChip = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 0.84,
    color: Colors.white,
    leadingDistribution: _lead,
  );

  static const homeStatValue = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 0,
    color: Colors.white,
    leadingDistribution: _lead,
  );

  static const homeStatLabel = TextStyle(
    fontSize: 9.5,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 1.14,
    color: TwColors.whiteA55,
    leadingDistribution: _lead,
  );

  static const heroCta = TextStyle(
    fontSize: 14.5,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 0,
    color: TwColors.deepInk,
    leadingDistribution: _lead,
  );

  static const heroCtaGhost = TextStyle(
    fontSize: 14.5,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 0,
    color: Colors.white,
    leadingDistribution: _lead,
  );

  static const kpiValue = TextStyle(
    fontSize: 27,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 0,
    color: TwColors.ink,
    leadingDistribution: _lead,
  );

  static const navLabel = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    height: 1.0,
    letterSpacing: 0,
    leadingDistribution: _lead,
  );

  static const kpiLabel = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
    height: 1.20,
    letterSpacing: 0,
    color: TwColors.secondary,
    leadingDistribution: _lead,
  );
}

/// `martes 25 · agosto 2026` (§10). Requiere `initializeDateFormatting('es')`,
/// que `main()` ya ejecuta al arrancar.
String formatearFechaLarga(DateTime fecha) {
  return DateFormat("EEEE d '·' MMMM y", 'es').format(fecha).toLowerCase();
}

/// Rango de una actividad de captura: un día usa [formatearFechaLarga];
/// varios días, `12–14 · septiembre 2026` (o meses distintos si cruza).
String formatearFechaActividad(DateTime fecha, int duracionDias) {
  if (duracionDias <= 1) return formatearFechaLarga(fecha);
  final inicio = DateTime(fecha.year, fecha.month, fecha.day);
  final fin = inicio.add(Duration(days: duracionDias - 1));
  if (inicio.year == fin.year && inicio.month == fin.month) {
    final mesAnio = DateFormat('MMMM y', 'es').format(inicio);
    return '${inicio.day}–${fin.day} · $mesAnio'.toLowerCase();
  }
  if (inicio.year == fin.year) {
    final desde = DateFormat("d '·' MMMM", 'es').format(inicio);
    final hasta = DateFormat("d '·' MMMM y", 'es').format(fin);
    return '$desde – $hasta'.toLowerCase();
  }
  return '${formatearFechaLarga(inicio)} – ${formatearFechaLarga(fin)}';
}

/// `25 AGO` — píldora corta del hero del home.
String formatearDiaMesCorto(DateTime fecha) {
  final dia = DateFormat('d', 'es').format(fecha);
  final mes = DateFormat(
    'MMM',
    'es',
  ).format(fecha).toUpperCase().replaceAll('.', '');
  return '$dia $mes';
}
