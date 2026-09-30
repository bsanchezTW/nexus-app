import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/errors/rpe_exception.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/network/offline_guard.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/tw_tokens.dart';
import '../../../core/widgets/app_modals.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/form_sections.dart';
import '../../../core/widgets/nexus_components.dart';
import '../../../core/widgets/require_permission.dart';
import '../../../core/widgets/tw_components.dart';
import '../../../data/models/evento.dart';
import '../../../data/models/ocupacion_evento.dart';
import '../../../data/models/subevento.dart';
import '../../../data/repositories/subeventos_repository.dart';
import '../../eventos/providers/eventos_providers.dart';
import '../providers/subeventos_providers.dart';
import '../subevento_desde_evento.dart';

class SubeventosEventoScreen extends StatelessWidget {
  const SubeventosEventoScreen({super.key, required this.eventoId});

  final String eventoId;

  @override
  Widget build(BuildContext context) {
    return RequirePermission(
      allowed: (perfil) => perfil.canCreateContent,
      deniedMessage: 'Solo administradores y organizadores gestionan talleres.',
      builder: (context) => _ListaSubeventos(eventoId: eventoId),
    );
  }
}

/// Tras cualquier alta, baja o cambio de talleres: la lista del evento, su
/// ocupación y la lista general (que agrupa talleres bajo su evento).
void _invalidarTalleres(WidgetRef ref, String eventoId) {
  ref.invalidate(subeventosPorEventoProvider(eventoId));
  ref.invalidate(ocupacionEventoProvider(eventoId));
  ref.invalidate(subeventosTodosProvider);
}

class _ListaSubeventos extends ConsumerWidget {
  const _ListaSubeventos({required this.eventoId});

  final String eventoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final principal = ref.watch(eventoByIdProvider(eventoId)).valueOrNull;
    final talleres = ref.watch(subeventosPorEventoProvider(eventoId));
    final ocupacion = ref.watch(ocupacionEventoProvider(eventoId));
    final puedeAgrupar = principal?.esTaller != true;
    return AppScaffold(
      title: 'Talleres',
      body: talleres.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(subeventosPorEventoProvider(eventoId)),
        ),
        data: (lista) {
          final grupos = <String, List<Subevento>>{};
          for (final taller in lista) {
            final clave = DateFormat('yyyy-MM-dd').format(taller.dia);
            grupos.putIfAbsent(clave, () => []).add(taller);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              TwSpacing.screenH,
              14,
              TwSpacing.screenH,
              28,
            ),
            children: [
              if (principal != null)
                _ResumenPrincipal(principal: principal, total: lista.length),
              if (puedeAgrupar) ...[
                const SizedBox(height: 12),
                TwActionTile(
                  icon: Symbols.playlist_add_check_rounded,
                  title: 'Sumar talleres existentes',
                  subtitle: 'Elige talleres ya creados como eventos',
                  onTap: () => _seleccionarTalleres(context, ref, lista),
                ),
              ],
              if (lista.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: EmptyStateView(
                    icon: Symbols.co_present_rounded,
                    message:
                        'Este evento todavía no tiene talleres.\nCrea uno nuevo o suma uno existente.',
                  ),
                ),
              for (final entrada in grupos.entries) ...[
                TwSectionLabel(
                  DateFormat(
                    "EEEE d 'de' MMMM",
                    'es',
                  ).format(entrada.value.first.dia),
                ),
                for (var i = 0; i < entrada.value.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _TallerTile(
                    taller: entrada.value[i],
                    ocupacion: ocupacion.valueOrNull?.subeventos[entrada
                        .value[i]
                        .id],
                    onTap: () => context.push(
                      RoutePaths.editarSubevento(eventoId, entrada.value[i].id),
                    ),
                  ),
                ],
              ],
            ],
          );
        },
      ),
      bottomBar: FormActionBar(
        label: 'Nuevo taller',
        onPressed: () {
          if (!requireOnline(context, ref)) return;
          context.push(RoutePaths.crearSubevento(eventoId));
        },
      ),
    );
  }

  Future<void> _seleccionarTalleres(
    BuildContext context,
    WidgetRef ref,
    List<Subevento> actuales,
  ) async {
    if (!requireOnline(context, ref)) return;
    final Evento principal;
    try {
      principal = await ref.read(eventoByIdProvider(eventoId).future);
    } catch (_) {
      if (context.mounted) {
        showAppSnackBar(context, 'No se pudo cargar el evento.', isError: true);
      }
      return;
    }
    if (principal.esTaller) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          'Solo un evento principal puede agrupar talleres.',
          isError: true,
        );
      }
      return;
    }
    if (!context.mounted) return;
    final yaVinculados = {
      for (final taller in actuales)
        if (taller.eventoOrigenId != null) taller.eventoOrigenId!,
    };
    final elegidos = await showAppModalBottomSheet<List<Evento>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          _SelectorTalleres(eventoId: eventoId, yaVinculados: yaVinculados),
    );
    if (elegidos == null || elegidos.isEmpty || !context.mounted) return;
    final confirmar = await confirmDialog(
      context,
      title: 'Agregar talleres',
      message:
          'Se agregan ${elegidos.length} talleres a ${principal.nombre}. '
          'Siguen existiendo como talleres y sus inscripciones no se copian.',
      confirmLabel: 'Agregar',
    );
    if (!confirmar || !context.mounted) return;

    final talleresRepo = ref.read(subeventosRepositoryProvider);
    final noAgregados = <String>[];
    var orden = actuales.length;
    for (final origen in elegidos) {
      try {
        await talleresRepo.crear(
          subeventoDesdeEvento(
            principal: principal,
            origen: origen,
            orden: orden,
          ),
        );
        orden++;
      } catch (_) {
        noAgregados.add(origen.nombre);
      }
    }
    _invalidarTalleres(ref, eventoId);
    if (!context.mounted) return;
    if (noAgregados.isEmpty) {
      showAppSnackBar(context, 'Talleres agregados.');
      return;
    }
    showAppSnackBar(
      context,
      'No se pudieron agregar: ${noAgregados.join(', ')}.',
      isError: true,
    );
  }
}

/// Cabecera de la lista: a qué evento pertenecen los talleres.
class _ResumenPrincipal extends StatelessWidget {
  const _ResumenPrincipal({required this.principal, required this.total});

  final Evento principal;
  final int total;

  @override
  Widget build(BuildContext context) {
    return TwCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          DateTile(date: principal.fecha, muted: principal.yaOcurrio),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  principal.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TwText.tileTitle.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  total == 1 ? '1 taller' : '$total talleres',
                  style: TwText.tileSubtitle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectorTalleres extends ConsumerStatefulWidget {
  const _SelectorTalleres({required this.eventoId, required this.yaVinculados});

  final String eventoId;
  final Set<String> yaVinculados;

  @override
  ConsumerState<_SelectorTalleres> createState() => _SelectorTalleresState();
}

class _SelectorTalleresState extends ConsumerState<_SelectorTalleres> {
  final _elegidos = <String>{};

  @override
  Widget build(BuildContext context) {
    final eventos = ref.watch(eventosListProvider);
    final altura = MediaQuery.sizeOf(context).height * 0.7;
    return SafeArea(
      child: SizedBox(
        height: altura,
        child: eventos.when(
          loading: () => const LoadingView(),
          error: (error, _) => ErrorView(
            message: error.toString(),
            onRetry: () => ref.invalidate(eventosListProvider),
          ),
          data: (lista) {
            final talleres = [
              for (final evento in lista)
                if (evento.esTaller &&
                    evento.id != widget.eventoId &&
                    !widget.yaVinculados.contains(evento.id))
                  evento,
            ]..sort((a, b) => a.fecha.compareTo(b.fecha));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    TwSpacing.screenH,
                    0,
                    TwSpacing.screenH,
                    4,
                  ),
                  child: Text(
                    'Sumar talleres',
                    style: TwText.tileTitle.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    TwSpacing.screenH,
                    0,
                    TwSpacing.screenH,
                    12,
                  ),
                  child: Text(
                    'Elige los talleres que forman parte de este evento.',
                    style: TwText.tileSubtitle,
                  ),
                ),
                Expanded(
                  child: talleres.isEmpty
                      ? const EmptyStateView(
                          icon: Symbols.co_present_rounded,
                          message:
                              'No hay talleres disponibles.\nCrea un evento y márcalo como Taller.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: TwSpacing.screenH,
                          ),
                          itemCount: talleres.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final evento = talleres[index];
                            final marcado = _elegidos.contains(evento.id);
                            return _OpcionTaller(
                              evento: evento,
                              marcado: marcado,
                              onTap: () => setState(() {
                                if (!_elegidos.remove(evento.id)) {
                                  _elegidos.add(evento.id);
                                }
                              }),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    TwSpacing.screenH,
                    12,
                    TwSpacing.screenH,
                    12,
                  ),
                  child: Opacity(
                    opacity: _elegidos.isEmpty ? 0.5 : 1,
                    child: TwPrimaryButton(
                      label: _elegidos.isEmpty
                          ? 'Selecciona talleres'
                          : 'Agregar (${_elegidos.length})',
                      onTap: _elegidos.isEmpty
                          ? null
                          : () {
                              final seleccion = talleres
                                  .where((e) => _elegidos.contains(e.id))
                                  .toList();
                              Navigator.of(context).pop(seleccion);
                            },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OpcionTaller extends StatelessWidget {
  const _OpcionTaller({
    required this.evento,
    required this.marcado,
    required this.onTap,
  });

  final Evento evento;
  final bool marcado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: marcado,
      child: TwPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: marcado ? TwColors.blueTint : TwColors.surface,
            borderRadius: TwRadii.tile,
            border: Border.all(
              color: marcado ? TwColors.fieldBorderActive : TwColors.border07,
              width: marcado ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              DateTile(date: evento.fecha),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      evento.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TwText.tileTitle.copyWith(fontSize: 14),
                    ),
                    if ((evento.lugar ?? '').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        evento.lugar!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TwText.tileSubtitle.copyWith(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                marcado
                    ? Symbols.check_circle_rounded
                    : Symbols.radio_button_unchecked_rounded,
                fill: marcado ? 1 : 0,
                size: 22,
                color: marcado ? TwColors.hero700 : TwColors.chevron,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TallerTile extends StatelessWidget {
  const _TallerTile({
    required this.taller,
    required this.ocupacion,
    required this.onTap,
  });

  final Subevento taller;
  final OcupacionItem? ocupacion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inicio = horaATexto(taller.horaInicio)?.substring(0, 5) ?? '';
    final fin = horaATexto(taller.horaFin)?.substring(0, 5) ?? '';
    final cupo = ocupacion?.cupoMaximo;
    final inscritos = ocupacion?.inscritos ?? 0;
    final sobrecupo = (ocupacion?.sobrecupo ?? 0) > 0;
    final meta = [
      if ((taller.sala ?? '').isNotEmpty) taller.sala!,
      if ((taller.expositor ?? '').isNotEmpty) taller.expositor!,
    ].join(' · ');
    return TwPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: const BoxDecoration(
          color: TwColors.surface,
          borderRadius: TwRadii.tile,
          border: Border.fromBorderSide(BorderSide(color: TwColors.border07)),
          boxShadow: TwShadows.card,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    inicio,
                    style: TwText.tileTitle.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: TwColors.hero700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    fin,
                    style: TwText.tileSubtitle.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              width: 1,
              height: 34,
              margin: const EdgeInsets.only(right: 12),
              color: TwColors.border10,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    taller.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TwText.tileTitle.copyWith(fontSize: 14, height: 1.3),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TwText.tileSubtitle.copyWith(fontSize: 12),
                    ),
                  ],
                  if (sobrecupo || !taller.visiblePublico) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (sobrecupo)
                          const StatusChip(
                            label: 'Sobrecupo',
                            variant: StatusChipVariant.warning,
                          ),
                        if (!taller.visiblePublico)
                          const StatusChip(
                            label: 'Oculto en la web',
                            variant: StatusChipVariant.neutral,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  cupo == null ? '$inscritos' : '$inscritos/$cupo',
                  style: TwText.tileTitle.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'inscritos',
                  style: TwText.tileSubtitle.copyWith(fontSize: 11),
                ),
              ],
            ),
            const SizedBox(width: 2),
            const Icon(
              Symbols.chevron_right_rounded,
              size: 20,
              color: TwColors.chevron,
            ),
          ],
        ),
      ),
    );
  }
}

class CrearEditarSubeventoScreen extends StatelessWidget {
  const CrearEditarSubeventoScreen({
    super.key,
    required this.eventoId,
    this.subeventoId,
  });

  final String eventoId;
  final String? subeventoId;

  @override
  Widget build(BuildContext context) {
    return RequirePermission(
      allowed: (perfil) => perfil.canCreateContent,
      deniedMessage: 'Solo administradores y organizadores gestionan talleres.',
      builder: (context) =>
          _FormularioSubevento(eventoId: eventoId, subeventoId: subeventoId),
    );
  }
}

class _FormularioSubevento extends ConsumerStatefulWidget {
  const _FormularioSubevento({required this.eventoId, this.subeventoId});

  final String eventoId;
  final String? subeventoId;

  @override
  ConsumerState<_FormularioSubevento> createState() =>
      _FormularioSubeventoState();
}

class _FormularioSubeventoState extends ConsumerState<_FormularioSubevento> {
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _descripcion = TextEditingController();
  final _sala = TextEditingController();
  final _expositor = TextEditingController();
  final _cupo = TextEditingController();
  final _orden = TextEditingController(text: '0');
  DateTime? _dia;
  TimeOfDay _inicio = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _fin = const TimeOfDay(hour: 11, minute: 0);
  bool _visible = true;
  bool _guardando = false;
  bool _cargado = false;

  bool get _edicion => widget.subeventoId != null;

  bool get _horarioInvalido =>
      _fin.hour * 60 + _fin.minute <= _inicio.hour * 60 + _inicio.minute;

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    _sala.dispose();
    _expositor.dispose();
    _cupo.dispose();
    _orden.dispose();
    super.dispose();
  }

  void _cargar(Subevento taller) {
    if (_cargado) return;
    _cargado = true;
    _nombre.text = taller.nombre;
    _descripcion.text = taller.descripcion ?? '';
    _sala.text = taller.sala ?? '';
    _expositor.text = taller.expositor ?? '';
    _cupo.text = taller.cupoMaximo?.toString() ?? '';
    _orden.text = taller.orden.toString();
    _dia = taller.dia;
    _inicio = taller.horaInicio;
    _fin = taller.horaFin;
    _visible = taller.visiblePublico;
  }

  Future<void> _elegirHora({required bool inicio}) async {
    final hora = await showTimePicker(
      context: context,
      initialTime: inicio ? _inicio : _fin,
    );
    if (hora == null || !mounted) return;
    setState(() {
      if (inicio) {
        _inicio = hora;
      } else {
        _fin = hora;
      }
    });
  }

  Future<void> _guardar(Evento evento) async {
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
    final taller = Subevento(
      id: widget.subeventoId ?? '',
      eventoId: widget.eventoId,
      codigo: '',
      nombre: _nombre.text.trim(),
      descripcion: _descripcion.text.trim().isEmpty
          ? null
          : _descripcion.text.trim(),
      dia: _dia ?? evento.fecha,
      horaInicio: _inicio,
      horaFin: _fin,
      sala: _sala.text.trim().isEmpty ? null : _sala.text.trim(),
      expositor: _expositor.text.trim().isEmpty ? null : _expositor.text.trim(),
      cupoMaximo: int.tryParse(_cupo.text.trim()),
      orden: int.tryParse(_orden.text.trim()) ?? 0,
      visiblePublico: _visible,
    );
    try {
      final repo = ref.read(subeventosRepositoryProvider);
      final mapa = taller.toInsertMap()..remove('evento_id');
      if ((mapa['codigo'] as String?)?.isEmpty ?? true) mapa.remove('codigo');
      if (_edicion) {
        await repo.actualizar(widget.subeventoId!, mapa);
      } else {
        await repo.crear(taller);
      }
      _invalidarTalleres(ref, widget.eventoId);
      if (mounted) context.pop();
    } on RpeException catch (error) {
      if (mounted) showAppSnackBar(context, error.mensaje, isError: true);
    } catch (error) {
      if (mounted) showAppSnackBar(context, error.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hayRed = ref.watch(isOnlineProvider);
    final eventoAsync = ref.watch(eventoByIdProvider(widget.eventoId));
    final existente = widget.subeventoId == null
        ? null
        : ref.watch(subeventosPorEventoProvider(widget.eventoId));
    existente?.whenData((lista) {
      final actual = lista.where((t) => t.id == widget.subeventoId).firstOrNull;
      if (actual != null) _cargar(actual);
    });
    final evento = eventoAsync.valueOrNull;
    final editable = !_guardando && hayRed;
    return AppScaffold(
      title: _edicion ? 'Editar taller' : 'Nuevo taller',
      actions: [
        if (_edicion && evento != null)
          NexusHeaderAction(
            icon: Symbols.delete_outline_rounded,
            tooltip: 'Eliminar taller',
            danger: true,
            onTap: editable ? () => _borrar(evento) : null,
          ),
      ],
      bottomBar: evento == null
          ? null
          : FormActionBar(
              label: _edicion ? 'Guardar cambios' : 'Crear taller',
              loading: _guardando,
              onPressed: editable ? () => _guardar(evento) : null,
            ),
      body: eventoAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(message: error.toString()),
        data: (evento) {
          final dias = _diasDelEvento(evento);
          _dia ??= dias.first;
          return AbsorbPointer(
            absorbing: _guardando,
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  TwSpacing.screenH,
                  14,
                  TwSpacing.screenH,
                  28,
                ),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  FormNotice('Taller de ${evento.nombre}'),
                  const SizedBox(height: FormSection.gap),
                  FormSection(
                    icon: Symbols.info_rounded,
                    title: 'Información del taller',
                    children: [
                      FormLabeledField(
                        label: 'Nombre',
                        child: TextFormField(
                          controller: _nombre,
                          enabled: editable,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'Ej. Liderazgo en equipos remotos',
                          ),
                          validator: (valor) {
                            final texto = valor?.trim() ?? '';
                            if (texto.length < 2 || texto.length > 150) {
                              return 'Entre 2 y 150 caracteres.';
                            }
                            return null;
                          },
                        ),
                      ),
                      FormLabeledField(
                        label: 'Expositor',
                        opcional: true,
                        child: TextFormField(
                          controller: _expositor,
                          enabled: editable,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            hintText: 'Nombre de quien lo dicta',
                            prefixIcon: Icon(Symbols.person_rounded, size: 20),
                          ),
                          validator: (valor) => (valor ?? '').length > 120
                              ? 'Máximo 120 caracteres.'
                              : null,
                        ),
                      ),
                      FormLabeledField(
                        label: 'Descripción',
                        opcional: true,
                        child: TextFormField(
                          controller: _descripcion,
                          enabled: editable,
                          minLines: 3,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'De qué trata el taller',
                          ),
                          validator: (valor) => (valor ?? '').length > 2000
                              ? 'Máximo 2000 caracteres.'
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: FormSection.gap),
                  FormSection(
                    icon: Symbols.schedule_rounded,
                    title: 'Día y horario',
                    children: [
                      FormLabeledField(
                        label: 'Día',
                        child: DropdownButtonFormField<DateTime>(
                          // El taller puede llegar después del primer frame:
                          // la clave rehace el campo con el día cargado.
                          key: ValueKey(_cargado),
                          initialValue: _dia,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(
                              Symbols.calendar_today_rounded,
                              size: 20,
                            ),
                          ),
                          items: [
                            for (final dia in dias)
                              DropdownMenuItem(
                                value: dia,
                                child: Text(
                                  DateFormat(
                                    "EEEE d 'de' MMMM",
                                    'es',
                                  ).format(dia),
                                ),
                              ),
                          ],
                          onChanged: editable
                              ? (dia) => setState(() => _dia = dia)
                              : null,
                        ),
                      ),
                      FormFieldRow(
                        minWidth: 260,
                        left: FormLabeledField(
                          label: 'Inicio',
                          child: FormPickerField(
                            valor: _inicio.format(context),
                            placeholder: '',
                            icon: Symbols.schedule_rounded,
                            enabled: editable,
                            error: _horarioInvalido,
                            onTap: () => _elegirHora(inicio: true),
                          ),
                        ),
                        right: FormLabeledField(
                          label: 'Término',
                          child: FormPickerField(
                            valor: _fin.format(context),
                            placeholder: '',
                            icon: Symbols.schedule_rounded,
                            enabled: editable,
                            error: _horarioInvalido,
                            onTap: () => _elegirHora(inicio: false),
                          ),
                        ),
                      ),
                      if (_horarioInvalido)
                        const FormNotice(
                          'El término debe ser posterior al inicio.',
                          error: true,
                        ),
                    ],
                  ),
                  const SizedBox(height: FormSection.gap),
                  FormSection(
                    icon: Symbols.meeting_room_rounded,
                    title: 'Sala y cupo',
                    children: [
                      FormFieldRow(
                        minWidth: 280,
                        left: FormLabeledField(
                          label: 'Sala',
                          opcional: true,
                          child: TextFormField(
                            controller: _sala,
                            enabled: editable,
                            decoration: const InputDecoration(
                              hintText: 'Ej. Salón B',
                            ),
                            validator: (valor) => (valor ?? '').length > 120
                                ? 'Máximo 120 caracteres.'
                                : null,
                          ),
                        ),
                        right: FormLabeledField(
                          label: 'Cupo',
                          opcional: true,
                          child: TextFormField(
                            controller: _cupo,
                            enabled: editable,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: 'Sin límite',
                            ),
                            validator: (valor) {
                              final texto = valor?.trim() ?? '';
                              if (texto.isEmpty) return null;
                              final cupo = int.tryParse(texto);
                              if (cupo == null || cupo <= 0) {
                                return 'Debe ser mayor que 0.';
                              }
                              return null;
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: FormSection.gap),
                  FormSection(
                    icon: Symbols.language_rounded,
                    title: 'Publicación',
                    children: [
                      FormToggleRow(
                        icon: Symbols.visibility_rounded,
                        title: 'Visible en la web',
                        subtitle: 'Los asistentes pueden inscribirse en línea.',
                        value: _visible,
                        onChanged: editable
                            ? (valor) => setState(() => _visible = valor)
                            : null,
                      ),
                      const FormDivider(),
                      FormLabeledField(
                        label: 'Orden en el día',
                        opcional: true,
                        ayuda:
                            'Desempata talleres que empiezan a la misma hora.',
                        child: TextFormField(
                          controller: _orden,
                          enabled: editable,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(hintText: '0'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _borrar(Evento evento) async {
    if (!requireOnline(context, ref)) return;
    final ocupacion = ref
        .read(ocupacionEventoProvider(widget.eventoId))
        .valueOrNull;
    final item = ocupacion?.subeventos[widget.subeventoId];
    final ok = await confirmDialog(
      context,
      title: 'Eliminar taller',
      message:
          'Tiene ${item?.inscritos ?? 0} inscritos y ${item?.asistentes ?? 0} asistentes. Se borran sus inscripciones.',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref
          .read(subeventosRepositoryProvider)
          .eliminar(widget.subeventoId!);
      _invalidarTalleres(ref, widget.eventoId);
      if (mounted) context.pop();
    } on RpeException catch (error) {
      if (mounted) showAppSnackBar(context, error.mensaje, isError: true);
    }
  }

  List<DateTime> _diasDelEvento(Evento evento) {
    return [
      for (var i = 0; i < evento.duracionDias; i++)
        DateTime(evento.fecha.year, evento.fecha.month, evento.fecha.day + i),
    ];
  }
}
