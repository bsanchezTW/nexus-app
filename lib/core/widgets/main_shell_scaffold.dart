import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../features/auth/providers/auth_providers.dart';
import '../theme/app_theme.dart';
import 'app_widgets.dart';
import 'ios_native_tab_bar.dart';
import 'permissions_bootstrap.dart';
import 'shell_tab_scroll.dart';
import 'tw_bottom_nav_bar.dart';

/// Solo Android nativo necesita interceptar el back en la raíz para confirmar
/// el cierre. En Windows el único back admitido es X1 y en web manda el
/// historial del navegador; hacer que el shell los capture provoca un pop
/// rechazado y la animación de rebote.
bool shellConfirmsNativeExit({bool? isWeb, TargetPlatform? platform}) {
  return !(isWeb ?? kIsWeb) &&
      (platform ?? defaultTargetPlatform) == TargetPlatform.android;
}

/// Shell con la navegación del rediseño: `UITabBar` nativo en iOS, barra
/// Material 3 en Android y web móvil, y rail izquierdo en Windows y web de PC.
///
/// En Android, un único [PopScope] en el shell (no por rama) evita que el
/// diálogo de salida deje de aparecer tras cambiar de tab o volver de rutas
/// hijas. Windows y web no pasan por ese interceptor.
class MainShellScaffold extends ConsumerWidget {
  const MainShellScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _branchInicio = 0;
  static const _branchEventos = 1;
  static const _branchCapturador = 2;
  static const _branchUsuarios = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final puedeGestionarUsuarios = ref.watch(canManageUsersProvider);
    final branchActual = navigationShell.currentIndex;

    final tabs = <_TabItem>[
      const _TabItem(
        icon: Symbols.home_rounded,
        label: 'Inicio',
        branch: _branchInicio,
        sfSymbol: 'house',
        sfSymbolActive: 'house.fill',
      ),
      const _TabItem(
        icon: Symbols.calendar_month_rounded,
        label: 'Eventos',
        branch: _branchEventos,
        sfSymbol: 'calendar',
        sfSymbolActive: 'calendar.fill',
      ),
      // SF Symbols de proporción cuadrada a propósito: `UITabBar` mide cada
      // ítem por su icono, así que los símbolos anchos (`person.3`,
      // `person.crop.circle.badge.magnifyingglass`) estiraban su celda y
      // dejaban la fila descompensada.
      const _TabItem(
        icon: Symbols.person_search_rounded,
        label: 'Leads',
        branch: _branchCapturador,
        sfSymbol: 'person.crop.circle',
        sfSymbolActive: 'person.crop.circle.fill',
      ),
      if (puedeGestionarUsuarios)
        const _TabItem(
          icon: Symbols.group_rounded,
          label: 'Usuarios',
          branch: _branchUsuarios,
          sfSymbol: 'person.2',
          sfSymbolActive: 'person.2.fill',
        ),
    ];

    final selectedVisual = tabs.indexWhere((t) => t.branch == branchActual);
    final selectedIndex = selectedVisual < 0 ? 0 : selectedVisual;

    final contenido = ShellNavScope(
      child: PermissionsBootstrap(
        child: MainShellNavHost(
          selectedIndex: selectedIndex,
          onItemSelected: (index) {
            final branch = tabs[index].branch;
            navigationShell.goBranch(branch, initialLocation: true);
            ref.read(shellTabEpochProvider(branch).notifier).state++;
          },
          items: [
            for (final tab in tabs)
              TwNavItemData(
                icon: tab.icon,
                label: tab.label,
                sfSymbol: tab.sfSymbol,
                sfSymbolActive: tab.sfSymbolActive,
              ),
          ],
          body: navigationShell,
        ),
      ),
    );

    if (!shellConfirmsNativeExit()) return contenido;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final salir = await confirmDialog(
          context,
          title: 'Salir de la aplicación',
          message: '¿Deseas cerrar RegisPro?',
          confirmLabel: 'Salir',
        );
        if (salir && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: contenido,
    );
  }
}

/// Coloca el menú abajo (iOS nativo / Android / web móvil) o a la izquierda
/// (Windows y web de PC).
class MainShellNavHost extends StatelessWidget {
  const MainShellNavHost({
    super.key,
    required this.body,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.items,
  });

  final Widget body;
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final List<TwNavItemData> items;

  @override
  Widget build(BuildContext context) {
    if (GlassNavTokens.usesSideRailOf(context)) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Row(
          children: [
            TwSideNavRail(
              selectedIndex: selectedIndex,
              onItemSelected: onItemSelected,
              items: items,
            ),
            Expanded(child: body),
          ],
        ),
      );
    }

    if (GlassNavTokens.usesNativeIosTabBar) {
      return Scaffold(
        body: body,
        extendBody: true,
        bottomNavigationBar: IosNativeTabBar(
          currentIndex: selectedIndex,
          onTap: onItemSelected,
          items: items,
          tint: AppColors.primary,
        ),
      );
    }

    // `extendBody` se mantiene: las pantallas ya reservan el alto de la barra
    // con [GlassNavTokens.contentBottomInset].
    return Scaffold(
      body: body,
      extendBody: true,
      bottomNavigationBar: TwBottomNavBar(
        selectedIndex: selectedIndex,
        onItemSelected: onItemSelected,
        items: items,
      ),
    );
  }
}

class _TabItem {
  const _TabItem({
    required this.icon,
    required this.label,
    required this.branch,
    required this.sfSymbol,
    this.sfSymbolActive,
  });

  final IconData icon;
  final String label;
  final int branch;
  final String sfSymbol;
  final String? sfSymbolActive;
}
