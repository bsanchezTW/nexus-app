import '../../data/models/evento.dart';
import '../../data/models/subevento.dart';

/// Una sección del selector "Sumar talleres": el evento al que ya están
/// agregados esos talleres, o `null` para los que aún no tienen evento.
typedef GrupoTalleres = ({Evento? evento, List<Evento> talleres});

/// Agrupa los [talleres] (eventos de tipo taller) por el evento principal al
/// que ya están agregados. Un taller queda agregado a un evento cuando un
/// subevento de ese evento apunta a él (`evento_origen_id`); puede estarlo en
/// más de uno, y entonces aparece en cada sección.
///
/// Orden: primero "sin evento" (los que se suelen sumar), luego los eventos
/// del más reciente al más antiguo. Dentro de cada sección, por fecha.
List<GrupoTalleres> agruparTalleresPorEvento({
  required List<Evento> talleres,
  required List<Evento> eventos,
  required List<Subevento> subeventos,
}) {
  final porId = {for (final evento in eventos) evento.id: evento};
  final eventosDeTaller = <String, Set<String>>{};
  for (final subevento in subeventos) {
    final origen = subevento.eventoOrigenId;
    if (origen == null) continue;
    eventosDeTaller.putIfAbsent(origen, () => {}).add(subevento.eventoId);
  }

  final sinEvento = <Evento>[];
  final porEvento = <String, List<Evento>>{};
  for (final taller in talleres) {
    final destinos = [
      for (final id in eventosDeTaller[taller.id] ?? const <String>{})
        if (porId.containsKey(id)) id,
    ];
    if (destinos.isEmpty) {
      sinEvento.add(taller);
      continue;
    }
    for (final id in destinos) {
      porEvento.putIfAbsent(id, () => []).add(taller);
    }
  }

  int porFecha(Evento a, Evento b) => a.fecha.compareTo(b.fecha);
  final principales = [for (final id in porEvento.keys) porId[id]!]
    ..sort((a, b) => b.fecha.compareTo(a.fecha));
  return [
    if (sinEvento.isNotEmpty)
      (evento: null, talleres: sinEvento..sort(porFecha)),
    for (final principal in principales)
      (evento: principal, talleres: porEvento[principal.id]!..sort(porFecha)),
  ];
}
