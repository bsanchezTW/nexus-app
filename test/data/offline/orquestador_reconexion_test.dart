import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/core/conexion/estado_conexion.dart';
import 'package:transworld_nexus/core/conexion/monitor_conexion.dart';
import 'package:transworld_nexus/data/offline/almacen/almacen_copia_local.dart';
import 'package:transworld_nexus/data/offline/offline_read_cache.dart';
import 'package:transworld_nexus/data/offline/orquestador_reconexion.dart';
import 'package:transworld_nexus/data/offline/snapshot_service.dart';
import 'package:transworld_nexus/data/offline/sync_coordinator.dart';
import 'package:transworld_nexus/data/offline/sync_queue_service.dart';

/// Registra el orden en que el orquestador llama a cada paso.
class _Bitacora {
  final pasos = <String>[];
}

class _CoordinadorFalso implements SyncCoordinator {
  _CoordinadorFalso(this._bitacora);

  final _Bitacora _bitacora;

  @override
  Future<int> sincronizarAhora() async {
    _bitacora.pasos.add('cola');
    return 0;
  }
}

class _SnapshotFalso extends SnapshotService {
  _SnapshotFalso(super.ref, this._bitacora);

  final _Bitacora _bitacora;

  @override
  Future<void> respaldar() async => _bitacora.pasos.add('respaldo');
}

final _estado = StateProvider<EstadoConexion>(
  (ref) => EstadoConexion.verificando,
);

/// Cambia el estado y lo resuelve al tiro, para que los listeners vean cada
/// transición por separado.
void _poner(ProviderContainer container, EstadoConexion estado) {
  container.read(_estado.notifier).state = estado;
  container.read(estadoConexionProvider);
}

(ProviderContainer, _Bitacora) _montar({int pendientes = 0}) {
  final bitacora = _Bitacora();
  final container = ProviderContainer(
    overrides: [
      estadoConexionProvider.overrideWith((ref) => ref.watch(_estado)),
      syncCoordinatorProvider.overrideWithValue(_CoordinadorFalso(bitacora)),
      snapshotServiceProvider.overrideWith(
        (ref) => _SnapshotFalso(ref, bitacora),
      ),
      pendingSyncCountProvider.overrideWithValue(pendientes),
      offlineReadCacheProvider.overrideWithValue(
        OfflineReadCache(AlmacenCopiaLocal.enMemoria(), ownerId: 'u'),
      ),
    ],
  );
  container.listen(epocaServidorProvider, (_, _) {
    bitacora.pasos.add('recarga');
  });
  container.read(orquestadorReconexionProvider);
  return (container, bitacora);
}

void main() {
  testWidgets('al abrir la app solo sube la cola', (tester) async {
    final (container, bitacora) = _montar();

    _poner(container, EstadoConexion.estable);
    await tester.pump(const Duration(seconds: 10));

    expect(bitacora.pasos, ['cola']);
    container.dispose();
  });

  testWidgets('al volver de modo degradado: cola, recarga y respaldo', (
    tester,
  ) async {
    final (container, bitacora) = _montar();

    _poner(container, EstadoConexion.inestable);
    await tester.pump();
    _poner(container, EstadoConexion.estable);
    await tester.pump();
    expect(bitacora.pasos, ['cola', 'recarga']);

    await tester.pump(esperaRespaldoTrasRecarga);
    expect(bitacora.pasos, ['cola', 'recarga', 'respaldo']);
    container.dispose();
  });

  testWidgets('si se vuelve a degradar antes del respaldo, no respalda', (
    tester,
  ) async {
    final (container, bitacora) = _montar();

    _poner(container, EstadoConexion.sinInternet);
    await tester.pump();
    _poner(container, EstadoConexion.estable);
    await tester.pump();
    _poner(container, EstadoConexion.inestable);
    await tester.pump(esperaRespaldoTrasRecarga);

    expect(bitacora.pasos, ['cola', 'recarga']);
    container.dispose();
  });

  testWidgets('con la conexión estable reintenta los pendientes', (
    tester,
  ) async {
    final (container, bitacora) = _montar(pendientes: 2);

    _poner(container, EstadoConexion.estable);
    await tester.pump();
    bitacora.pasos.clear();

    await tester.pump(intervaloReintentoPendientes);
    expect(bitacora.pasos, ['cola']);

    _poner(container, EstadoConexion.inestable);
    await tester.pump(intervaloReintentoPendientes);
    expect(bitacora.pasos, ['cola'], reason: 'degradado no reintenta');
    container.dispose();
  });
}
