import 'package:sqlite3/sqlite3.dart';

import '../core/app_failure.dart';
import 'app_database.dart';
import 'models.dart';

/// Datos del emisor que aparecen en el recibo, ancho del papel y la impresora
/// elegida.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  OwnerSettings load() {
    final rows = _db.rows(
      'SELECT issuer_name, issuer_id, issuer_address, issuer_phone, '
      'printer_name, printer_transport, printer_target, receipt_prefix, '
      'receipt_width_mm, receipt_margin_mm, ascii_only, '
      'printer_printable_dots, printer_margin_dots, printer_baud_rate, '
      'backup_export_dir '
      'FROM owner_settings WHERE id = 1',
    );
    if (rows.isEmpty) {
      final defaults = const OwnerSettings.empty();
      save(defaults);
      return defaults;
    }
    final row = rows.first;
    final width = (row['receipt_width_mm'] as int?) ?? 80;
    final margin = (row['receipt_margin_mm'] as num?)?.toDouble() ?? 3.5;
    return OwnerSettings(
      issuerName: (row['issuer_name'] as String?) ?? '',
      issuerId: (row['issuer_id'] as String?) ?? '',
      issuerAddress: (row['issuer_address'] as String?) ?? '',
      issuerPhone: (row['issuer_phone'] as String?) ?? '',
      printerName: row['printer_name'] as String?,
      printerTransport: PrinterTransport.parse(
        row['printer_transport'] as String?,
      ),
      printerTarget: row['printer_target'] as String?,
      receiptPrefix: (row['receipt_prefix'] as String?) ?? 'REC',
      receiptWidthMm: width == 58 ? 58 : 80,
      receiptMarginMm: margin <= 0 ? 3.5 : (margin > 15 ? 15 : margin),
      asciiOnly: ((row['ascii_only'] as int?) ?? 0) == 1,
      printerPrintableDots: _clampDots(row['printer_printable_dots'] as int?),
      printerMarginDots: _clampMargin(row['printer_margin_dots'] as int?),
      printerBaudRate: _clampBaud(row['printer_baud_rate'] as int?),
      backupExportDir: (row['backup_export_dir'] as String?) ?? '',
    );
  }

  /// Un valor de calibración fuera de rango es un dato inválido: se descarta
  /// (vuelve a "sin calibrar") en vez de recortar boletas en silencio.
  static int _clampDots(int? value) {
    if (value == null || value < 96 || value > 1200) return 0;
    return value;
  }

  static int _clampBaud(int? value) {
    const valid = [9600, 19200, 38400, 57600, 115200];
    return valid.contains(value) ? value! : 9600;
  }

  /// El margen puede ser pequeño (0 es válido: solo el margen necesario).
  static int _clampMargin(int? value) {
    if (value == null || value < 0 || value > 240) return 0;
    return value;
  }

  void save(OwnerSettings settings) {
    final prefix = settings.receiptPrefix.trim().isEmpty
        ? 'REC'
        : settings.receiptPrefix.trim();
    final margin = settings.receiptMarginMm <= 0
        ? 3.5
        : (settings.receiptMarginMm > 15 ? 15.0 : settings.receiptMarginMm);
    try {
      _db.run(
        'INSERT INTO owner_settings '
        '(id, issuer_name, issuer_id, issuer_address, issuer_phone, printer_name, '
        'printer_transport, printer_target, receipt_prefix, receipt_width_mm, '
        'receipt_margin_mm, ascii_only, printer_printable_dots, '
        'printer_margin_dots, printer_baud_rate, backup_export_dir, updated_at) '
        'VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT (id) DO UPDATE SET '
        'issuer_name = excluded.issuer_name, issuer_id = excluded.issuer_id, '
        'issuer_address = excluded.issuer_address, issuer_phone = excluded.issuer_phone, '
        'printer_name = excluded.printer_name, '
        'printer_transport = excluded.printer_transport, '
        'printer_target = excluded.printer_target, '
        'receipt_prefix = excluded.receipt_prefix, '
        'receipt_width_mm = excluded.receipt_width_mm, '
        'receipt_margin_mm = excluded.receipt_margin_mm, '
        'ascii_only = excluded.ascii_only, '
        'printer_printable_dots = excluded.printer_printable_dots, '
        'printer_margin_dots = excluded.printer_margin_dots, '
        'printer_baud_rate = excluded.printer_baud_rate, '
        'backup_export_dir = excluded.backup_export_dir, '
        'updated_at = excluded.updated_at',
        [
          settings.issuerName.trim(),
          settings.issuerId.trim(),
          settings.issuerAddress.trim(),
          settings.issuerPhone.trim(),
          settings.printerName,
          settings.printerTransport.name,
          settings.printerTarget,
          prefix,
          settings.receiptWidthMm == 58 ? 58 : 80,
          margin,
          settings.asciiOnly ? 1 : 0,
          _clampDots(settings.printerPrintableDots),
          _clampMargin(settings.printerMarginDots),
          _clampBaud(settings.printerBaudRate),
          settings.backupExportDir.trim(),
          DateTime.now().toIso8601String(),
        ],
      );
    } on SqliteException catch (error) {
      throw AppFailure(
        'No se pudieron guardar los datos del negocio.',
        cause: error,
      );
    }
  }
}
