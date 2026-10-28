import 'dart:async';

/// Fallos de red de peticiones reales, para que `MonitorConexion` degrade sin
/// esperar a su próximo sondeo.
///
/// Es global y no un provider porque la fuente principal es el cliente HTTP de
/// Supabase, que se crea en `main` antes de que exista Riverpod (ver
/// `ObservarFallosDeRedClient`).
///
/// Solo se reportan fallos de transporte y topes que indican una red mala, no
/// la espera corta de la UI: una consulta pesada que tarda más de 5 s con una
/// conexión buena no puede mandar la app a modo sin conexión.
final StreamController<void> _fallos = StreamController<void>.broadcast();

void reportarFalloDeRed() => _fallos.add(null);

Stream<void> get fallosDeRed => _fallos.stream;
