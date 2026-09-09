import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/router/refresh_on_visible.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/network/offline_guard.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/constants/duracion_actividad.dart';
import '../../../core/constants/paises_evento.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/campo_pais_evento.dart';
import '../../../core/widgets/campos_fecha_inicio_termino.dart';
import '../../../core/widgets/nexus_components.dart';
import '../../../core/widgets/require_permission.dart';
import '../../../core/widgets/selector_imagen.dart';
import '../../../data/models/evento_lead.dart';
import '../../../data/repositories/eventos_leads_repository.dart';
import '../../../data/repositories/storage_cleanup_service.dart';
import '../../../data/repositories/storage_repository.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/capturador_providers.dart';

class CrearEditarEventoLeadScreen extends StatelessWidget {
  const CrearEditarEventoLeadScreen({super.key, this.eventoId});

  final String? eventoId;

  @override
  Widget build(BuildContext context) {
    return RequirePermission(
      allowed: (p) => p.canCreateContent,
      deniedMessage:
          'Solo administradores y organizadores pueden crear o editar '
          'actividades de captura.',
      builder: (context) => _CrearEditarEventoLeadForm(eventoId: eventoId),
    );
  }
}

class _CrearEditarEventoLeadForm extends ConsumerStatefulWidget {
  const _CrearEditarEventoLeadForm({this.eventoId});

  final String? eventoId;

  @override
  ConsumerState<_CrearEditarEventoLeadForm> createState() =>
      _CrearEditarEventoLeadFormState();
}

class _CrearEditarEventoLeadFormState
    extends ConsumerState<_CrearEditarEventoLeadForm> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _tematicaController = TextEditingController();

  DateTime _fecha = DateTime.now();
  int _duracionDias = 1;
  String _pais = kPaisEventoChile;
  Uint8List? _imagenBytes;
  String? _imagenUrlExistente;
  bool _guardando = false;
  bool _cargado = false;
  bool _heredada = false;

  String _nombre0 = '';
  String _pais0 = '';
  String _tematica0 = '';
  DateTime? _fecha0;
  int _duracionDias0 = 1;
  String? _imagenUrl0;

  bool get _esEdicion => widget.eventoId != null;
  bool get _fichaSoloLectura => _heredada;

  bool get _hayCambios {
    if (!_esEdicion || !_cargado || _fichaSoloLectura) return false;
    return _nombreController.text != _nombre0 ||
        _pais != _pais0 ||
        _tematicaController.text != _tematica0 ||
        _fecha != _fecha0 ||
        _duracionDias != _duracionDias0 ||
        _imagenBytes != null ||
        _imagenUrlExistente != _imagenUrl0;
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _tematicaController.dispose();
    super.dispose();
  }

  void _precargar(EventoLead evento) {
    if (_cargado) return;
    _cargado = true;
    _nombreController.text = evento.nombre;
    _pais = normalizarPaisEvento(evento.pais);
    _tematicaController.text = evento.tematica ?? '';
    _fecha = evento.fecha;
    _duracionDias = evento.duracionDias;
    _imagenUrlExistente = evento.imagenUrl;
    _heredada = evento.esInterno;
    _nombre0 = _nombreController.text;
    _pais0 = _pais;
    _tematica0 = _tematicaController.text;
    _fecha0 = _fecha;
    _duracionDias0 = _duracionDias;
    _imagenUrl0 = _imagenUrlExistente;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _elegirImagen() async {
    if (_fichaSoloLectura) return;
    final bytes = await elegirImagenComprimida(
      context,
      recorteProporcion: kProporcionImagenEvento,
      tituloRecorte: 'Recortar portada',
    );
    if (bytes == null || !mounted) return;
    setState(() => _imagenBytes = bytes);
  }

  void _quitarImagen() {
    if (_fichaSoloLectura) return;
    setState(() {
      _imagenBytes = null;
      _imagenUrlExistente = null;
    });
  }

  Future<void> _guardar() async {
    if (_fichaSoloLectura) return;
    if (!requireOnline(context, ref)) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);

    try {
      var imagenUrl = _imagenUrlExistente;
      if (!_fichaSoloLectura && _imagenBytes != null) {
        imagenUrl = await ref
            .read(storageRepositoryProvider)
            .subirImagenEvento(_imagenBytes!, 'jpg');
      }
      final cambioImagen =
          !_fichaSoloLectura && _esEdicion && imagenUrl != _imagenUrl0;

      final evento = EventoLead(
        id: widget.eventoId ?? '',
        nombre: _nombreController.text.trim(),
        fecha: _fecha,
        duracionDias: _duracionDias,
        pais: _pais,
        tematica: _tematicaController.text.trim().isEmpty
            ? null
            : _tematicaController.text.trim(),
        imagenUrl: imagenUrl,
        tipo: _heredada ? TipoEventoLead.interno : TipoEventoLead.externo,
      );

      final repo = ref.read(eventosLeadsRepositoryProvider);
      if (_esEdicion) {
        await repo.actualizar(widget.eventoId!, evento.toUpdateMap());
      } else {
        await repo.crear(evento);
      }

      ref.invalidate(eventosLeadsListProvider);
      if (widget.eventoId != null) {
        ref.invalidate(eventoLeadByIdProvider(widget.eventoId!));
      }
      // Tanto reemplazar como quitar la portada deja el objeto anterior sin
      // referencia. El trigger lo encola y la función lo borra de Storage.
      if (cambioImagen) {
        await ref.read(storageCleanupServiceProvider).drenar();
      }

      if (mounted) {
        showAppSnackBar(
          context,
          _esEdicion ? 'Actividad actualizada.' : 'Actividad creada.',
        );
        volverAtras(context);
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _eliminar() async {
    if (!requireOnline(context, ref)) return;
    final confirmado = await confirmDialog(
      context,
      title: 'Eliminar actividad',
      message:
          'Esta acción no se puede deshacer. ¿Eliminar la actividad de captura?',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (!confirmado) return;

    try {
      await ref.read(eventosLeadsRepositoryProvider).eliminar(widget.eventoId!);
      await ref.read(storageCleanupServiceProvider).drenar();
      ref.invalidate(eventosLeadsListProvider);
      ref.invalidate(eventoLeadByIdProvider(widget.eventoId!));
      if (mounted) context.go(RoutePaths.capturador);
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          'No se pudo eliminar la actividad.',
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final esAdmin = ref.watch(isAdminProvider);
    final hayRed = ref.watch(isOnlineProvider);
    final eventoAsync = widget.eventoId == null
        ? null
        : ref.watch(eventoLeadByIdProvider(widget.eventoId!));

    if (eventoAsync != null) {
      eventoAsync.whenData(_precargar);
    }

    return AppScaffold(
      title: _esEdicion
          ? (_fichaSoloLectura
                ? 'Actividad de captura'
                : 'Editar actividad de captura')
          : 'Nueva actividad',
      onWillPop: () => handleFormExit(
        context: context,
        isCreate: !_esEdicion,
        isDirty: _hayCambios,
        readOnly: _fichaSoloLectura || !hayRed,
        save: _guardar,
      ),
      actions: [
        if (_esEdicion && esAdmin)
          NexusHeaderAction(
            icon: Symbols.delete_outline_rounded,
            tooltip: 'Eliminar actividad',
            danger: true,
            onTap: (_guardando || !hayRed) ? null : _eliminar,
          ),
      ],
      body: eventoAsync != null && eventoAsync.isLoading && !_cargado
          ? const LoadingView()
          : AbsorbPointer(
              absorbing: _guardando,
              child: SingleChildScrollView(
                padding: AppSpacing.form,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_fichaSoloLectura) ...[
                        const _HerenciaBanner(),
                        const SizedBox(height: 16),
                      ],
                      const _FieldLabel('Foto'),
                      const SizedBox(height: 6),
                      SelectorImagen(
                        bytes: _imagenBytes,
                        urlExistente: _imagenUrlExistente,
                        enabled: !_guardando && !_fichaSoloLectura && hayRed,
                        aspectRatio: 16 / 9,
                        anchoMaximo: kAnchoSelectorImagenEvento,
                        etiquetaVacio: 'Agregar imagen de la actividad',
                        onElegir: _elegirImagen,
                        onQuitar:
                            _fichaSoloLectura ||
                                (_imagenBytes == null &&
                                    _imagenUrlExistente == null)
                            ? null
                            : _quitarImagen,
                      ),
                      const SizedBox(height: 14),
                      const _FieldLabel('Nombre de la actividad'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _nombreController,
                        enabled: !_guardando && !_fichaSoloLectura && hayRed,
                        decoration: const InputDecoration(
                          hintText: 'Ej. Feria retail 2026',
                        ),
                        validator: (v) {
                          if (_fichaSoloLectura) return null;
                          return (v == null || v.trim().isEmpty)
                              ? 'Requerido'
                              : null;
                        },
                      ),
                      const SizedBox(height: 14),
                      CamposFechaInicioTermino(
                        fechaInicio: _fecha,
                        duracionDias: _duracionDias,
                        textoDuracion: textoDuracionActividad(_duracionDias),
                        enabledInicio:
                            !_guardando && !_fichaSoloLectura && hayRed,
                        enabledTermino:
                            !_guardando && !_fichaSoloLectura && hayRed,
                        onInicioChanged: (fecha) => setState(() {
                          _fecha = fecha;
                          _duracionDias = 1;
                        }),
                        onTerminoChanged: (termino) => setState(
                          () => _duracionDias = duracionDesdeRango(
                            _fecha,
                            termino,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const _FieldLabel('País'),
                      const SizedBox(height: 6),
                      CampoPaisEvento(
                        value: _pais,
                        enabled: !_guardando && !_fichaSoloLectura && hayRed,
                        onChanged: (pais) => setState(() => _pais = pais),
                      ),
                      const SizedBox(height: 14),
                      const _FieldLabel('Temática'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _tematicaController,
                        enabled: !_guardando && !_fichaSoloLectura && hayRed,
                        decoration: const InputDecoration(
                          hintText: 'Ej. Telecomunicaciones',
                        ),
                        validator: (v) {
                          if (_fichaSoloLectura) return null;
                          return (v == null || v.trim().isEmpty)
                              ? 'Requerido'
                              : null;
                        },
                      ),
                      if (!_fichaSoloLectura) ...[
                        const SizedBox(height: 24),
                        PrimaryGradientButton(
                          label: _esEdicion
                              ? 'Guardar cambios'
                              : 'Crear actividad',
                          loading: _guardando,
                          onPressed: (_guardando || !hayRed) ? null : _guardar,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _HerenciaBanner extends StatelessWidget {
  const _HerenciaBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.tintNavy,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        'Estos datos vienen del evento ligado y cambian con él. '
        'Para actualizarlos, edita el evento de registro.',
        style: TextStyle(
          fontSize: 13,
          height: 1.4,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
      ),
    );
  }
}
