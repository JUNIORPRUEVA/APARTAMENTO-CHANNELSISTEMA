import '../data/app_database.dart';

/// Resultado de las verificaciones silenciosas del arranque.
class StartupReport {
  const StartupReport({
    this.integrityIssue,
    this.pendingDocuments = 0,
    this.recoveredEvents = 0,
  });

  final String? integrityIssue;

  /// Recibos cuyo PDF quedó pendiente/fallido (se regeneran en la Fase 2).
  final int pendingDocuments;

  final int recoveredEvents;

  bool get hasIntegrityIssue => integrityIssue != null;
}

/// Verificaciones al iniciar: integridad de la base y trabajos de documentos
/// que quedaron a medias por un corte de energía.
///
/// No cobra nada, no crea pagos y no bloquea la interfaz: solo informa.
/// La regeneración real de PDF se conecta en la Fase 2; aquí queda el conteo y
/// el registro para que el arranque sea idempotente y auditable.
class StartupService {
  const StartupService(this._db);

  final AppDatabase _db;

  StartupReport run() {
    final integrity = _db.quickCheck();
    if (integrity != null) {
      _db.logEvent('integridad', integrity);
    }

    final pending =
        _db
                .rows(
                  "SELECT COUNT(*) AS c FROM receipts "
                  "WHERE pdf_status IN ('pendiente', 'fallido', 'faltante')",
                )
                .first['c']
            as int;

    if (pending > 0) {
      _db.logEvent(
        'documentos_pendientes',
        '$pending recibos pendientes de PDF (se regeneran sin volver a cobrar).',
      );
    }

    final events =
        _db.rows('SELECT COUNT(*) AS c FROM app_events').first['c'] as int;

    return StartupReport(
      integrityIssue: integrity,
      pendingDocuments: pending,
      recoveredEvents: events,
    );
  }
}
