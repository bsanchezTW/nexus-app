import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/constants/supabase_tables.dart';
import '../../../core/network/offline_guard.dart';
import '../../../core/router/refresh_on_visible.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/collapsing_nav.dart';
import '../../../core/widgets/nexus_components.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/require_admin.dart';
import '../../../core/widgets/shell_tab_scroll.dart';
import '../../../data/models/perfil.dart';
import '../../../data/offline/offline_read_cache.dart';
import '../providers/usuarios_providers.dart';

class GestionarUsuariosScreen extends StatelessWidget {
  const GestionarUsuariosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RequireAdmin(builder: (context) => const _GestionarUsuariosBody());
  }
}

class _GestionarUsuariosBody extends ConsumerStatefulWidget {
  const _GestionarUsuariosBody();

  @override
  ConsumerState<_GestionarUsuariosBody> createState() =>
      _GestionarUsuariosBodyState();
}

class _GestionarUsuariosBodyState extends ConsumerState<_GestionarUsuariosBody>
    with RefreshOnVisible {
  @override
  String get refreshWhenLocation => RoutePaths.usuarios;

  @override
  void onBecomeVisible() {
    ref.invalidate(usuariosListProvider);
  }

  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Perfil> _visibles(List<Perfil> usuarios) => usuarios
      .where((u) => u.id != SupabaseTables.perfilUsuarioEliminadoId)
      .toList();

  List<Perfil> _filtrar(List<Perfil> usuarios) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return usuarios;
    return usuarios
        .where(
          (u) =>
              u.nombreCompleto.toLowerCase().contains(q) ||
              u.rol.label.toLowerCase().contains(q),
        )
        .toList();
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
          hintText: 'Buscar usuario…',
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

  Widget _buildPinnedSearch() {
    return Row(
      children: [
        Expanded(child: _buildSearchField()),
        const SizedBox(width: 8),
        PinnedSearchActionButton(
          icon: Symbols.person_add_rounded,
          onTap: () {
            if (!requireOnline(context, ref)) return;
            context.push(RoutePaths.nuevoUsuario);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final usuariosAsync = ref.watch(usuariosListProvider);

    return CollapsingScrollScaffold(
      title: 'Usuarios',
      onRefresh: () => refrescarLecturas(
        ref,
        context: context,
        invalidar: () => ref.invalidate(usuariosListProvider),
        pendientes: () => [ref.read(usuariosListProvider.future)],
      ),
      pinnedSearch: _buildPinnedSearch(),
      pinnedContentHeight: 60,
      scrollResetToken:
          '${ref.watch(shellTabEpochProvider(ShellTabBranch.usuarios))}|$_query',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: usuariosAsync.when(
              skipLoadingOnReload: true,
              loading: () => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Usuarios',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Miembros del equipo',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              error: (_, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Usuarios',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                ],
              ),
              data: (usuarios) {
                final visibles = _visibles(usuarios);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Usuarios',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${visibles.length} ${visibles.length == 1 ? 'miembro del equipo' : 'miembros del equipo'}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        ...usuariosAsync.when(
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
                message: 'No se pudieron cargar los usuarios.',
                onRetry: () => ref.invalidate(usuariosListProvider),
              ),
            ),
          ],
          data: (usuarios) {
            final visibles = _visibles(usuarios);
            final filtrados = _filtrar(visibles);

            if (visibles.isEmpty) {
              return [
                const SliverFillRemaining(
                  child: EmptyStateView(
                    icon: Icons.people_outline_rounded,
                    message: 'No hay usuarios todavía.',
                  ),
                ),
              ];
            }
            if (filtrados.isEmpty) {
              return [
                const SliverFillRemaining(
                  child: EmptyStateView(
                    icon: Icons.search_off_rounded,
                    message: 'No hay usuarios que coincidan con la búsqueda.',
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
                    final usuario = filtrados[index];
                    return _UsuarioRow(usuario: usuario, index: index);
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

class _UsuarioRow extends ConsumerWidget {
  const _UsuarioRow({required this.usuario, required this.index});

  final Perfil usuario;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Pressable(
      onTap: () {
        if (!requireOnline(context, ref)) return;
        context.push(RoutePaths.editarUsuario(usuario.id));
      },
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
            AvatarPerfil(
              nombre: usuario.nombreCompleto,
              fotoUrl: usuario.fotoUrl,
              size: 44,
              index: index,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                usuario.nombreCompleto,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            StatusChip(
              label: usuario.rol.label,
              variant: usuario.isAdmin
                  ? StatusChipVariant.navy
                  : StatusChipVariant.neutral,
            ),
          ],
        ),
      ),
    );
  }
}
