import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/errors/rpe_exception.dart';
import '../../../core/router/refresh_on_visible.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/network/offline_guard.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/constants/duracion_actividad.dart';
import '../../../core/constants/paises_evento.dart';
import '../../../core/theme/tw_tokens.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/campo_pais_evento.dart';
import '../../../core/widgets/campos_fecha_inicio_termino.dart';
import '../../../core/widgets/form_sections.dart';
import '../../../core/widgets/selector_imagen.dart';
import '../../../core/widgets/require_permission.dart';
import '../../../core/widgets/tw_components.dart';
import '../../../data/models/evento.dart';
import '../../../data/offline/offline_cache_tables.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/repositories/eventos_repository.dart';
import '../../../data/repositories/storage_repository.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/eventos_providers.dart';
import '../../subeventos/providers/subeventos_providers.dart';
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
  bool _accesoQr = false;
  TipoEvento _tipo = TipoEvento.evento;
  final _cupoController = TextEditingController();
  final _descripcionController = TextEditingController();
  final _mapaController = TextEditingController();
  TimeOfDay? _horaInicio;
  TimeOfDay? _horaFin;
  DateTime? _cierre;
  Uint8List? _imagenBytes;
  String? _imagenUrlExistente;
  bool _guardando = false;
  bool _cargado = false;

  /// Foto de lo que se precargó, para saber si hay cambios sin guardar.
  Map<String, Object?> _original = const {};

  bool get _esEdicion => widget.eventoId != null;

  Map<String, Object?> _instantanea() => {
    'nombre': _nombreController.text,
    'pais': _pais,
    'tematica': _tematicaController.text,
    'direccion': _direccionController.text,
    'lugar': _lugarController.text,
    'fecha': _fecha,
    'duracion': _duracionDias,
    'certificacion': _certificacion,
    'accesoQr': _accesoQr,
    'tipo': _tipo,
    'cupo': _cupoController.text,
    'descripcion': _descripcionController.text,
    'mapa': _mapaController.text,
    'horaInicio': _horaInicio,
    'horaFin': _horaFin,
    'cierre': _cierre,
    'imagen': _imagenUrlExistente,
  };

  bool get _hayCambios {
    if (!_esEdicion || !_cargado) return false;
    if (_imagenBytes != null) return true;
    final actual = _instantanea();
    return actual.entries.any((e) => _original[e.key] != e.value);
  }

  /// Al crear: ¿el usuario ya escribió o eligió algo que se perdería?
  bool get _hayDatosNuevos =>
      [
        _nombreController,
        _tematicaController,
        _direccionController,
        _lugarController,
        _cupoController,
        _descripcionController,
        _mapaController,
      ].any((c) => c.text.trim().isNotEmpty) ||
      _imagenBytes != null ||
      _horaInicio != null ||
      _horaFin != null ||
      _cierre != null;

  /// El término del horario tiene que ir después del inicio.
  bool get _horarioInvalido {
    final inicio = _horaInicio;
    final fin = _horaFin;
    if (inicio == null || fin == null) return false;
    return fin.hour * 60 + fin.minute <= inicio.hour * 60 + inicio.minute;
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _tematicaController.dispose();
    _direccionController.dispose();
    _lugarController.dispose();
    _cupoController.dispose();
    _descripcionController.dispose();
    _mapaController.dispose();
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
    _accesoQr = evento.accesoQr;
    _tipo = evento.tipo;
    _cupoController.text = evento.cupoMaximo?.toString() ?? '';
    _descripcionController.text = evento.descripcion ?? '';
    _mapaController.text = evento.mapaUrl ?? '';
    _horaInicio = evento.horaInicio;
    _horaFin = evento.horaFin;
    _cierre = evento.inscripcionesCierre;
    _imagenUrlExistente = evento.imagenUrl;
    _original = _instantanea();
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

  Future<void> _elegirHora({required bool inicio}) async {
    final actual = inicio ? _horaInicio : _horaFin;
    final hora = await showTimePicker(
      context: context,
      initialTime:
          actual ??
          (inicio
              ? const TimeOfDay(hour: 9, minute: 0)
              : const TimeOfDay(hour: 18, minute: 0)),
    );
    if (hora == null || !mounted) return;
    setState(() {
      if (inicio) {
        _horaInicio = hora;
      } else {
        _horaFin = hora;
      }
    });
  }

  Future<void> _elegirCierre() async {
    final base = _cierre ?? DateTime(_fecha.year, _fecha.month, _fecha.day);
    final dia = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: fechaTerminoActividad(_fecha, _duracionDias),
    );
    if (dia == null || !mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: _cierre == null
          ? const TimeOfDay(hour: 23, minute: 59)
          : TimeOfDay.fromDateTime(_cierre!),
    );
    if (hora == null || !mounted) return;
    setState(
      () => _cierre = DateTime(
        dia.year,
        dia.month,
        dia.day,
        hora.hour,
        hora.minute,
      ),
    );
  }

  Future<void> _cambiarTipo(TipoEvento tipo) async {
    if (tipo == _tipo) return;
    if (tipo.esTaller && widget.eventoId != null) {
      try {
        final talleres = await ref.read(
          subeventosPorEventoProvider(widget.eventoId!).future,
        );
        if (!mounted) return;
        if (talleres.isNotEmpty) {
          showAppSnackBar(
            context,
            'Quita los subeventos antes de marcarlo como taller.',
            isError: true,
          );
          return;
        }
      } catch (_) {
        if (!mounted) return;
        showAppSnackBar(
          context,
          'No se pudo comprobar si este evento tiene subeventos.',
          isError: true,
        );
        return;
      }
    }
    setState(() => _tipo = tipo);
  }

  Future<void> _guardar() async {
    if (!requireOnline(context, ref)) return;
    final formularioOk = _formKey.currentState!.validate();
    if (!formularioOk || _horarioInvalido) {
      showAppSnackBar(
        context,
        'Revisa los campos marcados antes de guardar.',
        isError: true,
      );
      return;
    }
    setState(() => _guardando = true);

    try {
      var imagenUrl = _imagenUrlExistente;
      if (_imagenBytes != null) {
        imagenUrl = await ref
            .read(storageRepositoryProvider)
            .subirImagenEvento(_imagenBytes!, 'jpg');
      }
      final cambioImagen = _esEdicion && imagenUrl != _original['imagen'];

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
        accesoQr: _accesoQr,
        tipo: _tipo,
        cupoMaximo: int.tryParse(_cupoController.text.trim()),
        descripcion: _descripcionController.text.trim().isEmpty
            ? null
            : _descripcionController.text.trim(),
        horaInicio: _horaInicio,
        horaFin: _horaFin,
        inscripcionesCierre: _cierre,
        mapaUrl: urlMapaEmbebible(_mapaController.text),
      );

      final repo = ref.read(eventosRepositoryProvider);
      if (_esEdicion) {
        final guardado = await conErroresRpe(
          () => repo.actualizar(widget.eventoId!, evento.toInsertMap()),
        );
        await _publicarEnCache(guardado);
      } else {
        await conErroresRpe(() => repo.crear(evento));
        ref.invalidate(eventosListProvider);
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

  /// Las lecturas del evento son cache-first: sin este parche, el detalle y la
  /// lista seguían mostrando la versión anterior al guardado hasta revalidar.
  Future<void> _publicarEnCache(Evento guardado) async {
    final cambios = guardado.toCacheMap();
    await publicarCambioEnLecturaCacheada(
      ref,
      tabla: OfflineCacheTables.eventoDetalle,
      eventoId: guardado.id,
      id: guardado.id,
      cambios: cambios,
      invalidar: () => ref.invalidate(eventoByIdProvider(guardado.id)),
    );
    await publicarCambioEnLecturaCacheada(
      ref,
      tabla: OfflineCacheTables.eventos,
      eventoId: cacheAmbitoGlobal,
      id: guardado.id,
      cambios: cambios,
      invalidar: () => ref.invalidate(eventosListProvider),
    );
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
        : ref.watch(eventoParaEditarProvider(widget.eventoId!));

    if (eventoAsync != null) {
      eventoAsync.whenData(_precargar);
    }

    final editable = !_guardando && hayRed;
    final cargando = eventoAsync != null && eventoAsync.isLoading && !_cargado;
    final nombreTipo = _tipo.esTaller ? 'taller' : 'evento';

    return AppScaffold(
      title: _esEdicion
          ? (_tipo.esTaller ? 'Editar taller' : 'Editar evento')
          : (_tipo.esTaller ? 'Nuevo taller' : 'Nuevo evento'),
      onWillPop: () => handleFormExit(
        context: context,
        isCreate: !_esEdicion,
        isDirty: _hayCambios,
        createHasInput: _hayDatosNuevos,
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
      bottomBar: cargando
          ? null
          : FormActionBar(
              label: _esEdicion ? 'Guardar cambios' : 'Crear $nombreTipo',
              loading: _guardando,
              onPressed: (_guardando || !hayRed) ? null : _guardar,
            ),
      body: cargando
          ? const LoadingView()
          : AbsorbPointer(
              absorbing: _guardando,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  TwSpacing.screenH,
                  14,
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
                      _seccionTipo(editable),
                      const SizedBox(height: FormSection.gap),
                      _seccionGeneral(editable),
                      const SizedBox(height: FormSection.gap),
                      _seccionFechas(editable),
                      const SizedBox(height: FormSection.gap),
                      _seccionUbicacion(editable),
                      const SizedBox(height: FormSection.gap),
                      _seccionInscripcion(editable),
                      const SizedBox(height: FormSection.gap),
                      _seccionWeb(editable),
                      if (_esEdicion && !_tipo.esTaller) ...[
                        const SizedBox(height: FormSection.gap),
                        _seccionTalleres(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _seccionTipo(bool editable) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TwSectionLabel(_esEdicion ? 'Tipo' : '¿Qué vas a crear?', top: 4),
        FormChoiceCards<TipoEvento>(
          value: _tipo,
          onChanged: editable ? _cambiarTipo : null,
          choices: const [
            FormChoice(
              value: TipoEvento.evento,
              icon: Symbols.event_rounded,
              title: 'Evento',
              description: 'Registra asistentes y puede agrupar talleres.',
            ),
            FormChoice(
              value: TipoEvento.taller,
              icon: Symbols.co_present_rounded,
              title: 'Taller',
              description: 'Actividad que luego se suma a un evento.',
            ),
          ],
        ),
      ],
    );
  }

  Widget _seccionGeneral(bool editable) {
    return FormSection(
      icon: Symbols.info_rounded,
      title: 'Información general',
      subtitle: 'Lo primero que ven el equipo y los asistentes.',
      children: [
        FormLabeledField(
          label: 'Portada',
          opcional: true,
          child: SelectorImagen(
            bytes: _imagenBytes,
            urlExistente: _imagenUrlExistente,
            enabled: editable,
            aspectRatio: 16 / 9,
            anchoMaximo: 520,
            etiquetaVacio: 'Agregar portada (16:9)',
            onElegir: _elegirImagen,
            onQuitar: _imagenBytes == null && _imagenUrlExistente == null
                ? null
                : _quitarImagen,
          ),
        ),
        FormLabeledField(
          label: 'Nombre',
          child: TextFormField(
            controller: _nombreController,
            enabled: editable,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: _tipo.esTaller
                  ? 'Ej. Taller de ventas consultivas'
                  : 'Ej. Congreso ALTAI 2026',
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Escribe un nombre.' : null,
          ),
        ),
        FormLabeledField(
          label: 'Temática',
          opcional: true,
          child: TextFormField(
            controller: _tematicaController,
            enabled: editable,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'Ej. Telecomunicaciones',
            ),
          ),
        ),
      ],
    );
  }

  Widget _seccionFechas(bool editable) {
    final cierre = _cierre == null
        ? null
        : DateFormat("EEE d MMM yyyy '·' HH:mm", 'es').format(_cierre!);
    return FormSection(
      icon: Symbols.calendar_month_rounded,
      title: 'Fecha y horario',
      children: [
        CamposFechaInicioTermino(
          fechaInicio: _fecha,
          duracionDias: _duracionDias,
          textoDuracion: _tipo.esTaller
              ? textoDuracionActividad(_duracionDias)
              : textoDuracionEvento(_duracionDias),
          enabledInicio: editable,
          enabledTermino: editable,
          onInicioChanged: (fecha) => setState(() {
            _fecha = fecha;
            _duracionDias = 1;
          }),
          onTerminoChanged: (termino) => setState(
            () => _duracionDias = duracionDesdeRango(_fecha, termino),
          ),
        ),
        FormFieldRow(
          minWidth: 260,
          left: FormLabeledField(
            label: 'Hora de inicio',
            child: FormPickerField(
              valor: _horaInicio?.format(context),
              placeholder: 'Opcional',
              icon: Symbols.schedule_rounded,
              enabled: editable,
              error: _horarioInvalido,
              onTap: () => _elegirHora(inicio: true),
              onClear: () => setState(() => _horaInicio = null),
            ),
          ),
          right: FormLabeledField(
            label: 'Hora de término',
            child: FormPickerField(
              valor: _horaFin?.format(context),
              placeholder: 'Opcional',
              icon: Symbols.schedule_rounded,
              enabled: editable,
              error: _horarioInvalido,
              onTap: () => _elegirHora(inicio: false),
              onClear: () => setState(() => _horaFin = null),
            ),
          ),
        ),
        if (_horarioInvalido)
          const FormNotice(
            'La hora de término debe ser posterior a la de inicio.',
            error: true,
          ),
        FormLabeledField(
          label: 'Cierre de inscripciones',
          opcional: true,
          ayuda: 'Después de esta fecha la web pública deja de inscribir.',
          child: FormPickerField(
            valor: cierre,
            placeholder: 'Abiertas hasta el evento',
            icon: Symbols.event_busy_rounded,
            enabled: editable,
            onTap: _elegirCierre,
            onClear: () => setState(() => _cierre = null),
          ),
        ),
      ],
    );
  }

  Widget _seccionUbicacion(bool editable) {
    return FormSection(
      icon: Symbols.location_on_rounded,
      title: 'Ubicación',
      children: [
        FormFieldRow(
          minWidth: 280,
          left: FormLabeledField(
            label: 'País',
            child: CampoPaisEvento(
              value: _pais,
              enabled: editable,
              onChanged: (pais) => setState(() => _pais = pais),
            ),
          ),
          right: FormLabeledField(
            label: 'Lugar',
            opcional: true,
            child: TextFormField(
              controller: _lugarController,
              enabled: editable,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'Hotel, centro…'),
            ),
          ),
        ),
        FormLabeledField(
          label: 'Dirección',
          opcional: true,
          child: TextFormField(
            controller: _direccionController,
            enabled: editable,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(hintText: 'Av. Vitacura 2885'),
          ),
        ),
      ],
    );
  }

  Widget _seccionInscripcion(bool editable) {
    return FormSection(
      icon: Symbols.how_to_reg_rounded,
      title: 'Inscripción y acceso',
      children: [
        FormLabeledField(
          label: 'Cupo máximo',
          opcional: true,
          ayuda: 'Déjalo vacío si no hay límite de asistentes.',
          child: TextFormField(
            controller: _cupoController,
            enabled: editable,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'Sin límite',
              prefixIcon: Icon(Symbols.groups_rounded, size: 20),
            ),
            validator: (valor) {
              final texto = valor?.trim() ?? '';
              if (texto.isEmpty) return null;
              final cupo = int.tryParse(texto);
              if (cupo == null || cupo <= 0) {
                return 'El cupo debe ser mayor que 0.';
              }
              return null;
            },
          ),
        ),
        const FormDivider(),
        FormToggleRow(
          icon: Symbols.qr_code_2_rounded,
          title: 'Acceso con QR',
          subtitle: 'Cada asistente recibe un código para entrar.',
          value: _accesoQr,
          onChanged: editable ? (v) => setState(() => _accesoQr = v) : null,
        ),
        const FormDivider(),
        FormToggleRow(
          icon: Symbols.workspace_premium_rounded,
          title: 'Requiere certificación',
          subtitle: 'Pide RUT y patente al registrar.',
          value: _certificacion,
          onChanged: editable
              ? (v) => setState(() => _certificacion = v)
              : null,
        ),
      ],
    );
  }

  Widget _seccionWeb(bool editable) {
    return FormSection(
      icon: Symbols.language_rounded,
      title: 'Página pública',
      subtitle: 'Lo que se muestra en la web de eventos.',
      children: [
        FormLabeledField(
          label: 'Descripción',
          opcional: true,
          child: TextFormField(
            controller: _descripcionController,
            enabled: editable,
            minLines: 3,
            maxLines: 6,
            maxLength: 5000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Cuenta de qué trata, a quién va dirigido…',
              counterText: '',
            ),
            validator: (valor) =>
                (valor ?? '').length > 5000 ? 'Máximo 5000 caracteres.' : null,
          ),
        ),
        FormLabeledField(
          label: 'Mapa (Google Maps)',
          opcional: true,
          ayuda:
              'En Google Maps: Compartir → Insertar un mapa → Copiar HTML. '
              'Pega aquí el código o solo el enlace; la web lo muestra en '
              '«Cómo llegar», en el detalle público del evento.',
          child: TextFormField(
            controller: _mapaController,
            enabled: editable,
            keyboardType: TextInputType.url,
            autocorrect: false,
            maxLines: null,
            decoration: const InputDecoration(
              hintText: 'https://www.google.com/maps/embed?pb=…',
              prefixIcon: Icon(Symbols.map_rounded, size: 20),
            ),
            validator: (valor) {
              final texto = valor?.trim() ?? '';
              if (texto.isEmpty || urlMapaEmbebible(texto) != null) {
                return null;
              }
              return 'Usa el enlace de "Insertar un mapa" de Google Maps '
                  '(https://www.google.com/maps/embed?…).';
            },
          ),
        ),
      ],
    );
  }

  Widget _seccionTalleres() {
    final talleres = ref
        .watch(subeventosPorEventoProvider(widget.eventoId!))
        .valueOrNull;
    final total = talleres?.length ?? 0;
    return TwActionTile(
      icon: Symbols.account_tree_rounded,
      iconStyle: TwIconBoxStyle.brand,
      title: 'Talleres del evento',
      subtitle: switch (total) {
        0 => 'Todavía no tiene talleres',
        1 => '1 taller agrupado',
        _ => '$total talleres agrupados',
      },
      onTap: () => context.push(RoutePaths.subeventos(widget.eventoId!)),
    );
  }
}
