import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../scanner_geometry.dart';

/// Overlay premium del escáner: blur exterior, esquinas animadas, controles y pill.
///
/// La animación de esquinas vive aquí (Ticker aislado) para no reconstruir
/// el árbol completo ni el preview de cámara a 60 fps.
class ScannerOverlay extends StatefulWidget {
  const ScannerOverlay({
    super.key,
    required this.animateCorners,
    required this.torchOn,
    required this.captureLeadMode,
    required this.onClose,
    required this.onToggleTorch,
    required this.onToggleCaptureLead,
    this.feedbackMessage,
    this.feedbackIsError = false,
    this.showTorch = true,
    this.scanWindowFraction = kScannerScanWindowFraction,
    this.modoControl,
  });

  final bool animateCorners;
  final bool torchOn;
  final bool captureLeadMode;
  final VoidCallback onClose;
  final VoidCallback onToggleTorch;
  final VoidCallback onToggleCaptureLead;
  final String? feedbackMessage;
  final bool feedbackIsError;
  final bool showTorch;
  final double scanWindowFraction;
  final Widget? modoControl;

  @override
  State<ScannerOverlay> createState() => _ScannerOverlayState();
}

class _ScannerOverlayState extends State<ScannerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _inset;

  static const _holeRadius = 18.0;
  static const _cornerMargin = 16.0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _inset = Tween<double>(
      begin: 0,
      end: 10,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    if (widget.animateCorners) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant ScannerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animateCorners && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.animateCorners && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final scanWindow = scannerScanWindowFor(
          size,
          fraction: widget.scanWindowFraction,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            // Blur + tint solo fuera del cuadro (el centro queda nítido).
            ClipPath(
              clipper: _OutsideScanHoleClipper(
                hole: scanWindow,
                radius: _holeRadius,
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.38)),
              ),
            ),
            // Esquinas: solo este painter se repinta con el pulse.
            AnimatedBuilder(
              animation: _inset,
              builder: (context, _) {
                return CustomPaint(
                  painter: _ScannerCornersPainter(
                    scanWindow: scanWindow,
                    cornerInset: widget.animateCorners ? _inset.value : 0,
                  ),
                );
              },
            ),
            Positioned(
              top: topInset + _cornerMargin,
              left: _cornerMargin,
              child: _TopIconButton(
                icon: CupertinoIcons.xmark,
                onPressed: widget.onClose,
              ),
            ),
            if (widget.modoControl != null)
              Positioned(
                top: topInset + 72,
                left: 72,
                right: 72,
                child: widget.modoControl!,
              ),
            if (widget.showTorch)
              Positioned(
                top: topInset + _cornerMargin,
                right: _cornerMargin,
                child: _TopIconButton(
                  icon: widget.torchOn
                      ? CupertinoIcons.bolt_fill
                      : CupertinoIcons.bolt,
                  onPressed: widget.onToggleTorch,
                ),
              ),
            Positioned(
              left: 24,
              right: 24,
              top: scanWindow.bottom + 28,
              child: const Text(
                'Escanea un código QR',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  height: 1.2,
                ),
              ),
            ),
            if (widget.feedbackMessage != null)
              Positioned(
                left: 32,
                right: 32,
                bottom: bottomInset + 128,
                child: _FeedbackBanner(
                  message: widget.feedbackMessage!,
                  isError: widget.feedbackIsError,
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomInset + 56,
              child: Center(
                child: _GlassPillButton(
                  label: 'Capturar Lead',
                  icon: CupertinoIcons.person_badge_plus,
                  active: widget.captureLeadMode,
                  onPressed: widget.onToggleCaptureLead,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Recorta todo excepto el rectángulo redondeado del área de escaneo.
class _OutsideScanHoleClipper extends CustomClipper<Path> {
  _OutsideScanHoleClipper({required this.hole, required this.radius});

  final Rect hole;
  final double radius;

  @override
  Path getClip(Size size) {
    final overlay = Path()..addRect(Offset.zero & size);
    final cutout = Path()
      ..addRRect(RRect.fromRectAndRadius(hole, Radius.circular(radius)));
    return Path.combine(PathOperation.difference, overlay, cutout);
  }

  @override
  bool shouldReclip(covariant _OutsideScanHoleClipper oldClipper) {
    return oldClipper.hole != hole || oldClipper.radius != radius;
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.all(12),
      minimumSize: Size.zero,
      onPressed: onPressed,
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}

class _GlassPillButton extends StatelessWidget {
  const _GlassPillButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              color: active
                  ? Colors.white.withValues(alpha: 0.28)
                  : Colors.white.withValues(alpha: 0.14),
              border: Border.all(
                color: Colors.white.withValues(alpha: active ? 0.55 : 0.28),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(width: 12),
                _MiniToggle(active: active),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Switch compacto dentro del pill (solo visual; el tap lo maneja el padre).
class _MiniToggle extends StatelessWidget {
  const _MiniToggle({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: 40,
      height: 24,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: active ? AppColors.accent : Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: active ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 19,
          height: 19,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: (isError ? AppColors.danger : AppColors.accent).withValues(
                alpha: 0.7,
              ),
            ),
          ),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
    );
  }
}

/// Solo dibuja las cuatro esquinas (el blur/dim va en otra capa).
class _ScannerCornersPainter extends CustomPainter {
  _ScannerCornersPainter({required this.scanWindow, required this.cornerInset});

  final Rect scanWindow;
  final double cornerInset;

  static const _cornerLength = 28.0;
  static const _stroke = 3.5;
  static const _radius = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    // Las esquinas se expanden hacia el blur (fuera del cuadro nítido).
    final hole = scanWindow.inflate(cornerInset);

    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = _stroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final left = hole.left;
    final top = hole.top;
    final right = hole.right;
    final bottom = hole.bottom;
    final r = _radius;
    final len = _cornerLength;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(left, top + r + len)
        ..lineTo(left, top + r)
        ..arcToPoint(Offset(left + r, top), radius: Radius.circular(r))
        ..lineTo(left + r + len, top),
      paint,
    );

    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(right - r - len, top)
        ..lineTo(right - r, top)
        ..arcToPoint(Offset(right, top + r), radius: Radius.circular(r))
        ..lineTo(right, top + r + len),
      paint,
    );

    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(right, bottom - r - len)
        ..lineTo(right, bottom - r)
        ..arcToPoint(Offset(right - r, bottom), radius: Radius.circular(r))
        ..lineTo(right - r - len, bottom),
      paint,
    );

    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(left + r + len, bottom)
        ..lineTo(left + r, bottom)
        ..arcToPoint(Offset(left, bottom - r), radius: Radius.circular(r))
        ..lineTo(left, bottom - r - len),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerCornersPainter oldDelegate) {
    return oldDelegate.scanWindow != scanWindow ||
        oldDelegate.cornerInset != cornerInset;
  }
}
