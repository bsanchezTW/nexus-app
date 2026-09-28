import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/inscripcion_subevento.dart';
import '../../../data/models/subevento.dart';
import '../../registrados/providers/registrados_providers.dart';
import '../../subeventos/providers/inscripciones_providers.dart';
import '../../subeventos/providers/subeventos_providers.dart';

class KpiSubevento {
  const KpiSubevento({
    required this.subevento,
    required this.inscritos,
    required this.asistentes,
    required this.cupo,
    required this.porcentajeAsistencia,
    required this.sobrecupo,
  });

  final Subevento subevento;
  final int inscritos;
  final int asistentes;
  final int? cupo;
  final double porcentajeAsistencia;
  final int sobrecupo;
}

class KpiData {
  const KpiData({
    required this.total,
    required this.acreditados,
    required this.pendientesDeSync,
    required this.porcentaje,
    required this.topEmpresas,
    required this.talleres,
  });

  final int total;
  final int acreditados;
  final int pendientesDeSync;
  final double porcentaje;
  final List<MapEntry<String, int>> topEmpresas;
  final List<KpiSubevento> talleres;
}

/// Cuenta cada taller en una sola pasada sobre las inscripciones en caché.
List<KpiSubevento> calcularKpisTalleres({
  required List<Subevento> subeventos,
  required List<InscripcionSubevento> inscripciones,
}) {
  final porTaller = <String, List<InscripcionSubevento>>{};
  for (final fila in inscripciones) {
    porTaller.putIfAbsent(fila.subeventoId, () => []).add(fila);
  }
  final ordenados = [...subeventos]..sort(_compararSubeventos);
  return [
    for (final taller in ordenados)
      _kpiDe(taller, porTaller[taller.id] ?? const []),
  ];
}

KpiSubevento _kpiDe(Subevento taller, List<InscripcionSubevento> filas) {
  final inscritos = filas.length;
  final asistentes = filas.where((fila) => fila.asistio).length;
  return KpiSubevento(
    subevento: taller,
    inscritos: inscritos,
    asistentes: asistentes,
    cupo: taller.cupoMaximo,
    porcentajeAsistencia: inscritos == 0 ? 0 : asistentes / inscritos,
    sobrecupo: filas.where((fila) => fila.sobrecupo).length,
  );
}

int _compararSubeventos(Subevento a, Subevento b) {
  final dia = DateTime(a.dia.year, a.dia.month, a.dia.day).compareTo(
    DateTime(b.dia.year, b.dia.month, b.dia.day),
  );
  if (dia != 0) return dia;
  final hora = _minutos(a.horaInicio) - _minutos(b.horaInicio);
  if (hora != 0) return hora;
  final orden = a.orden.compareTo(b.orden);
  if (orden != 0) return orden;
  return a.nombre.compareTo(b.nombre);
}

int _minutos(TimeOfDay hora) => hora.hour * 60 + hora.minute;

final kpiDataPorEventoProvider = FutureProvider.autoDispose
    .family<KpiData, String>((ref, eventoId) async {
      final registrados = await ref.watch(
        registradosPorEventoProvider(eventoId).future,
      );
      final subeventos = await ref.watch(
        subeventosPorEventoProvider(eventoId).future,
      );
      final inscripciones = await ref.watch(
        inscripcionesPorEventoProvider(eventoId).future,
      );

      final total = registrados.length;
      final acreditados = registrados.where((r) => r.acreditado).length;
      final pendientesDeSync = registrados
          .where((r) => r.pendienteDeSincronizar)
          .length;
      final porcentaje = total == 0 ? 0.0 : acreditados / total;

      final porEmpresa = <String, int>{};
      for (final r in registrados) {
        final empresa = (r.empresa ?? '').trim();
        if (empresa.isEmpty) continue;
        porEmpresa[empresa] = (porEmpresa[empresa] ?? 0) + 1;
      }

      final topEmpresas = porEmpresa.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return KpiData(
        total: total,
        acreditados: acreditados,
        pendientesDeSync: pendientesDeSync,
        porcentaje: porcentaje,
        topEmpresas: topEmpresas,
        talleres: calcularKpisTalleres(
          subeventos: subeventos,
          inscripciones: inscripciones,
        ),
      );
    });
