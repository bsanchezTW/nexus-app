import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/router/refresh_on_visible.dart';
import '../../../core/network/offline_guard.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tw_tokens.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/app_modals.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/nexus_components.dart';
import '../../../data/models/lead_comentario.dart';
import '../../../data/repositories/lead_comentarios_repository.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/capturador_providers.dart';
import '../../../core/widgets/espera_bloqueante.dart';

enum _AccionComentario { editar, borrar }

/// Hilo de comentarios de un lead. Carga al abrir y con pull-to-refresh;
/// entrar, publicar, editar y borrar exigen conexión.
class ComentariosLeadScreen extends ConsumerStatefulWidget {
  const ComentariosLeadScreen({
    super.key,
    required this.eventoId,
    required this.leadId,
    this.desdeEvento,
  });

  final String eventoId;
  final String leadId;
  final String? desdeEvento;

  @override
  ConsumerState<ComentariosLeadScreen> createState() =>
      _ComentariosLeadScreenState();
}

class _ComentariosLeadScreenState extends ConsumerState<ComentariosLeadScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  var _enviando = false;
  var _bloqueoOfflineHecho = false;

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bloqueoOfflineHecho) return;
    _bloqueoOfflineHecho = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (requireOnline(context, ref)) return;
      volverAtras(context);
    });
  }

  Future<void> _recargar() async {
    ref.invalidate(comentariosPorLeadProvider(widget.leadId));
    await ref.read(comentariosPorLeadProvider(widget.leadId).future);
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    final texto = _composer.text.trim();
    if (texto.isEmpty) return;
    if (!requireOnline(context, ref)) return;

    setState(() => _enviando = true);
    await conEspera(context, () async {
      try {
        await ref
            .read(leadComentariosRepositoryProvider)
            .crear(leadId: widget.leadId, cuerpo: texto);
        _composer.clear();
        await _recargar();
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scroll.hasClients) return;
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      } catch (_) {
        if (!mounted) return;
        showAppSnackBar(
          context,
          'No se pudo publicar el comentario.',
          isError: true,
        );
      } finally {
        if (mounted) setState(() => _enviando = false);
      }
    });
  }

  Future<void> _menuComentario(LeadComentario comentario) async {
    if (!requireOnline(context, ref)) return;
    final perfilId = ref.read(currentPerfilProvider).valueOrNull?.id;
    final propio = comentario.esPropio(perfilId);
    final puedeModerar = ref.read(canCreateContentProvider);
    if (!propio && !puedeModerar) return;

    final accion = await showAppModalBottomSheet<_AccionComentario>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.header),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (propio)
              ListTile(
                leading: const Icon(
                  Symbols.edit_rounded,
                  color: AppColors.primary,
                ),
                title: const Text('Editar'),
                onTap: () => Navigator.pop(ctx, _AccionComentario.editar),
              ),
            ListTile(
              leading: const Icon(
                Symbols.delete_rounded,
                color: AppColors.danger,
              ),
              title: const Text(
                'Borrar',
                style: TextStyle(color: AppColors.danger),
              ),
              onTap: () => Navigator.pop(ctx, _AccionComentario.borrar),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || accion == null) return;
    if (accion == _AccionComentario.editar) {
      await _editar(comentario);
      return;
    }
    await _borrar(comentario);
  }

  Future<void> _editar(LeadComentario comentario) async {
    if (!requireOnline(context, ref)) return;
    final texto = await showAppModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      // Hay texto en curso: ni el arrastre ni el toque fuera pueden tirarlo.
      // Se sale con Cancelar o Guardar.
      enableDrag: false,
      isDismissible: false,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.header),
        ),
      ),
      builder: (ctx) => _EditarComentarioSheet(cuerpo: comentario.cuerpo),
    );
    if (texto == null || !mounted) return;
    if (texto.isEmpty || texto == comentario.cuerpo) return;
    try {
      await ref
          .read(leadComentariosRepositoryProvider)
          .editar(comentarioId: comentario.id, cuerpo: texto);
      await _recargar();
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        'No se pudo editar el comentario.',
        isError: true,
      );
    }
  }

  Future<void> _borrar(LeadComentario comentario) async {
    if (!requireOnline(context, ref)) return;
    try {
      await confirmarYEjecutar(
        context,
        title: '¿Borrar comentario?',
        message: 'Esta acción no se puede deshacer.',
        confirmLabel: 'Borrar',
        destructive: true,
        accion: () async {
          await ref
              .read(leadComentariosRepositoryProvider)
              .borrar(comentario.id);
          await _recargar();
        },
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        'No se pudo borrar el comentario.',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final comentariosAsync = ref.watch(
      comentariosPorLeadProvider(widget.leadId),
    );
    final perfilId = ref.watch(currentPerfilProvider).valueOrNull?.id;
    final puedeModerar = ref.watch(canCreateContentProvider);

    return AppScaffold(
      title: 'Comentarios',
      body: Stack(
        children: [
          Positioned.fill(
            child: comentariosAsync.when(
              loading: () => const LoadingView(),
              error: (_, _) => ErrorView(
                message: 'No se pudieron cargar los comentarios.',
                onRetry: _recargar,
              ),
              data: (comentarios) {
                return RefreshIndicator(
                  onRefresh: _recargar,
                  child: comentarios.isEmpty
                      ? LayoutBuilder(
                          builder: (context, constraints) {
                            return ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                  height: constraints.maxHeight,
                                  child: const Padding(
                                    padding: EdgeInsets.only(bottom: 92),
                                    child: EmptyStateView(
                                      message: 'Sé el primero en comentar',
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        )
                      : ListView.builder(
                          controller: _scroll,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 104),
                          itemCount: comentarios.length,
                          itemBuilder: (context, index) {
                            final comentario = comentarios[index];
                            final propio = comentario.esPropio(perfilId);
                            final menu = propio || puedeModerar;
                            return _BurbujaComentario(
                              comentario: comentario,
                              propio: propio,
                              onLongPress: menu
                                  ? () => _menuComentario(comentario)
                                  : null,
                            );
                          },
                        ),
                );
              },
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _ComposerComentario(
              controller: _composer,
              enviando: _enviando,
              onEnviar: _enviar,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditarComentarioSheet extends StatefulWidget {
  const _EditarComentarioSheet({required this.cuerpo});

  final String cuerpo;

  @override
  State<_EditarComentarioSheet> createState() => _EditarComentarioSheetState();
}

class _EditarComentarioSheetState extends State<_EditarComentarioSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.cuerpo);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      // El aire de arriba lo daba el drag handle, ya retirado.
      padding: EdgeInsets.fromLTRB(16, 18, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Editar comentario',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            maxLength: kLeadComentarioMaxCaracteres,
            decoration: const InputDecoration(
              hintText: 'Escribe un comentario',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, _controller.text.trim()),
                  child: const Text('Guardar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComposerComentario extends StatelessWidget {
  const _ComposerComentario({
    required this.controller,
    required this.enviando,
    required this.onEnviar,
  });

  final TextEditingController controller;
  final bool enviando;
  final VoidCallback onEnviar;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Material(
          key: const Key('comentarios_lead_composer_floating'),
          color: TwColors.surface,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: const BorderSide(color: TwColors.border07),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              boxShadow: TwShadows.soft,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 5, 7, 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('comentarios_lead_composer'),
                      controller: controller,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: kLeadComentarioMaxCaracteres,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onEnviar(),
                      decoration: const InputDecoration(
                        hintText: 'Escribe un comentario',
                        counterText: '',
                        filled: false,
                        fillColor: Colors.transparent,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const Key('comentarios_lead_enviar'),
                    tooltip: 'Publicar',
                    onPressed: enviando ? null : onEnviar,
                    style: IconButton.styleFrom(
                      fixedSize: const Size.square(42),
                      minimumSize: const Size.square(42),
                      backgroundColor: TwColors.brand700,
                      disabledBackgroundColor: TwColors.brand700,
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white,
                    ),
                    icon: enviando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Symbols.send_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BurbujaComentario extends StatelessWidget {
  const _BurbujaComentario({
    required this.comentario,
    required this.propio,
    this.onLongPress,
  });

  final LeadComentario comentario;
  final bool propio;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final fecha = comentario.createdAt == null
        ? ''
        : DateFormat(
            'dd/MM/yyyy HH:mm',
          ).format(comentario.createdAt!.toLocal());
    final autor = (comentario.autorNombre ?? '').trim();
    final rol = comentario.rolEtiqueta;
    final alineacion = propio ? Alignment.centerRight : Alignment.centerLeft;
    final radio = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(propio ? 16 : 4),
      bottomRight: Radius.circular(propio ? 4 : 16),
    );
    final tintaMeta = propio
        ? Colors.white.withValues(alpha: 0.72)
        : TwColors.muted;

    return Align(
      alignment: alineacion,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            key: Key('comentario_burbuja_${comentario.id}'),
            onLongPress: onLongPress,
            onSecondaryTap: onLongPress,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: propio ? TwColors.brand700 : TwColors.surface,
                borderRadius: radio,
                border: propio ? null : Border.all(color: TwColors.border07),
                boxShadow: TwShadows.soft,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(
                  crossAxisAlignment: propio
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (autor.isNotEmpty)
                      Text(
                        autor,
                        style: TwText.tileSubtitle.copyWith(
                          color: propio ? Colors.white : TwColors.blueInk,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (rol != null) ...[
                      const SizedBox(height: 4),
                      StatusChip(
                        label: rol,
                        variant: propio
                            ? StatusChipVariant.navy
                            : StatusChipVariant.neutral,
                      ),
                    ],
                    if (autor.isNotEmpty || rol != null)
                      const SizedBox(height: 4),
                    Text(
                      comentario.cuerpo,
                      style: TwText.tileTitle.copyWith(
                        color: propio ? Colors.white : TwColors.ink,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (fecha.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        comentario.fueEditado ? '$fecha · editado' : fecha,
                        style: TwText.tileSubtitle.copyWith(color: tintaMeta),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
