import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/splash_providers.dart';

/// Lado de la caja del logo en el arranque, en dp.
///
/// Es el mismo tamaño que usan los splash nativos —`splash_logo_inset.xml` y
/// `launch_background.xml` en Android, `LaunchScreen.storyboard` en iOS— para
/// que el logo no salte de tamaño ni de lugar al pasar a Flutter.
const double tamanoLogoInicio = 208;

/// El logo limpio, sin recuadro: las mismas imágenes del Lottie, compuestas
/// y bajadas por el nudge óptico. Es el que muestran los splash nativos.
const _logoInicio = AssetImage('assets/images/splash/logo_inicio.png');

/// Opacidad del logo de base una vez que la animación empieza a dibujar
/// encima: se ve el trazo avanzando sobre una guía tenue.
const double _opacidadLogoDeFondo = 0.14;

bool _primerCuadroRetenido = false;

/// Retiene el primer cuadro de Flutter hasta que el logo del inicio esté
/// decodificado. Sin esto, el splash nativo se va con el primer cuadro y la
/// imagen todavía no está: el logo parpadea justo en el traspaso.
///
/// Se llama en `main` antes de `runApp`. Nunca retiene más de 600 ms: es
/// preferible un cuadro sin logo a una app que tarda en abrir.
void retenerPrimerCuadroHastaElLogo(WidgetsBinding binding) {
  binding.deferFirstFrame();
  _primerCuadroRetenido = true;
  Timer(const Duration(milliseconds: 600), _soltarPrimerCuadro);
}

void _soltarPrimerCuadro() {
  if (!_primerCuadroRetenido) return;
  _primerCuadroRetenido = false;
  WidgetsBinding.instance.allowFirstFrame();
}

/// Pantalla de arranque: draw-on del mark Transworld en bucle mientras
/// carga bootstrap / sesión / perfil.
///
/// El JSON incluye un exit de preview; el loop se queda en el hold
/// (~2100 / 2500 ms) y vuelve a empezar. La animación **no** bloquea el
/// redirect: [splashReadyProvider] se marca en el primer frame.
///
/// El primer cuadro muestra el logo limpio exactamente donde lo dejó el
/// splash nativo. Cuando el Lottie carga, ese logo baja a una guía tenue y la
/// animación lo dibuja encima: sin recuadro ni salto entre una cosa y otra.
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
  var _logoPrecargado = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _markReady());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_logoPrecargado) return;
    _logoPrecargado = true;
    precacheImage(_logoInicio, context).whenComplete(_soltarPrimerCuadro);
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
    setState(() => _looping = true);
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
    const lado = tamanoLogoInicio;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SizedBox.square(
          dimension: lado,
          child: Stack(
            children: [
              // El nudge ya viene en la imagen; por eso no se traslada.
              AnimatedOpacity(
                opacity: _looping ? _opacidadLogoDeFondo : 1,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
                child: const Image(
                  image: _logoInicio,
                  width: lado,
                  height: lado,
                  gaplessPlayback: true,
                ),
              ),
              Transform.translate(
                // Nudge óptico ~3.7% del mark box (spec §2).
                offset: const Offset(0, lado * 0.037),
                child: Lottie.asset(
                  _asset,
                  controller: _controller,
                  width: lado,
                  height: lado,
                  fit: BoxFit.contain,
                  frameRate: FrameRate.max,
                  onLoaded: _startLoop,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
