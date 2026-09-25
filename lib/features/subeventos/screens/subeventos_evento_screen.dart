import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/errors/rpe_exception.dart';
import '../../../core/network/offline_guard.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/require_permission.dart';
import '../../../data/models/evento.dart';
import '../../../data/models/ocupacion_evento.dart';
import '../../../data/models/subevento.dart';
import '../../../data/repositories/subeventos_repository.dart';
import '../../eventos/providers/eventos_providers.dart';
import '../providers/subeventos_providers.dart';

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

class _ListaSubeventos extends ConsumerWidget {
  const _ListaSubeventos({required this.eventoId});

  final String eventoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final talleres = ref.watch(subeventosPorEventoProvider(eventoId));
    final ocupacion = ref.watch(ocupacionEventoProvider(eventoId));
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
            padding: AppSpacing.form,
            children: [
              for (final entrada in grupos.entries) ...[
                Text(
                  DateFormat('EEEE d MMM', 'es').format(entrada.value.first.dia),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final taller in entrada.value)
                  _TallerTile(
                    taller: taller,
                    ocupacion: ocupacion.valueOrNull?.subeventos[taller.id],
                    onTap: () => context.push(
                      RoutePaths.editarSubevento(eventoId, taller.id),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (lista.isEmpty)
                const Text('Este evento todavía no tiene talleres.'),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (!requireOnline(context, ref)) return;
          context.push(RoutePaths.crearSubevento(eventoId));
        },
        icon: const Icon(Symbols.add_rounded),
        label: const Text('Nuevo taller'),
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
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        onTap: onTap,
        title: Text(taller.nombre),
        subtitle: Text(
          [
            '$inicio–$fin',
            if (taller.sala != null && taller.sala!.isNotEmpty) taller.sala!,
            if (taller.expositor != null && taller.expositor!.isNotEmpty)
              taller.expositor!,
          ].join(' · '),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(cupo == null ? '$inscritos' : '$inscritos/$cupo'),
            if ((ocupacion?.sobrecupo ?? 0) > 0)
              const Text('Sobrecupo', style: TextStyle(color: AppColors.warning)),
            if (!taller.visiblePublico) const Text('No visible en web'),
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
      builder: (context) => _FormularioSubevento(
        eventoId: eventoId,
        subeventoId: subeventoId,
      ),
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

  Future<void> _guardar(Evento evento) async {
    if (!requireOnline(context, ref)) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    final taller = Subevento(
      id: widget.subeventoId ?? '',
      eventoId: widget.eventoId,
      codigo: '',
      nombre: _nombre.text.trim(),
      descripcion: _descripcion.text.trim().isEmpty ? null : _descripcion.text.trim(),
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
        mapa.remove('evento_id');
        await repo.actualizar(widget.subeventoId!, mapa);
      } else {
        mapa['evento_id'] = widget.eventoId;
        await repo.crear(
          Subevento(
            id: '',
            eventoId: widget.eventoId,
            codigo: '',
            nombre: taller.nombre,
            descripcion: taller.descripcion,
            dia: taller.dia,
            horaInicio: taller.horaInicio,
            horaFin: taller.horaFin,
            sala: taller.sala,
            expositor: taller.expositor,
            cupoMaximo: taller.cupoMaximo,
            orden: taller.orden,
            visiblePublico: taller.visiblePublico,
          ),
        );
      }
      ref.invalidate(subeventosPorEventoProvider(widget.eventoId));
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
    final eventoAsync = ref.watch(eventoByIdProvider(widget.eventoId));
    final existente = widget.subeventoId == null
        ? null
        : ref.watch(subeventosPorEventoProvider(widget.eventoId));
    existente?.whenData((lista) {
      final actual = lista.where((t) => t.id == widget.subeventoId).firstOrNull;
      if (actual != null) _cargar(actual);
    });
    return AppScaffold(
      title: _edicion ? 'Editar taller' : 'Nuevo taller',
      body: eventoAsync.when(
        loading: () => const LoadingView(),
        error: (error, _) => ErrorView(message: error.toString()),
        data: (evento) {
          final dias = _diasDelEvento(evento);
          _dia ??= dias.first;
          return Form(
            key: _formKey,
            child: ListView(
              padding: AppSpacing.form,
              children: [
                DropdownButtonFormField<DateTime>(
                  initialValue: _dia,
                  decoration: const InputDecoration(labelText: 'Día'),
                  items: [
                    for (final dia in dias)
                      DropdownMenuItem(
                        value: dia,
                        child: Text(DateFormat('EEE d MMM', 'es').format(dia)),
                      ),
                  ],
                  onChanged: _guardando ? null : (dia) => setState(() => _dia = dia),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _nombre,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (valor) {
                    final texto = valor?.trim() ?? '';
                    if (texto.length < 2 || texto.length > 150) {
                      return 'Entre 2 y 150 caracteres.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Inicio ${_inicio.format(context)}'),
                  onTap: () async {
                    final hora = await showTimePicker(context: context, initialTime: _inicio);
                    if (hora != null) setState(() => _inicio = hora);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Término ${_fin.format(context)}'),
                  onTap: () async {
                    final hora = await showTimePicker(context: context, initialTime: _fin);
                    if (hora != null) setState(() => _fin = hora);
                  },
                ),
                TextFormField(
                  controller: _descripcion,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                  maxLines: 3,
                  validator: (valor) =>
                      (valor ?? '').length > 2000 ? 'Máximo 2000 caracteres.' : null,
                ),
                TextFormField(
                  controller: _sala,
                  decoration: const InputDecoration(labelText: 'Sala'),
                  validator: (valor) =>
                      (valor ?? '').length > 120 ? 'Máximo 120 caracteres.' : null,
                ),
                TextFormField(
                  controller: _expositor,
                  decoration: const InputDecoration(labelText: 'Expositor'),
                  validator: (valor) =>
                      (valor ?? '').length > 120 ? 'Máximo 120 caracteres.' : null,
                ),
                TextFormField(
                  controller: _cupo,
                  decoration: const InputDecoration(labelText: 'Cupo (vacío = sin límite)'),
                  keyboardType: TextInputType.number,
                  validator: (valor) {
                    final texto = valor?.trim() ?? '';
                    if (texto.isEmpty) return null;
                    final cupo = int.tryParse(texto);
                    if (cupo == null || cupo <= 0) return 'El cupo debe ser mayor que 0.';
                    return null;
                  },
                ),
                TextFormField(
                  controller: _orden,
                  decoration: const InputDecoration(labelText: 'Orden'),
                  keyboardType: TextInputType.number,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Visible en la web'),
                  value: _visible,
                  onChanged: (valor) => setState(() => _visible = valor),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: _guardando ? null : () => _guardar(evento),
                  child: Text(_guardando ? 'Guardando…' : 'Guardar'),
                ),
                if (_edicion)
                  TextButton(
                    onPressed: _guardando ? null : () => _borrar(evento),
                    child: const Text('Eliminar taller'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _borrar(Evento evento) async {
    if (!requireOnline(context, ref)) return;
    final ocupacion = ref.read(ocupacionEventoProvider(widget.eventoId)).valueOrNull;
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
      await ref.read(subeventosRepositoryProvider).eliminar(widget.subeventoId!);
      ref.invalidate(subeventosPorEventoProvider(widget.eventoId));
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
