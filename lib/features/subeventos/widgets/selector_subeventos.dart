import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/evento.dart';
import '../../../data/models/ocupacion_evento.dart';
import '../../../data/models/subevento.dart';

class SelectorSubeventos extends StatelessWidget {
  const SelectorSubeventos({
    super.key,
    required this.subeventos,
    required this.seleccionados,
    required this.onChanged,
    this.ocupacion,
    this.yaInscritos = const {},
    this.permitirSobrecupo = false,
  });

  final List<Subevento> subeventos;
  final OcupacionEvento? ocupacion;
  final Set<String> seleccionados;
  final Set<String> yaInscritos;
  final bool permitirSobrecupo;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final grupos = <String, List<Subevento>>{};
    for (final taller in subeventos) {
      final clave = DateFormat('yyyy-MM-dd').format(taller.dia);
      grupos.putIfAbsent(clave, () => []).add(taller);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final grupo in grupos.entries) ...[
          Text(
            DateFormat('EEE d MMM', 'es').format(grupo.value.first.dia),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final taller in grupo.value)
            _FilaTaller(
              taller: taller,
              ocupacion: ocupacion?.subeventos[taller.id],
              seleccionado: seleccionados.contains(taller.id),
              yaInscrito: yaInscritos.contains(taller.id),
              chocaCon: _nombreChoque(taller),
              permitirSobrecupo: permitirSobrecupo,
              onChanged: (marcado) {
                final siguiente = {...seleccionados};
                if (marcado) {
                  siguiente.add(taller.id);
                } else {
                  siguiente.remove(taller.id);
                }
                onChanged(siguiente);
              },
            ),
        ],
      ],
    );
  }

  String? _nombreChoque(Subevento taller) {
    for (final otro in subeventos) {
      if (otro.id == taller.id) continue;
      final elegido = seleccionados.contains(otro.id) || yaInscritos.contains(otro.id);
      if (elegido && taller.seSuperponeCon(otro)) return otro.nombre;
    }
    return null;
  }
}

class _FilaTaller extends StatelessWidget {
  const _FilaTaller({
    required this.taller,
    required this.seleccionado,
    required this.yaInscrito,
    required this.permitirSobrecupo,
    required this.onChanged,
    this.ocupacion,
    this.chocaCon,
  });

  final Subevento taller;
  final OcupacionItem? ocupacion;
  final bool seleccionado;
  final bool yaInscrito;
  final bool permitirSobrecupo;
  final String? chocaCon;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final termino = taller.yaTermino(DateTime.now());
    final lleno = ocupacion?.lleno ?? false;
    final bloqueado = yaInscrito || termino || chocaCon != null || (lleno && !permitirSobrecupo);
    final inicio = horaATexto(taller.horaInicio)?.substring(0, 5) ?? '';
    final fin = horaATexto(taller.horaFin)?.substring(0, 5) ?? '';
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: yaInscrito || seleccionado,
      onChanged: bloqueado ? null : (valor) => onChanged(valor ?? false),
      title: Text(taller.nombre),
      subtitle: Text(
        [
          '$inicio–$fin',
          if (yaInscrito) 'Ya inscrito',
          if (termino) 'Terminado',
          if (chocaCon != null) 'Choca con $chocaCon',
          if (lleno && permitirSobrecupo) 'Sobrecupo',
          if (lleno && !permitirSobrecupo) 'Sin cupo',
        ].join(' · '),
      ),
    );
  }
}
