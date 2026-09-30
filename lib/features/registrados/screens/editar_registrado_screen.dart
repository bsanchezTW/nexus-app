import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/constants/supabase_tables.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/network/offline_guard.dart';
import '../../../core/router/refresh_on_visible.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/mascara_contacto.dart';
import '../../../core/utils/registro_asistente.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/campos_registro_asistente.dart';
import '../../../core/theme/tw_tokens.dart';
import '../../../core/widgets/form_sections.dart';
import '../../../core/widgets/nexus_components.dart';
import '../../../data/models/inscripcion_subevento.dart';
import '../../../data/models/registrado.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/offline/sync_queue_service.dart';
import '../../../data/repositories/inscripciones_subevento_repository.dart';
import '../../../data/repositories/registrados_repository.dart';
import '../../auth/providers/auth_providers.dart';
import '../../eventos/providers/eventos_providers.dart';
import '../../subeventos/providers/inscripciones_providers.dart';
import '../../subeventos/providers/subeventos_providers.dart';
import '../../subeventos/widgets/selector_subeventos.dart';
import '../providers/registrados_providers.dart';

class EditarRegistradoScreen extends ConsumerStatefulWidget {
  const EditarRegistradoScreen({
    super.key,
    required this.eventoId,
    required this.registradoId,
  });

  final String eventoId;
  final String registradoId;

  @override
  ConsumerState<EditarRegistradoScreen> createState() =>
      _EditarRegistradoScreenState();
}

class _EditarRegistradoScreenState
    extends ConsumerState<EditarRegistradoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _empresaController = TextEditingController();
  final _cargoController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _rutController = TextEditingController();
  final _patenteController = TextEditingController();
  PaisTelefono _paisTelefono = kPaisTelefonoChile;
  PaisTelefono _paisTelefonoEvento = kPaisTelefonoChile;
  bool _paisTelefonoEventoInicializado = false;
  bool _telefonoTienePaisExplicito = false;
  bool _acreditado = false;
  bool _cargado = false;
  bool _guardando = false;
  final Set<String> _talleresIniciales = {};
  final Set<String> _talleresSeleccionados = {};
  bool _talleresCargados = false;

  String _nombre0 = '';
  String _empresa0 = '';
  String _cargo0 = '';
  String _telefono0 = '';
  String _rut0 = '';
  String _patente0 = '';
  bool _acreditado0 = false;

  /// Teléfono real de la ficha. Los roles que no pueden ver el contacto tienen
  /// el campo en solo lectura con la máscara puesta, así que es este valor —y
  /// no el del controlador— el que se vuelve a guardar.
  String _telefonoGuardado = '';

  /// Un insert todavía en la cola no tiene fila en el servidor: su id es el
  /// temporal que generó [SyncQueueService], no un uuid real.
  bool get _esPendiente => esIdSoloLocal(widget.registradoId);

  @override
  void dispose() {
    _nombreController.dispose();
    _empresaController.dispose();
    _cargoController.dispose();
    _telefonoController.dispose();
    _rutController.dispose();
    _patenteController.dispose();
    super.dispose();
  }

  void _precargar(Registrado r, {required bool puedeVerContacto}) {
    if (_cargado) return;
    _cargado = true;
    _nombreController.text = r.nombreCompleto;
    _empresaController.text = r.empresa ?? '';
    _cargoController.text = r.cargo ?? '';
    _telefonoGuardado = (r.telefono ?? '').trim();
    final paisDetectado = detectarPaisTelefono(_telefonoGuardado);
    if (paisDetectado != null) {
      _paisTelefono = paisDetectado;
      _telefonoTienePaisExplicito = true;
    }
    _sincronizarTelefono(puedeVerContacto);
    _rutController.text = r.rut ?? '';
    _patenteController.text = r.patente ?? '';
    _acreditado = r.acreditado;
    _nombre0 = _nombreController.text;
    _empresa0 = _empresaController.text;
    _cargo0 = _cargoController.text;
    _telefono0 = _telefonoGuardado;
    _rut0 = _rutController.text;
    _patente0 = _patenteController.text;
    _acreditado0 = _acreditado;
  }

  /// Una ficha sin teléfono no tiene nada que ocultar: se deja escribible para
  /// no bloquear el único momento en que se puede completar el dato.
  bool _telefonoProtegido(bool puedeVerContacto) =>
      !puedeVerContacto && _telefonoGuardado.isNotEmpty;

  /// El perfil puede resolverse después de la primera pintada, así que la
  /// máscara se vuelve a aplicar cuando cambia el permiso.
  void _sincronizarTelefono(bool puedeVerContacto) {
    _telefonoController.text = _telefonoProtegido(puedeVerContacto)
        ? enmascararTelefono(_telefonoGuardado)
        : formatearTelefonoNacional(_telefonoGuardado, _paisTelefono);
  }

  void _inicializarPaisTelefonoEvento(
    String? paisEvento, {
    required bool puedeVerContacto,
  }) {
    if (_paisTelefonoEventoInicializado) return;
    _paisTelefonoEvento = paisTelefonoPorPaisEvento(paisEvento);
    _paisTelefonoEventoInicializado = true;
    if (_telefonoTienePaisExplicito) return;
    _paisTelefono = _paisTelefonoEvento;
    if (_cargado && !_telefonoProtegido(puedeVerContacto)) {
      _sincronizarTelefono(puedeVerContacto);
      _telefono0 = _telefonoController.text;
    }
  }

  String _telefonoAGuardar({required bool puedeVerContacto}) {
    return _telefonoProtegido(puedeVerContacto)
        ? _telefonoGuardado
        : telefonoInternacional(_telefonoController.text, _paisTelefono);
  }

  bool get _hayCambios {
    if (!_cargado) return false;
    final puedeVerContacto = ref.read(canViewContactDataProvider);
    return _nombreController.text != _nombre0 ||
        _empresaController.text != _empresa0 ||
        _cargoController.text != _cargo0 ||
        _telefonoAGuardar(puedeVerContacto: puedeVerContacto) != _telefono0 ||
        _rutController.text != _rut0 ||
        _patenteController.text != _patente0 ||
        _acreditado != _acreditado0;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final puedeVerContacto = ref.read(canViewContactDataProvider);
    setState(() => _guardando = true);

    final cache = ref.read(offlineReadCacheProvider);

    final cambios = {
      'nombre_completo': _nombreController.text.trim(),
      'empresa': _empresaController.text.trim(),
      'cargo': _cargoController.text.trim(),
      'telefono': _telefonoAGuardar(puedeVerContacto: puedeVerContacto),
      'rut': _paisTelefono.iso == 'CL'
          ? formatearRut(_rutController.text)
          : _rutController.text.trim(),
      'patente': formatearPatente(_patenteController.text),
      'acreditado': _acreditado,
    };

    if (!requireOnline(context, ref)) {
      setState(() => _guardando = false);
      return;
    }

    try {
      // Una revalidación iniciada antes del UPDATE todavía puede traer la fila
      // antigua. Se deja terminar antes de escribir y parchear la caché.
      await cache.esperarRevalidaciones();
      if (!_esPendiente) {
        await ref
            .read(registradosRepositoryProvider)
            .actualizar(widget.registradoId, cambios);
      } else {
        // La fila solo existe en la cola local: el cambio se fusiona con su
        // insert pendiente, no crea una operación nueva.
        await ref
            .read(syncQueueServiceProvider.notifier)
            .enqueueUpdate(
              table: SupabaseTables.registrados,
              entityId: widget.registradoId,
              changes: cambios,
            );
      }
      final fallos = <String>[];
      final inscripcionesAsync = ref.read(
        inscripcionesPorEventoProvider(widget.eventoId),
      );
      // El build ya observa las inscripciones: solo se tocan talleres con datos.
      final tocarTalleres = _talleresCargados && !inscripcionesAsync.hasError;
      if (tocarTalleres &&
          ref.read(isOnlineProvider) &&
          !esIdSoloLocal(widget.registradoId)) {
        final agregar = _talleresSeleccionados.difference(_talleresIniciales);
        final quitar = _talleresIniciales.difference(_talleresSeleccionados);
        if (agregar.isNotEmpty || quitar.isNotEmpty) {
          final repo = ref.read(inscripcionesSubeventoRepositoryProvider);
          // El build ya observa los talleres.
          final talleres =
              ref.read(subeventosPorEventoProvider(widget.eventoId)).valueOrNull ??
              const [];
          String nombreDe(String id) {
            return talleres
                    .where((taller) => taller.id == id)
                    .map((taller) => taller.nombre)
                    .firstOrNull ??
                'un taller';
          }

          for (final id in agregar) {
            try {
              final resultado = await repo.inscribir(
                registradoId: widget.registradoId,
                subeventoId: id,
              );
              if (resultado['ok'] == false) fallos.add(nombreDe(id));
            } catch (_) {
              fallos.add(nombreDe(id));
            }
          }
          for (final id in quitar) {
            try {
              await repo.quitar(
                registradoId: widget.registradoId,
                subeventoId: id,
              );
            } catch (_) {
              fallos.add(nombreDe(id));
            }
          }
          ref.invalidate(inscripcionesPorEventoProvider(widget.eventoId));
        }
      }
      await publicarCambioEnLecturaCacheada(
        ref,
        tabla: SupabaseTables.registrados,
        eventoId: widget.eventoId,
        id: widget.registradoId,
        cambios: cambios,
        invalidar: () =>
            ref.invalidate(registradosPorEventoProvider(widget.eventoId)),
      );
      if (mounted) {
        showAppSnackBar(
          context,
          fallos.isEmpty
              ? 'Cambios guardados.'
              : 'Cambios guardados. No se actualizaron: ${fallos.join(', ')}.',
          isError: fallos.isNotEmpty,
        );
        volverALista(context, RoutePaths.verRegistrados(widget.eventoId));
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 'No se pudo guardar.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _eliminar() async {
    if (!requireOnline(context, ref)) return;
    final confirmado = await confirmDialog(
      context,
      title: 'Eliminar registrado',
      message: '¿Eliminar este registro? Esta acción no se puede deshacer.',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (!confirmado) return;
    try {
      await ref
          .read(registradosRepositoryProvider)
          .eliminar(widget.registradoId);
      ref.invalidate(registradosPorEventoProvider(widget.eventoId));
      if (mounted) {
        volverALista(context, RoutePaths.verRegistrados(widget.eventoId));
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 'No se pudo eliminar.', isError: true);
      }
    }
  }

  void _volcarTalleres(List<InscripcionSubevento> filas) {
    _talleresCargados = true;
    for (final fila in filas) {
      if (fila.registradoId != widget.registradoId) continue;
      _talleresIniciales.add(fila.subeventoId);
      _talleresSeleccionados.add(fila.subeventoId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final esAdmin = ref.watch(isAdminProvider);
    final hayRed = ref.watch(isOnlineProvider);
    final puedeVerContacto = ref.watch(canViewContactDataProvider);
    final inscripcionesAsync = ref.watch(
      inscripcionesPorEventoProvider(widget.eventoId),
    );
    ref.watch(subeventosPorEventoProvider(widget.eventoId));
    if (inscripcionesAsync.hasValue && !_talleresCargados) {
      _volcarTalleres(inscripcionesAsync.requireValue);
    }
    final evento = ref.watch(eventoByIdProvider(widget.eventoId)).valueOrNull;
    if (evento != null) {
      _inicializarPaisTelefonoEvento(
        evento.pais,
        puedeVerContacto: puedeVerContacto,
      );
    }
    final registradosAsync = ref.watch(
      registradosPorEventoProvider(widget.eventoId),
    );

    ref.listen(canViewContactDataProvider, (anterior, actual) {
      if (!_cargado) return;
      if (_telefonoProtegido(anterior ?? false) == _telefonoProtegido(actual)) {
        return;
      }
      setState(() => _sincronizarTelefono(actual));
    });

    return AppScaffold(
      title: 'Editar registrado',
      onWillPop: () => handleFormExit(
        context: context,
        isCreate: false,
        isDirty: _hayCambios,
        readOnly: !hayRed,
        save: _guardar,
      ),
      actions: [
        // Borrar un insert encolado no lo saca de la cola: reaparecería al
        // sincronizar, así que ni se ofrece.
        if (esAdmin && !_esPendiente)
          NexusHeaderAction(
            icon: Symbols.delete_outline_rounded,
            tooltip: 'Eliminar registrado',
            danger: true,
            onTap: (_guardando || !hayRed) ? null : _eliminar,
          ),
      ],
      bottomBar: registradosAsync.hasValue
          ? FormActionBar(
              label: 'Guardar cambios',
              loading: _guardando,
              onPressed: (_guardando || !hayRed) ? null : _guardar,
            )
          : null,
      body: registradosAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => const ErrorView(message: 'No se pudo cargar.'),
        data: (registrados) {
          final registrado = registrados
              .where((r) => r.id == widget.registradoId)
              .firstOrNull;
          if (registrado == null) {
            return const EmptyStateView(
              icon: Symbols.person_off_rounded,
              message: 'No se encontró este registro.',
            );
          }
          _precargar(registrado, puedeVerContacto: puedeVerContacto);
          final telefonoProtegido = _telefonoProtegido(puedeVerContacto);
          final talleres =
              ref
                  .watch(subeventosPorEventoProvider(widget.eventoId))
                  .valueOrNull ??
              const [];
          final hayTalleres =
              talleres.isNotEmpty || _talleresIniciales.isNotEmpty;

          return AbsorbPointer(
            absorbing: _guardando,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                TwSpacing.screenH,
                2,
                TwSpacing.screenH,
                28,
              ),
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PersonaIdentityBanner(
                      nombre: _nombreController.text,
                      email: puedeVerContacto
                          ? registrado.email
                          : enmascararEmail(registrado.email),
                      nombreController: _nombreController,
                      nombreHint: 'Ej. María González',
                      nombreEnabled: !_guardando && hayRed,
                      nombreValidator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                      badge: StatusChip(
                        label: _acreditado ? 'Acreditado' : 'Pendiente',
                        variant: _acreditado
                            ? StatusChipVariant.success
                            : StatusChipVariant.warning,
                      ),
                    ),
                    const SizedBox(height: FormSection.gap),
                    FormSection(
                      icon: Symbols.business_center_rounded,
                      title: 'Empresa',
                      children: [
                        FormLabeledField(
                          label: 'Empresa',
                          child: TextFormField(
                            controller: _empresaController,
                            enabled: !_guardando && hayRed,
                            decoration: const InputDecoration(
                              hintText: 'Ej. Transworld',
                            ),
                          ),
                        ),
                        FormLabeledField(
                          label: 'Cargo',
                          child: TextFormField(
                            controller: _cargoController,
                            enabled: !_guardando && hayRed,
                            decoration: const InputDecoration(
                              hintText: 'Ej. Gerente comercial',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: FormSection.gap),
                    FormSection(
                      icon: Symbols.contact_phone_rounded,
                      title: 'Contacto',
                      subtitle: telefonoProtegido
                          ? 'Solo visible para administradores y organizadores.'
                          : null,
                      children: [
                        FormLabeledField(
                          label: 'Teléfono',
                          child: telefonoProtegido
                              ? TextFormField(
                                  controller: _telefonoController,
                                  readOnly: true,
                                  keyboardType: TextInputType.phone,
                                  decoration: twReadOnlyDecoration(
                                    hintText: 'Contacto protegido',
                                    suffixIcon: const Icon(
                                      Symbols.lock_rounded,
                                      size: 18,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                )
                              : CampoTelefonoInternacional(
                                  controller: _telefonoController,
                                  pais: _paisTelefono,
                                  onPaisChanged: (pais) =>
                                      setState(() => _paisTelefono = pais),
                                  enabled: !_guardando && hayRed,
                                  labelText: null,
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: FormSection.gap),
                    FormSection(
                      icon: Symbols.workspace_premium_rounded,
                      title: 'Certificación',
                      subtitle: 'Solo si el evento entrega certificado.',
                      children: [
                        FormFieldRow(
                          minWidth: 280,
                          left: FormLabeledField(
                            label: _paisTelefono.iso == 'CL'
                                ? 'RUT'
                                : 'RUT / RUC',
                            opcional: true,
                            child: TextFormField(
                              controller: _rutController,
                              enabled: !_guardando && hayRed,
                              decoration: InputDecoration(
                                hintText: _paisTelefono.iso == 'CL'
                                    ? '12.345.678-5'
                                    : 'Documento',
                              ),
                              validator: (v) => validarRut(
                                v,
                                requerido: false,
                                esChile: _paisTelefono.iso == 'CL',
                              ),
                            ),
                          ),
                          right: FormLabeledField(
                            label: 'Patente',
                            opcional: true,
                            child: TextFormField(
                              controller: _patenteController,
                              enabled: !_guardando && hayRed,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                hintText: 'ABCD12',
                              ),
                              validator: (v) =>
                                  validarPatente(v, requerido: false),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (hayTalleres) ...[
                      const SizedBox(height: FormSection.gap),
                      FormSection(
                        icon: Symbols.co_present_rounded,
                        title: 'Talleres',
                        children: [
                          if (inscripcionesAsync.hasError && !_talleresCargados)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const FormNotice(
                                  'No se pudieron cargar los talleres.',
                                  error: true,
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton(
                                    onPressed: () => ref.invalidate(
                                      inscripcionesPorEventoProvider(
                                        widget.eventoId,
                                      ),
                                    ),
                                    child: const Text('Reintentar'),
                                  ),
                                ),
                              ],
                            )
                          else if (inscripcionesAsync.isLoading &&
                              !_talleresCargados)
                            const SizedBox(height: 88, child: LoadingView())
                          else
                            SelectorSubeventos(
                              subeventos: talleres,
                              ocupacion: ref
                                  .watch(
                                    ocupacionEventoProvider(widget.eventoId),
                                  )
                                  .valueOrNull,
                              seleccionados: _talleresSeleccionados,
                              yaInscritos: _talleresIniciales,
                              permitirSobrecupo: ref.watch(
                                canCreateContentProvider,
                              ),
                              onChanged:
                                  hayRed && !esIdSoloLocal(widget.registradoId)
                                  ? (ids) => setState(() {
                                      _talleresSeleccionados
                                        ..clear()
                                        ..addAll(ids);
                                    })
                                  : (_) {},
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: FormSection.gap),
                    FormSection(
                      icon: Symbols.verified_rounded,
                      title: 'Acreditación',
                      children: [
                        FormToggleRow(
                          icon: Symbols.how_to_reg_rounded,
                          title: 'Acreditado',
                          subtitle: 'Ya ingresó al evento.',
                          value: _acreditado,
                          onChanged: hayRed
                              ? (v) => setState(() => _acreditado = v)
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
