import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/core/router/route_paths.dart';
import 'package:transworld_nexus/core/router/user_event_route_policy.dart';

void main() {
  const eventId = 'evento-autorizado';
  const otherId = 'evento-ajeno';
  const authorized = {eventId};

  group('isUserEventRouteAllowed', () {
    test('permite listado y rutas ajenas al módulo de eventos', () {
      expect(
        isUserEventRouteAllowed(
          location: RoutePaths.eventos,
          authorizedEventIds: null,
        ),
        isTrue,
      );
      expect(
        isUserEventRouteAllowed(
          location: RoutePaths.capturador,
          authorizedEventIds: null,
        ),
        isTrue,
      );
    });

    test(
      'deniega fail-closed mientras las asignaciones no están resueltas',
      () {
        expect(
          isUserEventRouteAllowed(
            location: RoutePaths.usarEvento(eventId),
            authorizedEventIds: null,
          ),
          isFalse,
        );
      },
    );

    test('permite operaciones conocidas solo del evento autorizado', () {
      final allowed = <String>[
        RoutePaths.usarEvento(eventId),
        RoutePaths.registrar(eventId),
        RoutePaths.registroPorCliente(eventId),
        RoutePaths.acreditarConfirmado(eventId),
        RoutePaths.acreditarQr(eventId),
        RoutePaths.verRegistrados(eventId),
        RoutePaths.editarRegistrado(eventId, 'registrado-1'),
        RoutePaths.kpi(eventId),
      ];

      for (final location in allowed) {
        expect(
          isUserEventRouteAllowed(
            location: location,
            authorizedEventIds: authorized,
          ),
          isTrue,
          reason: location,
        );
      }

      expect(
        isUserEventRouteAllowed(
          location: RoutePaths.usarEvento(otherId),
          authorizedEventIds: authorized,
        ),
        isFalse,
      );
    });

    test(
      'deniega creación, edición, exportación y rutas futuras desconocidas',
      () {
        final denied = <String>[
          RoutePaths.crearEvento,
          RoutePaths.editarEvento(eventId),
          RoutePaths.accesoEvento(eventId),
          RoutePaths.exportar(eventId),
          '/eventos/$eventId/accion-futura',
        ];

        for (final location in denied) {
          expect(
            isUserEventRouteAllowed(
              location: location,
              authorizedEventIds: authorized,
            ),
            isFalse,
            reason: location,
          );
        }
      },
    );
  });

  test('isEventAccessManagementRoute reconoce solo /eventos/:id/acceso', () {
    expect(
      isEventAccessManagementRoute(RoutePaths.accesoEvento(eventId)),
      isTrue,
    );
    expect(
      isEventAccessManagementRoute(RoutePaths.editarEvento(eventId)),
      isFalse,
    );
    expect(isEventAccessManagementRoute(RoutePaths.eventos), isFalse);
    expect(isEventAccessManagementRoute('/eventos/crear/acceso'), isFalse);
  });

  test('isDataExportRoute reconoce solo exportaciones de eventos y leads', () {
    expect(isDataExportRoute(RoutePaths.exportar(eventId)), isTrue);
    expect(isDataExportRoute(RoutePaths.exportarLeads(eventId)), isTrue);
    expect(isDataExportRoute(RoutePaths.usarEvento(eventId)), isFalse);
    expect(isDataExportRoute('/eventos/exportar'), isFalse);
  });
}
