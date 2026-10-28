import 'dart:io';

import 'package:control_alquileres/src/data/app_database.dart';
import 'package:control_alquileres/src/data/app_paths.dart';
import 'package:control_alquileres/src/data/schema.dart';
import 'package:control_alquileres/src/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ca_migracion');
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {
      // Windows puede mantener el archivo bloqueado unos milisegundos.
    }
  });

  group('migración 1 → 2', () {
    late String dbPath;

    setUp(() {
      dbPath = p.join(tempDir.path, 'fase1.sqlite');
      final raw = sqlite3.open(dbPath);
      for (final statement in kSchemaV1Statements) {
        raw.execute(statement);
      }
      raw.execute('PRAGMA user_version = 1');
      raw.execute(
        "INSERT INTO apartment_groups (name, sort_order, is_demo, created_at) "
        "VALUES ('Anamelia', 1, 0, '2026-01-01')",
      );
      raw.execute(
        "INSERT INTO apartments (group_id, identifier, location, rent_cents, "
        "status, is_demo, created_at, updated_at) "
        "VALUES (1, '101', 'Primer nivel', 850000, 'ocupado', 0, 'x', 'x')",
      );
      raw.execute(
        "INSERT INTO tenants (full_name, cedula, phone, notes, is_demo, created_at) "
        "VALUES ('María Pérez', '00112345678', '809-555-0123', '', 0, 'x')",
      );
      raw.execute(
        "INSERT INTO leases (apartment_id, tenant_id, monthly_rent_cents, due_day, "
        "start_date, status, created_at) "
        "VALUES (1, 1, 850000, 5, '2026-01-05', 'activo', 'x')",
      );
      raw.execute(
        "INSERT INTO payment_periods (lease_id, period_year, period_month, amount_due_cents) "
        'VALUES (1, 2026, 1, 850000)',
      );
      raw.execute(
        "INSERT INTO payments (request_id, lease_id, period_id, concept, payment_date, "
        "method, amount_cents, created_at) "
        "VALUES ('req-v1', 1, 1, 'Alquiler', '2026-01-05', 'efectivo', 850000, 'x')",
      );
      raw.execute(
        "INSERT INTO receipts (series, number, payment_id, issued_at, total_cents, "
        "pdf_status) VALUES ('REC', 1, 1, 'x', 850000, 'generado')",
      );
      raw.close();
    });

    test('actualiza la base poblada sin perder datos', () {
      final db = AppDatabase.openAt(dbPath);
      addTearDown(db.close);

      expect(db.userVersion, kSchemaVersion);
      expect(db.quickCheck(), isNull);

      // Datos intactos
      expect(db.rows('SELECT COUNT(*) AS c FROM apartments').first['c'], 1);
      expect(db.rows('SELECT COUNT(*) AS c FROM payments').first['c'], 1);
      final receipt = db.rows('SELECT * FROM receipts').single;
      expect(receipt['number'], 1);
      expect(receipt['kind'], 'alquiler');
      expect(receipt['payment_id'], 1);
      expect(receipt['pdf_status'], 'generado');
      expect(receipt['snapshot_json'], '{}');

      // Columnas nuevas con valores por defecto seguros
      final lease = db.rows('SELECT * FROM leases').single;
      expect(lease['deposit_required_cents'], 0);
      expect(db.rows('SELECT * FROM payment_periods').single['due_date'], '');
      expect(
        db.rows('SELECT * FROM payments').single['balance_after_cents'],
        0,
      );
      final settings = db.rows(
        'SELECT receipt_width_mm, backup_export_dir FROM owner_settings',
      );
      expect(settings, isEmpty); // no había fila todavía

      // Tablas nuevas disponibles
      db.run(
        "INSERT INTO payment_reversals (payment_id, request_id, reason, created_at) "
        "VALUES (1, 'rev-1', 'prueba', 'x')",
      );
      expect(
        db.rows('SELECT COUNT(*) AS c FROM payment_reversals').first['c'],
        1,
      );

      // El recibo ahora admite depósitos (payment_id nulo)
      db.run(
        "INSERT INTO deposit_movements (lease_id, request_id, kind, amount_cents, "
        "movement_date, reason, created_at) "
        "VALUES (1, 'dep-1', 'recibido', 800000, '2026-01-05', '', 'x')",
      );
      final depositId = db.lastInsertId;
      db.run(
        "INSERT INTO receipts (series, number, kind, deposit_id, issued_at, "
        "total_cents, snapshot_json) VALUES ('REC', 2, 'deposito', ?, 'x', 800000, '{}')",
        [depositId],
      );
      expect(db.rows('SELECT COUNT(*) AS c FROM receipts').first['c'], 2);
    });

    test('la migración es idempotente al reabrir', () {
      final first = AppDatabase.openAt(dbPath);
      first.close();
      final second = AppDatabase.openAt(dbPath);
      addTearDown(second.close);
      expect(second.userVersion, kSchemaVersion);
      expect(second.quickCheck(), isNull);
      expect(second.rows('SELECT COUNT(*) AS c FROM receipts').first['c'], 1);
    });
  });

  group('migración 2 → 3', () {
    late String dbPath;

    setUp(() {
      dbPath = p.join(tempDir.path, 'fase2.sqlite');
      final raw = sqlite3.open(dbPath);
      // Base tal como la dejaba la Fase 2: v1 + paso 1 → 2.
      for (final statement in kSchemaV1Statements) {
        raw.execute(statement);
      }
      for (final statement in kMigrationV2Statements) {
        raw.execute(statement);
      }
      raw.execute('PRAGMA user_version = 2');
      raw.execute(
        "INSERT INTO apartment_groups (name, sort_order, is_demo, created_at) "
        "VALUES ('Anamelia', 1, 0, '2026-01-01')",
      );
      raw.execute(
        "INSERT INTO apartments (group_id, identifier, location, rent_cents, "
        "status, is_demo, created_at, updated_at) "
        "VALUES (1, '101', 'Primer nivel', 850000, 'ocupado', 0, 'x', 'x')",
      );
      raw.execute(
        "INSERT INTO tenants (full_name, cedula, phone, notes, is_demo, created_at) "
        "VALUES ('María Pérez', '00112345678', '809-555-0123', '', 0, 'x')",
      );
      raw.execute(
        "INSERT INTO leases (apartment_id, tenant_id, monthly_rent_cents, due_day, "
        "start_date, status, created_at, deposit_required_cents, notes) "
        "VALUES (1, 1, 850000, 5, '2026-01-05', 'activo', 'x', 850000, '')",
      );
      raw.execute(
        "INSERT INTO payment_periods (lease_id, period_year, period_month, "
        "amount_due_cents, due_date) VALUES (1, 2026, 1, 850000, '2026-01-05')",
      );
      raw.execute(
        "INSERT INTO payments (request_id, lease_id, period_id, concept, payment_date, "
        "method, amount_cents, balance_after_cents, note, created_at) "
        "VALUES ('req-v2', 1, 1, 'Alquiler', '2026-01-05', 'transferencia', 850000, 0, 'ok', 'x')",
      );
      raw.execute(
        "INSERT INTO receipts (series, number, kind, payment_id, issued_at, "
        "total_cents, snapshot_json, pdf_status) "
        "VALUES ('REC', 1, 'alquiler', 1, 'x', 850000, '{}', 'generado')",
      );
      raw.execute(
        "INSERT INTO owner_settings (id, issuer_name, printer_name, receipt_prefix, "
        "receipt_width_mm, updated_at) VALUES (1, 'Anamelia Rentas', 'EPSON', 'REC', 80, 'x')",
      );
      raw.close();
    });

    test('agrega referencia de pago y configuración de impresora', () {
      final db = AppDatabase.openAt(dbPath);
      addTearDown(db.close);

      expect(db.userVersion, kSchemaVersion);
      expect(db.quickCheck(), isNull);

      // Nada se pierde.
      expect(db.rows('SELECT COUNT(*) AS c FROM payments').first['c'], 1);
      expect(db.rows('SELECT COUNT(*) AS c FROM receipts').first['c'], 1);

      // Campos nuevos con valores por defecto seguros.
      final payment = db.rows('SELECT * FROM payments').single;
      expect(payment['reference'], '');
      expect(payment['note'], 'ok');

      final settings = db.rows('SELECT * FROM owner_settings').single;
      expect(settings['issuer_name'], 'Anamelia Rentas');
      expect(settings['printer_name'], 'EPSON');
      expect(settings['printer_transport'], 'windows');
      expect(settings['printer_target'], isNull);
      expect(settings['receipt_margin_mm'], 3.5);
      expect(settings['ascii_only'], 0);
    });

    test('acepta una referencia de transferencia después de migrar', () {
      final db = AppDatabase.openAt(dbPath);
      addTearDown(db.close);
      db.run("UPDATE payments SET reference = 'TRF-9911' WHERE id = 1");
      expect(
        db.rows('SELECT reference FROM payments').single['reference'],
        'TRF-9911',
      );
    });

    test('la migración 1 → 3 se aplica completa en un solo arranque', () {
      final v1Path = p.join(tempDir.path, 'fase1-directa.sqlite');
      final raw = sqlite3.open(v1Path);
      for (final statement in kSchemaV1Statements) {
        raw.execute(statement);
      }
      raw.execute('PRAGMA user_version = 1');
      raw.close();

      final db = AppDatabase.openAt(v1Path);
      addTearDown(db.close);
      expect(db.userVersion, kSchemaVersion);
      final columns = db
          .rows('PRAGMA table_info(owner_settings)')
          .map((row) => row['name'])
          .toList();
      expect(columns, contains('printer_transport'));
      expect(columns, contains('receipt_margin_mm'));
      expect(columns, contains('ascii_only'));
      expect(
        db.rows('PRAGMA table_info(payments)').map((row) => row['name']),
        contains('reference'),
      );
    });
  });

  group('migración 3 → 4', () {
    late String dbPath;

    setUp(() {
      dbPath = p.join(tempDir.path, 'fase3.sqlite');
      final raw = sqlite3.open(dbPath);
      // Base tal como la dejaba la Fase 3 (v3).
      for (final statement in kSchemaV1Statements) {
        raw.execute(statement);
      }
      for (final statement in kMigrationV2Statements) {
        raw.execute(statement);
      }
      for (final statement in kMigrationV3Statements) {
        raw.execute(statement);
      }
      raw.execute('PRAGMA user_version = 3');
      raw.execute(
        "INSERT INTO owner_settings (id, issuer_name, printer_name, "
        "printer_transport, printer_target, receipt_prefix, receipt_width_mm, "
        "receipt_margin_mm, ascii_only, updated_at) "
        "VALUES (1, 'Anamelia Rentas', '2C-POS80', 'serial', 'COM5', 'REC', "
        "80, 3.5, 0, 'x')",
      );
      raw.execute(
        "INSERT INTO apartment_groups (name, sort_order, is_demo, created_at) "
        "VALUES ('Anamelia', 1, 0, 'x')",
      );
      raw.close();
    });

    test('agrega el perfil calibrado sin perder la configuración', () {
      final db = AppDatabase.openAt(dbPath);
      addTearDown(db.close);

      expect(db.userVersion, kSchemaVersion);
      expect(db.quickCheck(), isNull);

      final settings = db.rows('SELECT * FROM owner_settings').single;
      expect(settings['issuer_name'], 'Anamelia Rentas');
      expect(settings['printer_name'], '2C-POS80');
      expect(settings['printer_transport'], 'serial');
      expect(settings['printer_target'], 'COM5');
      // Valores nuevos: sin calibrar, sin margen extra, 9600 baudios.
      expect(settings['printer_printable_dots'], 0);
      expect(settings['printer_margin_dots'], 0);
      expect(settings['printer_baud_rate'], 9600);
      expect(
        db.rows('SELECT COUNT(*) AS c FROM apartment_groups').first['c'],
        1,
      );
    });

    test('la migración 1 → 4 se aplica completa en un solo arranque', () {
      final v1Path = p.join(tempDir.path, 'fase1-a-4.sqlite');
      final raw = sqlite3.open(v1Path);
      for (final statement in kSchemaV1Statements) {
        raw.execute(statement);
      }
      raw.execute('PRAGMA user_version = 1');
      raw.close();

      final db = AppDatabase.openAt(v1Path);
      addTearDown(db.close);
      expect(db.userVersion, kSchemaVersion);
      final columns = db
          .rows('PRAGMA table_info(owner_settings)')
          .map((row) => row['name'])
          .toList();
      expect(
        columns,
        containsAll(<String>[
          'printer_printable_dots',
          'printer_margin_dots',
          'printer_baud_rate',
        ]),
      );
      expect(db.quickCheck(), isNull);
    });
  });

  group('copia de seguridad y restauración', () {
    test('la copia es consistente con WAL y se puede abrir (restaurar)', () {
      final paths = AppPaths.create(p.join(tempDir.path, 'datos'));
      final db = AppDatabase.openAt(paths.databaseFile);
      addTearDown(db.close);

      db.run(
        "INSERT INTO apartment_groups (name, sort_order, is_demo, created_at) "
        "VALUES ('Anamelia', 1, 0, 'x')",
      );
      db.run(
        "INSERT INTO apartments (group_id, identifier, location, rent_cents, "
        "status, is_demo, created_at, updated_at) "
        "VALUES (1, '101', '', 850000, 'disponible', 0, 'x', 'x')",
      );
      // Archivo de recibo simulado dentro de la carpeta de recibos.
      File(
        p.join(paths.receiptsDir, 'REC-00000001.pdf'),
      ).writeAsStringSync('%PDF-1.4 recibo de prueba');

      final backup = BackupService(database: db, paths: paths);
      final report = backup.runNow();

      expect(Directory(report.path).existsSync(), isTrue);
      expect(report.copiedReceipts, 1);
      expect(report.bytes, greaterThan(0));

      final copyPath = p.join(report.path, 'control_alquileres.sqlite');
      expect(File(copyPath).existsSync(), isTrue);
      expect(
        File(p.join(report.path, 'recibos', 'REC-00000001.pdf')).existsSync(),
        isTrue,
      );

      // Verificación de la copia: se abre como base independiente (restauración)
      final restored = AppDatabase.openAt(copyPath);
      addTearDown(restored.close);
      expect(restored.userVersion, kSchemaVersion);
      expect(restored.quickCheck(), isNull);
      expect(
        restored.rows('SELECT COUNT(*) AS c FROM apartments').first['c'],
        1,
      );
      expect(restored.rows('PRAGMA foreign_keys').first.values.first, 1);

      expect(backup.lastRun, isNotNull);
      expect(backup.isDue, isFalse);
    });

    test('conserva las últimas 14 copias', () {
      final paths = AppPaths.create(p.join(tempDir.path, 'datos2'));
      final db = AppDatabase.openAt(paths.databaseFile);
      addTearDown(db.close);
      final backup = BackupService(database: db, paths: paths);

      for (var i = 0; i < 16; i++) {
        final folder = Directory(
          p.join(
            paths.backupsDir,
            'copia-20260101-0000${i.toString().padLeft(2, '0')}',
          ),
        )..createSync(recursive: true);
        File(
          p.join(folder.path, 'control_alquileres.sqlite'),
        ).writeAsStringSync('x');
      }
      backup.runNow();
      expect(backup.list().length, lessThanOrEqualTo(14));
    });
  });
}
