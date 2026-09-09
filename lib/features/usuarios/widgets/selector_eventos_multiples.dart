import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/evento.dart';

/// Selector multi-evento con búsqueda y lista.
///
/// En modo creación solo se ofrecen eventos no finalizados.
/// En edición, los ya autorizados siguen visibles aunque hayan finalizado
/// (para poder quitarlos).
class SelectorEventosMultiples extends StatefulWidget {
  const SelectorEventosMultiples({
    super.key,
    required this.eventos,
    required this.seleccionados,
    required this.onChanged,
    this.enabled = true,
    this.soloActivosDisponibles = true,
    this.emptyHelperText = 'Selecciona al menos un evento.',
    this.errorText,
  });

  final List<Evento> eventos;
  final Set<String> seleccionados;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;
  final bool soloActivosDisponibles;
  final String emptyHelperText;
  final String? errorText;

  @override
  State<SelectorEventosMultiples> createState() =>
      _SelectorEventosMultiplesState();
}

class _SelectorEventosMultiplesState extends State<SelectorEventosMultiples> {
  final _busquedaController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  List<Evento> get _candidatos {
    final seleccionados = widget.seleccionados;
    final list =
        widget.eventos.where((e) {
          if (seleccionados.contains(e.id)) return true;
          if (!widget.soloActivosDisponibles) return true;
          return !e.yaOcurrio;
        }).toList()..sort(
          (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
        );
    return list;
  }

  List<Evento> get _filtrados {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _candidatos;
    return _candidatos
        .where((e) => e.nombre.toLowerCase().contains(q))
        .toList();
  }

  void _toggle(String id) {
    if (!widget.enabled) return;
    final next = {...widget.seleccionados};
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _busquedaController,
          enabled: widget.enabled,
          decoration: const InputDecoration(
            hintText: 'Buscar eventos…',
            prefixIcon: Icon(Symbols.search_rounded, size: 20),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 10),
        Container(
          constraints: const BoxConstraints(maxHeight: 280),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: widget.errorText != null
                  ? AppColors.danger
                  : AppColors.border,
            ),
          ),
          child: filtrados.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No hay eventos para mostrar.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              : Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: filtrados.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: AppColors.divider),
                    itemBuilder: (context, index) {
                      final e = filtrados[index];
                      final checked = widget.seleccionados.contains(e.id);
                      final finalizado = e.yaOcurrio;
                      return CheckboxListTile(
                        dense: true,
                        value: checked,
                        onChanged: widget.enabled ? (_) => _toggle(e.id) : null,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(
                          e.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: finalizado && !checked
                                ? AppColors.textTertiary
                                : AppColors.ink,
                          ),
                        ),
                        subtitle: finalizado
                            ? const Text(
                                'Finalizado',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              )
                            : null,
                      );
                    },
                  ),
                ),
        ),
        if (widget.errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.errorText!,
            style: const TextStyle(fontSize: 12, color: AppColors.danger),
          ),
        ] else ...[
          const SizedBox(height: 6),
          Text(
            widget.seleccionados.isEmpty
                ? widget.emptyHelperText
                : '${widget.seleccionados.length} evento'
                      '${widget.seleccionados.length == 1 ? '' : 's'} '
                      'autorizado${widget.seleccionados.length == 1 ? '' : 's'}.',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
