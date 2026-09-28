import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/router/refresh_on_visible.dart';
import '../scanner_controller.dart';
import '../scanner_geometry.dart';
import '../scanner_models.dart';
import 'scanner_overlay.dart';

/// Vista de escáner: cámara a pantalla completa + overlay.
///
/// El [MobileScanner] no se reconstruye en cada cambio de estado del
/// controlador; solo el overlay escucha [ScannerController].
class ScannerView extends StatelessWidget {
  const ScannerView({
    super.key,
    required this.controller,
    this.onClose,
    this.modoControl,
  });

  final ScannerController controller;
  final VoidCallback? onClose;
  final Widget? modoControl;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final permission = controller.permission;

        if (permission == ScannerPermissionStatus.checking) {
          return const ColoredBox(
            color: Colors.black,
            child: Center(
              child: CupertinoActivityIndicator(
                radius: 14,
                color: Colors.white,
              ),
            ),
          );
        }

        if (permission == ScannerPermissionStatus.denied ||
            permission == ScannerPermissionStatus.unavailable) {
          return ScannerPermissionDeniedView(
            onOpenSettings: controller.openSettings,
            onRetry: controller.retryPermission,
          );
        }

        return _ScannerCameraLayer(
          controller: controller,
          onClose: onClose,
          modoControl: modoControl,
        );
      },
    );
  }
}

/// Capa de cámara estable: el preview no se recrea al togglear flash/modo.
class _ScannerCameraLayer extends StatefulWidget {
  const _ScannerCameraLayer({
    required this.controller,
    this.onClose,
    this.modoControl,
  });

  final ScannerController controller;
  final VoidCallback? onClose;
  final Widget? modoControl;

  @override
  State<_ScannerCameraLayer> createState() => _ScannerCameraLayerState();
}

class _ScannerCameraLayerState extends State<_ScannerCameraLayer> {
  @override
  void initState() {
    super.initState();
    // start() solo es válido con el widget MobileScanner ya montado.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.startAfterAttach();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final previewSize = constraints.biggest;
          final scanWindow = scannerScanWindowFor(previewSize);

          return Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: widget.controller.mobileController,
                scanWindow: scanWindow,
                onDetect: (capture) => widget.controller.handleDetection(
                  capture,
                  previewSize: previewSize,
                  scanWindow: scanWindow,
                  orientation: widget
                      .controller
                      .mobileController
                      .value
                      .deviceOrientation,
                ),
                tapToFocus: !kIsWeb,
                // Lifecycle lo maneja AcreditarQrScreen vía el controller.
                useAppLifecycleState: false,
                errorBuilder: (context, error) {
                  final isPermission =
                      error.errorCode ==
                      MobileScannerErrorCode.permissionDenied;
                  final detail = error.errorDetails?.message?.trim();
                  final message = (detail != null && detail.isNotEmpty)
                      ? detail
                      : error.errorCode.message;
                  return ScannerPermissionDeniedView(
                    message: message,
                    onOpenSettings: widget.controller.openSettings,
                    onRetry: isPermission
                        ? widget.controller.retryPermission
                        : () => widget.controller.startAfterAttach(),
                  );
                },
              ),
              ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  return ScannerOverlay(
                    animateCorners: widget.controller.isAnimatingCorners,
                    torchOn: widget.controller.torchOn,
                    captureLeadMode: widget.controller.captureLeadMode,
                    showTorch: !kIsWeb,
                    feedbackMessage: widget.controller.feedbackMessage,
                    feedbackIsError: widget.controller.feedbackIsError,
                    onClose:
                        widget.onClose ??
                        () {
                          volverAtras(context);
                        },
                    onToggleTorch: widget.controller.toggleTorch,
                    onToggleCaptureLead:
                        widget.controller.toggleCaptureLeadMode,
                    modoControl: widget.modoControl,
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Vista elegante cuando falta acceso a la cámara.
class ScannerPermissionDeniedView extends StatelessWidget {
  const ScannerPermissionDeniedView({
    super.key,
    required this.onOpenSettings,
    required this.onRetry,
    this.message,
  });

  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: CupertinoButton(
                  padding: const EdgeInsets.all(12),
                  minimumSize: Size.zero,
                  onPressed: () {
                    volverAtras(context);
                  },
                  child: const Icon(
                    CupertinoIcons.xmark,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(
                CupertinoIcons.camera,
                color: Colors.white70,
                size: 48,
              ),
              const SizedBox(height: 24),
              const Text(
                'Acceso a la cámara',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message ??
                    'Para escanear códigos QR necesitamos acceso a la cámara. '
                        'Actívalo en Configuración.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 16,
                  height: 1.35,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  borderRadius: BorderRadius.circular(14),
                  onPressed: () async {
                    await onOpenSettings();
                  },
                  child: const Text(
                    'Abrir Configuración',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              CupertinoButton(
                onPressed: () async {
                  await onRetry();
                },
                child: Text(
                  'Reintentar',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
