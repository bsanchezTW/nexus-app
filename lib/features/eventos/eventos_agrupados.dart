import '../../data/models/evento.dart';
import '../../data/models/subevento.dart';

/// Un evento de la lista con los talleres que agrupa.
class EventoAgrupado {
  const EventoAgrupado({required this.evento, this.talleres = const []});

  final Evento evento;

  /// Talleres del evento, en orden de día, hora y orden manual.
  final List<Subevento> talleres;

  bool get tieneTalleres => talleres.isNotEmpty;
}

/// Cuelga cada taller de su evento principal, respetando el orden de
/// [eventos].
///
/// Un evento de tipo taller que ya se sumó a un principal visible (su id es
/// el `evento_origen_id` de algún taller) no se repite como fila suelta: se
/// ve dentro de su principal. Si el principal no está en la lista (RLS, otro
/// filtro), el taller sigue apareciendo solo para que no se pierda.
List<EventoAgrupado> agruparEventos(
  List<Evento> eventos,
  List<Subevento> subeventos,
) {
  final visibles = {for (final evento in eventos) evento.id};
  final porPrincipal = <String, List<Subevento>>{};
  final absorbidos = <String>{};

  for (final taller in subeventos) {
    if (!visibles.contains(taller.eventoId)) continue;
    porPrincipal.putIfAbsent(taller.eventoId, () => []).add(taller);
    final origen = taller.eventoOrigenId;
    if (origen != null) absorbidos.add(origen);
  }

  for (final lista in porPrincipal.values) {
    lista.sort(_compararTalleres);
  }

  return [
    for (final evento in eventos)
      if (!absorbidos.contains(evento.id))
        EventoAgrupado(
          evento: evento,
          talleres: porPrincipal[evento.id] ?? const [],
        ),
  ];
}

/// Filtra por texto: el grupo entra si coincide el evento (nombre o lugar)
/// o alguno de sus talleres (nombre, sala o expositor). En el segundo caso
/// conviene mostrarlo abierto, para que se vea por qué apareció.
({List<EventoAgrupado> grupos, Set<String> abiertosPorBusqueda})
filtrarGruposPorTexto(List<EventoAgrupado> grupos, String consulta) {
  final q = consulta.trim().toLowerCase();
  if (q.isEmpty) return (grupos: grupos, abiertosPorBusqueda: const {});

  bool contiene(String? texto) => (texto ?? '').toLowerCase().contains(q);

  final resultado = <EventoAgrupado>[];
  final abiertos = <String>{};
  for (final grupo in grupos) {
    final evento = grupo.evento;
    final coincideEvento =
        contiene(evento.nombre) || contiene(evento.lugar ?? evento.pais);
    final coincideTaller = grupo.talleres.any(
      (t) => contiene(t.nombre) || contiene(t.sala) || contiene(t.expositor),
    );
    if (!coincideEvento && !coincideTaller) continue;
    resultado.add(grupo);
    if (coincideTaller) abiertos.add(evento.id);
  }
  return (grupos: resultado, abiertosPorBusqueda: abiertos);
}

int _compararTalleres(Subevento a, Subevento b) {
  final dia = a.dia.compareTo(b.dia);
  if (dia != 0) return dia;
  final hora =
      (a.horaInicio.hour * 60 + a.horaInicio.minute) -
      (b.horaInicio.hour * 60 + b.horaInicio.minute);
  if (hora != 0) return hora;
  return a.orden.compareTo(b.orden);
}
