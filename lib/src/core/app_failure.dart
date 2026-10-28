/// Error de negocio/almacenamiento con un mensaje ya redactado para el usuario
/// final (sin jerga técnica). Las capas de datos lanzan [AppFailure] y la
/// interfaz lo muestra en una notificación breve.
class AppFailure implements Exception {
  const AppFailure(this.message, {this.cause});

  /// Texto listo para mostrar: corto, claro y en español.
  final String message;

  /// Detalle técnico para el registro de eventos (nunca visible al usuario).
  final Object? cause;

  @override
  String toString() => message;
}

/// Traduce excepciones de SQLite a mensajes comprensibles.
AppFailure storageFailure(
  Object error, {
  String fallback = 'No se pudo guardar el cambio.',
}) {
  return AppFailure(fallback, cause: error);
}
