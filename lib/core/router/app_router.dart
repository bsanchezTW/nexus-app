import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/acreditacion/screens/acreditar_confirmado_screen.dart';
import '../../features/acreditacion/screens/acreditar_qr_screen.dart';
import '../../features/auth/providers/auth_providers.dart';
import '../../features/auth/providers/splash_providers.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/recrear_pass_screen.dart';
import '../../features/auth/screens/recuperar_password_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/capturador/screens/crear_editar_evento_lead_screen.dart';
import '../../features/capturador/screens/crear_lead_screen.dart';
import '../../features/capturador/screens/comentarios_lead_screen.dart';
import '../../features/capturador/screens/exportar_leads_screen.dart';
import '../../features/capturador/screens/lista_leads_screen.dart';
import '../../features/capturador/screens/listar_eventos_leads_screen.dart';
import '../../features/capturador/screens/usar_evento_lead_screen.dart';
import '../../data/models/capturar_lead_route_extra.dart';
import '../../features/eventos/screens/crear_editar_evento_screen.dart';
import '../../features/eventos/screens/gestionar_acceso_evento_screen.dart';
import '../../features/eventos/screens/listar_eventos_screen.dart';
import '../../features/exportacion/screens/exportar_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/kpi/screens/kpi_screen.dart';
import '../../features/notificaciones/screens/notificaciones_screen.dart';
import '../../features/perfil/screens/mi_perfil_screen.dart';
import '../../features/perfil/screens/mis_acreditados_screen.dart';
import '../../features/updates/screens/actualizaciones_screen.dart';
import '../../features/registrados/screens/editar_registrado_screen.dart';
import '../../features/registrados/screens/ver_registrados_screen.dart';
import '../../features/registro/screens/registrar_confirmado_screen.dart';
import '../../features/registro/screens/registro_por_cliente_screen.dart';
import '../../features/sincronizacion/screens/sincronizacion_screen.dart';
import '../../features/externo/screens/evento_finalizado_screen.dart';
import '../../features/externo/screens/usar_evento_externo_screen.dart';
import '../../features/subeventos/screens/subeventos_evento_screen.dart';
import '../../features/usar_app/screens/usar_evento_screen.dart';
import '../../features/usuarios/screens/editar_usuario_screen.dart';
import '../../features/usuarios/screens/gestionar_usuarios_screen.dart';
import '../../features/usuarios/screens/nuevo_usuario_screen.dart';
import '../../data/offline/snapshot_service.dart';
import '../network/connectivity_service.dart';
import 'external_route_policy.dart';
import 'go_router_refresh_stream.dart';
import 'page_transitions.dart';
import 'refresh_on_visible.dart';
import 'route_paths.dart';
import 'session_boot_route.dart';
import 'user_event_route_policy.dart';
import '../widgets/action_lock.dart';
import '../widgets/ios_native_tab_bar.dart';
import '../widgets/main_shell_scaffold.dart';
import '../widgets/sheet_depth_observer.dart';

/// Rutas que no requieren sesión iniciada.
bool _esRutaPublica(String location) {
  return location == RoutePaths.login ||
      location == RoutePaths.recuperarPassword ||
      location == RoutePaths.eventoFinalizado;
}

/// La captura de leads de un externo solo puede nacer del push en memoria que
/// hace el escáner. El query param por sí solo es falsificable y no constituye
/// una prueba de procedencia. En web, recargar esta ruta pierde `extra` y vuelve
/// de forma segura al evento activo.
bool _hasTrustedScannerContext(GoRouterState state) {
  final sourceEventId = state.uri.queryParameters['desdeEvento'];
  final extra = state.extra;
  return sourceEventId != null &&
      sourceEventId.isNotEmpty &&
      extra is CapturarLeadRouteExtra &&
      extra.prefill != null &&
      extra.eventoRegistroId == sourceEventId;
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authClient = Supabase.instance.client.auth;

  final refreshListenable = GoRouterRefreshStream(authClient.onAuthStateChange);
  ref.onDispose(refreshListenable.dispose);
  // El redirect también depende del perfil de negocio (cambiar_pass), que
  // llega de forma asíncrona después del login: re-evaluar al resolverse.
  ref.listen(currentPerfilProvider, (_, _) => refreshListenable.refresh());
  ref.listen(externoEventoProvider, (_, _) => refreshListenable.refresh());
  ref.listen(
    externoEventosAutorizadosProvider,
    (_, _) => refreshListenable.refresh(),
  );
  ref.listen(
    externoEventoActivoOverrideProvider,
    (_, _) => refreshListenable.refresh(),
  );
  ref.listen(
    usuarioEventosAutorizadosProvider,
    (_, _) => refreshListenable.refresh(),
  );
  ref.listen(
    splashNavigationTimedOutProvider,
    (_, _) => refreshListenable.refresh(),
  );
  // Varias decisiones del redirect (cerrar sesión, forzar cambio de clave)
  // ahora dependen de si hay red: al recuperarla hay que re-evaluarlas.
  ref.listen(connectivityStreamProvider, (_, _) => refreshListenable.refresh());
  ref.listen(
    esperandoPrimerSnapshotProvider,
    (_, _) => refreshListenable.refresh(),
  );

  final router = GoRouter(
    initialLocation: authClient.currentSession != null
        ? RoutePaths.splash
        : RoutePaths.login,
    observers: [
      // Avisa al lado nativo cuándo hay una transición en curso: sin esto las
      // vistas Liquid Glass siguen recalculándose durante el slide.
      crearCNTransitionObserver(),
      CNTabBarRouteObserver(),
      SheetDepthObserver(),
      ActionLockObserver(),
    ],
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final location = state.matchedLocation;

      final session = authClient.currentSession;
      final esPublica = _esRutaPublica(location);
      final enSplash = location == RoutePaths.splash;
      final splashTimedOut = ref.read(splashNavigationTimedOutProvider);
      final hayRed = ref.read(isOnlineProvider);

      if (session == null && (!esPublica || enSplash)) {
        return RoutePaths.login;
      }

      final perfilAsync = ref.read(currentPerfilProvider);
      final perfil = perfilAsync.valueOrNull;

      // Sesión viva sin perfil: esperar en splash, nunca en el formulario de
      // login (en web eso flashaba el login y después avanzaba sola al home).
      // Escapes: error de perfil o timeout del splash.
      // No tratar AsyncData(null) inmediato como error: justo tras login
      // currentSession puede ir un frame delante del rebuild del provider.
      if (session != null && perfil == null) {
        final perfilFallido =
            (perfilAsync.hasError && !perfilAsync.isLoading) || splashTimedOut;
        // Sin red la sesión no se cierra jamás: el perfil puede estar en disco
        // o llegar en el próximo intento, y un `signOut()` obliga a un login
        // que offline es imposible. Este era el camino del bug de "abrir sin
        // internet y aparecer en Login".
        if (perfilFallido && hayRed) {
          Future.microtask(() => authClient.signOut());
        }
        return rutaMientrasCargaPerfil(
          location: location,
          esPublica: esPublica,
          perfilFallido: perfilFallido,
        );
      }

      // Primera instalación: sin ninguna copia en disco no hay nada que
      // mostrar, así que el splash retiene hasta que baje el set completo.
      // Solo la primera pasada; después se entra con caché y se refresca por
      // detrás. Cada etapa va acotada por su propio timeout, de modo que la
      // espera siempre termina.
      if (session != null &&
          perfil != null &&
          enSplash &&
          ref.read(esperandoPrimerSnapshotProvider)) {
        return null;
      }

      if (session != null &&
          perfil != null &&
          (location == RoutePaths.login || enSplash)) {
        if (perfil.isExterno) {
          final eventoId = ref.read(externoEventoIdProvider);
          if (eventoId == null || eventoId.isEmpty) {
            return RoutePaths.eventoFinalizado;
          }
          return RoutePaths.externoEvento(eventoId);
        }
        return RoutePaths.home;
      }

      // `activo = false` solo se acata cuando viene confirmado con red: offline
      // el perfil puede ser una copia de disco y no hay forma de volver a
      // entrar si se cierra la sesión por error.
      if (session != null && perfil != null && !perfil.activo && hayRed) {
        authClient.signOut();
        return RoutePaths.login;
      }

      // El cambio obligatorio de contraseña necesita red para completarse: sin
      // ella se opera con la clave vieja en vez de encerrar al usuario en una
      // pantalla que no puede enviar nada.
      if (session != null &&
          perfil != null &&
          perfil.cambiarPass &&
          hayRed &&
          !esPublica &&
          location != RoutePaths.recrearPass) {
        return RoutePaths.recrearPass;
      }

      if (session != null && perfil != null && perfil.isExterno) {
        // El cambio obligatorio es una ruta técnica y debe sobrevivir a la
        // allowlist operativa del externo, incluso si venía desde una ruta
        // pública como `eventoFinalizado`. Sin red se omite: no se puede
        // guardar la clave nueva y el externo quedaría sin poder capturar.
        if (perfil.cambiarPass && hayRed) {
          return location == RoutePaths.recrearPass
              ? null
              : RoutePaths.recrearPass;
        }

        final autorizadosIds = ref.read(externoEventosAutorizadosIdsProvider);
        final preferidoCarga =
            ref.read(externoEventoIdProvider) ?? perfil.eventoAsignadoId;
        final holdExterno = preferidoCarga != null && preferidoCarga.isNotEmpty
            ? RoutePaths.externoEvento(preferidoCarga)
            : RoutePaths.eventoFinalizado;

        // null = lista aún cargando. Se confía temporalmente solo en el evento
        // preferido del perfil; RLS sigue validando que esté autorizado.
        if (autorizadosIds == null) {
          final idsTemporales = preferidoCarga == null || preferidoCarga.isEmpty
              ? const <String>{}
              : {preferidoCarga};
          if (isExternalOperationalRouteAllowed(
            location: location,
            authorizedEventIds: idsTemporales,
            captureSourceEventId: state.uri.queryParameters['desdeEvento'],
            hasTrustedScannerContext: _hasTrustedScannerContext(state),
          )) {
            return null;
          }
          if (idsTemporales.isEmpty &&
              location == RoutePaths.eventoFinalizado) {
            return null;
          }
          return holdExterno;
        }

        final eventoId = ref.read(externoEventoIdProvider);
        if (eventoId == null || eventoId.isEmpty) {
          if (location != RoutePaths.eventoFinalizado) {
            return RoutePaths.eventoFinalizado;
          }
          return null;
        }

        final sinOperables = ref.read(externoSinEventosOperablesProvider);
        if (sinOperables == null) {
          if (isExternalOperationalRouteAllowed(
            location: location,
            authorizedEventIds: {eventoId},
            captureSourceEventId: state.uri.queryParameters['desdeEvento'],
            hasTrustedScannerContext: _hasTrustedScannerContext(state),
          )) {
            return null;
          }
          return RoutePaths.externoEvento(eventoId);
        }
        if (sinOperables) {
          if (location != RoutePaths.eventoFinalizado) {
            return RoutePaths.eventoFinalizado;
          }
          return null;
        }

        // Activo no operable pero hay alternativas → ir al primero operable.
        final primerOperable = ref.read(externoPrimerEventoOperableIdProvider);
        final activoAsync = ref.read(externoEventoProvider);
        final activo = activoAsync.valueOrNull;
        if (primerOperable != null &&
            activo != null &&
            !eventoExternoOperable(activo) &&
            primerOperable != eventoId) {
          return RoutePaths.externoEvento(primerOperable);
        }

        if (location == RoutePaths.eventoFinalizado) {
          return RoutePaths.externoEvento(eventoId);
        }

        final idsPermitidos = autorizadosIds.isEmpty
            ? {eventoId}
            : autorizadosIds;

        if (isExternalOperationalRouteAllowed(
          location: location,
          authorizedEventIds: idsPermitidos,
          captureSourceEventId: state.uri.queryParameters['desdeEvento'],
          hasTrustedScannerContext: _hasTrustedScannerContext(state),
        )) {
          return null;
        }

        // Fail closed: toda ruta no enumerada vuelve al evento activo. Esto
        // cubre registro manual, autoregistro, estadísticas, perfil,
        // notificaciones, shell interno y enlaces profundos desconocidos.
        return RoutePaths.externoEvento(eventoId);
      }

      if (session != null &&
          perfil != null &&
          perfil.usesFullShell &&
          !perfil.canExportData &&
          isDataExportRoute(location)) {
        return location.startsWith('/capturador/')
            ? RoutePaths.capturador
            : RoutePaths.eventos;
      }

      if (session != null && perfil != null && perfil.rol.isUsuario) {
        final autorizados = ref.read(usuarioEventosAutorizadosIdsProvider);
        if (!isUserEventRouteAllowed(
          location: location,
          authorizedEventIds: autorizados,
        )) {
          return RoutePaths.eventos;
        }
      }

      if (session != null &&
          perfil != null &&
          !perfil.canManageUsers &&
          (location == RoutePaths.usuarios ||
              location.startsWith('/usuarios/'))) {
        return RoutePaths.home;
      }

      if (session != null &&
          perfil != null &&
          !perfil.canManageUsers &&
          isEventAccessManagementRoute(location)) {
        return RoutePaths.eventos;
      }

      if (session != null &&
          perfil != null &&
          perfil.usesFullShell &&
          location.startsWith('/externo/')) {
        return RoutePaths.home;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: RoutePaths.splash,
        builder: (context, state) =>
            const SplashScreen(armProfileTimeout: true),
      ),
      GoRoute(
        path: RoutePaths.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: RoutePaths.recuperarPassword,
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: const RecuperarPasswordScreen(),
        ),
      ),
      GoRoute(
        path: RoutePaths.recrearPass,
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: const RecrearPassScreen(),
        ),
      ),
      GoRoute(
        path: RoutePaths.eventoFinalizado,
        builder: (context, state) => const EventoFinalizadoScreen(),
      ),
      GoRoute(
        path: '/externo/eventos/:id',
        builder: (context, state) =>
            UsarEventoExternoScreen(eventoId: state.pathParameters['id']!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShellScaffold(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.eventos,
                builder: (context, state) => const ListarEventosScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.capturador,
                builder: (context, state) => const ListarEventosLeadsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.usuarios,
                builder: (context, state) => const GestionarUsuariosScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: RoutePaths.crearEvento,
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: const CrearEditarEventoScreen(),
        ),
      ),
      GoRoute(
        path: '/eventos/:id/editar',
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: CrearEditarEventoScreen(eventoId: state.pathParameters['id']),
        ),
      ),
      GoRoute(
        path: '/eventos/:id/acceso',
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: GestionarAccesoEventoScreen(
            eventoId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: '/eventos/:id/usar',
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: UsarEventoScreen(eventoId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/eventos/:id/subeventos',
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: SubeventosEventoScreen(eventoId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/eventos/:id/subeventos/crear',
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: CrearEditarSubeventoScreen(
            eventoId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: '/eventos/:id/subeventos/:subeventoId/editar',
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: CrearEditarSubeventoScreen(
            eventoId: state.pathParameters['id']!,
            subeventoId: state.pathParameters['subeventoId'],
          ),
        ),
      ),
      GoRoute(
        path: '/eventos/:id/registrar',
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: RegistrarConfirmadoScreen(
            eventoId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: '/eventos/:id/registro-cliente',
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: RegistroPorClienteScreen(
            eventoId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: '/eventos/:id/acreditar',
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: AcreditarConfirmadoScreen(
            eventoId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: '/eventos/:id/acreditar-qr',
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: AcreditarQrScreen(eventoId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/eventos/:id/registrados',
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: VerRegistradosScreen(eventoId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/eventos/:eventoId/registrados/:registradoId/editar',
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: EditarRegistradoScreen(
            eventoId: state.pathParameters['eventoId']!,
            registradoId: state.pathParameters['registradoId']!,
          ),
        ),
      ),
      GoRoute(
        path: '/eventos/:id/kpi',
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: KpiScreen(eventoId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/eventos/:id/exportar',
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: ExportarScreen(eventoId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: RoutePaths.crearEventoLead,
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: const CrearEditarEventoLeadScreen(),
        ),
      ),
      GoRoute(
        path: '/capturador/:id/editar',
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: CrearEditarEventoLeadScreen(
            eventoId: state.pathParameters['id'],
          ),
        ),
      ),
      GoRoute(
        path: '/capturador/:id/usar',
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: UsarEventoLeadScreen(eventoId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/capturador/:id/capturar',
        pageBuilder: (context, state) {
          final routeExtra = CapturarLeadRouteExtra.from(state.extra);
          final desdeEvento = state.uri.queryParameters['desdeEvento'];
          return sharedAxisPage(
            key: state.pageKey,
            child: CrearLeadScreen(
              eventoId: state.pathParameters['id']!,
              prefill: routeExtra.prefill,
              eventoRegistroId: routeExtra.eventoRegistroId ?? desdeEvento,
            ),
          );
        },
      ),
      GoRoute(
        path: '/capturador/:eventoId/leads/:leadId/comentarios',
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: ComentariosLeadScreen(
            eventoId: state.pathParameters['eventoId']!,
            leadId: state.pathParameters['leadId']!,
            desdeEvento: state.uri.queryParameters['desdeEvento'],
          ),
        ),
      ),
      GoRoute(
        path: '/capturador/:id/leads',
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: ListaLeadsScreen(
            eventoId: state.pathParameters['id']!,
            desdeEvento: state.uri.queryParameters['desdeEvento'],
          ),
        ),
      ),
      GoRoute(
        path: '/capturador/:eventoId/leads/:leadId',
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: DetalleLeadScreen(
            eventoId: state.pathParameters['eventoId']!,
            leadId: state.pathParameters['leadId']!,
            desdeEvento: state.uri.queryParameters['desdeEvento'],
          ),
        ),
      ),
      GoRoute(
        path: '/capturador/:id/exportar',
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: ExportarLeadsScreen(eventoId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: RoutePaths.perfil,
        pageBuilder: (context, state) =>
            sharedAxisPage(key: state.pageKey, child: const MiPerfilScreen()),
      ),
      GoRoute(
        path: RoutePaths.misAcreditados,
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: const MisAcreditadosScreen(),
        ),
      ),
      GoRoute(
        path: RoutePaths.sincronizacion,
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: const SincronizacionScreen(),
        ),
      ),
      GoRoute(
        path: RoutePaths.actualizaciones,
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: const ActualizacionesScreen(),
        ),
      ),
      GoRoute(
        path: RoutePaths.notificaciones,
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: const NotificacionesScreen(),
        ),
      ),
      GoRoute(
        path: RoutePaths.nuevoUsuario,
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: const NuevoUsuarioScreen(),
        ),
      ),
      GoRoute(
        path: '/usuarios/:id/editar',
        pageBuilder: (context, state) => sharedAxisPage(
          key: state.pageKey,
          child: EditarUsuarioScreen(usuarioId: state.pathParameters['id']!),
        ),
      ),
    ],
  );

  // El atrás de la app consume historial del navegador solo por encima de
  // esta marca; ver `sembrarBaseDeHistorial`.
  sembrarBaseDeHistorial(router);
  return router;
});
