import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme/tw_tokens.dart';

/// Indicador de carga de una imagen: un bloque con un brillo que barre.
///
/// Ocupa todo el espacio del padre, así que en un avatar recortado con
/// `ClipOval` sale circular sin tener que decírselo.
///
/// Todos los esqueletos vivos comparten **un solo** [Ticker]: una lista de
/// doscientos leads con foto no puede levantar doscientos
/// `AnimationController`, y además así el brillo va sincronizado entre
/// tarjetas en vez de parpadear cada una por su lado.
class AppImageSkeleton extends StatelessWidget {
  const AppImageSkeleton({super.key, this.radio});

  /// Redondeo propio. Se omite cuando el padre ya recorta (avatares, portadas).
  final BorderRadius? radio;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _relojShimmer,
      builder: (context, _) {
        // -1 → 2: la banda de brillo entra por la izquierda y sale por la
        // derecha, con una pausa natural entre pasadas.
        final x = -1.0 + 3.0 * _relojShimmer.progreso;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radio,
            gradient: LinearGradient(
              begin: Alignment(x - 1, -0.6),
              end: Alignment(x + 1, 0.6),
              colors: const [_base, _brillo, _base],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }

  static const _base = TwColors.surfaceTint;
  static const _brillo = Color(0xFFF3F6FB);
}

/// Bloque de esqueleto de medida fija (iconos, chips, botones). Sin [radio]
/// sale en píldora.
class AppSkeletonBox extends StatelessWidget {
  const AppSkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radio,
    this.color,
  });

  final double? width;
  final double height;
  final BorderRadius? radio;

  /// Relleno plano en vez del brillo: sobre fondos oscuros (el hero navy)
  /// el brillo claro no funciona.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final r = radio ?? BorderRadius.circular(height / 2);
    return SizedBox(
      width: width,
      height: height,
      child: color == null
          ? AppImageSkeleton(radio: r)
          : DecoratedBox(
              decoration: BoxDecoration(color: color, borderRadius: r),
            ),
    );
  }
}

/// Barra de esqueleto en lugar de un texto. Mide lo mismo que [muestra]
/// pintada con [style] (alto de línea, escala de fuente del teléfono), así
/// que el contenido real no salta al llegar.
class AppSkeletonText extends StatelessWidget {
  const AppSkeletonText({
    super.key,
    required this.muestra,
    required this.style,
    this.width,
    this.color,
  });

  /// Texto representativo: solo da el alto (y el ancho si falta [width]).
  final String muestra;
  final TextStyle style;
  final double? width;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Stack(
        children: [
          Text(
            muestra,
            maxLines: 1,
            softWrap: false,
            style: style.copyWith(color: const Color(0x00000000)),
          ),
          // La barra ocupa ~70 % del alto de línea, como la tinta del texto.
          Positioned.fill(
            child: FractionallySizedBox(
              heightFactor: 0.7,
              child: LayoutBuilder(
                builder: (context, c) =>
                    AppSkeletonBox(height: c.maxHeight, color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _periodo = Duration(milliseconds: 1400);

final _relojShimmer = _RelojShimmer();

/// Reloj compartido por todos los [AppImageSkeleton] montados.
///
/// El [Ticker] solo corre mientras hay al menos un esqueleto escuchando: sin
/// fotos cargando no se pide un solo frame de más.
class _RelojShimmer extends ChangeNotifier {
  _RelojShimmer() {
    _ticker = Ticker(_alLatir);
  }

  late final Ticker _ticker;
  double _progreso = 0;

  /// Posición del brillo dentro del ciclo, de 0 a 1.
  double get progreso => _progreso;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (!_ticker.isActive) _ticker.start();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners && _ticker.isActive) {
      _ticker.stop();
      _progreso = 0;
    }
  }

  void _alLatir(Duration transcurrido) {
    _progreso =
        (transcurrido.inMilliseconds % _periodo.inMilliseconds) /
        _periodo.inMilliseconds;
    notifyListeners();
  }
}
