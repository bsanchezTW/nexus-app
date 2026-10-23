import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/core/theme/app_theme.dart';
import 'package:transworld_nexus/core/theme/tw_tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppColors ancla navy y lima del logo Transworld', () {
    expect(AppColors.primary, const Color(0xFF203E6D));
    expect(AppColors.primaryDeep, const Color(0xFF162B4C));
    expect(AppColors.primaryLight, const Color(0xFF2E568F));
    expect(AppColors.accent, const Color(0xFFB1F22A));
    expect(AppColors.accentGlow, const Color(0xFFA0DE2A));
    expect(AppColors.successTint, AppColors.tintLime);
    expect(AppColors.toastCheck, AppColors.accent);
  });

  testWidgets('ThemeData light usa brand colors en ColorScheme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const SizedBox.shrink()),
    );

    final scheme = Theme.of(tester.element(find.byType(SizedBox))).colorScheme;
    expect(scheme.primary, AppColors.primary);
    expect(scheme.tertiary, AppColors.accent);
    expect(scheme.onTertiary, AppColors.primaryDeep);
    expect(scheme.tertiaryContainer, AppColors.tintLime);
  });

  test('usesSideRail en Windows nativo, no en Android ni iOS', () {
    final previous = debugDefaultTargetPlatformOverride;
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(GlassNavTokens.usesSideRail, isFalse);
      expect(GlassNavTokens.usesNativeIosTabBar, isFalse);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(GlassNavTokens.usesSideRail, isFalse);
      expect(GlassNavTokens.usesNativeIosTabBar, isTrue);

      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(GlassNavTokens.usesSideRail, isTrue);
      expect(GlassNavTokens.usesNativeIosTabBar, isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });

  test('la tab bar Liquid Glass de iOS usa iconos compactos', () {
    expect(GlassNavTokens.nativeIosIconSize, 16);
    expect(GlassNavTokens.nativeIosIconSize, lessThan(GlassNavTokens.iconSize));
  });

  test('usesSideRail en web de PC y no en web móvil', () {
    expect(
      GlassNavTokens.usesSideRailFor(
        isWeb: true,
        platform: TargetPlatform.windows,
      ),
      isTrue,
    );
    expect(
      GlassNavTokens.usesSideRailFor(
        isWeb: true,
        platform: TargetPlatform.macOS,
      ),
      isTrue,
    );
    expect(
      GlassNavTokens.usesSideRailFor(
        isWeb: true,
        platform: TargetPlatform.linux,
      ),
      isTrue,
    );
    expect(
      GlassNavTokens.usesSideRailFor(isWeb: true, platform: TargetPlatform.iOS),
      isFalse,
    );
    expect(
      GlassNavTokens.usesSideRailFor(
        isWeb: true,
        platform: TargetPlatform.android,
      ),
      isFalse,
    );
    expect(
      GlassNavTokens.usesSideRailFor(
        isWeb: false,
        platform: TargetPlatform.macOS,
      ),
      isFalse,
    );
    expect(
      GlassNavTokens.usesSideRailFor(
        isWeb: false,
        platform: TargetPlatform.linux,
      ),
      isFalse,
    );
  });

  testWidgets('usesSideRailOf en web solo con viewport de escritorio', (
    tester,
  ) async {
    Future<bool> railFor({required Size size}) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: size),
          child: const SizedBox(),
        ),
      );
      final context = tester.element(find.byType(SizedBox));
      return GlassNavTokens.usesSideRailOf(
        context,
        isWeb: true,
        platform: TargetPlatform.windows,
      );
    }

    expect(await railFor(size: const Size(1280, 720)), isTrue);
    expect(await railFor(size: const Size(840, 600)), isTrue);
    expect(await railFor(size: const Size(839, 600)), isFalse);
    expect(await railFor(size: const Size(390, 844)), isFalse);

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(1280, 720)),
        child: SizedBox(),
      ),
    );
    final wide = tester.element(find.byType(SizedBox));
    expect(
      GlassNavTokens.usesSideRailOf(
        wide,
        isWeb: true,
        platform: TargetPlatform.iOS,
      ),
      isFalse,
    );
  });

  testWidgets('contentBottomInset no reserva la tab bar en Windows', (
    tester,
  ) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(size: Size(1280, 720)),
          child: SizedBox(),
        ),
      );
      final context = tester.element(find.byType(SizedBox));
      expect(GlassNavTokens.contentBottomInset(context), AppSpacing.xl);
      expect(AppSpacing.shellFabBottomOf(context), AppSpacing.sm);
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });

  testWidgets('contentBottomInset reserva la barra inferior en Android', (
    tester,
  ) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(size: Size(390, 844)),
          child: SizedBox(),
        ),
      );
      final context = tester.element(find.byType(SizedBox));
      expect(
        GlassNavTokens.contentBottomInset(context),
        GlassNavTokens.occupiedHeightOf() + AppSpacing.xl,
      );
      expect(
        AppSpacing.shellFabBottomOf(context),
        GlassNavTokens.occupiedHeightOf() + AppSpacing.sm,
      );
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });

  testWidgets('contentBottomInset reserva el UITabBar nativo en iOS', (
    tester,
  ) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            viewPadding: EdgeInsets.only(bottom: 34),
          ),
          child: SizedBox(),
        ),
      );
      final context = tester.element(find.byType(SizedBox));
      // La barra nativa va pegada al borde y ya cubre el home indicator, así
      // que el safe area no se suma otra vez.
      expect(
        GlassNavTokens.contentBottomInset(context),
        GlassNavTokens.nativeIosOccupied + AppSpacing.xl,
      );
      expect(
        AppSpacing.shellFabBottomOf(context),
        GlassNavTokens.nativeIosOccupied + AppSpacing.sm,
      );
      expect(
        GlassNavTokens.shellToastLift(),
        GlassNavTokens.nativeIosHeight + AppSpacing.sm,
      );
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });

  test(
    'campos editables: fondo blanco y marco navy; disabled, el del fondo',
    () {
      final theme = AppTheme.light.inputDecorationTheme;
      final fill = theme.fillColor! as WidgetStateColor;
      expect(fill.resolve(const {}), TwColors.fieldBg);
      expect(fill.resolve(const {WidgetState.disabled}), TwColors.bg);
      expect(TwColors.fieldBg, TwColors.surface);
      expect(
        (theme.enabledBorder! as OutlineInputBorder).borderSide.color,
        TwColors.fieldBorderActive,
      );
      expect(
        (theme.focusedBorder! as OutlineInputBorder).borderSide.width,
        1.5,
      );
      expect(
        (theme.disabledBorder! as OutlineInputBorder).borderSide.color,
        TwColors.fieldBorder,
      );
    },
  );
}
