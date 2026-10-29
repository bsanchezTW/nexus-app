import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/conexion/estado_conexion.dart';
import '../../core/conexion/monitor_conexion.dart';
import 'offline_read_cache.dart';
import 'snapshot_service.dart';
import 'sync_coordinator.dart';
import 'sync_queue_service.dart';

/// Cada cuánto se reintentan los pendientes con la conexión estable.
///
/// Un envío puede fallar con la conexión estable (un corte de segundos que el
/// monitor no alcanzó a ver) y, sin esto, se quedaba esperando a que la app
/// volviera a degradarse y recuperarse.
const Duration intervaloReintentoPendientes = Duration(seconds: 60);

/// Qué hace la app cuando la conexión vuelve a ser estable, en orden.
///
/// 1. Sube la cola: lo capturado sin conexión llega primero al servidor.
/// 2. Si venía de modo degradado, pide a todas las lecturas vivas que vuelvan
///    a consultar el servidor, que ya incluye lo recién subido.
/// 3. Poco después, vuelve a bajar la copia local, cuando las pantallas ya
///    recargaron y no compiten con el respaldo por la red.
///
/// Antes estos tres pasos colgaban cada uno de su propio listener de
/// conectividad, con esperas distintas y sin orden garantizado: la bajada
/// podía pisar listas a las que aún les faltaba lo local.
///
/// La primera confirmación al abrir la app (`verificando → estable`) solo sube
/// la cola: las pantallas acaban de cargar del servidor y el respaldo inicial
/// ya lo programa `snapshotAutoStartProvider`.
///
/// Se lee una vez cerca de la raíz (ver `app.dart`).
final orquestadorReconexionProvider = Provider<void>((ref) {
  var vivo = true;
  Timer? respaldo;

  Future<void> alEstabilizarse({required bool veniaDegradado}) async {
    await ref.read(syncCoordinatorProvider).sincronizarAhora();
    if (!vivo || !veniaDegradado) return;
    ref.read(offlineReadCacheProvider).olvidarCopiasServidas();
    exigirLecturaDelServidor(ref.read(epocaServidorProvider.notifier));
    respaldo?.cancel();
    respaldo = Timer(esperaRespaldoTrasRecarga, () {
      if (ref.read(estadoConexionProvider) != EstadoConexion.estable) return;
      unawaited(ref.read(snapshotServiceProvider.notifier).respaldar());
    });
  }

  ref.listen<EstadoConexion>(estadoConexionProvider, (antes, ahora) {
    if (ahora != EstadoConexion.estable || antes == EstadoConexion.estable) {
      return;
    }
    unawaited(alEstabilizarse(veniaDegradado: antes?.degradado ?? false));
  }, fireImmediately: true);

  final reintento = Timer.periodic(intervaloReintentoPendientes, (_) {
    if (ref.read(estadoConexionProvider) != EstadoConexion.estable) return;
    if (ref.read(pendingSyncCountProvider) == 0) return;
    unawaited(ref.read(syncCoordinatorProvider).sincronizarAhora());
  });

  ref.onDispose(() {
    vivo = false;
    respaldo?.cancel();
    reintento.cancel();
  });
});
