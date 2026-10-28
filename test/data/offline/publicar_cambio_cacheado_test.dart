import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/offline/almacen/almacen_copia_local.dart';
import 'package:transworld_nexus/data/offline/offline_read_cache.dart';

void main() {
  for (final caso in <({String tabla, String nombre})>[
    (tabla: 'leads__all', nombre: 'lead'),
    (tabla: 'registrados', nombre: 'registrado'),
  ]) {
    testWidgets(
      'publica el cambio del ${caso.nombre} antes de revalidar la lista',
      (tester) async {
        final cache = OfflineReadCache(
          AlmacenCopiaLocal.enMemoria(),
          ownerId: 'usuario-1',
        );
        const eventoId = 'evento-1';
        const filaId = 'persona-1';
        await cache.guardar(caso.tabla, eventoId, const [
          {'id': filaId, 'nombre_completo': 'Nombre anterior'},
        ]);

        var invalidaciones = 0;
        final container = ProviderContainer(
          overrides: [offlineReadCacheProvider.overrideWithValue(cache)],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) => ElevatedButton(
                    onPressed: () async {
                      await publicarCambioEnLecturaCacheada(
                        ref,
                        tabla: caso.tabla,
                        eventoId: eventoId,
                        id: filaId,
                        cambios: const {
                          'nombre_completo': 'Nombre actualizado',
                        },
                        invalidar: () => invalidaciones++,
                      );
                    },
                    child: const Text('Guardar'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();

        final local = cache.leerLocal(
          tabla: caso.tabla,
          eventoId: eventoId,
          desdeFila: (fila) => fila,
        );
        expect(local?.single['nombre_completo'], 'Nombre actualizado');
        expect(invalidaciones, 1);
        expect(
          container.read(cacheRevisionProvider('${caso.tabla}:$eventoId')),
          1,
        );
      },
    );
  }
}
