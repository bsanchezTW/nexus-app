import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/models/evento.dart';
import 'package:transworld_nexus/features/eventos/providers/eventos_providers.dart';
import 'package:transworld_nexus/features/registro_publico/screens/registro_publico_screen.dart';

void main() {
  testWidgets('un evento fuera de vigencia muestra Evento finalizado', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final ayer = DateTime.now().subtract(const Duration(days: 1));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventoPublicoByIdProvider.overrideWith(
            (ref, id) async => Evento(
              id: id,
              nombre: 'Feria 2024',
              fecha: DateTime(ayer.year, ayer.month, ayer.day),
            ),
          ),
        ],
        child: const MaterialApp(
          home: RegistroPublicoScreen(eventoId: 'evento-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Evento finalizado'), findsOneWidget);
    expect(find.text('Registrarme'), findsNothing);
  });

  testWidgets('un evento vigente muestra el formulario', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventoPublicoByIdProvider.overrideWith(
            (ref, id) async => Evento(
              id: id,
              nombre: 'Feria vigente',
              fecha: DateTime(2099, 8, 20),
            ),
          ),
        ],
        child: const MaterialApp(
          home: RegistroPublicoScreen(eventoId: 'evento-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Feria vigente'), findsOneWidget);
    expect(find.text('Registrarme'), findsOneWidget);
    expect(find.text('Evento finalizado'), findsNothing);
  });
}
