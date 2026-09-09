import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/constants/fijados_limits.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/network/offline_guard.dart';
import '../../../core/router/refresh_on_visible.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/evento_list_sort.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/collapsing_nav.dart';
import '../../../core/widgets/evento_list_context_menu.dart';
import '../../../core/widgets/nexus_components.dart';
import '../../../core/widgets/shell_tab_scroll.dart';
import '../../../core/widgets/tw_components.dart';
import '../../../data/models/evento_lead.dart';
import '../../../data/offline/offline_availability.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/repositories/eventos_leads_repository.dart';
import '../../../data/repositories/fijados_repository.dart';
import '../../../data/repositories/storage_cleanup_service.dart';
import '../../auth/providers/auth_providers.dart';
import '../../fijados/providers/fijados_providers.dart';
import '../../home/providers/home_featured_providers.dart';
import '../providers/capturador_providers.dart';

class ListarEventosLeadsScreen extends ConsumerStatefulWidget {
  const ListarEventosLeadsScreen({super.key});

  @override
  ConsumerState<ListarEventosLeadsScreen> createState() =>
      _ListarEventosLeadsScreenState();
}

class _ListarEventosLeadsScreenState
    extends ConsumerState<ListarEventosLeadsScreen>
    with RefreshOnVisible {
  @override
  String get refreshWhenLocation => RoutePaths.capturador;

  @override
  void onBecomeVisible() {
    ref.invalidate(eventosLeadsListProvider);
    ref.invalidate(campanasFijadasProvider);
  }

  final _searchController = TextEditingController();
  String _query = '';
  String _filtro = 'Todos';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<EventoLead> _filtrar(List<EventoLead> eventos, Set<String> fijados) {
    final porEstado = switch (_filtro) {
      'Activos' => eventos.where((e) => !e.yaOcurrio).toList(),
      'Finalizados' => eventos.where((e) => e.yaOcurrio).toList(),
      _ => List<EventoLead>.from(eventos),
    };

    final q = _query.trim().toLowerCase();
    final filtrados = q.isEmpty
        ? porEstado
        : porEstado.where((e) {
            final pais = (e.pais ?? '').toLowerCase();
            final tematica = (e.tematica ?? '').toLowerCase();
            return e.nombre.toLowerCase().contains(q) ||
                pais.contains(q) ||
                tematica.contains(q);
          }).toList();

    ordenarEventoListItems(
      items: filtrados,
      fijados: fijados,
      id: (e) => e.id,
      fecha: (e) => e.fecha,
      finalizado: (e) => e.yaOcurrio,
    );
    return filtrados;
  }

  Future<void> _mostrarMenuEventoLead(
    EventoLead evento,
    Set<String> fijados,
  ) async {
    final puedeEditar = ref.read(canCreateContentProvider);
    final puedeEliminar = ref.read(isAdminProvider);
    final fijado = fijados.contains(evento.id);

    final accion = await showEventoListContextMenu(
      context,
      titulo: evento.nombre,
      fijado: fijado,
      puedeEditar: puedeEditar,
      puedeEliminar: puedeEliminar,
    );
    if (!mounted || accion == null) return;

    final repoFijados = ref.read(fijadosRepositoryProvider);
    switch (accion) {
      case EventoListMenuAction.fijar:
        try {
          await repoFijados.fijarCampana(evento.id);
          ref.invalidate(campanasFijadasProvider);
          ref.invalidate(homeFeaturedItemsProvider);
        } on FijadosLimitException catch (e) {
          if (mounted) showAppSnackBar(context, e.toString(), isError: true);
        } catch (_) {
          if (mounted) {
            showAppSnackBar(
              context,
              'No se pudo fijar la actividad.',
              isError: true,
            );
          }
        }
      case EventoListMenuAction.desfijar:
        await repoFijados.desfijarCampana(evento.id);
        ref.invalidate(campanasFijadasProvider);
        ref.invalidate(homeFeaturedItemsProvider);
      case EventoListMenuAction.editar:
        if (!mounted) return;
        context.push(RoutePaths.editarEventoLead(evento.id));
      case EventoListMenuAction.eliminar:
        if (!requireOnline(context, ref)) return;
        await _eliminarEventoLead(evento);
    }
  }

  Future<void> _eliminarEventoLead(EventoLead evento) async {
    final confirmado = await confirmDialog(
      context,
      title: 'Eliminar actividad',
      message:
          'Esta acción no se puede deshacer. ¿Eliminar la actividad de captura?',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (!confirmado || !mounted) return;

    try {
      await ref.read(eventosLeadsRepositoryProvider).eliminar(evento.id);
      await ref.read(storageCleanupServiceProvider).drenar();
      await ref.read(fijadosRepositoryProvider).desfijarCampana(evento.id);
      ref.invalidate(eventosLeadsListProvider);
      ref.invalidate(campanasFijadasProvider);
      ref.invalidate(homeFeaturedItemsProvider);
      ref.invalidate(eventoLeadByIdProvider(evento.id));
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          'No se pudo eliminar la actividad.',
          isError: true,
        );
      }
    }
  }

  Widget _buildSearchField() {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.input),
        boxShadow: AppColors.shadowRest,
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _query = v),
        style: const TextStyle(
          fontSize: 14,
          color: AppColors.ink,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'Buscar actividad…',
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

  Widget _buildPinnedControls({required bool puedeCrear}) {
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              Expanded(child: _buildSearchField()),
              if (puedeCrear) ...[
                const SizedBox(width: 8),
                PinnedSearchActionButton(
                  icon: Symbols.add_rounded,
                  onTap: () {
                    if (!requireOnline(context, ref)) return;
                    context.push(RoutePaths.crearEventoLead);
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: FilterChipBar(
                options: const ['Todos', 'Activos', 'Finalizados'],
                selected: _filtro,
                onSelected: (v) => setState(() => _filtro = v),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader({int? total, int? proximos}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Captura de Leads',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 2),
        const Text(
          'Registre actividades y capture oportunidades potenciales de negocio.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        if (total != null && proximos != null) ...[
          const SizedBox(height: 6),
          Text(
            '$total actividades · $proximos próximas',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final eventosAsync = ref.watch(eventosLeadsListProvider);
    final fijadosAsync = ref.watch(campanasFijadasProvider);
    final puedeCrear = ref.watch(canCreateContentProvider);
    final fijados = fijadosAsync.valueOrNull ?? const <String>{};
    // Sin red solo se entra a lo que quedó en disco: la caché conserva el set
    // activo y suelta lo vencido (ver `offline_retention_policy.dart`).
    final sinRed = !ref.watch(isOnlineProvider);
    final cache = ref.watch(offlineReadCacheProvider);
    final verTodosLosLeads = ref.watch(canViewAllLeadsProvider);

    return CollapsingScrollScaffold(
      title: 'Captura de Leads',
      onRefresh: () => refrescarLecturas(
        ref,
        invalidar: () {
          ref.invalidate(eventosLeadsListProvider);
          ref.invalidate(campanasFijadasProvider);
        },
        pendientes: () => [
          ref.read(eventosLeadsListProvider.future),
          ref.read(campanasFijadasProvider.future),
        ],
      ),
      pinnedContent: _buildPinnedControls(puedeCrear: puedeCrear),
      pinnedContentHeight: 112,
      scrollResetToken:
          '${ref.watch(shellTabEpochProvider(ShellTabBranch.leads))}|$_query|$_filtro|${fijados.length}',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: eventosAsync.when(
              skipLoadingOnReload: true,
              loading: () => _buildHeader(),
              error: (_, _) => _buildHeader(),
              data: (eventos) {
                final proximos = eventos.where((e) => !e.yaOcurrio).length;
                return _buildHeader(total: eventos.length, proximos: proximos);
              },
            ),
          ),
        ),
        ...eventosAsync.when(
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
                message: 'No se pudieron cargar las actividades de captura.',
                onRetry: () => ref.invalidate(eventosLeadsListProvider),
              ),
            ),
          ],
          data: (eventos) {
            final filtrados = _filtrar(eventos, fijados);
            if (eventos.isEmpty) {
              return [
                const SliverFillRemaining(
                  child: EmptyStateView(
                    icon: Icons.person_search_rounded,
                    message: 'Todavía no hay actividades de captura creadas.',
                  ),
                ),
              ];
            }
            if (filtrados.isEmpty) {
              final porBusqueda = _query.trim().isNotEmpty;
              return [
                SliverFillRemaining(
                  child: EmptyStateView(
                    icon: porBusqueda
                        ? Icons.search_off_rounded
                        : Icons.filter_list_off_rounded,
                    message: porBusqueda
                        ? 'No hay actividades que coincidan con la búsqueda.'
                        : 'No hay actividades en este filtro.',
                  ),
                ),
              ];
            }
            return [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                sliver: SliverList.separated(
                  itemCount: filtrados.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final evento = filtrados[index];
                    final fijado = fijados.contains(evento.id);
                    final sinCache =
                        sinRed &&
                        !actividadDisponibleOffline(
                          cache,
                          evento.id,
                          canViewAllLeads: verTodosLosLeads,
                        );
                    return EventRow(
                      date: evento.fecha,
                      title: evento.nombre,
                      place: evento.pais ?? '',
                      finalizado: evento.yaOcurrio,
                      fijado: fijado,
                      sinCache: sinCache,
                      chip: evento.esMultiDia
                          ? Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                TwOriginPill(interno: evento.esInterno),
                                StatusChip(
                                  label: evento.etiquetaDuracion,
                                  variant: StatusChipVariant.neutral,
                                ),
                              ],
                            )
                          : TwOriginPill(interno: evento.esInterno),
                      onTap: () {
                        if (sinCache) {
                          showOfflineUnavailableToast(context);
                          return;
                        }
                        context.push(RoutePaths.usarEventoLead(evento.id));
                      },
                      onLongPress: () =>
                          _mostrarMenuEventoLead(evento, fijados),
                    );
                  },
                ),
              ),
            ];
          },
        ),
      ],
    );
  }
}
