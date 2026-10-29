import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/supabase_tables.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/supabase/supabase_client_provider.dart';
import '../../auth/providers/auth_providers.dart';
import '../../capturador/providers/capturador_providers.dart';

/// Pausa mínima para que volver a la app cuente como "volver": los diálogos
/// del sistema (permiso de cámara, selector de fotos) también pausan la app
/// y no deben disparar una recarga completa.
const Duration _pausaMinimaParaRecargar = Duration(seconds: 20);

/// Agrupa ráfagas de cambios (p. ej. un evento y su actividad interna creados
/// juntos) en una sola recarga.
const Duration _ventanaCambios = Duration(milliseconds: 800);

/// Mantiene la app alineada con Supabase mientras la conexión es estable.
/// Sube la época de servidor (ver [epocaServidorProvider]) cuando:
///
/// - la app vuelve a primer plano tras una pausa real;
/// - Realtime informa un cambio en eventos, actividades de captura o
///   asignaciones de eventos, venga de este u otro dispositivo.
///
/// Los leads cambian mucho más seguido (cada captura de cada capturador), así
/// que no suben la época global: solo se recargan las listas y conteos de la
/// actividad afectada.
///
/// Realtime solo entrega lo que RLS deja ver al perfil, igual que una
/// consulta normal. Requiere las tablas en la publicación `supabase_realtime`
/// (migración 202610201200); sin ella el canal no recibe nada y quedan los
/// otros disparadores.
///
/// El canal solo vive mientras [usaServidorProvider] es `true`: con la conexión
/// degradada la app opera con su copia local y no tiene sentido mantener un
/// socket que se cae a cada rato. Volver a estable ya recarga todo (ver
/// `orquestadorReconexionProvider`).
///
/// Se lee una vez cerca de la raíz (ver `app.dart`).
final sincronizacionEnVivoProvider = Provider<void>((ref) {
  final client = ref.watch(supabaseClientProvider);
  RealtimeChannel? canal;
  Timer? pendiente;
  DateTime? pausadaDesde;

  void exigirServidor() {
    pendiente?.cancel();
    pendiente = Timer(_ventanaCambios, () {
      if (!ref.read(usaServidorProvider)) return;
      exigirLecturaDelServidor(ref.read(epocaServidorProvider.notifier));
    });
  }

  void leadCambio(PostgresChangePayload payload) {
    final eventoId =
        payload.newRecord['evento_id']?.toString() ??
        payload.oldRecord['evento_id']?.toString();
    if (eventoId == null || eventoId.isEmpty) {
      // DELETE solo trae la clave primaria: no se sabe de qué actividad era.
      ref.invalidate(leadsPorEventoProvider);
      ref.invalidate(leadsResumenRemotoProvider);
      return;
    }
    ref.invalidate(leadsPorEventoProvider(eventoId));
    ref.invalidate(leadsResumenRemotoProvider(eventoId));
  }

  void suscribir() {
    if (canal != null) return;
    var nuevo = client.channel('sincronizacion_en_vivo');
    for (final tabla in const [
      SupabaseTables.eventos,
      SupabaseTables.eventosLeads,
      SupabaseTables.usuariosEventos,
    ]) {
      nuevo = nuevo.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: tabla,
        callback: (_) => exigirServidor(),
      );
    }
    canal = nuevo
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: SupabaseTables.leads,
          callback: leadCambio,
        )
        .subscribe();
  }

  void desuscribir() {
    final actual = canal;
    canal = null;
    if (actual != null) unawaited(client.removeChannel(actual));
  }

  void sincronizarSuscripcion() {
    final session = ref.read(authStateChangesProvider).valueOrNull?.session;
    final perfil = ref.read(currentPerfilProvider).valueOrNull;
    final enLinea = ref.read(usaServidorProvider);
    if (session != null && perfil != null && enLinea) {
      suscribir();
    } else {
      desuscribir();
    }
  }

  ref.listen(authStateChangesProvider, (_, _) => sincronizarSuscripcion());
  ref.listen(currentPerfilProvider, (_, _) => sincronizarSuscripcion());
  ref.listen<bool>(usaServidorProvider, (_, _) => sincronizarSuscripcion());

  final ciclo = AppLifecycleListener(
    onPause: () => pausadaDesde = DateTime.now(),
    onResume: () {
      final desde = pausadaDesde;
      pausadaDesde = null;
      if (desde == null) return;
      if (DateTime.now().difference(desde) < _pausaMinimaParaRecargar) return;
      exigirServidor();
    },
  );

  sincronizarSuscripcion();

  ref.onDispose(() {
    pendiente?.cancel();
    ciclo.dispose();
    desuscribir();
  });
});
