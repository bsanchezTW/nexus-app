import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../constants/duracion_actividad.dart';
import '../theme/tw_tokens.dart';
import 'form_sections.dart';
import 'nexus_components.dart';

/// Fecha de inicio + fecha de término. Al cambiar el inicio, el término
/// vuelve al mismo día (dura 1 día) hasta que el usuario lo mueva.
class CamposFechaInicioTermino extends StatelessWidget {
  const CamposFechaInicioTermino({
    super.key,
    required this.fechaInicio,
    required this.duracionDias,
    required this.textoDuracion,
    required this.onInicioChanged,
    required this.onTerminoChanged,
    this.enabledInicio = true,
    this.enabledTermino = true,
  });

  final DateTime fechaInicio;
  final int duracionDias;
  final String textoDuracion;
  final ValueChanged<DateTime> onInicioChanged;
  final ValueChanged<DateTime> onTerminoChanged;
  final bool enabledInicio;
  final bool enabledTermino;

  DateTime get _fechaTermino =>
      fechaTerminoActividad(fechaInicio, duracionDias);

  Future<void> _elegirInicio(BuildContext context) async {
    final seleccionada = await showDatePicker(
      context: context,
      initialDate: fechaInicio,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (seleccionada != null) onInicioChanged(seleccionada);
  }

  Future<void> _elegirTermino(BuildContext context) async {
    final termino = _fechaTermino;
    final tope = fechaTerminoActividad(fechaInicio, kDuracionActividadMaxDias);
    final seleccionada = await showDatePicker(
      context: context,
      initialDate: termino,
      firstDate: fechaCalendario(fechaInicio),
      lastDate: tope,
    );
    if (seleccionada != null) onTerminoChanged(seleccionada);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormFieldRow(
          left: FormLabeledField(
            label: 'Fecha de inicio',
            child: FechaPickerField(
              fecha: fechaInicio,
              onTap: () => _elegirInicio(context),
              enabled: enabledInicio,
            ),
          ),
          right: FormLabeledField(
            label: 'Fecha de término',
            child: FechaPickerField(
              fecha: _fechaTermino,
              onTap: () => _elegirTermino(context),
              enabled: enabledTermino,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Row(
            children: [
              const Icon(
                Symbols.schedule_rounded,
                size: 15,
                color: TwColors.muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  textoDuracion,
                  style: TwText.tileSubtitle.copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
