import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/tw_tokens.dart';

/// Toasts del rediseño (§6). Reemplazan por completo a `SnackBar` en las
/// pantallas rediseñadas: se montan en el `Overlay` raíz, así que sobreviven a
/// cambios de pantalla y nunca empujan el layout.
///
/// Un solo toast a la vez: el nuevo reemplaza al anterior. Aparece arriba,
/// bajo la barra de estado: cae con un leve rebote, sale subiendo y se puede
/// descartar deslizándolo hacia arriba. Arriba no compite con la barra
/// inferior ni con los botones de los formularios.
enum TwToastKind { info, success, error, progress, link }

class _TwToastData {
  const _TwToastData(this.message, this.kind, this.seq);

  final String message;
  final TwToastKind kind;
  final int seq;
}

class TwToast {
  TwToast._();

  static final ValueNotifier<_TwToastData?> _data = ValueNotifier(null);
  static OverlayEntry? _entry;
  static Timer? _timer;
  static int _seq = 0;

  static void show(
    BuildContext context,
    String message, {
    TwToastKind kind = TwToastKind.info,
    Duration duration = const Duration(milliseconds: 2600),
  }) {
    _timer?.cancel();
    _mount(context);
    _data.value = _TwToastData(sinPuntoFinal(message), kind, ++_seq);
    if (kind != TwToastKind.progress) {
      _timer = Timer(duration, hide);
    }
  }

  /// Los toasts no llevan punto final (se ven mejor sin él), tampoco los
  /// mensajes que llegan del servidor. Los puntos suspensivos se mantienen.
  @visibleForTesting
  static String sinPuntoFinal(String message) {
    final texto = message.trimRight();
    if (texto.endsWith('.') && !texto.endsWith('..')) {
      return texto.substring(0, texto.length - 1);
    }
    return texto;
  }

  static void info(BuildContext c, String m) =>
      show(c, m, kind: TwToastKind.info);

  static void success(BuildContext c, String m) =>
      show(c, m, kind: TwToastKind.success);

  static void error(BuildContext c, String m) => show(
    c,
    m,
    kind: TwToastKind.error,
    duration: const Duration(milliseconds: 3200),
  );

  static void link(BuildContext c, String m) =>
      show(c, m, kind: TwToastKind.link);

  /// No se auto-oculta: ciérralo con [hide] o reemplázalo por otro toast.
  static void progress(BuildContext c, String m) =>
      show(c, m, kind: TwToastKind.progress);

  static void hide() {
    _timer?.cancel();
    _timer = null;
    _data.value = null;
  }

  /// El overlay que hospedaba el toast se fue (cambio de árbol, cierre de la
  /// app, fin de un test). Sin esto el temporizador de auto-cierre quedaba
  /// vivo apuntando a una entrada muerta.
  static void _onLayerDisposed() {
    _timer?.cancel();
    _timer = null;
    _entry = null;
  }

  static void _mount(BuildContext context) {
    // `mounted` en false = la entrada quedó huérfana de un árbol anterior.
    if (_entry != null && _entry!.mounted) return;
    _entry = null;
    _data.value = null;

    final entry = OverlayEntry(
      builder: (_) => ValueListenableBuilder<_TwToastData?>(
        valueListenable: _data,
        builder: (ctx, data, _) => _TwToastLayer(data: data),
      ),
    );
    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }
}

class _TwToastLayer extends StatefulWidget {
  const _TwToastLayer({required this.data});

  final _TwToastData? data;

  @override
  State<_TwToastLayer> createState() => _TwToastLayerState();
}

class _TwToastLayerState extends State<_TwToastLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  _TwToastData? _shown;

  /// Desplazamiento del dedo al descartar deslizando hacia arriba.
  double _arrastre = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _fade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0, 0.45, curve: Curves.easeOut),
      reverseCurve: Curves.easeIn,
    );
    // Cae desde arriba con un leve rebote y sale subiendo.
    _slide = Tween<Offset>(begin: const Offset(0, -1.4), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _ctrl,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeInCubic,
          ),
        );
    _ctrl.addStatusListener((status) {
      if (!mounted) return;
      if (status == AnimationStatus.dismissed && widget.data == null) {
        setState(() {
          _shown = null;
          _arrastre = 0;
        });
      }
    });
    _sync(widget.data, fromInit: true);
  }

  @override
  void didUpdateWidget(covariant _TwToastLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) {
      _sync(widget.data);
    }
  }

  void _sync(_TwToastData? data, {bool fromInit = false}) {
    if (data != null) {
      _shown = data;
      _arrastre = 0;
      _ctrl.forward(from: 0);
      if (!fromInit) setState(() {});
      return;
    }
    if (_shown != null) {
      _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    TwToast._onLayerDisposed();
    super.dispose();
  }

  void _arrastrar(DragUpdateDetails details) {
    // Solo hacia arriba; hacia abajo se resiste.
    setState(() => _arrastre = (_arrastre + details.delta.dy).clamp(-200, 8));
  }

  void _soltar(DragEndDetails details) {
    final velocidad = details.primaryVelocity ?? 0;
    if (_arrastre < -24 || velocidad < -300) {
      TwToast.hide();
      return;
    }
    setState(() => _arrastre = 0);
  }

  @override
  Widget build(BuildContext context) {
    final data = _shown;
    final top = MediaQuery.paddingOf(context).top + 10;

    return Positioned(
      left: 16,
      right: 16,
      top: top,
      child: data == null
          ? const SizedBox.shrink()
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: _arrastrar,
                  onVerticalDragEnd: _soltar,
                  child: Transform.translate(
                    offset: Offset(0, _arrastre),
                    child: FadeTransition(
                      key: const Key('tw-toast-fade'),
                      opacity: _fade,
                      child: SlideTransition(
                        key: const Key('tw-toast-slide'),
                        position: _slide,
                        child: _TwToastCard(
                          key: ValueKey(data.seq),
                          data: data,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _TwToastCard extends StatelessWidget {
  const _TwToastCard({super.key, required this.data});

  final _TwToastData data;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 15),
        decoration: const BoxDecoration(
          color: TwColors.toastBg,
          borderRadius: TwRadii.toast,
          boxShadow: TwShadows.toast,
        ),
        child: Row(
          children: [
            _leading(data.kind),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                data.message,
                style: TwText.toastText,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _leading(TwToastKind kind) {
    if (kind == TwToastKind.progress) {
      return const SizedBox(
        width: 17,
        height: 17,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: TwColors.toastInfo,
          backgroundColor: Color(0x4DFFFFFF),
        ),
      );
    }

    final (icon, color) = switch (kind) {
      TwToastKind.success => (
        Symbols.check_circle_rounded,
        TwColors.toastSuccess,
      ),
      TwToastKind.error => (Symbols.error_rounded, TwColors.toastError),
      TwToastKind.link => (Symbols.link_rounded, TwColors.toastSuccess),
      TwToastKind.info ||
      TwToastKind.progress => (Symbols.info_rounded, TwColors.toastInfo),
    };
    return Icon(icon, size: 19, color: color, fill: 1);
  }
}
