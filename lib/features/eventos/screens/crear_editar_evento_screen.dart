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
import '../../../core/widgets/selector_imagen.dart';
import '../../../core/widgets/require_permission.dart';
import '../../../data/models/evento.dart';
import '../../../data/repositories/eventos_repository.dart';
import '../../../data/repositories/storage_repository.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/eventos_providers.dart';
import '../../../data/repositories/storage_cleanup_service.dart';

/// Crear o editar un evento. Disponible para cualquier usuario autenticado.
class CrearEditarEventoScreen extends StatelessWidget {
  const CrearEditarEventoScreen({super.key, this.eventoId});

  final String? eventoId;

  @override
  Widget build(BuildContext context) {
    return RequirePermission(
      allowed: (p) => p.canCreateContent,
      deniedMessage:
          'Solo administradores y organizadores pueden crear o editar eventos.',
      builder: (context) => _CrearEditarEventoForm(eventoId: eventoId),
    );
  }
}

class _CrearEditarEventoForm extends ConsumerStatefulWidget {
  const _CrearEditarEventoForm({this.eventoId});

  final String? eventoId;

  @override
  ConsumerState<_CrearEditarEventoForm> createState() =>
      _CrearEditarEventoFormState();
}

class _CrearEditarEventoFormState
    extends ConsumerState<_CrearEditarEventoForm> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _tematicaController = TextEditingController();
  final _direccionController = TextEditingController();
  final _lugarController = TextEditingController();

  DateTime _fecha = DateTime.now();
  int _duracionDias = 1;
  String _pais = kPaisEventoChile;
  bool _certificacion = false;
  TipoRegistroEvento _tipoRegistro = TipoRegistroEvento.comercial;
  Uint8List? _imagenBytes;
  String? _imagenUrlExistente;
  bool _guardando = false;
  bool _cargado = false;

  String _nombre0 = '';
  String _pais0 = '';
  String _tematica0 = '';
  String _direccion0 = '';
  String _lugar0 = '';
  DateTime? _fecha0;
  int _duracionDias0 = 1;
  bool? _certificacion0;
  TipoRegistroEvento? _tipoRegistro0;
  String? _imagenUrl0;

  bool get _esEdicion => widget.eventoId != null;

  bool get _hayCambios {
    if (!_esEdicion || !_cargado) return false;
    return _nombreController.text != _nombre0 ||
        _pais != _pais0 ||
        _tematicaController.text != _tematica0 ||
        _direccionController.text != _direccion0 ||
        _lugarController.text != _lugar0 ||
        _fecha != _fecha0 ||
        _duracionDias != _duracionDias0 ||
        _certificacion != _certificacion0 ||
        _tipoRegistro != _tipoRegistro0 ||
        _imagenBytes != null ||
        _imagenUrlExistente != _imagenUrl0;
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _tematicaController.dispose();
    _direccionController.dispose();
    _lugarController.dispose();
    super.dispose();
  }

  void _precargar(Evento evento) {
    if (_cargado) return;
    _cargado = true;
    _nombreController.text = evento.nombre;
    _pais = normalizarPaisEvento(evento.pais);
    _tematicaController.text = evento.tematica ?? '';
    _direccionController.text = evento.direccion ?? '';
    _lugarController.text = evento.lugar ?? '';
    _fecha = evento.fecha;
    _duracionDias = evento.duracionDias;
    _certificacion = evento.certificacionCapacitacion;
    _tipoRegistro = evento.tipoRegistro;
    _imagenUrlExistente = evento.imagenUrl;
    _nombre0 = _nombreController.text;
    _pais0 = _pais;
    _tematica0 = _tematicaController.text;
    _direccion0 = _direccionController.text;
    _lugar0 = _lugarController.text;
    _fecha0 = _fecha;
    _duracionDias0 = _duracionDias;
    _certificacion0 = _certificacion;
    _tipoRegistro0 = _tipoRegistro;
    _imagenUrl0 = _imagenUrlExistente;
  }

  Future<void> _elegirImagen() async {
    final bytes = await elegirImagenComprimida(
      context,
      recorteProporcion: kProporcionImagenEvento,
      tituloRecorte: 'Recortar portada',
    );
    if (bytes == null || !mounted) return;
    setState(() => _imagenBytes = bytes);
  }

  void _quitarImagen() {
    setState(() {
      _imagenBytes = null;
      _imagenUrlExistente = null;
    });
  }

  Future<void> _guardar() async {
    if (!requireOnline(context, ref)) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);

    try {
      var imagenUrl = _imagenUrlExistente;
      if (_imagenBytes != null) {
        imagenUrl = await ref
            .read(storageRepositoryProvider)
            .subirImagenEvento(_imagenBytes!, 'jpg');
      }
      final cambioImagen = _esEdicion && imagenUrl != _imagenUrl0;

      final evento = Evento(
        id: widget.eventoId ?? '',
        nombre: _nombreController.text.trim(),
        fecha: _fecha,
        duracionDias: _duracionDias,
        pais: _pais,
        tematica: _tematicaController.text.trim(),
        direccion: _direccionController.text.trim(),
        lugar: _lugarController.text.trim(),
        certificacionCapacitacion: _certificacion,
        imagenUrl: imagenUrl,
        tipoRegistro: _tipoRegistro,
      );

      final repo = ref.read(eventosRepositoryProvider);
      if (_esEdicion) {
        await repo.actualizar(widget.eventoId!, evento.toInsertMap());
      } else {
        await repo.crear(evento);
      }

      ref.invalidate(eventosListProvider);
      if (widget.eventoId != null) {
        ref.invalidate(eventoByIdProvider(widget.eventoId!));
      }
      // Reemplazar la portada sube un UUID nuevo; quitarla también deja el
      // objeto anterior sin referencia. El trigger lo encola y aquí esperamos
      // el intento de borrado antes de abandonar el formulario.
      if (cambioImagen) {
        await ref.read(storageCleanupServiceProvider).drenar();
      }

      if (mounted) {
        if (_esEdicion) {
          showAppSnackBar(context, 'Evento actualizado.');
        } else {
          showAppSnackBar(context, 'Evento creado correctamente');
        }
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
      title: 'Eliminar evento',
      message:
          'Esta acción no se puede deshacer. ¿Eliminar el evento y sus registrados?',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (!confirmado) return;

    try {
      await ref.read(eventosRepositoryProvider).eliminar(widget.eventoId!);
      await ref.read(storageCleanupServiceProvider).drenar();
      ref.invalidate(eventosListProvider);
      ref.invalidate(eventoByIdProvider(widget.eventoId!));
      if (mounted) context.go(RoutePaths.eventos);
    } on EventoConEventoLeadException catch (e) {
      if (mounted) showAppSnackBar(context, e.toString(), isError: true);
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          'No se pudo eliminar el evento.',
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
        : ref.watch(eventoByIdProvider(widget.eventoId!));

    if (eventoAsync != null) {
      eventoAsync.whenData(_precargar);
    }

    return AppScaffold(
      title: _esEdicion ? 'Editar evento' : 'Nuevo evento',
      onWillPop: () => handleFormExit(
        context: context,
        isCreate: !_esEdicion,
        isDirty: _hayCambios,
        readOnly: !hayRed,
        save: _guardar,
      ),
      actions: [
        if (_esEdicion && esAdmin)
          NexusHeaderAction(
            icon: Symbols.delete_outline_rounded,
            tooltip: 'Eliminar evento',
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
                      _FieldLabel('Foto'),
                      const SizedBox(height: 6),
                      SelectorImagen(
                        bytes: _imagenBytes,
                        urlExistente: _imagenUrlExistente,
                        enabled: !_guardando && hayRed,
                        aspectRatio: 16 / 9,
                        anchoMaximo: kAnchoSelectorImagenEvento,
                        etiquetaVacio: 'Agregar imagen del evento',
                        onElegir: _elegirImagen,
                        onQuitar:
                            _imagenBytes == null && _imagenUrlExistente == null
                            ? null
                            : _quitarImagen,
                      ),
                      const SizedBox(height: 14),
                      _FieldLabel('Nombre'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _nombreController,
                        enabled: !_guardando && hayRed,
                        decoration: const InputDecoration(
                          hintText: 'Ej. Taller ALTAI 2026',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Requerido'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      CamposFechaInicioTermino(
                        fechaInicio: _fecha,
                        duracionDias: _duracionDias,
                        textoDuracion: textoDuracionEvento(_duracionDias),
                        enabledInicio: !_guardando && hayRed,
                        enabledTermino: !_guardando && hayRed,
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
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _FieldLabel('País'),
                                const SizedBox(height: 6),
                                CampoPaisEvento(
                                  value: _pais,
                                  enabled: !_guardando && hayRed,
                                  onChanged: (pais) =>
                                      setState(() => _pais = pais),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _FieldLabel('Lugar'),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _lugarController,
                                  enabled: !_guardando && hayRed,
                                  decoration: const InputDecoration(
                                    hintText: 'Hotel…',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _FieldLabel('Dirección'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _direccionController,
                        enabled: !_guardando && hayRed,
                        decoration: const InputDecoration(
                          hintText: 'Av. Vitacura 2885',
                        ),
                      ),
                      const SizedBox(height: 14),
                      _FieldLabel('Temática'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _tematicaController,
                        enabled: !_guardando && hayRed,
                        decoration: const InputDecoration(
                          hintText: 'Ej. Telecomunicaciones',
                        ),
                      ),
                      const SizedBox(height: 14),
                      _FieldLabel('Tipo de registro'),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<TipoRegistroEvento>(
                        initialValue: _tipoRegistro,
                        decoration: const InputDecoration(),
                        items: const [
                          DropdownMenuItem(
                            value: TipoRegistroEvento.comercial,
                            child: Text('Comercial'),
                          ),
                          DropdownMenuItem(
                            value: TipoRegistroEvento.cliente,
                            child: Text('Cliente'),
                          ),
                        ],
                        onChanged: (_guardando || !hayRed)
                            ? null
                            : (value) => setState(
                                () => _tipoRegistro = value ?? _tipoRegistro,
                              ),
                      ),
                      const SizedBox(height: 14),
                      _ToggleCard(
                        title: 'Requiere certificación',
                        subtitle: 'Habilita los campos RUT y patente',
                        value: _certificacion,
                        onChanged: (v) => setState(() => _certificacion = v),
                      ),
                      const SizedBox(height: 20),
                      PrimaryGradientButton(
                        label: _esEdicion ? 'Guardar' : 'Crear evento',
                        loading: _guardando,
                        onPressed: (_guardando || !hayRed) ? null : _guardar,
                      ),
                    ],
                  ),
                ),
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

class _ToggleCard extends StatelessWidget {
  const _ToggleCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              NexusToggle(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}
