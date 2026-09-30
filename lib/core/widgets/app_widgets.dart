import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_modals.dart';
import 'tw_toast.dart';

/// Colección pequeña de widgets reutilizables para no repetir boilerplate
/// de estados de carga / error / vacío en cada pantalla.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  /// En las listas del shell el [SliverFillRemaining] llega detrás de la tab
  /// bar: el centro geométrico queda bajo. Mismo lift que [EmptyStateView].
  static const _mobileAlign = Alignment(0, -0.28);

  @override
  Widget build(BuildContext context) {
    final liftForNav =
        ShellNavScope.visibleOf(context) &&
        !GlassNavTokens.usesSideRailOf(context);
    final bottomInset = liftForNav
        ? GlassNavTokens.contentBottomInset(context)
        : 0.0;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Align(
        alignment: liftForNav ? _mobileAlign : Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(message!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: AppColors.danger,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Reintentar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.message,
    this.icon = Icons.inbox_rounded,
    this.action,
    this.onRefresh,
  });

  final String message;
  final IconData icon;
  final Widget? action;
  final VoidCallback? onRefresh;

  /// En Android/iOS el [SliverFillRemaining] llega detrás de la tab bar, así
  /// que el centro geométrico queda bajo. Reservamos ese hueco y subimos un
  /// poco más el aviso hacia el centro visible.
  static const _mobileAlign = Alignment(0, -0.28);

  @override
  Widget build(BuildContext context) {
    final liftForNav =
        onRefresh != null && !GlassNavTokens.usesSideRailOf(context);
    final bottomInset = liftForNav
        ? GlassNavTokens.contentBottomInset(context)
        : 0.0;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Align(
        alignment: liftForNav ? _mobileAlign : Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 48,
                color: AppColors.textSecondary.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (onRefresh != null) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: onRefresh,
                  child: const Text('Actualizar'),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Presente solo bajo [MainShellScaffold], donde la bottom nav está a la vista.
/// Las rutas push (Actualizaciones, Perfil, etc.) no lo heredan.
class ShellNavScope extends InheritedWidget {
  const ShellNavScope({super.key, required super.child});

  static bool visibleOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellNavScope>() != null;

  @override
  bool updateShouldNotify(ShellNavScope oldWidget) => false;
}

/// Aviso breve al usuario. Un solo camino para toda la app: el toast del
/// rediseño ([TwToast]). Antes los errores salían por `SnackBar` y el resto
/// por otro toast, así que el mismo evento se veía distinto según la pantalla.
void showAppSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  final bottomOffset =
      ShellNavScope.visibleOf(context) &&
          !GlassNavTokens.usesSideRailOf(context)
      ? GlassNavTokens.shellToastLift()
      : TwToast.kBottom;

  if (isError) {
    TwToast.error(context, message, bottomOffset: bottomOffset);
  } else {
    TwToast.success(context, message, bottomOffset: bottomOffset);
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirmar',
  String cancelLabel = 'Cancelar',
  bool destructive = false,
  bool? barrierDismissible,
}) async {
  final result = await showAppDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible ?? !destructive,
    builder: (context) => AlertDialog(
      icon: destructive
          ? const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.danger,
              size: 36,
            )
          : null,
      title: Text(title, textAlign: destructive ? TextAlign.center : null),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Resultado del modal de salida con cambios en un formulario de edición.
enum FormExitAction { stay, discard, save }

/// Crear: al ir atrás, ¿descartar lo que se estaba creando?
///
/// Con [hayDatos] en `false` (formulario todavía vacío) no hay nada que
/// perder: se sale sin preguntar.
Future<bool> confirmDiscardCreate(
  BuildContext context, {
  bool hayDatos = true,
}) {
  if (!hayDatos) return Future.value(true);
  return confirmDialog(
    context,
    title: '¿Descartar?',
    message: 'Si sales ahora se perderá lo que estabas creando.',
    confirmLabel: 'Descartar',
  );
}

/// Editar: hay cambios. Seguir, descartar o guardar.
Future<FormExitAction> confirmSaveEdits(BuildContext context) async {
  final result = await showAppDialog<FormExitAction>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('¿Guardar los cambios?'),
      content: const Text('Hay cambios sin guardar.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(FormExitAction.stay),
          child: const Text('Seguir editando'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(FormExitAction.discard),
          child: const Text('Descartar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(FormExitAction.save),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
  return result ?? FormExitAction.stay;
}

/// Intercepta atrás en formularios de crear/editar.
///
/// En edición, [save] debe navegar por su cuenta si el guardado funciona
/// (pop / go a la lista). Este helper entonces devuelve `false` para no
/// hacer un segundo pop.
Future<bool> handleFormExit({
  required BuildContext context,
  required bool isCreate,
  bool isDirty = false,
  bool readOnly = false,
  bool createHasInput = true,
  Future<void> Function()? save,
}) async {
  if (isCreate) {
    return confirmDiscardCreate(context, hayDatos: createHasInput);
  }
  if (readOnly || !isDirty) return true;
  final action = await confirmSaveEdits(context);
  switch (action) {
    case FormExitAction.stay:
      return false;
    case FormExitAction.discard:
      return true;
    case FormExitAction.save:
      await save?.call();
      return false;
  }
}
