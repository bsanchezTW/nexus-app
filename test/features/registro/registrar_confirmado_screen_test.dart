import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/core/constants/app_role.dart';
import 'package:transworld_nexus/core/network/connectivity_service.dart';
import 'package:transworld_nexus/core/theme/tw_tokens.dart';
import 'package:transworld_nexus/data/models/ocupacion_evento.dart';
import 'package:transworld_nexus/data/models/evento.dart';
import 'package:transworld_nexus/data/models/perfil.dart';
import 'package:transworld_nexus/features/auth/providers/auth_providers.dart';
import 'package:transworld_nexus/features/eventos/providers/eventos_providers.dart';
import 'package:transworld_nexus/features/registro/screens/registrar_confirmado_screen.dart';
import 'package:transworld_nexus/features/subeventos/providers/subeventos_providers.dart';

void main() {
  testWidgets('el formulario muestra una card de información sobre el QR', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityStreamProvider.overrideWith((ref) => Stream.value(true)),
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
            ),
          ),
          subeventosPorEventoProvider.overrideWith((ref, id) async => const []),
          ocupacionEventoProvider.overrideWith(
            (ref, id) async => const OcupacionEvento(
              evento: OcupacionItem(cupoMaximo: null, inscritos: 0, asistentes: 0),
              subeventos: {},
            ),
          ),
        ],
        child: const MaterialApp(
          home: RegistrarConfirmadoScreen(eventoId: 'evento-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Completa los datos del asistente. Al guardar se enviará el código QR '
        'al correo indicado.',
      ),
      findsOneWidget,
    );

    final fondo = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.color == TwColors.surfaceTint);
    expect(fondo.color, TwColors.surfaceTint);

    final cardTop = tester
        .getRect(
          find.text(
            'Completa los datos del asistente. Al guardar se enviará el código QR '
            'al correo indicado.',
          ),
        )
        .top;
    expect(cardTop, greaterThan(8));
  });

  testWidgets('un evento de Perú preselecciona el prefijo +51', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityStreamProvider.overrideWith((ref) => Stream.value(true)),
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
              nombre: 'Evento Lima',
              fecha: DateTime(2026, 8, 20),
              pais: 'Perú',
            ),
          ),
          subeventosPorEventoProvider.overrideWith((ref, id) async => const []),
          ocupacionEventoProvider.overrideWith(
            (ref, id) async => const OcupacionEvento(
              evento: OcupacionItem(cupoMaximo: null, inscritos: 0, asistentes: 0),
              subeventos: {},
            ),
          ),
        ],
        child: const MaterialApp(
          home: RegistrarConfirmadoScreen(eventoId: 'evento-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+51'), findsOneWidget);
  });
}
