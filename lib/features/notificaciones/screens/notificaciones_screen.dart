import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tw_tokens.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/tw_components.dart';
import '../../../data/models/notificacion.dart';
import '../../../data/repositories/notificaciones_repository.dart';
import '../notificacion_destino.dart';
import '../providers/notificaciones_providers.dart';

class NotificacionesScreen extends ConsumerStatefulWidget {
  const NotificacionesScreen({super.key});

  @override
  ConsumerState<NotificacionesScreen> createState() =>
      _NotificacionesScreenState();
}

class _NotificacionesScreenState extends ConsumerState<NotificacionesScreen> {
  bool _marcandoTodas = false;
  bool _eliminando = false;
  final Set<String> _seleccionados = {};
  final Set<String> _descartadas = {};

  bool get _modoSeleccion => _seleccionados.isNotEmpty;
  bool get _ocupado => _marcandoTodas || _eliminando;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _marcarTodasAlAbrir());
  }

  Future<void> _marcarTodasAlAbrir() async {
    final lista = ref.read(notificacionesInboxProvider).valueOrNull;
    if (lista == null || lista.isEmpty) return;

    final pendientes = lista.where((n) => !n.leida).map((n) => n.id).toList();
    if (pendientes.isEmpty) return;

    setState(() => _marcandoTodas = true);
    try {
      await ref
          .read(notificacionesRepositoryProvider)
          .marcarTodasLeidas(pendientes);
      ref.invalidate(notificacionesInboxProvider);
    } finally {
      if (mounted) setState(() => _marcandoTodas = false);
    }
  }

  /// Abre lo que la notificación referencia: el hilo del lead comentado o el
  /// evento del registro. Sin destino (evento borrado, campaña eliminada) se
  /// queda en el inbox en vez de navegar a una ruta rota.
  void _abrir(NotificacionInbox notificacion) {
    final destino = destinoDeNotificacion(notificacion);
    if (destino == null) {
      showAppSnackBar(
        context,
        'Esta notificación ya no tiene a dónde llevarte.',
      );
      return;
    }
    context.push(destino);
  }

  void _activarSeleccion(String id) {
    setState(() => _seleccionados.add(id));
  }

  void _alternarSeleccion(String id) {
    setState(() {
      if (_seleccionados.contains(id)) {
        _seleccionados.remove(id);
      } else {
        _seleccionados.add(id);
      }
    });
  }

  Future<void> _descartar(String id) async {
    setState(() {
      _descartadas.add(id);
      _seleccionados.remove(id);
    });
    try {
      await ref.read(notificacionesRepositoryProvider).ocultarNotificaciones([
        id,
      ]);
      ref.invalidate(notificacionesInboxProvider);
    } catch (_) {
      if (!mounted) return;
      setState(() => _descartadas.remove(id));
      showAppSnackBar(
        context,
        'No se pudo eliminar la notificación.',
        isError: true,
      );
    }
  }

  Future<void> _eliminar(List<NotificacionInbox> lista) async {
    if (_ocupado || lista.isEmpty) return;

    final esSeleccion = _seleccionados.isNotEmpty;
    final cantidad = esSeleccion ? _seleccionados.length : lista.length;

    final confirmado = await confirmDialog(
      context,
      title: esSeleccion ? 'Eliminar seleccionadas' : 'Eliminar todas',
      message: esSeleccion
          ? '¿Deseas eliminar $cantidad notificación(es) seleccionada(s)?'
          : '¿Deseas eliminar todas las notificaciones?',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (!confirmado || !mounted) return;

    setState(() => _eliminando = true);
    try {
      final repo = ref.read(notificacionesRepositoryProvider);
      if (esSeleccion) {
        await repo.ocultarNotificaciones(_seleccionados.toList());
      } else {
        await repo.ocultarTodasNotificaciones();
      }
      ref.invalidate(notificacionesInboxProvider);
      if (mounted) {
        setState(() {
          _seleccionados.clear();
          if (!esSeleccion) _descartadas.clear();
        });
      }
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          'No se pudieron eliminar las notificaciones.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _eliminando = false);
    }
  }

  String _formatoFecha(DateTime? fecha) {
    if (fecha == null) return '';
    final local = fecha.toLocal();
    final ahora = DateTime.now();
    final diff = ahora.difference(local);
    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inHours < 1) return 'Hace ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'Hace ${diff.inHours} h';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} d';
    return DateFormat('d MMM · HH:mm', 'es').format(local);
  }

  List<Widget> _accionesCabecera(List<NotificacionInbox> lista) {
    if (lista.isEmpty) {
      if (_marcandoTodas) {
        return [
          const NexusHeaderAction(
            icon: Symbols.delete_outline_rounded,
            loading: true,
            onTap: null,
          ),
        ];
      }
      return const [];
    }

    return [
      NexusHeaderAction(
        icon: Symbols.delete_outline_rounded,
        tooltip: _modoSeleccion ? 'Eliminar seleccionadas' : 'Eliminar todas',
        danger: true,
        loading: _eliminando,
        onTap: _ocupado ? null : () => _eliminar(lista),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final inboxAsync = ref.watch(notificacionesInboxProvider);

    return AppScaffold(
      title: _modoSeleccion ? null : 'Notificaciones',
      titleWidget: _modoSeleccion
          ? Text('${_seleccionados.length} seleccionada(s)')
          : null,
      actions: inboxAsync.maybeWhen(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        data: _accionesCabecera,
        orElse: () => const [],
      ),
      body: inboxAsync.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: 'No se pudieron cargar las notificaciones.',
          onRetry: () => ref.invalidate(notificacionesInboxProvider),
        ),
        data: (lista) {
          final visibles = lista
              .where((item) => !_descartadas.contains(item.id))
              .toList();
          if (visibles.isEmpty) {
            return const EmptyStateView(
              icon: Symbols.notifications_rounded,
              message: 'Sin notificaciones',
            );
          }

          return RefreshIndicator(
            color: TwColors.brand700,
            onRefresh: () async {
              ref.invalidate(notificacionesInboxProvider);
              await ref.read(notificacionesInboxProvider.future);
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(
                TwSpacing.screenH,
                8,
                TwSpacing.screenH,
                32,
              ),
              itemCount: visibles.length,
              itemBuilder: (context, index) {
                final item = visibles[index];
                final hueco = EdgeInsets.only(
                  bottom: index == visibles.length - 1 ? 0 : 12,
                );
                final seleccionada = _seleccionados.contains(item.id);
                final card = _NotificacionCard(
                  notificacion: item,
                  fecha: _formatoFecha(item.createdAt),
                  seleccionada: seleccionada,
                  modoSeleccion: _modoSeleccion,
                  onLongPress: _ocupado
                      ? null
                      : () => _activarSeleccion(item.id),
                  onTap: _ocupado
                      ? null
                      : _modoSeleccion
                      ? () => _alternarSeleccion(item.id)
                      : () => _abrir(item),
                );

                if (_modoSeleccion || _ocupado) {
                  return Padding(padding: hueco, child: card);
                }

                return Dismissible(
                  key: ValueKey(item.id),
                  direction: DismissDirection.horizontal,
                  onDismissed: (_) => _descartar(item.id),
                  background: Padding(
                    padding: hueco,
                    child: const _FondoDescartar(
                      alineacion: Alignment.centerLeft,
                    ),
                  ),
                  secondaryBackground: Padding(
                    padding: hueco,
                    child: const _FondoDescartar(
                      alineacion: Alignment.centerRight,
                    ),
                  ),
                  child: Padding(padding: hueco, child: card),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

IconData _iconoParaTipo(TipoNotificacion tipo) {
  if (tipo.esAcreditacion) return Symbols.verified_rounded;
  if (tipo.esComentario) return Symbols.chat_bubble_rounded;
  return Symbols.person_add_rounded;
}

TwIconBoxStyle _estiloParaTipo(TipoNotificacion tipo) {
  if (tipo.esAcreditacion) return TwIconBoxStyle.greenTint;
  if (tipo.esComentario) return TwIconBoxStyle.purpleTint;
  return TwIconBoxStyle.blueTint;
}

class _FondoDescartar extends StatelessWidget {
  const _FondoDescartar({required this.alineacion});

  final Alignment alineacion;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alineacion,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: const BoxDecoration(
        color: TwColors.dangerTint,
        borderRadius: TwRadii.card,
      ),
      child: const Icon(
        Symbols.delete_rounded,
        color: TwColors.danger,
        size: 22,
      ),
    );
  }
}

class _NotificacionCard extends StatelessWidget {
  const _NotificacionCard({
    required this.notificacion,
    required this.fecha,
    required this.seleccionada,
    required this.modoSeleccion,
    this.onTap,
    this.onLongPress,
  });

  final NotificacionInbox notificacion;
  final String fecha;
  final bool seleccionada;
  final bool modoSeleccion;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final icono = modoSeleccion
        ? (seleccionada
              ? Symbols.check_circle_rounded
              : Symbols.radio_button_unchecked_rounded)
        : _iconoParaTipo(notificacion.tipo);
    final iconStyle = modoSeleccion
        ? (seleccionada ? TwIconBoxStyle.brand : TwIconBoxStyle.blueTint)
        : _estiloParaTipo(notificacion.tipo);

    final contenido = AnimatedContainer(
      duration: AppMotion.toggle,
      curve: AppMotion.ease,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 15, 14, 15),
      decoration: BoxDecoration(
        color: seleccionada ? TwColors.blueTint : TwColors.surface,
        borderRadius: TwRadii.card,
        border: Border.all(
          color: seleccionada ? TwColors.fieldBorderActive : TwColors.border07,
        ),
        boxShadow: TwShadows.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Opacity(
            opacity: notificacion.leida && !modoSeleccion ? 0.78 : 1,
            child: TwIconBox(icono, variant: iconStyle),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notificacion.cuerpo,
                  style: TwText.tileTitle.copyWith(
                    fontWeight: notificacion.leida
                        ? FontWeight.w600
                        : FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                if (fecha.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(fecha, style: TwText.tileSubtitle),
                ],
              ],
            ),
          ),
          if (!notificacion.leida && !modoSeleccion) ...[
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: TwColors.brand700,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null && onLongPress == null) {
      return contenido;
    }

    return Pressable(onTap: onTap, onLongPress: onLongPress, child: contenido);
  }
}
