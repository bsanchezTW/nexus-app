import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/splash_providers.dart';

/// Pantalla de arranque: draw-on del mark Transworld en bucle mientras
/// carga bootstrap / sesión / perfil.
///
/// El JSON incluye un exit de preview; el loop se queda en el hold
/// (~2100 / 2500 ms) y vuelve a empezar. La animación **no** bloquea el
/// redirect: [splashReadyProvider] se marca en el primer frame.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key, this.armProfileTimeout = false});

  /// El timeout de perfil solo aplica en la ruta `/splash` del router,
  /// no en el splash de bootstrap (ahí aún no hay sesión que recortar).
  final bool armProfileTimeout;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _asset = 'assets/motion/transworld-logo-draw.json';
  static const _holdProgress = 2100.0 / 2500.0;

  /// Tiempo máximo esperando sesión/perfil después de mostrar el splash.
  static const _navigationTimeout = Duration(seconds: 8);

  late final AnimationController _controller;
  Timer? _navigationTimeoutTimer;
  var _markedReady = false;
  var _looping = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _markReady());
  }

  void _markReady() {
    if (_markedReady || !mounted) return;
    _markedReady = true;
    ref.read(splashReadyProvider.notifier).state = true;
    if (widget.armProfileTimeout) {
      _armNavigationTimeout();
    }
  }

  void _armNavigationTimeout() {
    ref.read(splashNavigationTimedOutProvider.notifier).state = false;
    _navigationTimeoutTimer?.cancel();
    _navigationTimeoutTimer = Timer(_navigationTimeout, () {
      if (!mounted) return;
      ref.read(splashNavigationTimedOutProvider.notifier).state = true;
    });
  }

  void _startLoop(LottieComposition composition) {
    if (!mounted || _looping) return;
    _looping = true;
    _controller
      ..duration = composition.duration
      ..repeat(min: 0, max: _holdProgress);
  }

  @override
  void dispose() {
    _navigationTimeoutTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width * 0.54;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Transform.translate(
          // Nudge óptico ~3.7% del mark box (spec §2).
          offset: Offset(0, width * 0.037),
          child: Lottie.asset(
            _asset,
            controller: _controller,
            width: width,
            height: width,
            fit: BoxFit.contain,
            frameRate: FrameRate.max,
            onLoaded: _startLoop,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
