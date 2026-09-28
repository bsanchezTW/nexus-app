import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/router/refresh_on_visible.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/mascara_contacto.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/collapsing_nav.dart';
import '../../../core/widgets/nexus_components.dart';
import '../../../core/widgets/pressable.dart';
import '../../../data/models/inscripcion_subevento.dart';
import '../../../data/models/registrado.dart';
import '../../../data/models/subevento.dart';
import '../../auth/providers/auth_providers.dart';
import '../../registrados/providers/registrados_providers.dart';
import '../../subeventos/providers/inscripciones_providers.dart';
import '../../subeventos/providers/subeventos_providers.dart';

List<Registrado> filtrarRegistradosPorModo({
  required List<Registrado> registrados,
  required List<InscripcionSubevento> inscripciones,
  String? subeventoId,
}) {
  if (subeventoId == null) return registrados;
  final ids = inscripciones
      .where((fila) => fila.subeventoId == subeventoId)
      .map((fila) => fila.registradoId)
      .toSet();
  return [
    for (final registrado in registrados)
      if (ids.contains(registrado.id)) registrado,
  ];
}

class AcreditarConfirmadoScreen extends ConsumerStatefulWidget {
  const AcreditarConfirmadoScreen({super.key, required this.eventoId});

  final String eventoId;

  @override
  ConsumerState<AcreditarConfirmadoScreen> createState() =>
      _AcreditarConfirmadoScreenState();
}

class _AcreditarConfirmadoScreenState
    extends ConsumerState<AcreditarConfirmadoScreen> {
  final _busquedaController = TextEditingController();
  String _busqueda = '';
  String? _subeventoId;

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  Future<void> _marcar(Registrado registrado) async {
    final subeventoId = _subeventoId;
    if (subeventoId == null) return;
    try {
      await persistirAsistenciaSubevento(
        ref,
        eventoId: widget.eventoId,
        registradoId: registrado.id,
        subeventoId: subeventoId,
        accion: 'marcar_asistencia',
      );
      if (mounted) {
        showAppSnackBar(
          context,
          'Asistencia de ${registrado.nombreCompleto} marcada.',
        );
      }
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          'No se pudo marcar la asistencia.',
          isError: true,
        );
      }
    }
  }

  Future<void> _acreditar(Registrado registrado) async {
    final userId = ref.read(currentPerfilProvider).valueOrNull?.id;

    try {
      await persistirAcreditacion(
        ref,
        registrado: registrado,
        acreditado: true,
        acreditadoPorId: userId ?? '',
      );
      if (mounted) {
        showAppSnackBar(context, '${registrado.nombreCompleto} acreditado.');
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 'No se pudo acreditar.', isError: true);
      }
    }
  }

  Widget _buildSearchField({required bool puedeVerContacto}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.input),
        boxShadow: AppColors.shadowRest,
      ),
      child: TextField(
        controller: _busquedaController,
        onChanged: (v) => setState(() => _busqueda = v.trim().toLowerCase()),
        style: const TextStyle(
          fontSize: 14,
          color: AppColors.ink,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: puedeVerContacto
              ? 'Buscar por nombre o email…'
              : 'Buscar por nombre…',
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
  }) {
    return registrados.where((r) {
      if (_busqueda.isEmpty) return true;
      // Sin permiso para ver el contacto tampoco se busca por email: si no, el
      // correo oculto se podría reconstruir por tanteo.
      return r.nombreCompleto.toLowerCase().contains(_busqueda) ||
          (puedeVerContacto && r.email.toLowerCase().contains(_busqueda));
    }).toList();
  }

  void _actualizarRegistrados() {
    ref.invalidate(registradosPorEventoProvider(widget.eventoId));
    ref.invalidate(inscripcionesPorEventoProvider(widget.eventoId));
  }

  Widget _selectorModo({
    required bool puedeVerContacto,
    required List<Subevento> talleres,
  }) {
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: _buildSearchField(puedeVerContacto: puedeVerContacto),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              FilterChip(
                label: const Text('Entrada'),
                selected: _subeventoId == null,
                onSelected: (_) => setState(() => _subeventoId = null),
              ),
              for (final taller in talleres)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: FilterChip(
                    label: Text(taller.nombre),
                    selected: _subeventoId == taller.id,
                    onSelected: (_) => setState(() => _subeventoId = taller.id),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final registradosAsync = ref.watch(
      registradosPorEventoProvider(widget.eventoId),
    );
    final puedeVerContacto = ref.watch(canViewContactDataProvider);
    final talleres =
        ref.watch(subeventosPorEventoProvider(widget.eventoId)).valueOrNull ??
        const <Subevento>[];
    final inscripciones =
        ref.watch(inscripcionesPorEventoProvider(widget.eventoId)).valueOrNull ??
        const <InscripcionSubevento>[];
    final filtrados = registradosAsync.maybeWhen(
      data: (registrados) {
        final delModo = filtrarRegistradosPorModo(
          registrados: registrados,
          inscripciones: inscripciones,
          subeventoId: _subeventoId,
        );
        return _filtrarRegistrados(
          delModo,
          puedeVerContacto: puedeVerContacto,
        );
      },
      orElse: () => const <Registrado>[],
    );
    final listaVacia = registradosAsync.hasValue && filtrados.isEmpty;

    return CollapsingScrollScaffold(
      title: 'Acreditar asistente',
      alwaysShowActions: true,
      overlayLeading: CollapsingNavButton(
        icon: Symbols.arrow_back_rounded,
        tooltip: 'Volver',
        onTap: () => volverAtras(context),
      ),
      pinnedContent: talleres.isEmpty
          ? _buildSearchField(puedeVerContacto: puedeVerContacto)
          : _selectorModo(
              puedeVerContacto: puedeVerContacto,
              talleres: talleres,
            ),
      pinnedContentHeight: talleres.isEmpty ? 60 : 108,
      scrollResetToken: '$_busqueda|$_subeventoId',
      lockScroll: listaVacia,
      onRefresh: () async => _actualizarRegistrados(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: registradosAsync.when(
              loading: () => _buildHeader(),
              error: (_, _) => _buildHeader(),
              data: (registrados) {
                final delModo = filtrarRegistradosPorModo(
                  registrados: registrados,
                  inscripciones: inscripciones,
                  subeventoId: _subeventoId,
                );
                final pendientes = _subeventoId == null
                    ? delModo.where((r) => !r.acreditado).length
                    : inscripciones
                          .where(
                            (fila) =>
                                fila.subeventoId == _subeventoId && !fila.asistio,
                          )
                          .length;
                return _buildHeader(
                  total: delModo.length,
                  pendientes: pendientes,
                  modoTaller: _subeventoId != null,
                );
              },
            ),
          ),
        ),
        ...registradosAsync.when(
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
            final delModo = filtrarRegistradosPorModo(
              registrados: registrados,
              inscripciones: inscripciones,
              subeventoId: _subeventoId,
            );
            final filtrados = _filtrarRegistrados(
              delModo,
              puedeVerContacto: puedeVerContacto,
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
            if (delModo.isEmpty) {
              return [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyStateView(
                    icon: Symbols.group_off_rounded,
                    message: 'Nadie inscrito en este taller.',
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
                    message: 'No se encontraron resultados.',
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
                  itemBuilder: (context, index) => _buildRegistradoTile(
                    filtrados[index],
                    index,
                    puedeVerContacto: puedeVerContacto,
                    inscripciones: inscripciones,
                  ),
                ),
              ),
            ];
          },
        ),
      ],
    );
  }

  Widget _buildHeader({int? total, int? pendientes, bool modoTaller = false}) {
    final detalle = total == null
        ? 'Acreditación manual'
        : modoTaller
        ? '$pendientes pendientes · $total inscritos'
        : '$pendientes pendientes · $total registrados';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Acreditar asistente',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 2),
        Text(
          detalle,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildRegistradoTile(
    Registrado r,
    int index, {
    required bool puedeVerContacto,
    required List<InscripcionSubevento> inscripciones,
  }) {
    final correo = puedeVerContacto ? r.email : enmascararEmail(r.email);
    final asistio = _subeventoId != null &&
        inscripciones.any(
          (fila) =>
              fila.registradoId == r.id &&
              fila.subeventoId == _subeventoId &&
              fila.asistio,
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.shadowRest,
      ),
      child: Row(
        children: [
          AvatarInitials(name: r.nombreCompleto, size: 42, index: index),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.nombreCompleto,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$correo${r.empresa != null && r.empresa!.isNotEmpty ? ' · ${r.empresa}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_subeventoId != null)
            asistio
                ? const StatusChip(
                    label: 'Asistió',
                    variant: StatusChipVariant.success,
                  )
                : Pressable(
                    scale: 0.95,
                    onTap: () => _marcar(r),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: AppColors.headerGradient,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        boxShadow: AppColors.shadowRest,
                      ),
                      child: const Text(
                        'Marcar',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  )
          else if (r.acreditado)
            const StatusChip(
              label: 'Acreditado',
              variant: StatusChipVariant.success,
            )
          else
            Pressable(
              scale: 0.95,
              onTap: () => _acreditar(r),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: AppColors.headerGradient,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: AppColors.shadowRest,
                ),
                child: const Text(
                  'Acreditar',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
