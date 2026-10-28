import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transworld_nexus/core/constants/supabase_tables.dart';
import 'package:transworld_nexus/core/network/connectivity_service.dart';
import 'package:transworld_nexus/data/models/registrado.dart';
import 'package:transworld_nexus/data/offline/sync_queue_item.dart';
import 'package:transworld_nexus/data/offline/sync_queue_service.dart';
import 'package:transworld_nexus/data/repositories/registrados_repository.dart';
import 'package:transworld_nexus/features/registrados/providers/registrados_providers.dart';

/// Repositorio cuyo `acreditar` responde lo que diga [respuesta].
class _RepoAcreditar extends Fake implements RegistradosRepository {
  _RepoAcreditar(this.respuesta);

  final Future<void> Function() respuesta;

  @override
  Future<void> acreditar(String id, {required String acreditadoPorId}) =>
      respuesta();
}

const _asistente = Registrado(
  id: 'asistente-1',
  eventoId: 'evento-1',
  nombreCompleto: 'Ana Pérez',
  email: 'ana@empresa.com',
);

/// Monta un botón que acredita a [_asistente] con la red "encendida" —la
/// interfaz dice conectado— y devuelve el contenedor para leer la cola.
Future<(ProviderContainer, List<Object>)> _montar(
  WidgetTester tester,
  RegistradosRepository repo,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final errores = <Object>[];

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        isOnlineProvider.overrideWith((ref) => true),
        syncQueueActiveOwnerIdProvider.overrideWithValue('owner-1'),
        registradosRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () async {
              try {
                await persistirAcreditacion(
                  ref,
                  registrado: _asistente,
                  acreditado: true,
                  acreditadoPorId: 'owner-1',
                );
              } catch (e) {
                errores.add(e);
              }
            },
            child: const Text('acreditar'),
          ),
        ),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.text('acreditar')),
  );
  return (container, errores);
}

void main() {
  testWidgets('un fallo de red con interfaz encendida deja la acreditación '
      'en la cola', (tester) async {
    final (container, errores) = await _montar(
      tester,
      _RepoAcreditar(() async => throw const SocketException('sin salida')),
    );

    await tester.tap(find.text('acreditar'));
    await tester.pumpAndSettle();

    expect(errores, isEmpty);
    final cola = container.read(syncQueueServiceProvider);
    expect(cola, hasLength(1));
    expect(cola.single.table, SupabaseTables.registrados);
    expect(cola.single.operation, SyncOperation.update);
    expect(cola.single.payload['changes'], {
      'acreditado': true,
      'acreditado_por': 'owner-1',
    });
  });

  testWidgets('un servidor que no contesta pasa a la cola tras el tope', (
    tester,
  ) async {
    final (container, errores) = await _montar(
      tester,
      _RepoAcreditar(() => Completer<void>().future),
    );

    await tester.tap(find.text('acreditar'));
    await tester.pump();
    expect(container.read(syncQueueServiceProvider), isEmpty);

    await tester.pump(esperaMaximaEscrituraDirecta);
    await tester.pumpAndSettle();

    expect(errores, isEmpty);
    expect(container.read(syncQueueServiceProvider), hasLength(1));
  });

  testWidgets('un rechazo del servidor no se disfraza de pendiente', (
    tester,
  ) async {
    final (container, errores) = await _montar(
      tester,
      _RepoAcreditar(() async => throw StateError('permiso denegado')),
    );

    await tester.tap(find.text('acreditar'));
    await tester.pumpAndSettle();

    expect(errores.single, isA<StateError>());
    expect(container.read(syncQueueServiceProvider), isEmpty);
  });
}
