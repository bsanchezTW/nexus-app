import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'estado_conexion.dart';
import 'interfaz_red.dart';
import 'politica_conexion.dart';
import 'senal_fallos_red.dart';
import 'sondeo_backend.dart';

/// Única fuente de verdad sobre la comunicación con el backend.
///
/// Junta tres señales y deja que [PoliticaConexion] decida:
///
/// - la interfaz de red, que detecta al instante cuando no hay red;
/// - un sondeo periódico al backend, que mide si responde y cuánto tarda;
/// - los fallos de red de peticiones reales ([reportarFalloDeRed]), que
///   degradan sin esperar al próximo sondeo.
///
/// Mientras nadie llame a [iniciar] no sondea: el estado sale solo de la
/// interfaz. Así un widget que lee la conexión en un test no deja timers ni
/// peticiones vivas; la app real lo inicia desde la raíz
/// ([monitorConexionInitializerProvider]).
class MonitorConexion extends StateNotifier<EstadoConexion> {
  /// [_sondear] pregunta al backend; en la app es `sondearBackend`.
  MonitorConexion(
    this._sondear, {
    bool? hayInterfaz,
    DateTime Function()? reloj,
  }) : _hayInterfaz = hayInterfaz,
       _ahora = reloj ?? DateTime.now,
       super(
         hayInterfaz == false
             ? EstadoConexion.sinInternet
             : EstadoConexion.verificando,
       ) {
    if (state.degradado) _degradadoDesde = _ahora();
  }

  final Future<LecturaSondeo> Function() _sondear;
  final DateTime Function() _ahora;

  bool? _hayInterfaz;
  final List<LecturaSondeo> _historial = [];
  DateTime? _degradadoDesde;

  bool _activo = false;
  bool _sondeando = false;
  Timer? _proximo;

  /// Sube al pausar: un sondeo que vuelve después ya no vale.
  int _generacion = 0;

  /// Empieza a sondear. Idempotente.
  void iniciar() {
    if (_activo) return;
    _activo = true;
    unawaited(_sondearAhora());
  }

  /// Deja de sondear (app en segundo plano: ahorra batería y datos).
  void pausar() {
    _activo = false;
    _generacion++;
    _proximo?.cancel();
  }

  /// Vuelve de segundo plano: confirma el estado de inmediato.
  void reanudar() => iniciar();

  void interfazCambio(bool hayInterfaz) {
    final antes = _hayInterfaz;
    _hayInterfaz = hayInterfaz;
    if (!hayInterfaz) {
      _historial.clear();
      _aplicar(EstadoConexion.sinInternet);
    } else if (antes == false) {
      // Volvió la interfaz: no prueba nada, pero conviene preguntar ya. Sin
      // sondeos activos no hay quien confirme, así que se vuelve a no saber.
      if (_activo) {
        unawaited(_sondearAhora());
      } else {
        _aplicar(EstadoConexion.verificando);
      }
    }
  }

  /// Una petición real no llegó al backend.
  ///
  /// Degrada de inmediato y reinicia la racha de sondeos sanos: volver a
  /// estable tiene que ganarse de nuevo.
  void reportarFallo() {
    _historial.clear();
    if (!state.degradado) {
      _aplicar(EstadoConexion.inestable);
      if (_activo) _programar();
    }
  }

  Future<void> _sondearAhora() async {
    _proximo?.cancel();
    if (_sondeando || !mounted) return;
    if (_hayInterfaz == false) {
      _programar();
      return;
    }

    _sondeando = true;
    final generacion = _generacion;
    final lectura = await _sondear();
    _sondeando = false;
    if (!mounted || generacion != _generacion) return;

    _historial.add(lectura);
    if (_historial.length > PoliticaConexion.ventanaSondeos) {
      _historial.removeAt(0);
    }
    final desde = _degradadoDesde;
    _aplicar(
      PoliticaConexion.siguiente(
        actual: state,
        hayInterfaz: _hayInterfaz ?? true,
        historial: _historial,
        tiempoDegradado: desde == null
            ? Duration.zero
            : _ahora().difference(desde),
      ),
    );
    _programar();
  }

  void _programar() {
    _proximo?.cancel();
    if (!_activo || !mounted) return;
    _proximo = Timer(
      state == EstadoConexion.estable
          ? PoliticaConexion.intervaloEstable
          : PoliticaConexion.intervaloDegradado,
      () => unawaited(_sondearAhora()),
    );
  }

  void _aplicar(EstadoConexion nuevo) {
    if (nuevo == state) return;
    if (nuevo.degradado && !state.degradado) {
      _degradadoDesde = _ahora();
    } else if (!nuevo.degradado) {
      _degradadoDesde = null;
    }
    state = nuevo;
  }

  @override
  void dispose() {
    _proximo?.cancel();
    super.dispose();
  }
}

final monitorConexionProvider =
    StateNotifierProvider<MonitorConexion, EstadoConexion>((ref) {
      final monitor = MonitorConexion(
        sondearBackend,
        hayInterfaz: ref.read(connectivityStreamProvider).valueOrNull,
      );
      ref.listen<AsyncValue<bool>>(connectivityStreamProvider, (_, next) {
        final hay = next.valueOrNull;
        if (hay != null) monitor.interfazCambio(hay);
      });
      final suscripcion = fallosDeRed.listen((_) => monitor.reportarFallo());
      ref.onDispose(suscripcion.cancel);
      return monitor;
    });

/// Estado de la comunicación con el backend. Es lo que deben leer las
/// pantallas y servicios; nunca la interfaz de red a secas.
final estadoConexionProvider = Provider<EstadoConexion>((ref) {
  return ref.watch(monitorConexionProvider);
});

/// Arranca los sondeos y los pausa con la app en segundo plano. Se lee una
/// vez cerca de la raíz (ver `app.dart`).
final monitorConexionInitializerProvider = Provider<void>((ref) {
  final monitor = ref.watch(monitorConexionProvider.notifier);
  monitor.iniciar();
  final ciclo = AppLifecycleListener(
    onPause: monitor.pausar,
    onResume: monitor.reanudar,
  );
  ref.onDispose(ciclo.dispose);
});
