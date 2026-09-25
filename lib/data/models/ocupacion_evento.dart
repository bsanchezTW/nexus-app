class OcupacionItem {
  const OcupacionItem({
    required this.cupoMaximo,
    required this.inscritos,
    required this.asistentes,
    this.sobrecupo = 0,
  });

  final int? cupoMaximo;
  final int inscritos;
  final int asistentes;
  final int sobrecupo;

  int? get disponibles => cupoMaximo == null ? null : cupoMaximo! - inscritos;

  bool get lleno => disponibles != null && disponibles! <= 0;
}

class OcupacionEvento {
  const OcupacionEvento({required this.evento, required this.subeventos});

  final OcupacionItem evento;
  final Map<String, OcupacionItem> subeventos;
}
