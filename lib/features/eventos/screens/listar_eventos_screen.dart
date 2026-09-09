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
import '../../../data/offline/offline_availability.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../../../data/repositories/eventos_repository.dart';
import '../../../data/repositories/fijados_repository.dart';
import '../../../data/repositories/storage_cleanup_service.dart';
import '../../auth/providers/auth_providers.dart';
import '../../fijados/providers/fijados_providers.dart';
import '../../home/providers/home_featured_providers.dart';
import '../providers/eventos_providers.dart';
import '../widgets/evento_acceso_button.dart';

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
  }

  final _searchController = TextEditingController();
  String _query = '';
  String _filtro = 'Todos';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Evento> _filtrar(List<Evento> eventos, Set<String> fijados) {
    final porEstado = switch (_filtro) {
      'Activos' => eventos.where((e) => !e.yaOcurrio).toList(),
      'Finalizados' => eventos.where((e) => e.yaOcurrio).toList(),
      _ => List<Evento>.from(eventos),
    };

    final q = _query.trim().toLowerCase();
    final filtrados = q.isEmpty
        ? porEstado
        : porEstado.where((e) {
            final lugar = (e.lugar ?? e.pais ?? '').toLowerCase();
            return e.nombre.toLowerCase().contains(q) || lugar.contains(q);
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
        },
        pendientes: () => [
          ref.read(usuarioEventosAutorizadosProvider.future),
          ref.read(eventosListProvider.future),
          ref.read(eventosFijadosProvider.future),
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
                message: 'No se pudieron cargar los eventos.',
                onRetry: () => ref.invalidate(eventosListProvider),
              ),
            ),
          ],
          data: (eventos) {
            final filtrados = _filtrar(eventos, fijados);
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
            if (filtrados.isEmpty) {
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
                  itemCount: filtrados.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final evento = filtrados[index];
                    final fijado = fijados.contains(evento.id);
                    final sinCache =
                        sinRed && !eventoDisponibleOffline(cache, evento.id);
                    return EventRow(
                      date: evento.fecha,
                      title: evento.nombre,
                      place: evento.lugar ?? evento.pais ?? '',
                      finalizado: evento.yaOcurrio,
                      fijado: fijado,
                      sinCache: sinCache,
                      chip: evento.esMultiDia
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
