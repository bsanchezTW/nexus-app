import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tw_tokens.dart';
import '../../../core/widgets/app_modals.dart';
import '../../../core/widgets/tw_components.dart';
import '../models/home_featured_item.dart';
import '../providers/orden_carrusel_provider.dart';

/// Hoja "Ordenar" del carrusel del inicio. Cada cambio se guarda al soltar la
/// tarjeta; el orden vale solo para este teléfono.
Future<void> showOrdenarCarruselSheet(
  BuildContext context, {
  required List<HomeFeaturedItem> items,
}) {
  return showAppModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TwColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _OrdenarCarrusel(items: items),
  );
}

class _OrdenarCarrusel extends ConsumerStatefulWidget {
  const _OrdenarCarrusel({required this.items});

  final List<HomeFeaturedItem> items;

  @override
  ConsumerState<_OrdenarCarrusel> createState() => _OrdenarCarruselState();
}

class _OrdenarCarruselState extends ConsumerState<_OrdenarCarrusel> {
  late final List<HomeFeaturedItem> _items = List.of(widget.items);

  void _mover(int desde, int hasta) {
    setState(() {
      final item = _items.removeAt(desde);
      _items.insert(hasta, item);
    });
    ref.read(ordenCarruselProvider.notifier).guardar(_items);
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.7;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: TwSectionLabel('Ordenar inicio', top: 0),
                  ),
                  TextButton(
                    onPressed: () async {
                      await ref
                          .read(ordenCarruselProvider.notifier)
                          .restablecer();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: const Text('Restablecer'),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(19, 0, 16, 8),
              child: Text(
                'Arrastra para cambiar el orden. Solo cambia en este teléfono.',
                style: TwText.tileSubtitle,
              ),
            ),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  // La barra inferior flota sobre la hoja: la lista termina sobre ella.
                  GlassNavTokens.contentBottomInset(context) -
                      MediaQuery.viewPaddingOf(context).bottom,
                ),
                itemCount: _items.length,
                onReorderItem: _mover,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return Padding(
                    key: ValueKey('orden_${item.kind.name}_${item.id}'),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _FilaOrden(item: item, index: index),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaOrden extends StatelessWidget {
  const _FilaOrden({required this.item, required this.index});

  final HomeFeaturedItem item;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: const BoxDecoration(
        color: TwColors.surface,
        borderRadius: TwRadii.card,
        border: Border.fromBorderSide(BorderSide(color: TwColors.border07)),
      ),
      child: Row(
        children: [
          Icon(
            item.esFijado ? Symbols.push_pin_rounded : Symbols.schedule_rounded,
            size: 18,
            color: TwColors.muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TwText.tileTitle,
                ),
                const SizedBox(height: 2),
                Text(
                  '${_capitalizar(item.etiqueta)} · '
                  '${formatearDiaMesCorto(item.fecha)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TwText.tileSubtitle,
                ),
              ],
            ),
          ),
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(
                Symbols.drag_indicator_rounded,
                color: TwColors.muted,
                semanticLabel: 'Arrastrar para ordenar',
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _capitalizar(String texto) {
    final minus = texto.toLowerCase();
    return minus.isEmpty
        ? minus
        : '${minus[0].toUpperCase()}${minus.substring(1)}';
  }
}
