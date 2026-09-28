import 'dart:developer' as developer;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/supabase_tables.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/network/offline_guard.dart';
import '../../../core/router/refresh_on_visible.dart';
import '../../../core/router/route_paths.dart';
import '../../../data/models/capturar_lead_route_extra.dart';
import '../../../data/models/lead_existente.dart';
import '../../../data/models/lead_prefill.dart';
import '../../../data/models/inscripcion_subevento.dart';
import '../../../data/models/registrado.dart';
import '../../../data/repositories/inscripciones_subevento_repository.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/repositories/leads_repository.dart';
import '../../../data/repositories/registrados_repository.dart';
import '../../auth/providers/auth_providers.dart';
import '../../capturador/lead_comentario_flujo.dart';
import '../../capturador/providers/capturador_providers.dart';
import '../../capturador/services/evento_lead_interno_service.dart';
import '../../eventos/providers/eventos_providers.dart';
import '../../registrados/providers/registrados_providers.dart';
import '../../../core/widgets/app_widgets.dart';
import '../qr_codigo_parser.dart';
import '../decidir_accion_escaneo.dart';
import '../../subeventos/providers/inscripciones_providers.dart';
import '../../subeventos/providers/subeventos_providers.dart';
import '../scanner/qr_scanner_service.dart';
import '../scanner/scanner_controller.dart';
import '../scanner/widgets/scanner_view.dart';

/// Pantalla de dominio: acredita o captura lead tras un QR.
///
/// La UI de cámara vive en [ScannerView]; esta pantalla solo orquesta
/// reglas de negocio sobre el resultado del [ScannerController].
/// Cada detección consulta al servidor (acreditación y lead), aunque el
/// mismo QR se lea varias veces con el escáner todavía abierto.
class AcreditarQrScreen extends ConsumerStatefulWidget {
  const AcreditarQrScreen({super.key, required this.eventoId, this.subeventoId});

  final String eventoId;
  final String? subeventoId;

  @override
  ConsumerState<AcreditarQrScreen> createState() => _AcreditarQrScreenState();
}

class _AcreditarQrScreenState extends ConsumerState<AcreditarQrScreen>
    with WidgetsBindingObserver {
  late final ScannerController _scanner;
  late String? _subeventoId;

  @override
  void initState() {
    super.initState();
    _subeventoId = widget.subeventoId;
    WidgetsBinding.instance.addObserver(this);
    _scanner = ScannerController(onCodeDetected: _onCodeDetected);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scanner.initialize();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanner.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Solo paused/resumed: `inactive` dispara con diálogos de permiso del OS
    // y provoca stop/start concurrentes → CAMERA_ERROR en release.
    switch (state) {
      case AppLifecycleState.resumed:
        // La ruta puede seguir montada bajo otra pantalla (p. ej. capturar lead).
        if (!mounted) return;
        if (ModalRoute.of(context)?.isCurrent != true) return;
        _scanner.resumeCamera();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _scanner.pauseCamera();
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<List<Registrado>> _listaAsistentes() async {
    final async = ref.read(registradosPorEventoProvider(widget.eventoId));
    if (async.hasValue) return async.requireValue;
    if (async.isLoading) {
      try {
        return await ref.read(
          registradosPorEventoProvider(widget.eventoId).future,
        );
      } catch (_) {
        return [];
      }
    }
    return async.valueOrNull ?? [];
  }

  Future<Registrado?> _resolverPorCodigo(String codigo) async {
    final registrados = await _listaAsistentes();
    final enCache = registrados.where((r) => r.codigoQr == codigo).firstOrNull;

    return resolverRegistradoParaAcreditacion(
      hayRed: ref.read(isOnlineProvider),
      enCache: enCache,
      obtenerDelServidor: () => ref
          .read(registradosRepositoryProvider)
          .obtenerPorCodigoQrEnEvento(codigo, widget.eventoId),
      escribirCache: (fresco) async {
        await ref
            .read(offlineReadCacheProvider)
            .parchearFila(
              tabla: SupabaseTables.registrados,
              eventoId: widget.eventoId,
              id: fresco.id,
              cambios: fresco.toCacheMap(),
            );
      },
    );
  }

  Future<void> _acreditar(Registrado registrado) async {
    final userId = ref.read(currentPerfilProvider).valueOrNull?.id.trim();
    if (userId == null || userId.isEmpty) {
      throw Exception(
        'No se pudo identificar al usuario acreditador. Intenta de nuevo.',
      );
    }

    await persistirAcreditacion(
      ref,
      registrado: registrado,
      acreditado: true,
      acreditadoPorId: userId,
    );
  }

  Future<void> _acreditarSiEsNecesarioParaLead(Registrado registrado) async {
    if (registrado.acreditado) return;
    await _acreditar(registrado);
  }

  Future<void> _navegarACaptura(Registrado registrado) async {
    final evento = await ref.read(eventoByIdProvider(widget.eventoId).future);
    final eventoLead = await obtenerOCrearEventoLeadInterno(ref, evento);

    if (!mounted) return;
    await _scanner.pauseCamera();
    if (!mounted) return;
    // `pushYEsperarSalida` y no `context.push`: en web el atrás del navegador
    // no hace pop y el futuro del push nunca resuelve, así que la cámara se
    // quedaba pausada para siempre al volver del formulario.
    await pushYEsperarSalida(
      context,
      RoutePaths.capturarLead(eventoLead.id, desdeEvento: widget.eventoId),
      extra: CapturarLeadRouteExtra(
        prefill: LeadPrefill.fromRegistrado(registrado),
        eventoRegistroId: widget.eventoId,
      ),
    );
    if (!mounted) return;
    await _scanner.resumeCamera();
    _scanner.resumeScanning();
  }

  Future<LeadExistente?> _buscarLeadExistente(
    String eventoLeadId,
    String? email,
  ) async {
    final perfilId = ref.read(currentPerfilProvider).valueOrNull?.id;
    final texto = email?.trim() ?? '';
    return resolverLeadExistenteParaCaptura(
      hayRed: ref.read(isOnlineProvider),
      email: email,
      buscarEnServidor: () => ref
          .read(leadsRepositoryProvider)
          .buscarPorEmail(eventoId: eventoLeadId, email: texto),
      buscarEnCache: () async {
        try {
          final enCache = await ref.read(
            leadsPorEventoProvider(eventoLeadId).future,
          );
          return leadExistenteEnLista(enCache, email, perfilId: perfilId);
        } catch (_) {
          return null;
        }
      },
    );
  }

  Future<void> _procesarAcreditar(Registrado registrado) async {
    if (registrado.acreditado) {
      _scanner.showFeedback(
        '${registrado.nombreCompleto} ya había ingresado.',
        isError: false,
      );
      return;
    }

    await _acreditar(registrado);
    _scanner.showFeedback(
      'Bienvenido/a ${registrado.nombreCompleto}',
      isError: false,
    );
  }

  Future<void> _procesarCapturarLead(Registrado registrado) async {
    await _acreditarSiEsNecesarioParaLead(registrado);
    if (!mounted) return;

    final evento = await ref.read(eventoByIdProvider(widget.eventoId).future);
    final eventoLead = await obtenerOCrearEventoLeadInterno(ref, evento);
    final existente = await _buscarLeadExistente(
      eventoLead.id,
      registrado.email,
    );
    if (!mounted) return;

    if (existente != null) {
      _scanner.holdScanning();
      final comentar = await confirmarAgregarComentarioLead(context);
      if (!mounted) return;
      if (comentar) {
        if (!requireOnline(context, ref)) {
          _scanner.resumeScanning();
          return;
        }
        await _scanner.pauseCamera();
        if (!mounted) return;
        await irAComentariosLead(
          context,
          ref,
          eventoId: eventoLead.id,
          leadId: existente.leadId,
          desdeEvento: widget.eventoId,
        );
        if (!mounted) return;
        await _scanner.resumeCamera();
      }
      _scanner.resumeScanning();
      return;
    }

    await _navegarACaptura(registrado);
  }

  bool _cerrando = false;
  bool _inscripcionesNoCargadas = false;

  Future<List<InscripcionSubevento>> _listaInscripciones() async {
    // El build ya observa las inscripciones; aquí se espera si aún cargan.
    final async = ref.read(inscripcionesPorEventoProvider(widget.eventoId));
    if (async.hasValue) {
      _inscripcionesNoCargadas = false;
      return async.requireValue;
    }
    if (async.isLoading) {
      try {
        final lista = await ref.read(
          inscripcionesPorEventoProvider(widget.eventoId).future,
        );
        _inscripcionesNoCargadas = false;
        return lista;
      } catch (error, stackTrace) {
        _inscripcionesNoCargadas = true;
        developer.log(
          'No se pudieron cargar las inscripciones',
          name: 'AsistenciaSubevento',
          error: error,
          stackTrace: stackTrace,
        );
        return [];
      }
    }
    _inscripcionesNoCargadas = true;
    developer.log(
      'No se pudieron cargar las inscripciones',
      name: 'AsistenciaSubevento',
      error: async.error,
      stackTrace: async.stackTrace,
    );
    return async.valueOrNull ?? [];
  }

  Future<void> _cerrarEscaner() async {
    if (_cerrando) return;
    _cerrando = true;
    // Hay que cortar el MediaStream *antes* de desmontar el <video>;
    // si no, en web el indicador de cámara queda encendido.
    await _scanner.stopCamera();
    if (!mounted) return;
    if (context.canPop()) {
      volverAtras(context);
      return;
    }
    // Fallback si el stack quedó sin historial (p. ej. un go previo).
    final isExterno =
        ref.read(currentPerfilProvider).valueOrNull?.isExterno ?? false;
    context.go(
      isExterno
          ? RoutePaths.externoEvento(widget.eventoId)
          : RoutePaths.usarEvento(widget.eventoId),
    );
  }

  Future<void> _onCodeDetected(QrScanDecode decode) async {
    final registradosAsync = ref.read(
      registradosPorEventoProvider(widget.eventoId),
    );
    final isOnline = ref.read(isOnlineProvider);
    if (!isOnline && registradosAsync.isLoading) {
      _scanner.showFeedback(
        'Espera a que carguen los asistentes (modo offline).',
        isError: true,
      );
      return;
    }

    try {
      if (decode.lectura.tipo == QrLecturaTipo.formatoAntiguo) {
        _scanner.showFeedback(
          'Este QR usa un formato antiguo y ya no sirve.',
          isError: true,
        );
        return;
      }
      if (!decode.isValid || decode.lectura.codigo == null) {
        _scanner.showFeedback('El código no es válido.', isError: true);
        return;
      }

      final registrado = await _resolverPorCodigo(decode.lectura.codigo!);

      if (registrado == null) {
        _scanner.showFeedback(
          'Código no válido o no pertenece a este evento.',
          isError: true,
        );
        return;
      }

      if (_scanner.captureLeadMode) {
        await _procesarCapturarLead(registrado);
      } else if (_subeventoId == null) {
        await _procesarAcreditar(registrado);
      } else {
        await _procesarAsistencia(registrado, _subeventoId!);
      }
    } catch (e) {
      _scanner.showFeedback(
        _scanner.captureLeadMode
            ? e.toString().replaceFirst('Exception: ', '')
            : 'No se pudo acreditar. Intenta de nuevo.',
        isError: true,
      );
    }
  }

  Widget _selectorModo() {
    final talleres =
        ref.watch(subeventosPorEventoProvider(widget.eventoId)).valueOrNull ??
        const [];
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: _subeventoId,
          dropdownColor: Colors.black87,
          style: const TextStyle(color: Colors.white),
          items: [
            const DropdownMenuItem(value: null, child: Text('Entrada')),
            for (final taller in talleres)
              DropdownMenuItem(value: taller.id, child: Text(taller.nombre)),
          ],
          onChanged: (valor) => setState(() => _subeventoId = valor),
        ),
      ),
    );
  }

  Future<void> _procesarAsistencia(Registrado registrado, String subeventoId) async {
    final perfil = ref.read(currentPerfilProvider).valueOrNull;
    final inscripcion = await resolverInscripcionParaEscaneo(
      cargar: _listaInscripciones,
      registradoId: registrado.id,
      subeventoId: subeventoId,
    );
    final accion = decidirAccionEscaneo(
      formatoAntiguo: false,
      invalido: false,
      registrado: registrado,
      inscripcion: inscripcion,
      modoEntrada: false,
      esExterno: perfil?.isExterno ?? false,
      puedeCrear: perfil?.canCreateContent ?? false,
      hayRed: ref.read(isOnlineProvider),
    );
    switch (accion.tipo) {
      case AccionEscaneoTipo.marcarAsistencia:
        await persistirAsistenciaSubevento(
          ref,
          eventoId: widget.eventoId,
          registradoId: registrado.id,
          subeventoId: subeventoId,
          accion: 'marcar_asistencia',
        );
        _scanner.showFeedback('Asistencia marcada.', isError: false);
      case AccionEscaneoTipo.yaMarcado:
        _scanner.showFeedback('Ya tenía asistencia en este taller.', isError: false);
      case AccionEscaneoTipo.soloAviso:
        _scanner.showFeedback(
          'No está inscrito en este taller.',
          isError: true,
        );
      case AccionEscaneoTipo.ofrecerInscribirYMarcar:
        if (_inscripcionesNoCargadas && ref.read(isOnlineProvider)) {
          final resultado = await ref
              .read(inscripcionesSubeventoRepositoryProvider)
              .marcarAsistencia(
                registradoId: registrado.id,
                subeventoId: subeventoId,
              );
          if (!mounted) return;
          if (resultado['ok'] != false) {
            ref.invalidate(inscripcionesPorEventoProvider(widget.eventoId));
            ref.invalidate(registradosPorEventoProvider(widget.eventoId));
            _scanner.showFeedback('Asistencia marcada.', isError: false);
            return;
          }
          if (resultado['motivo']?.toString() != 'no_inscrito') {
            _scanner.showFeedback(
              'No se pudo marcar la asistencia.',
              isError: true,
            );
            return;
          }
        }
        if (!mounted) return;
        final ok = await confirmDialog(
          context,
          title: 'No está inscrito',
          message: accion.puedeForzar
              ? 'Puedes inscribir y marcar, incluso si el cupo está lleno.'
              : 'Puedes inscribir y marcar la asistencia.',
          confirmLabel: 'Inscribir y marcar',
        );
        if (!ok || !mounted) return;
        try {
          await persistirAsistenciaSubevento(
            ref,
            eventoId: widget.eventoId,
            registradoId: registrado.id,
            subeventoId: subeventoId,
            accion: 'inscribir_y_marcar',
            forzar: accion.puedeForzar,
          );
          _scanner.showFeedback('Inscrito y asistencia marcada.', isError: false);
        } on AsistenciaRechazada catch (rechazo) {
          await _resolverRechazoInscripcion(
            rechazo,
            registrado: registrado,
            subeventoId: subeventoId,
            puedeForzar: accion.puedeForzar,
          );
        }
      default:
        _scanner.showFeedback('No se pudo usar este QR.', isError: true);
    }
  }

  Future<void> _resolverRechazoInscripcion(
    AsistenciaRechazada rechazo, {
    required Registrado registrado,
    required String subeventoId,
    required bool puedeForzar,
  }) async {
    if (rechazo.motivo == 'sin_cupo') {
      _scanner.showFeedback('Sin cupo en este taller.', isError: true);
      return;
    }
    if (rechazo.motivo != 'superpuesto') {
      _scanner.showFeedback('No se pudo inscribir en el taller.', isError: true);
      return;
    }

    // El build ya observa los talleres.
    final talleres =
        ref.read(subeventosPorEventoProvider(widget.eventoId)).valueOrNull ??
        const [];
    final nombres = [
      for (final id in rechazo.conflictos)
        talleres
                .where((taller) => taller.id == id)
                .map((taller) => taller.nombre)
                .firstOrNull ??
            'otro taller',
    ];
    final etiqueta = nombres.isEmpty ? 'otro taller' : nombres.join(', ');
    final inscripciones = await _listaInscripciones();
    final yaAsistio = inscripciones.any(
      (fila) =>
          fila.registradoId == registrado.id &&
          rechazo.conflictos.contains(fila.subeventoId) &&
          fila.asistio,
    );
    if (yaAsistio) {
      _scanner.showFeedback(
        'Ya asistió a $etiqueta a la misma hora.',
        isError: true,
      );
      return;
    }

    if (!mounted) return;
    final mover = await confirmDialog(
      context,
      title: 'Taller solapado',
      message: 'Ya está inscrito en $etiqueta a la misma hora.',
      confirmLabel: nombres.length == 1
          ? 'Mover desde ${nombres.first}'
          : 'Mover desde el taller solapado',
    );
    if (!mover || !mounted) return;
    try {
      await persistirAsistenciaSubevento(
        ref,
        eventoId: widget.eventoId,
        registradoId: registrado.id,
        subeventoId: subeventoId,
        accion: 'inscribir_y_marcar',
        forzar: puedeForzar,
        reemplazar: true,
      );
      _scanner.showFeedback('Movido y asistencia marcada.', isError: false);
    } on AsistenciaRechazada {
      _scanner.showFeedback('No se pudo mover desde $etiqueta.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Precarga asistentes, talleres e inscripciones sin reconstruir el preview.
    ref.watch(registradosPorEventoProvider(widget.eventoId));
    ref.watch(subeventosPorEventoProvider(widget.eventoId));
    ref.watch(inscripcionesPorEventoProvider(widget.eventoId));

    return PopScope(
      // El gesto iOS de deslizar atrás exige canPop: el cierre (botón o
      // swipe) corta la cámara en dispose / [_cerrarEscaner].
      canPop: true,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _cerrarEscaner();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: ScannerView(
          controller: _scanner,
          onClose: _cerrarEscaner,
          modoControl: _selectorModo(),
        ),
      ),
    );
  }
}

/// Espera la lista y devuelve la inscripción de esa persona en ese taller.
@visibleForTesting
Future<InscripcionSubevento?> resolverInscripcionParaEscaneo({
  required Future<List<InscripcionSubevento>> Function() cargar,
  required String registradoId,
  required String subeventoId,
}) async {
  final lista = await cargar();
  for (final fila in lista) {
    if (fila.registradoId == registradoId && fila.subeventoId == subeventoId) {
      return fila;
    }
  }
  return null;
}

/// Con red pide esa fila al servidor; sin red (o si el GET falla) usa el padrón
/// local. Así el flag `acreditado` no se decide con una copia stale.
///
/// Cada lectura del mismo QR debe invocar esto de nuevo: no hay memoización.
@visibleForTesting
Future<Registrado?> resolverRegistradoParaAcreditacion({
  required bool hayRed,
  required Registrado? enCache,
  required Future<Registrado?> Function() obtenerDelServidor,
  required Future<void> Function(Registrado fresco) escribirCache,
}) async {
  if (!hayRed) return enCache;
  try {
    final fresco = await obtenerDelServidor();
    if (fresco == null) return enCache;
    await escribirCache(fresco);
    return fresco;
  } catch (_) {
    return enCache;
  }
}

/// Con red pregunta al RPC si ya hay un lead; la caché solo cubre offline o
/// un fallo de red. Un hit local no evita la consulta.
@visibleForTesting
Future<LeadExistente?> resolverLeadExistenteParaCaptura({
  required bool hayRed,
  required String? email,
  required Future<LeadExistente?> Function() buscarEnServidor,
  required Future<LeadExistente?> Function() buscarEnCache,
}) async {
  if (emailLeadNormalizado(email) == null) return null;
  if (!hayRed) return buscarEnCache();
  try {
    return await buscarEnServidor();
  } catch (_) {
    return buscarEnCache();
  }
}
