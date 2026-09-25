import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/core/router/external_route_policy.dart';
import 'package:transworld_nexus/core/router/route_paths.dart';

void main() {
  const eventId = 'evento-autorizado';
  const otherEventId = 'evento-ajeno';
  const campaignId = 'campana-leads';
  const authorized = {eventId};

  bool allowed(
    String location, {
    String? sourceEventId,
    bool trustedScannerContext = false,
  }) {
    return isExternalOperationalRouteAllowed(
      location: location,
      authorizedEventIds: authorized,
      captureSourceEventId: sourceEventId,
      hasTrustedScannerContext: trustedScannerContext,
    );
  }

  test('permite solo dashboard y escáner QR de eventos autorizados', () {
    expect(allowed(RoutePaths.externoEvento(eventId)), isTrue);
    expect(allowed(RoutePaths.acreditarQr(eventId)), isTrue);

    expect(allowed(RoutePaths.externoEvento(otherEventId)), isFalse);
    expect(allowed(RoutePaths.acreditarQr(otherEventId)), isFalse);
  });

  test('captura lead exige que el evento de origen sea autorizado', () {
    final location = RoutePaths.capturarLead(campaignId);

    // Desde el escáner, con prefill del padrón.
    expect(
      allowed(location, sourceEventId: eventId, trustedScannerContext: true),
      isTrue,
    );
    // Y desde el CTA del evento, que es captura manual sin escáner: es la
    // operación principal del externo, no un atajo sospechoso.
    expect(allowed(location, sourceEventId: eventId), isTrue);

    // Lo que sigue cerrado es capturar contra un evento ajeno.
    expect(
      allowed(
        location,
        sourceEventId: otherEventId,
        trustedScannerContext: true,
      ),
      isFalse,
    );
    expect(allowed(location, sourceEventId: otherEventId), isFalse);
    expect(
      allowed(location),
      isFalse,
      reason: 'sin evento de origen no hay nada que autorice la captura',
    );
  });

  test('lista, detalle y comentarios de leads exigen el evento de origen', () {
    final lista = RoutePaths.verLeads(campaignId);
    final detalle = RoutePaths.detalleLead(campaignId, 'lead-1');
    final comentarios = RoutePaths.comentariosLead(campaignId, 'lead-1');

    for (final location in [lista, detalle, comentarios]) {
      expect(
        allowed(location, sourceEventId: eventId),
        isTrue,
        reason: location,
      );
      expect(
        allowed(location, sourceEventId: otherEventId),
        isFalse,
        reason: location,
      );
      expect(allowed(location), isFalse, reason: location);
    }
  });

  test('el menú de cuenta del externo está permitido', () {
    // Su ficha y el estado del dispositivo no dependen de ningún evento.
    expect(allowed(RoutePaths.perfil), isTrue);
    expect(allowed(RoutePaths.sincronizacion), isTrue);
    expect(allowed(RoutePaths.actualizaciones), isTrue);
  });

  test('bloquea registro, notificaciones, estadísticas y shell interno', () {
    final forbidden = <String>[
      RoutePaths.registrar(eventId),
      RoutePaths.registroPorCliente(eventId),
      RoutePaths.notificaciones,
      RoutePaths.kpi(eventId),
      RoutePaths.verRegistrados(eventId),
      RoutePaths.eventos,
      RoutePaths.capturador,
      RoutePaths.usuarios,
      RoutePaths.home,
    ];

    for (final location in forbidden) {
      expect(allowed(location), isFalse, reason: 'debe bloquear $location');
    }
  });

  test('con autorizaciones aún desconocidas la política falla cerrada', () {
    expect(
      isExternalOperationalRouteAllowed(
        location: RoutePaths.notificaciones,
        authorizedEventIds: const {},
      ),
      isFalse,
    );
    expect(
      isExternalOperationalRouteAllowed(
        location: RoutePaths.registrar(eventId),
        authorizedEventIds: const {},
      ),
      isFalse,
    );
  });
}
