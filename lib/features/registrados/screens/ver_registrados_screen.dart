import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/network/connectivity_service.dart';
import '../../../core/network/offline_guard.dart';
import '../../../core/router/refresh_on_visible.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/mascara_contacto.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/app_modals.dart';
import '../../../core/widgets/collapsing_nav.dart';
import '../../../core/widgets/nexus_components.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/selector_filtro_sheet.dart';
import '../../../data/models/inscripcion_subevento.dart';
import '../../../data/models/registrado.dart';
import '../../../data/models/subevento.dart';
import '../../../data/models/resultado_envio_qr.dart';
import '../../../data/offline/sync_queue_service.dart';
import '../../../data/repositories/registrados_repository.dart';
import '../../acreditacion/screens/acreditar_confirmado_screen.dart';
import '../../auth/providers/auth_providers.dart';
import '../../registrados/providers/registrados_providers.dart';
import '../../subeventos/providers/inscripciones_providers.dart';
import '../../subeventos/providers/subeventos_providers.dart';
import '../../../core/widgets/espera_bloqueante.dart';

enum _Filtro { todos, acreditados, pendientes }

class VerRegistradosScreen extends ConsumerStatefulWidget {
  const VerRegistradosScreen({super.key, required this.eventoId});

  final String eventoId;

  @override
  ConsumerState<VerRegistradosScreen> createState() =>
      _VerRegistradosScreenState();
}

class _VerRegistradosScreenState extends ConsumerState<VerRegistradosScreen>
    with RefreshOnVisible {
  @override
  String get refreshWhenLocation => RoutePaths.verRegistrados(widget.eventoId);

  @override
  void onBecomeVisible() {
    ref.invalidate(registradosPorEventoProvider(widget.eventoId));
  }

  _Filtro _filtro = _Filtro.todos;
  String? _tallerFiltro;
  final _busquedaController = TextEditingController();
  String _busqueda = '';
  Timer? _debounce;

  static const _filtroLabels = {
    _Filtro.todos: 'Todos',
    _Filtro.acreditados: 'Acreditados',
    _Filtro.pendientes: 'Pendientes',
  };

  @override
  void dispose() {
    _debounce?.cancel();
    _busquedaController.dispose();
    super.dispose();
  }

  Widget _buildSearchField() {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.input),
        boxShadow: AppColors.shadowRest,
      ),
      child: TextField(
        controller: _busquedaController,
        onChanged: (v) {
          if (_debounce?.isActive ?? false) _debounce!.cancel();
          _debounce = Timer(const Duration(milliseconds: 300), () {
            if (mounted) {
              setState(() => _busqueda = v.trim().toLowerCase());
            }
          });
        },
        style: const TextStyle(
          fontSize: 14,
          color: AppColors.ink,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'Buscar registrado…',
          hintStyle: const TextStyle(color: AppColors.placeholder),
          prefixIcon: const Icon(
            Symbols.search_rounded,
            color: AppColors.placeholder,
            size: 20,
          ),
          filled: true,
          fillColor: AppColors.surface,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
            borderSide: const BorderSide(
              color: AppColors.primaryLight,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  List<Registrado> _filtrarRegistrados(
    List<Registrado> registrados, {
    required bool puedeVerContacto,
    required List<InscripcionSubevento> inscripciones,
  }) {
    final delTaller = filtrarRegistradosPorModo(
      registrados: registrados,
      inscripciones: inscripciones,
      subeventoId: _tallerFiltro,
    );
    return delTaller.where((r) {
      if (_filtro == _Filtro.acreditados && !r.acreditado) {
        return false;
      }
      if (_filtro == _Filtro.pendientes && r.acreditado) return false;
      if (_busqueda.isEmpty) return true;
      // Sin permiso para ver el contacto tampoco se busca por email: si no, el
      // correo oculto se podría reconstruir por tanteo.
      return r.nombreCompleto.toLowerCase().contains(_busqueda) ||
          (puedeVerContacto && r.email.toLowerCase().contains(_busqueda));
    }).toList();
  }

  void _actualizarRegistrados() {
    ref.invalidate(registradosPorEventoProvider(widget.eventoId));
  }

  /// Selector del estado (Todos / Acreditados / Pendientes), con cuántos
  /// asistentes quedan en cada uno dentro del taller elegido.
  Future<void> _elegirEstado(List<Registrado> delTaller) async {
    final acreditados = delTaller.where((r) => r.acreditado).length;
    final elegido = await showSelectorFiltroSheet<_Filtro>(
      context,
      titulo: 'Filtrar por estado',
      seleccionado: _filtro,
      opciones: [
        OpcionFiltro(
          valor: _Filtro.todos,
          titulo: _filtroLabels[_Filtro.todos]!,
          conteo: delTaller.length,
        ),
        OpcionFiltro(
          valor: _Filtro.acreditados,
          titulo: _filtroLabels[_Filtro.acreditados]!,
          conteo: acreditados,
        ),
        OpcionFiltro(
          valor: _Filtro.pendientes,
          titulo: _filtroLabels[_Filtro.pendientes]!,
          conteo: delTaller.length - acreditados,
        ),
      ],
    );
    if (elegido == null || !mounted) return;
    setState(() => _filtro = elegido.valor);
  }

  /// Selector del filtro de talleres, con cuántos inscritos tiene cada uno.
  Future<void> _elegirTaller({
    required List<Subevento> talleres,
    required List<Registrado> registrados,
    required List<InscripcionSubevento> inscripciones,
  }) async {
    final elegido = await showSelectorFiltroSheet<String?>(
      context,
      titulo: 'Filtrar por taller',
      seleccionado: _tallerFiltro,
      opciones: [
        OpcionFiltro(
          valor: null,
          titulo: 'Todos los talleres',
          conteo: registrados.length,
        ),
        for (final taller in talleres)
          OpcionFiltro(
            valor: taller.id,
            titulo: taller.nombre,
            detalle: DateFormat("EEE d MMM '·' HH:mm", 'es').format(
              DateTime(
                taller.dia.year,
                taller.dia.month,
                taller.dia.day,
                taller.horaInicio.hour,
                taller.horaInicio.minute,
              ),
            ),
            conteo: filtrarRegistradosPorModo(
              registrados: registrados,
              inscripciones: inscripciones,
              subeventoId: taller.id,
            ).length,
          ),
      ],
    );
    if (elegido == null || !mounted) return;
    setState(() => _tallerFiltro = elegido.valor);
  }

  Widget _buildPinnedControls() {
    final talleres =
        ref.watch(subeventosPorEventoProvider(widget.eventoId)).valueOrNull ??
        const <Subevento>[];
    final tallerElegido = talleres
        .where((taller) => taller.id == _tallerFiltro)
        .firstOrNull;
    final registrados =
        ref.watch(registradosPorEventoProvider(widget.eventoId)).valueOrNull ??
        const <Registrado>[];
    final inscripciones =
        ref
            .watch(inscripcionesPorEventoProvider(widget.eventoId))
            .valueOrNull ??
        const <InscripcionSubevento>[];
    return Column(
      children: [
        SizedBox(height: 48, child: _buildSearchField()),
        const SizedBox(height: 4),
        Expanded(
          // La fila se desliza hasta el borde de la pantalla: con talleres
          // no cabe entera y, recortada en el margen, la última píldora
          // quedaba cortada sin borde.
          child: LayoutBuilder(
            builder: (context, constraints) => OverflowBox(
              maxWidth: constraints.maxWidth + _margenFiltros * 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: _margenFiltros),
                  child: Row(
                    children: [
                      FiltroDesplegableChip(
                        key: const Key('filtro_estado'),
                        label: _filtro == _Filtro.todos
                            ? 'Estado'
                            : _filtroLabels[_filtro]!,
                        activo: _filtro != _Filtro.todos,
                        onTap: () => _elegirEstado(
                          filtrarRegistradosPorModo(
                            registrados: registrados,
                            inscripciones: inscripciones,
                            subeventoId: _tallerFiltro,
                          ),
                        ),
                      ),
                      if (talleres.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        FiltroDesplegableChip(
                          key: const Key('filtro_talleres'),
                          label: tallerElegido?.nombre ?? 'Talleres',
                          activo: tallerElegido != null,
                          onTap: () => _elegirTaller(
                            talleres: talleres,
                            registrados: registrados,
                            inscripciones: inscripciones,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Margen lateral de la cabecera fija ([CollapsingScrollScaffold.pinnedPadding]).
  static final _margenFiltros = CollapsingScrollScaffold.pinnedPadding.left;

  @override
  Widget build(BuildContext context) {
    final registradosAsync = ref.watch(
      registradosPorEventoProvider(widget.eventoId),
    );
    final puedeVerContacto = ref.watch(canViewContactDataProvider);
    final inscripciones =
        ref
            .watch(inscripcionesPorEventoProvider(widget.eventoId))
            .valueOrNull ??
        const <InscripcionSubevento>[];

    final filtrados = registradosAsync.maybeWhen(
      data: (registrados) => _filtrarRegistrados(
        registrados,
        puedeVerContacto: puedeVerContacto,
        inscripciones: inscripciones,
      ),
      orElse: () => const <Registrado>[],
    );
    final listaVacia = registradosAsync.hasValue && filtrados.isEmpty;

    return CollapsingScrollScaffold(
      title: 'Registrados',
      alwaysShowActions: true,
      overlayLeading: CollapsingNavButton(
        icon: Symbols.arrow_back_rounded,
        tooltip: 'Volver',
        onTap: () => volverAtras(context),
      ),
      pinnedContent: _buildPinnedControls(),
      pinnedContentHeight: 112,
      scrollResetToken: '$_busqueda|$_filtro|$_tallerFiltro',
      lockScroll: listaVacia,
      onRefresh: () async => _actualizarRegistrados(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: registradosAsync.when(
              skipLoadingOnReload: true,
              loading: () => _buildHeader(),
              error: (_, _) => _buildHeader(),
              data: (registrados) => _buildHeader(
                total: registrados.length,
                acreditados: registrados.where((r) => r.acreditado).length,
              ),
            ),
          ),
        ),
        ...registradosAsync.when(
          skipLoadingOnReload: true,
          loading: () => [
            const SliverFillRemaining(
              hasScrollBody: false,
              child: LoadingView(),
            ),
          ],
          error: (e, _) => [
            SliverFillRemaining(
              child: ErrorView(
                message: 'No se pudo cargar la lista.',
                onRetry: () => ref.invalidate(
                  registradosPorEventoProvider(widget.eventoId),
                ),
              ),
            ),
          ],
          data: (registrados) {
            final filtrados = _filtrarRegistrados(
              registrados,
              puedeVerContacto: puedeVerContacto,
              inscripciones: inscripciones,
            );

            if (registrados.isEmpty) {
              return [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyStateView(
                    icon: Symbols.group_off_rounded,
                    message: 'Aún no hay asistentes registrados.',
                    onRefresh: _actualizarRegistrados,
                  ),
                ),
              ];
            }
            if (filtrados.isEmpty) {
              return [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyStateView(
                    icon: Symbols.search_off_rounded,
                    message: 'No hay registrados con estos filtros.',
                    onRefresh: _actualizarRegistrados,
                  ),
                ),
              ];
            }

            return [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                sliver: SliverList.separated(
                  itemCount: filtrados.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.cardGap),
                  itemBuilder: (context, index) => _RegistradoTile(
                    registrado: filtrados[index],
                    eventoId: widget.eventoId,
                    index: index,
                  ),
                ),
              ),
            ];
          },
        ),
      ],
    );
  }

  Widget _buildHeader({int? total, int? acreditados}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Registrados', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 2),
        Text(
          total == null
              ? 'Asistentes del evento'
              : '$total ${total == 1 ? 'registrado' : 'registrados'} · '
                    '$acreditados acreditados',
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _RegistradoTile extends ConsumerWidget {
  const _RegistradoTile({
    required this.registrado,
    required this.eventoId,
    required this.index,
  });

  final Registrado registrado;
  final String eventoId;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final puedeVerContacto = ref.watch(canViewContactDataProvider);

    // Siempre se puede abrir: la pantalla de edición lee de esta misma lista
    // y sabe encolar los cambios de una fila que aún no llegó al servidor.
    return Pressable(
      onTap: () =>
          context.push(RoutePaths.editarRegistrado(eventoId, registrado.id)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
          boxShadow: AppColors.shadowRest,
        ),
        child: Row(
          children: [
            AvatarInitials(
              name: registrado.nombreCompleto,
              size: 42,
              index: index,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    registrado.nombreCompleto,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      puedeVerContacto
                          ? registrado.email
                          : enmascararEmail(registrado.email),
                      registrado.empresa,
                    ].where((s) => s != null && s.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusChip(
                        label: registrado.acreditado
                            ? 'Acreditado'
                            : 'Pendiente',
                        variant: registrado.acreditado
                            ? StatusChipVariant.success
                            : StatusChipVariant.warning,
                      ),
                      if (registrado.pendienteDeSincronizar)
                        const StatusChip(
                          label: 'Sin sync',
                          variant: StatusChipVariant.danger,
                        ),
                      // Antes eran íconos sueltos pegados a los botones de la
                      // derecha; ahora son parte de la fila de estado.
                      if (registrado.emailConfirmacionEnviado ||
                          registrado.smsConfirmacionEnviado)
                        _ChipQrEnviado(
                          email: registrado.emailConfirmacionEnviado,
                          sms: registrado.smsConfirmacionEnviado,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Mismo chip que el botón de acreditar de al lado: antes era un
            // IconButton pelado, con ripple y 48 de alto, y desalineaba la fila.
            Tooltip(
              message: 'Código QR de acreditación',
              child: Pressable(
                scale: 0.9,
                onTap: () => _mostrarQr(context, ref),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.tintNavy,
                    borderRadius: BorderRadius.circular(AppRadius.tile),
                  ),
                  child: const Icon(
                    Symbols.qr_code_2_rounded,
                    size: 20,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: registrado.acreditado ? 'Acreditado' : 'Acreditar',
              child: Pressable(
                key: Key('registrado_acreditar_${registrado.id}'),
                scale: 0.9,
                onTap: () => _onTapAcreditar(context, ref),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: registrado.acreditado
                        ? AppColors.successTint
                        : AppColors.tintNavy,
                    borderRadius: BorderRadius.circular(AppRadius.tile),
                  ),
                  child: Icon(
                    Symbols.confirmation_number_rounded,
                    size: 20,
                    color: registrado.acreditado
                        ? AppColors.success
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onTapAcreditar(BuildContext context, WidgetRef ref) async {
    if (registrado.acreditado) {
      try {
        final quitada = await confirmarYEjecutar(
          context,
          title: 'Quitar acreditación',
          message:
              '¿Deseas quitar la acreditación de ${registrado.nombreCompleto}?',
          confirmLabel: 'Quitar',
          destructive: true,
          accion: () => persistirAcreditacion(
            ref,
            registrado: registrado,
            acreditado: false,
            acreditadoPorId: '',
          ),
        );
        if (quitada && context.mounted) {
          showAppSnackBar(
            context,
            'Se quitó la acreditación de ${registrado.nombreCompleto}.',
          );
        }
      } catch (e) {
        if (context.mounted) {
          showAppSnackBar(
            context,
            'No se pudo quitar la acreditación.',
            isError: true,
          );
        }
      }
      return;
    }

    final userId = ref.read(currentPerfilProvider).valueOrNull?.id;

    try {
      final acreditado = await confirmarYEjecutar(
        context,
        title: 'Acreditar asistente',
        message: '¿Deseas acreditar a ${registrado.nombreCompleto}?',
        confirmLabel: 'Acreditar',
        accion: () => persistirAcreditacion(
          ref,
          registrado: registrado,
          acreditado: true,
          acreditadoPorId: userId ?? '',
        ),
      );
      if (acreditado && context.mounted) {
        showAppSnackBar(context, '${registrado.nombreCompleto} acreditado.');
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, 'No se pudo acreditar.', isError: true);
      }
    }
  }

  void _mostrarQr(BuildContext context, WidgetRef ref) {
    showAppModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      constraints: BoxConstraints(
        maxWidth: 520,
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.header),
        ),
      ),
      builder: (context) =>
          _QrSheet(registrado: registrado, eventoId: eventoId),
    );
  }
}

/// "QR enviado" con el canal por el que salió (correo, SMS o ambos). Solo
/// íconos y del alto de [StatusChip]: con texto no cabía junto al estado,
/// bajaba a otra línea y la tarjeta crecía.
class _ChipQrEnviado extends StatelessWidget {
  const _ChipQrEnviado({required this.email, required this.sms});

  final bool email;
  final bool sms;

  @override
  Widget build(BuildContext context) {
    final canales = [if (email) 'email', if (sms) 'SMS'].join(' y ');
    return Tooltip(
      message: 'QR enviado por $canales',
      child: Semantics(
        label: 'QR enviado por $canales',
        child: Container(
          key: const Key('chip_qr_enviado'),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.tintNavy,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (email)
                const Icon(
                  Symbols.mark_email_read_rounded,
                  size: 14,
                  color: AppColors.primary,
                ),
              if (email && sms) const SizedBox(width: 4),
              if (sms)
                const Icon(
                  Symbols.sms_rounded,
                  size: 14,
                  color: AppColors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// QR de acreditación de un registrado (codifica `registrados.id`, lo que
/// lee `AcreditarQrScreen`). Permite enviarlo por email y SMS vía
/// la Edge Function `enviar-qr`.

class _QrSheet extends ConsumerStatefulWidget {
  const _QrSheet({required this.registrado, required this.eventoId});

  final Registrado registrado;
  final String eventoId;

  @override
  ConsumerState<_QrSheet> createState() => _QrSheetState();
}

class _QrSheetState extends ConsumerState<_QrSheet> {
  bool _enviandoEmail = false;
  bool _enviandoSms = false;

  bool get _ocupado => _enviandoEmail || _enviandoSms;

  String _correoVisible({required bool puedeVerContacto}) {
    final correo = widget.registrado.email;
    return puedeVerContacto ? correo : enmascararEmail(correo);
  }

  String _telefonoVisible({required bool puedeVerContacto}) {
    final telefono = widget.registrado.telefono?.trim() ?? '';
    if (telefono.isEmpty) return '';
    return puedeVerContacto ? telefono : enmascararTelefono(telefono);
  }

  /// Nombres de los talleres en que está inscrito el asistente.
  List<String> _talleresInscritos(Registrado registrado) {
    final talleres =
        ref.watch(subeventosPorEventoProvider(widget.eventoId)).valueOrNull ??
        const [];
    final inscripciones =
        ref
            .watch(inscripcionesPorEventoProvider(widget.eventoId))
            .valueOrNull ??
        const [];
    final propios = inscripciones
        .where((fila) => fila.registradoId == registrado.id)
        .map((fila) => fila.subeventoId)
        .toSet();
    return [
      for (final taller in talleres)
        if (propios.contains(taller.id)) taller.nombre,
    ];
  }

  void _editarTalleres() {
    final destino = RoutePaths.editarRegistrado(
      widget.eventoId,
      widget.registrado.id,
    );
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(destino);
  }

  Future<void> _regenerar() async {
    if (!requireOnline(context, ref)) return;
    try {
      final regenerado = await confirmarYEjecutar(
        context,
        title: 'Regenerar QR',
        message: 'El código anterior dejará de servir. ¿Continuar?',
        confirmLabel: 'Regenerar',
        accion: () => ref
            .read(registradosRepositoryProvider)
            .regenerarCodigoQr(widget.registrado.id),
      );
      if (!regenerado) return;
      ref.invalidate(registradosPorEventoProvider(widget.eventoId));
      if (mounted) showAppSnackBar(context, 'Nuevo QR en camino');
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      }
    }
  }

  Future<void> _enviar({required String canal}) async {
    if (!requireOnline(context, ref)) return;
    final puedeVerContacto = ref.read(canViewContactDataProvider);
    setState(() {
      if (canal == CanalesEnvioQr.email) {
        _enviandoEmail = true;
      } else {
        _enviandoSms = true;
      }
    });
    try {
      final resultado = await ref
          .read(registradosRepositoryProvider)
          .enviarQr(widget.registrado.id, canales: [canal]);
      ref.invalidate(registradosPorEventoProvider(widget.eventoId));
      if (!mounted) return;
      final canalResultado = canal == CanalesEnvioQr.email
          ? resultado.email
          : resultado.sms;
      _mostrarResultadoCanal(
        resultado: canalResultado,
        canal: canal,
        destinoVisible: canal == CanalesEnvioQr.email
            ? _correoVisible(puedeVerContacto: puedeVerContacto)
            : _telefonoVisible(puedeVerContacto: puedeVerContacto),
      );
    } catch (e) {
      if (mounted) {
        debugPrint('enviar-qr ($canal) falló: $e');
        showAppSnackBar(
          context,
          canal == CanalesEnvioQr.email
              ? 'No se pudo enviar el QR por email. Intenta de nuevo en unos minutos.'
              : 'No se pudo enviar el QR por SMS. Intenta de nuevo en unos minutos.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _enviandoEmail = false;
          _enviandoSms = false;
        });
      }
    }
  }

  void _mostrarResultadoCanal({
    required ResultadoCanalQr resultado,
    required String canal,
    required String destinoVisible,
  }) {
    if (resultado.enviado) {
      Navigator.of(context).pop();
      final porSms = canal == CanalesEnvioQr.sms;
      showAppSnackBar(
        context,
        porSms
            ? (destinoVisible.isEmpty
                  ? 'QR enviado por SMS.'
                  : 'QR enviado por SMS a $destinoVisible.')
            : 'QR enviado a $destinoVisible.',
      );
      return;
    }
    if (resultado.omitido) {
      final motivo = switch (resultado.reason) {
        'sin_telefono' => 'Este asistente no tiene teléfono.',
        'sin_email' => 'Este asistente no tiene email.',
        'sin_acceso_qr' => 'Este evento no envía QR por SMS.',
        _ => 'No se envió el QR.',
      };
      showAppSnackBar(context, motivo);
      return;
    }
    showAppSnackBar(
      context,
      canal == CanalesEnvioQr.sms
          ? (resultado.mensajeBrevo.isEmpty
                ? 'No se pudo enviar el QR por SMS.'
                : resultado.mensajeBrevo)
          : (resultado.mensajeBrevo.isEmpty
                ? 'No se pudo enviar el QR por email.'
                : resultado.mensajeBrevo),
      isError: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(isOnlineProvider);
    final puedeVerContacto = ref.watch(canViewContactDataProvider);
    final r = widget.registrado;
    // Un registro que solo existe en la cola local todavía no tiene id real
    // en el servidor: su QR no serviría para acreditar ni para el email. Se
    // mira el id y no la insignia de pendiente, porque una fila ya
    // sincronizada que solo tiene una edición en cola sí tiene QR válido.
    final soloEnLaCola = esIdSoloLocal(r.id);
    final puedeEnviar = isOnline && !soloEnLaCola && !_ocupado;
    final telefonoVisible = _telefonoVisible(
      puedeVerContacto: puedeVerContacto,
    );
    final talleres = _talleresInscritos(r);
    final puedeEditarTalleres = isOnline && !soloEnLaCola;
    final puedeRegenerar = ref.watch(canCreateContentProvider) && !soloEnLaCola;

    return LayoutBuilder(
      builder: (context, constraints) {
        final qrSize = (constraints.maxWidth - AppSpacing.screenH * 2 - 64)
            .clamp(160.0, 240.0);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            0,
            AppSpacing.screenH,
            AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pase del asistente: sus datos y el QR en una sola tarjeta,
              // como lo vería en la entrada.
              Container(
                key: const Key('qr_pase'),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.border),
                  boxShadow: AppColors.shadowRest,
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                      child: Row(
                        children: [
                          AvatarInitials(name: r.nombreCompleto, size: 48),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.nombreCompleto,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _correoVisible(
                                    puedeVerContacto: puedeVerContacto,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                if (telefonoVisible.isNotEmpty)
                                  Text(
                                    telefonoVisible,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    StatusChip(
                                      label: r.acreditado
                                          ? 'Acreditado'
                                          : 'Pendiente',
                                      variant: r.acreditado
                                          ? StatusChipVariant.success
                                          : StatusChipVariant.warning,
                                    ),
                                    StatusChip(
                                      key: const Key('qr_talleres'),
                                      label: switch (talleres.length) {
                                        0 => 'Sin talleres',
                                        1 => '1 taller',
                                        final n => '$n talleres',
                                      },
                                      variant: StatusChipVariant.neutral,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (talleres.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            talleres.join(' · '),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    const Divider(height: 1, color: AppColors.border),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: soloEnLaCola
                          ? const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'Este registro aún no se sincroniza con el '
                                'servidor; su QR estará disponible cuando '
                                'vuelva la conexión.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.warning,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          : Column(
                              children: [
                                QrImageView(
                                  data: r.codigoQr,
                                  size: qrSize,
                                  backgroundColor: Colors.white,
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Código de acceso al evento',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _BotonSecundarioQr(
                      icono: Symbols.event_note_rounded,
                      texto: 'Editar talleres',
                      onTap: puedeEditarTalleres ? _editarTalleres : null,
                    ),
                  ),
                  if (puedeRegenerar) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: _BotonSecundarioQr(
                        icono: Symbols.autorenew_rounded,
                        texto: 'Regenerar QR',
                        onTap: puedeEnviar ? _regenerar : null,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              PrimaryGradientButton(
                // El envío por SMS no está disponible: solo correo.
                label: r.emailConfirmacionEnviado
                    ? 'Reenviar por correo'
                    : 'Enviar por correo',
                loading: _enviandoEmail,
                onPressed: puedeEnviar
                    ? () => _enviar(canal: CanalesEnvioQr.email)
                    : null,
              ),
              if (!isOnline)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    kMensajeSinConexion,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Botón secundario de la hoja del QR (Editar talleres, Regenerar QR): mismo
/// alto y estilo, lado a lado.
class _BotonSecundarioQr extends StatelessWidget {
  const _BotonSecundarioQr({
    required this.icono,
    required this.texto,
    required this.onTap,
  });

  final IconData icono;
  final String texto;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final habilitado = onTap != null;
    return Opacity(
      opacity: habilitado ? 1 : 0.5,
      child: Pressable(
        scale: 0.97,
        onTap: onTap,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.tintNavy,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icono, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  texto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
