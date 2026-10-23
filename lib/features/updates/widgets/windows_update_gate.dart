import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/update_providers.dart';
import '../services/update_platform.dart';
import '../services/update_service.dart';
import 'update_progress_view.dart';

/// En Windows, comprueba GitHub al arrancar y muestra un actualizador a
/// pantalla completa (estilo Discord) antes de entrar a la app.
class WindowsUpdateGate extends ConsumerStatefulWidget {
  const WindowsUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WindowsUpdateGate> createState() => _WindowsUpdateGateState();
}

class _WindowsUpdateGateState extends ConsumerState<WindowsUpdateGate> {
  var _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _started) return;
      _started = true;
      if (!otaResolvesWindowsAsset) return;
      ref.read(updateControllerProvider.notifier).checkOnColdStart();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!otaResolvesWindowsAsset) return widget.child;

    ref.listen<UpdateState>(updateControllerProvider, (prev, next) {
      if (next.status == UpdateStatus.available &&
          prev?.status != UpdateStatus.available) {
        ref.read(updateControllerProvider.notifier).downloadAndInstall();
      }
    });

    final state = ref.watch(updateControllerProvider);
    final blocking =
        state.status == UpdateStatus.checking ||
        state.status == UpdateStatus.available ||
        state.status == UpdateStatus.downloading ||
        state.status == UpdateStatus.verifying ||
        state.status == UpdateStatus.installing ||
        (state.status == UpdateStatus.failed && state.info != null);

    if (!blocking) return widget.child;

    return _WindowsUpdaterScaffold(state: state);
  }
}

class _WindowsUpdaterScaffold extends ConsumerWidget {
  const _WindowsUpdaterScaffold({required this.state});

  final UpdateState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloading = state.status == UpdateStatus.downloading;
    final verifying = state.status == UpdateStatus.verifying;
    final installing = state.status == UpdateStatus.installing;
    final failed = state.status == UpdateStatus.failed;
    final label = verifying
        ? 'Verificando integridad…'
        : installing
        ? 'Aplicando actualización…'
        : downloading
        ? null
        : 'Buscando actualizaciones…';

    // `Material` (y no `ColoredBox`): este scaffold se monta desde
    // `MaterialApp.builder`, fuera del Navigator. Sin un ancestro Material los
    // `Text` heredan el estilo de error de `WidgetsApp` — rojo con doble
    // subrayado amarillo.
    return Material(
      color: AppColors.background,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.tintNavy,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: AppColors.primary,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'RegisPro',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  state.info == null
                      ? 'Comprobando si hay una versión nueva'
                      : 'v${state.info!.installedVersion} → v${state.info!.remoteVersion}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 22),
                if (!failed)
                  UpdateProgressView(
                    progress: verifying || installing ? 1 : state.progress,
                    label: label,
                  ),
                if (failed && state.errorMessage != null) ...[
                  Text(
                    state.errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      ref
                          .read(updateControllerProvider.notifier)
                          .downloadAndInstall();
                    },
                    child: const Text('Reintentar'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      ref.read(updateControllerProvider.notifier).resetToIdle();
                    },
                    child: const Text('Entrar de todos modos'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
