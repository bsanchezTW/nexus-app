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
import '../../../data/models/evento.dart';
import '../../../data/models/subevento.dart';
import '../../../data/offline/offline_availability.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/repositories/eventos_repository.dart';
import '../../../data/repositories/fijados_repository.dart';
import '../../../data/repositories/storage_cleanup_service.dart';
import '../../auth/providers/auth_providers.dart';
import '../../fijados/providers/fijados_providers.dart';
import '../../home/providers/home_featured_providers.dart';
import '../../subeventos/providers/subeventos_providers.dart';
import '../eventos_agrupados.dart';
import '../providers/eventos_providers.dart';
import '../widgets/evento_acceso_button.dart';
import '../widgets/talleres_anidados.dart';

class ListarEventosScreen extends ConsumerStatefulWidget {
  const ListarEventosScreen({super.key});

  @override
  ConsumerState<ListarEventosScreen> createState() =>
      _ListarEventosScreenState();
}

class _ListarEventosScreenState extends ConsumerState<ListarEventosScreen>
    with RefreshOnVisible {
  @override
  String get refreshWhenLocation => RoutePaths.eventos;

  @override
  void onBecomeVisible() {
    ref.invalidate(usuarioEventosAutorizadosProvider);
    ref.invalidate(eventosListProvider);
    ref.invalidate(eventosFijadosProvider);
    ref.invalidate(subeventosTodosProvider);
  }

  final _searchController = TextEditingController();
  String _query = '';
  String _filtro = 'Todos';

  /// Eventos principales con sus talleres desplegados a mano.
  final _abiertos = <String>{};

  /// Grupos que la búsqueda abrió y el usuario volvió a cerrar.
  final _cerrados = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  ({List<EventoAgrupado> grupos, Set<String> abiertosPorBusqueda}) _filtrar(
    List<Evento> eventos,
    List<Subevento> talleres,
    Set<String> fijados,
  ) {
    final ordenados = List<Evento>.from(eventos);
    ordenarEventoListItems(
      items: ordenados,
      fijados: fijados,
      id: (e) => e.id,
      fecha: (e) => e.fecha,
      finalizado: (e) => e.yaOcurrio,
    );

    final grupos = agruparEventos(ordenados, talleres).where((grupo) {
      return switch (_filtro) {
        'Activos' => !grupo.evento.yaOcurrio,
        'Finalizados' => grupo.evento.yaOcurrio,
        _ => true,
      };
    }).toList();

    return filtrarGruposPorTexto(grupos, _query);
  }

  void _abrirTaller(Evento principal, Subevento taller, List<Evento> eventos) {
    final origen = taller.eventoOrigenId;
    if (origen != null && eventos.any((e) => e.id == origen)) {
      context.push(RoutePaths.usarEvento(origen));
      return;
    }
    if (ref.read(canCreateContentProvider)) {
      if (!requireOnline(context, ref)) return;
      context.push(RoutePaths.editarSubevento(principal.id, taller.id));
      return;
    }
    context.push(RoutePaths.usarEvento(principal.id));
  }

  Future<void> _mostrarMenuEvento(Evento evento, Set<String> fijados) async {
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
          await repoFijados.fijarEvento(evento.id);
          ref.invalidate(eventosFijadosProvider);
          ref.invalidate(homeFeaturedItemsProvider);
        } on FijadosLimitException catch (e) {
          if (mounted) showAppSnackBar(context, e.toString(), isError: true);
        } catch (_) {
          if (mounted) {
            showAppSnackBar(
              context,
              'No se pudo fijar el evento.',
              isError: true,
            );
          }
        }
      case EventoListMenuAction.desfijar:
        await repoFijados.desfijarEvento(evento.id);
        ref.invalidate(eventosFijadosProvider);
        ref.invalidate(homeFeaturedItemsProvider);
      case EventoListMenuAction.editar:
        if (!mounted) return;
        context.push(RoutePaths.editarEvento(evento.id));
      case EventoListMenuAction.eliminar:
        if (!requireOnline(context, ref)) return;
        await _eliminarEvento(evento);
    }
  }

  Future<void> _eliminarEvento(Evento evento) async {
    final confirmado = await confirmDialog(
      context,
      title: 'Eliminar evento',
      message:
          'Esta acción no se puede deshacer. ¿Eliminar el evento y sus registrados?',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (!confirmado || !mounted) return;

    try {
      await ref.read(eventosRepositoryProvider).eliminar(evento.id);
      await ref.read(fijadosRepositoryProvider).desfijarEvento(evento.id);
      // La portada del evento se quedó sin dueño: el servidor ya la tiene
      // encolada, acá solo se pide el vaciado.
      await ref.read(storageCleanupServiceProvider).drenar();
      ref.invalidate(eventosListProvider);
      ref.invalidate(eventosFijadosProvider);
      ref.invalidate(homeFeaturedItemsProvider);
      ref.invalidate(eventoByIdProvider(evento.id));
    } on EventoConEventoLeadException catch (e) {
      if (mounted) showAppSnackBar(context, e.toString(), isError: true);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          'No se pudo eliminar el evento.',
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
          hintText: 'Buscar evento…',
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
                    context.push(RoutePaths.crearEvento);
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
        Text('Eventos', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 2),
        const Text(
          'Registre eventos, invite a sus asistentes y acredite su entrada al evento',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        if (total != null && proximos != null) ...[
          const SizedBox(height: 6),
          Text(
            '$total eventos · $proximos próximos',
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
    final eventosAsync = ref.watch(eventosListProvider);
    final fijadosAsync = ref.watch(eventosFijadosProvider);
    final puedeCrear = ref.watch(canCreateContentProvider);
    final esAdmin = ref.watch(isAdminProvider);
    final esUsuario =
        ref.watch(currentPerfilProvider).valueOrNull?.rol.isUsuario ?? false;
    final fijados = fijadosAsync.valueOrNull ?? const <String>{};
    // Los talleres no bloquean la lista: si tardan o fallan, los eventos se
    // ven igual y los grupos aparecen cuando llegan.
    final talleres =
        ref.watch(subeventosTodosProvider).valueOrNull ?? const <Subevento>[];
    // Sin red solo se puede entrar a lo que quedó en disco: la caché conserva
    // el set activo y suelta los eventos vencidos (ver
    // `offline_retention_policy.dart`).
    final sinRed = !ref.watch(isOnlineProvider);
    final cache = ref.watch(offlineReadCacheProvider);

    return CollapsingScrollScaffold(
      title: 'Eventos',
      onRefresh: () => refrescarLecturas(
        ref,
        invalidar: () {
          ref.invalidate(usuarioEventosAutorizadosProvider);
          ref.invalidate(eventosListProvider);
          ref.invalidate(eventosFijadosProvider);
          ref.invalidate(subeventosTodosProvider);
        },
        pendientes: () => [
          ref.read(usuarioEventosAutorizadosProvider.future),
          ref.read(eventosListProvider.future),
          ref.read(eventosFijadosProvider.future),
          ref.read(subeventosTodosProvider.future),
        ],
      ),
      pinnedContent: _buildPinnedControls(puedeCrear: puedeCrear),
      pinnedContentHeight: 112,
      scrollResetToken:
          '${ref.watch(shellTabEpochProvider(ShellTabBranch.eventos))}|$_query|$_filtro|${fijados.length}',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: eventosAsync.when(
              skipLoadingOnReload: true,
              loading: () => _buildHeader(),
              error: (_, _) => _buildHeader(),
              data: (eventos) {
                final grupos = agruparEventos(eventos, talleres);
                final proximos = grupos
                    .where((g) => !g.evento.yaOcurrio)
                    .length;
                return _buildHeader(total: grupos.length, proximos: proximos);
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
                message: 'No se pudieron cargar los eventos.',
                onRetry: () => ref.invalidate(eventosListProvider),
              ),
            ),
          ],
          data: (eventos) {
            final (:grupos, :abiertosPorBusqueda) = _filtrar(
              eventos,
              talleres,
              fijados,
            );
            if (eventos.isEmpty) {
              return [
                SliverFillRemaining(
                  child: EmptyStateView(
                    icon: Icons.event_busy_rounded,
                    message: esUsuario
                        ? 'No tienes eventos asignados. Contacta a un administrador.'
                        : 'Todavía no hay eventos creados.',
                  ),
                ),
              ];
            }
            if (grupos.isEmpty) {
              final porBusqueda = _query.trim().isNotEmpty;
              return [
                SliverFillRemaining(
                  child: EmptyStateView(
                    icon: porBusqueda
                        ? Icons.search_off_rounded
                        : Icons.filter_list_off_rounded,
                    message: porBusqueda
                        ? 'No hay eventos que coincidan con la búsqueda.'
                        : 'No hay eventos en este filtro.',
                  ),
                ),
              ];
            }
            return [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                sliver: SliverList.separated(
                  itemCount: grupos.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final grupo = grupos[index];
                    final evento = grupo.evento;
                    final fijado = fijados.contains(evento.id);
                    final sinCache =
                        sinRed && !eventoDisponibleOffline(cache, evento.id);
                    final abierto =
                        _abiertos.contains(evento.id) ||
                        (abiertosPorBusqueda.contains(evento.id) &&
                            !_cerrados.contains(evento.id));
                    return EventRow(
                      footer: !grupo.tieneTalleres
                          ? null
                          : TalleresAnidados(
                              principal: evento,
                              talleres: grupo.talleres,
                              abierto: abierto,
                              deshabilitado: sinCache,
                              onToggle: () => setState(() {
                                if (abierto) {
                                  _abiertos.remove(evento.id);
                                  _cerrados.add(evento.id);
                                } else {
                                  _abiertos.add(evento.id);
                                  _cerrados.remove(evento.id);
                                }
                              }),
                              onTallerTap: (taller) =>
                                  _abrirTaller(evento, taller, eventos),
                            ),
                      date: evento.fecha,
                      title: evento.nombre,
                      place: evento.lugar ?? evento.pais ?? '',
                      finalizado: evento.yaOcurrio,
                      fijado: fijado,
                      sinCache: sinCache,
                      chip: evento.esTaller
                          ? const StatusChip(
                              label: 'Taller',
                              variant: StatusChipVariant.neutral,
                            )
                          : evento.esMultiDia
                          ? StatusChip(
                              label: evento.etiquetaDuracion,
                              variant: StatusChipVariant.neutral,
                            )
                          : null,
                      onTap: () {
                        if (sinCache) {
                          showOfflineUnavailableToast(context);
                          return;
                        }
                        context.push(RoutePaths.usarEvento(evento.id));
                      },
                      onLongPress: () => _mostrarMenuEvento(evento, fijados),
                      actions: esAdmin
                          ? [
                              EventoAccesoButton(
                                onTap: () {
                                  if (!requireOnline(context, ref)) return;
                                  context.push(
                                    RoutePaths.accesoEvento(evento.id),
                                  );
                                },
                              ),
                            ]
                          : null,
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
