import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/core/constants/app_role.dart';
import 'package:transworld_nexus/core/network/connectivity_service.dart';
import 'package:transworld_nexus/data/models/evento.dart';
import 'package:transworld_nexus/data/models/perfil.dart';
import 'package:transworld_nexus/features/auth/providers/auth_providers.dart';
import 'package:transworld_nexus/features/eventos/providers/eventos_providers.dart';
import 'package:transworld_nexus/features/eventos/screens/crear_editar_evento_screen.dart';

void main() {
  testWidgets('sin red el formulario de edición sigue scrolleable', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 520);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityStreamProvider.overrideWith((ref) => Stream.value(false)),
          isOnlineProvider.overrideWith((ref) => false),
          currentPerfilProvider.overrideWith(
            (ref) async => const Perfil(
              id: 'admin-1',
              nombreCompleto: 'Admin Demo',
              rol: AppRole.admin,
            ),
          ),
          eventoByIdProvider.overrideWith(
            (ref, id) async => Evento(
              id: id,
              nombre: 'Evento de prueba',
              fecha: DateTime(2026, 8, 20),
              pais: 'Chile',
              tematica: 'Capacitación',
              direccion: 'Av. Siempre Viva 742',
              lugar: 'Santiago',
            ),
          ),
        ],
        child: const MaterialApp(
          home: CrearEditarEventoScreen(eventoId: 'evento-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fecha de inicio'), findsOneWidget);
    expect(find.text('Fecha de término'), findsOneWidget);
    expect(find.text('Este evento durará 1 día'), findsOneWidget);

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.pixels, 0);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -140),
    );
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, greaterThan(0));
    expect(find.text('Evento activo'), findsNothing);
    expect(find.text('Requiere certificación'), findsOneWidget);
  });
}
