import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent;

import '../theme/app_theme.dart';
import 'app_modals.dart';

/// Bloquea toda la app mientras una operación que cambia datos (crear,
/// editar, eliminar) espera al servidor.
///
/// Antes el modal de confirmación se cerraba al tocar "Eliminar" y la
/// pantalla seguía operable durante los segundos que tardaba la base: se
/// podía tocar otra cosa, volver a eliminar o salir a medias. Mientras
/// [correr] está activo:
///
/// - una barrera invisible en el `Overlay` raíz absorbe todos los toques
///   (también el gesto de volver de iOS, que es un arrastre);
/// - el botón atrás de Android (también el predictivo) no hace nada.
///
/// El feedback visual es del botón que lanzó la operación (spinner en lugar
/// del texto, ver [confirmarYEjecutar] y `FormActionBar.loading`).
abstract final class EsperaBloqueante {
  static int _activas = 0;
  static OverlayEntry? _barrera;
  static OverlayState? _overlay;

  /// Diálogos u hojas abiertos durante la operación (p. ej. "Correo ya
  /// registrado" a mitad de un guardado). Mientras haya alguno la barrera se
  /// retira: si no, quedaría encima del diálogo y la app se congelaría.
  static int _modales = 0;

  static final _BloqueoAtras _bloqueoAtras = _BloqueoAtras();
  static bool _instalado = false;

  /// Hay una operación en curso.
  static bool get activa => _activas > 0;

  /// La app está bloqueada: hay operación y ningún modal esperando respuesta.
  static bool get bloqueando => activa && _modales == 0;

  /// Registra el bloqueo del botón atrás. Llamar en `main`, antes de
  /// `runApp`: los observadores de [WidgetsBinding] reciben el "atrás" en
  /// orden de registro, y este tiene que ir antes que el del router.
  static void instalar() {
    if (_instalado) return;
    _instalado = true;
    WidgetsBinding.instance.addObserver(_bloqueoAtras);
  }

  /// Ejecuta [tarea] con la app bloqueada. Anidable: la barrera se va cuando
  /// termina la última. Puede navegar o abrir modales: la barrera nunca tapa
  /// un diálogo que pide una decisión (ver [conModal]).
  static Future<T> correr<T>(
    BuildContext context,
    Future<T> Function() tarea,
  ) async {
    if (_activas == 0) {
      _overlay = Overlay.of(context, rootOverlay: true);
      _modales = 0;
      _ponerBarrera();
    }
    _activas++;
    try {
      return await tarea();
    } finally {
      _activas--;
      if (_activas == 0) {
        _quitarBarrera();
        _overlay = null;
        _modales = 0;
      }
    }
  }

  /// Abre un diálogo u hoja ([abrir]) sin barrera encima mientras está
  /// visible. Lo usan `showAppDialog` y `showAppModalBottomSheet`, la única
  /// puerta a los modales de la app.
  static Future<T> conModal<T>(Future<T> Function() abrir) async {
    if (!activa) return abrir();
    _modales++;
    _quitarBarrera();
    try {
      return await abrir();
    } finally {
      _modales--;
      if (bloqueando) _ponerBarrera();
    }
  }

  static void _ponerBarrera() {
    final overlay = _overlay;
    if (_barrera != null || overlay == null || !overlay.mounted) return;
    final barrera = OverlayEntry(
      builder: (_) =>
          const ModalBarrier(key: Key('espera_bloqueante'), dismissible: false),
    );
    _barrera = barrera;
    overlay.insert(barrera);
  }

  static void _quitarBarrera() {
    final barrera = _barrera;
    _barrera = null;
    // No se mira `barrera.mounted`: puesta y quitada en el mismo frame (un
    // diálogo que se abre enseguida) todavía no se construyó, pero ya está en
    // el overlay y hay que sacarla igual.
    if (barrera != null && (_overlay?.mounted ?? false)) barrera.remove();
  }
}

/// Atajo de [EsperaBloqueante.correr].
Future<T> conEspera<T>(BuildContext context, Future<T> Function() tarea) =>
    EsperaBloqueante.correr(context, tarea);

class _BloqueoAtras with WidgetsBindingObserver {
  @override
  Future<bool> didPopRoute() async => EsperaBloqueante.bloqueando;

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) =>
      EsperaBloqueante.bloqueando;
}

/// Modal de confirmación que **ejecuta** la acción antes de cerrarse.
///
/// Al tocar [confirmLabel] el texto del botón se reemplaza por un spinner,
/// "Cancelar" se deshabilita y toda la app queda bloqueada
/// ([EsperaBloqueante]) hasta que [accion] termina. Recién entonces se cierra
/// el modal.
///
/// Devuelve `true` si la acción se ejecutó y `false` si se canceló. Si
/// [accion] falla, el modal se cierra y el error se relanza para que quien
/// llama muestre su mensaje. [accion] no debe navegar: la navegación (volver
/// a la lista, etc.) va después, cuando esto devuelve `true`.
Future<bool> confirmarYEjecutar(
  BuildContext context, {
  required String title,
  required String message,
  required Future<void> Function() accion,
  String confirmLabel = 'Confirmar',
  String cancelLabel = 'Cancelar',
  bool destructive = false,
}) async {
  Object? error;
  StackTrace? pila;
  final ejecutado = await showAppDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DialogoConAccion(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      accion: accion,
      alFallar: (e, s) {
        error = e;
        pila = s;
      },
    ),
  );
  final fallo = error;
  if (fallo != null) Error.throwWithStackTrace(fallo, pila!);
  return ejecutado ?? false;
}

class _DialogoConAccion extends StatefulWidget {
  const _DialogoConAccion({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
    required this.accion,
    required this.alFallar,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final Future<void> Function() accion;
  final void Function(Object error, StackTrace pila) alFallar;

  @override
  State<_DialogoConAccion> createState() => _DialogoConAccionState();
}

class _DialogoConAccionState extends State<_DialogoConAccion> {
  bool _ejecutando = false;

  Future<void> _confirmar() async {
    setState(() => _ejecutando = true);
    var ok = true;
    try {
      await EsperaBloqueante.correr(context, widget.accion);
    } catch (e, s) {
      ok = false;
      widget.alFallar(e, s);
    }
    if (mounted) Navigator.of(context).pop(ok);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_ejecutando,
      child: AlertDialog(
        icon: widget.destructive
            ? const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.danger,
                size: 36,
              )
            : null,
        title: Text(
          widget.title,
          textAlign: widget.destructive ? TextAlign.center : null,
        ),
        content: Text(widget.message),
        actions: [
          TextButton(
            onPressed: _ejecutando
                ? null
                : () => Navigator.of(context).pop(false),
            child: Text(widget.cancelLabel),
          ),
          FilledButton(
            key: const Key('confirmar_y_ejecutar'),
            style: widget.destructive
                ? FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    disabledBackgroundColor: AppColors.danger,
                  )
                : null,
            // Deshabilitado mientras corre, pero con su color: el spinner
            // ocupa el lugar del texto.
            onPressed: _ejecutando ? null : _confirmar,
            child: _ejecutando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                      semanticsLabel: 'Procesando',
                    ),
                  )
                : Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }
}
