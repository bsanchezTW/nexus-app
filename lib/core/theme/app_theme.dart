import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tw_tokens.dart';

/// Tokens de color Nexus — anclados al mark Transworld (navy + lima).
///
/// Los neutros (texto gris, bordes, chevrons, superficies) **son** los de
/// [TwColors]: una sola escala para toda la app. Lo que sigue teniendo valor
/// propio es la identidad de marca — navy del logo, lima y sus tintes—, que
/// `test/core/theme/app_theme_test.dart` fija a propósito.
class AppColors {
  AppColors._();

  // Brand (muestreados del logo: navy #203E6D · lima #B1F22A).
  static const primary = Color(0xFF203E6D); // logo navy
  static const primaryDeep = Color(0xFF162B4C); // navy-900
  static const primaryLight = Color(0xFF2E568F); // navy-500
  static const accent = Color(0xFFB1F22A); // logo lima
  static const accentGlow = Color(0xFFA0DE2A); // lima glow del motion spec

  // Neutros unificados con el rediseño.
  static const ink = TwColors.ink;
  static const textSecondary = TwColors.secondary;
  static const textTertiary = TwColors.muted;
  static const background = TwColors.bg;
  static const surface = TwColors.surface;
  static const border = TwColors.fieldBorder;
  static const placeholder = TwColors.muted;
  static const chevronMuted = TwColors.chevron;
  static const divider = TwColors.border07;

  static const tintNavy = TwColors.blueTint;
  static const tintLime = Color(0xFFF3FCE0);

  // Semánticos: success en familia lima (más oscuro para texto legible).
  static const success = Color(0xFF6B9E14);
  static const successTint = tintLime;
  static const warning = TwColors.amberInk;
  static const warningTint = TwColors.amberTint;
  static const danger = TwColors.danger;
  static const dangerTint = TwColors.dangerTint;
  static const toastCheck = accent;

  static const surfaceMuted = tintNavy;

  static const headerGradient = LinearGradient(
    colors: [primaryDeep, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const shadowRest = TwShadows.card;
  static const shadowLifted = TwShadows.card;

  static const avatarPairs = <(Color, Color)>[
    (tintNavy, primary),
    (tintLime, success),
    (Color(0xFFFBF0DF), Color(0xFFB96E12)),
    (Color(0xFFF0EBF8), Color(0xFF6A4FA3)),
    (Color(0xFFFAE9E6), Color(0xFFC03A2B)),
  ];
}

/// Métricas de la navegación del shell ([TwBottomNavBar] / [TwSideNavRail] /
/// tab bar nativa iOS).
///
/// En Android, iOS nativo y web móvil el menú va abajo: barra estilo
/// Material 3 de 72 dp anclada al borde, en vidrio esmerilado, o `UITabBar` de ~49 dp en iPhone/iPad nativo. En
/// Windows y en la web de PC el menú pasa a un rail izquierdo del color del
/// contenedor, sin tapar el contenido.
/// Aquí viven las medidas que otras pantallas usan para reservar espacio.
abstract final class GlassNavTokens {
  /// Alto de la barra, sin el inset de la navegación del sistema.
  static const height = 72.0;

  /// Píldora del ítem activo (64×32, como Material 3).
  static const indicatorWidth = 64.0;
  static const indicatorHeight = 32.0;

  /// Alto visual del `UITabBar` nativo, sin home indicator.
  static const nativeIosHeight = 49.0;

  /// Aire que el plugin reserva sobre la barra para la píldora de selección
  /// de iOS 26 (se anima hasta ~14 pt por encima del borde superior).
  static const nativeIosPillRoom = 14.0;

  /// Alto real que ocupa el platform view de la tab bar nativa.
  static const nativeIosOccupied = nativeIosHeight + nativeIosPillRoom;

  /// Lado del SF Symbol en el `UITabBar` Liquid Glass.
  ///
  /// El defecto de UIKit es 25 y el plugin 24; con 20 seguían viéndose
  /// desproporcionados frente a las etiquetas y al resto de la app.
  static const nativeIosIconSize = 16.0;

  /// Ancho del rail de escritorio (icono + etiqueta, como Discord / WhatsApp).
  static const sideRailWidth = 96.0;

  /// Umbral de escritorio en web: por debajo se mantiene la barra flotante
  /// (ventana estrecha o preview móvil). Encima, el rail de Windows.
  static const sideRailMinWidth = 840.0;

  /// Aire interno del rail: separa los ítems del borde y de la title bar.
  static const sideRailPadding = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 16,
  );

  /// Hueco vertical de cada hairline entre ítems (incluye la línea).
  static const sideRailSeparatorHeight = 24.0;

  /// Sangría del hairline respecto al padding del rail.
  static const sideRailSeparatorIndent = 14.0;

  /// Holgura extra en PWA (iPhone): separa los ítems de la barra nativa.
  static const webBottomExtra = 14.0;

  static const iconSize = 24.0;
  static const labelSize = 12.0;

  static const transitionDuration = Duration(milliseconds: 200);
  static const transitionCurve = Curves.easeOutCubic;

  /// Barra sin safe area ni holgura web.
  static const occupiedHeight = height;

  static double webBottomGap() =>
      kIsWeb && !usesSideRailFor() ? webBottomExtra : 0;

  /// Barra + holgura web, sin safe area.
  static double occupiedHeightOf() => occupiedHeight + webBottomGap();

  /// Plataformas de PC: Windows nativo, y web cuyo UA es windows / macOS /
  /// linux. Android e iOS (app o PWA) quedan fuera.
  static bool usesSideRailFor({bool? isWeb, TargetPlatform? platform}) {
    final web = isWeb ?? kIsWeb;
    final p = platform ?? defaultTargetPlatform;
    if (!web) return p == TargetPlatform.windows;
    return p == TargetPlatform.windows ||
        p == TargetPlatform.macOS ||
        p == TargetPlatform.linux;
  }

  /// Windows nativo siempre. En web, solo con viewport de escritorio.
  static bool usesSideRailOf(
    BuildContext context, {
    bool? isWeb,
    TargetPlatform? platform,
  }) {
    if (!usesSideRailFor(isWeb: isWeb, platform: platform)) return false;
    final web = isWeb ?? kIsWeb;
    if (!web) return true;
    return MediaQuery.sizeOf(context).width >= sideRailMinWidth;
  }

  static bool get usesSideRail => usesSideRailFor();

  /// iPhone/iPad nativo: `UITabBar` Liquid Glass. Safari/PWA sigue con el
  /// panel Flutter — no hay UIKit.
  static bool get usesNativeIosTabBar =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Espacio al final del contenido para que no quede bajo la barra
  /// inferior. Con rail (Windows / web de PC) el menú no cubre el cuerpo. En
  /// iOS nativo la barra ya cubre el home indicator, así que el safe area no
  /// se suma aparte.
  static double contentBottomInset(BuildContext context) {
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom + AppSpacing.xl;
    if (usesSideRailOf(context)) return safeBottom;
    if (usesNativeIosTabBar) return nativeIosOccupied + AppSpacing.xl;
    return occupiedHeightOf() + safeBottom;
  }

  /// Holgura extra de toasts cuando el shell muestra barra inferior.
  static double shellToastLift() {
    if (usesNativeIosTabBar) return nativeIosHeight + AppSpacing.sm;
    return occupiedHeightOf() + AppSpacing.sm;
  }

  /// Relleno bajo los ítems: la barra se pinta también detrás de la
  /// navegación del sistema (gestos o botones), como en Material 3.
  static double bottomPadding(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).bottom + webBottomGap();

  /// Píldora del ítem activo: tinte navy más cargado que [AppColors.tintNavy]
  /// para que se distinga del blanco de la barra.
  static const indicatorColor = Color(0xFFD3DEF5);

  /// Ítems inactivos: slate oscuro (~9:1 sobre blanco), no el gris `muted`.
  static const inactiveForeground = Color(0xFF3F4B61);

  /// Velo del vidrio: el fondo de pantalla al 72 %, igual que la cabecera
  /// colapsable del home.
  static const glassTint = Color(0xB8F2F5F9);

  /// Posición horizontal (−1…1) del ítem [index] de [count] dentro de su
  /// celda. Con celdas iguales, esto deja la píldora del primero en el
  /// margen izquierdo del contenido, la del último en el derecho y el mismo
  /// hueco entre todas.
  static double itemAlignmentX(int index, int count) =>
      count <= 1 ? 0 : -1 + 2 * index / (count - 1);

  static Color activeColor(Brightness brightness) =>
      brightness == Brightness.dark ? AppColors.accent : AppColors.primary;

  static Color inactiveColor(Brightness brightness) =>
      brightness == Brightness.dark
      ? const Color.fromRGBO(255, 255, 255, 0.90)
      : AppColors.ink;
}

class AppSpacing {
  AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 28.0;

  static const screenH = 20.0;
  static const screen = EdgeInsets.symmetric(horizontal: screenH);
  static const contentMax = 760.0;

  /// Formularios en pantallas push: arrancan arriba, con un aire mínimo
  /// bajo la cabecera — el mismo ritmo que crear/editar evento.
  static const form = EdgeInsets.fromLTRB(screenH, 6, screenH, 32);
  static const field = SizedBox(height: 14);
  static const sectionGap = 22.0;
  static const cardGap = 10.0;

  /// Altura visual de la barra inferior (sin safe area).
  static const shellTabBarHeight = GlassNavTokens.height;

  /// Holgura inferior del FAB en pantallas dentro del shell anidado.
  /// El Scaffold interno no ve el [bottomNavigationBar] del padre.
  static const shellFabBottom = GlassNavTokens.occupiedHeight + sm;

  static double shellFabBottomOf([BuildContext? context]) {
    final rail = context == null
        ? GlassNavTokens.usesSideRail
        : GlassNavTokens.usesSideRailOf(context);
    if (rail) return sm;
    if (GlassNavTokens.usesNativeIosTabBar) {
      return GlassNavTokens.nativeIosOccupied + sm;
    }
    return GlassNavTokens.occupiedHeightOf() + sm;
  }
}

class AppRadius {
  AppRadius._();

  static const sm = 10.0;
  static const md = 12.0;
  static const tile = 13.0;
  static const input = 14.0;
  static const lg = 16.0;
  static const fab = 18.0;
  static const header = 28.0;
  static const pill = 99.0;
}

class AppMotion {
  AppMotion._();

  static const ease = Cubic(0.2, 0.8, 0.2, 1);
  static const screenIn = Duration(milliseconds: 350);
  static const pushIn = Duration(milliseconds: 320);
  static const cardIn = Duration(milliseconds: 400);
  static const press = Duration(milliseconds: 180);
  static const stagger = Duration(milliseconds: 40);
  static const toggle = Duration(milliseconds: 250);
  static const toast = Duration(milliseconds: 2300);

  static bool reduceMotion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);
}

class AppTheme {
  AppTheme._();

  static OutlineInputBorder _twFieldBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: TwRadii.field,
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static ThemeData get light {
    final colorScheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.tintNavy,
      onPrimaryContainer: AppColors.primaryDeep,
      secondary: AppColors.primaryLight,
      onSecondary: Colors.white,
      tertiary: AppColors.accent,
      onTertiary: AppColors.primaryDeep,
      tertiaryContainer: AppColors.tintLime,
      onTertiaryContainer: AppColors.primaryDeep,
      error: AppColors.danger,
      onError: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.border,
      outlineVariant: AppColors.divider,
    );

    final baseText = GoogleFonts.plusJakartaSansTextTheme();
    final textTheme = baseText.copyWith(
      displaySmall: baseText.displaySmall?.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: AppColors.ink,
      ),
      headlineMedium: baseText.headlineMedium?.copyWith(
        fontSize: 21,
        fontWeight: FontWeight.w800,
        height: 1.3,
        letterSpacing: -0.3,
        color: AppColors.ink,
      ),
      headlineSmall: baseText.headlineSmall?.copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w800,
        height: 1.28,
        letterSpacing: -0.4,
        color: AppColors.ink,
      ),
      titleLarge: baseText.titleLarge?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.35,
        color: AppColors.ink,
      ),
      titleMedium: baseText.titleMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.35,
        letterSpacing: -0.2,
        color: AppColors.ink,
      ),
      titleSmall: baseText.titleSmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
      ),
      bodyLarge: baseText.bodyLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.ink,
      ),
      bodyMedium: baseText.bodyMedium?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
      bodySmall: baseText.bodySmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      ),
      labelLarge: baseText.labelLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
      labelMedium: baseText.labelMedium?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: AppColors.textTertiary,
      ),
      labelSmall: baseText.labelSmall?.copyWith(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      dividerColor: AppColors.border,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
      // Campos editables: blanco + marco navy. Deshabilitados: fondo de
      // pantalla y borde hairline, para que no se confundan con un input.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return TwColors.bg;
          return TwColors.fieldBg;
        }),
        hintStyle: TwText.input.copyWith(color: TwColors.muted),
        labelStyle: TwText.input.copyWith(color: TwColors.secondary),
        border: _twFieldBorder(TwColors.fieldBorderActive),
        enabledBorder: _twFieldBorder(TwColors.fieldBorderActive),
        disabledBorder: _twFieldBorder(TwColors.fieldBorder),
        focusedBorder: _twFieldBorder(TwColors.fieldBorderActive, width: 1.5),
        errorBorder: _twFieldBorder(TwColors.danger),
        focusedErrorBorder: _twFieldBorder(TwColors.danger, width: 1.5),
        errorStyle: TwText.errorText,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 16,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.tintNavy,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        labelStyle: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryDeep,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border),
        ),
        margin: EdgeInsets.zero,
      ),
      listTileTheme: const ListTileThemeData(iconColor: AppColors.primary),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final active = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: GlassNavTokens.labelSize,
            fontWeight: active ? FontWeight.w500 : FontWeight.w400,
            height: 1.1,
            color: active ? AppColors.primary : AppColors.ink,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final active = states.contains(WidgetState.selected);
          return IconThemeData(
            color: active ? AppColors.primary : AppColors.ink,
            size: GlassNavTokens.iconSize,
          );
        }),
      ),
    );
  }
}

/// Decoración para campos `readOnly`: se funden con el fondo. Material no
/// tiene `WidgetState` para solo-lectura, así que hay que aplicarla a mano.
InputDecoration twReadOnlyDecoration({
  String? hintText,
  String? helperText,
  int? helperMaxLines,
  Widget? suffixIcon,
  String? labelText,
}) {
  const border = OutlineInputBorder(
    borderRadius: TwRadii.field,
    borderSide: BorderSide(color: TwColors.fieldBorder),
  );
  return InputDecoration(
    hintText: hintText,
    helperText: helperText,
    helperMaxLines: helperMaxLines,
    suffixIcon: suffixIcon,
    labelText: labelText,
    filled: true,
    fillColor: TwColors.bg,
    border: border,
    enabledBorder: border,
    disabledBorder: border,
    focusedBorder: border,
  );
}
