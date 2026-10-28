/// Cómo está la comunicación con el backend de Supabase.
///
/// No describe el wifi: un teléfono con la interfaz encendida en el wifi de un
/// recinto que no deja salir está [sinInternet], y uno con datos que tardan
/// segundos en responder está [inestable]. Lo decide `MonitorConexion` con
/// sondeos reales al backend.
enum EstadoConexion {
  /// Recién abierta la app, antes del primer sondeo. Se opera como [estable]:
  /// las lecturas ya tienen su propio tope y caen a la copia local si el
  /// servidor no contesta.
  verificando,

  /// El backend responde rápido: lecturas y escrituras van al servidor y la
  /// app recibe cambios en tiempo real.
  estable,

  /// El backend responde, pero lento o a ratos. En las plataformas con copia
  /// local la app pasa a modo sin conexión para no dejar a nadie esperando.
  inestable,

  /// No hay interfaz de red, o ni el backend ni Internet contestan.
  sinInternet,

  /// Hay Internet, pero el backend no contesta o responde con error de
  /// servidor: Supabase caído, pausado o inalcanzable desde esta red. Para la
  /// app es lo mismo que [sinInternet], pero el usuario tiene que saber que
  /// revisar su wifi no lo va a arreglar.
  sinBackend;

  /// La app opera con su copia local (o, en web, avisa del problema).
  bool get degradado => this != verificando && this != estable;

  /// No hay forma de hablar con el servidor, ni lento.
  bool get servidorInalcanzable => this == sinInternet || this == sinBackend;
}
