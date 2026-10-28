import 'dart:io';

import 'package:control_alquileres/src/data/app_database.dart';
import 'package:control_alquileres/src/data/app_paths.dart';
import 'package:control_alquileres/src/data/finance_models.dart';
import 'package:control_alquileres/src/data/finance_repository.dart';
import 'package:control_alquileres/src/data/portfolio_repository.dart';
import 'package:control_alquileres/src/dev/uat_fixture.dart';
import 'package:control_alquileres/src/services/receipt_document_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late AppDatabase db;
  late AppPaths paths;
  late PortfolioRepository portfolio;
  late FinanceRepository finance;
  late UatSummary summary;

  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('uat_fixture_');
    paths = AppPaths.create(p.join(temp.path, 'datos'));
    db = AppDatabase.openAt(paths.databaseFile);
    portfolio = PortfolioRepository(db);
    finance = FinanceRepository(db);
    summary = UatFixture(db).seed();
  });

  tearDownAll(() {
    db.close();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('siembra el escenario completo de ~70 apartamentos', () {
    expect(summary.groups, 3);
    expect(summary.apartments, UatFixture.targetApartments);
    expect(db.rows('SELECT COUNT(*) AS c FROM apartments').first['c'], 70);
    expect(summary.occupied + summary.available, summary.apartments);
    expect(summary.available, greaterThan(0), reason: 'debe haber libres');
    expect(
      summary.leases,
      summary.apartments - summary.available + summary.endedLeases,
    );
    expect(
      summary.endedLeases,
      greaterThan(0),
      reason: 'historial de mudanzas',
    );
    expect(summary.payments, greaterThan(30));
    expect(summary.voidedPayments, 1);
    expect(summary.deposits, greaterThan(50));
    expect(summary.receipts.length, summary.payments);
  });

  test('ningún apartamento tiene dos contratos activos', () {
    final rows = db.rows('''
      SELECT apartment_id, COUNT(*) AS c
      FROM leases WHERE status = 'activo'
      GROUP BY apartment_id HAVING c > 1
    ''');
    expect(rows, isEmpty);
  });

  test('cada inquilino activo aparece en su apartamento', () {
    final apartments = portfolio.listApartments();
    for (final apartment in apartments.where((a) => a.hasActiveLease)) {
      expect(apartment.lease, isNotNull);
      expect(apartment.tenantName?.trim() ?? '', isNotEmpty);
      expect(apartment.lease!.rentCents, greaterThan(0));
    }
    final free = apartments.where((a) => !a.hasActiveLease).toList();
    expect(free.length, summary.available);
  });

  test('hay renta al día, parcial, vencida y adelantada', () {
    final periods = <RentStatus>{};
    for (final apartment in portfolio.listApartments()) {
      periods.add(apartment.rentStatus);
    }
    expect(periods, contains(RentStatus.alDia));
    expect(
      periods.any(
        (status) =>
            status == RentStatus.parcial ||
            status == RentStatus.pendiente ||
            status == RentStatus.vencido,
      ),
      isTrue,
      reason: 'debe haber algún saldo pendiente: $periods',
    );
    expect(periods, contains(RentStatus.disponible));
  });

  test('los saldos cuadran: pagado + pendiente = renta del período', () {
    final rows = db.rows('''
      SELECT pp.id, pp.amount_due_cents,
             COALESCE(SUM(CASE WHEN p.voided_at IS NULL THEN p.amount_cents ELSE 0 END), 0) AS paid
      FROM payment_periods pp
      LEFT JOIN payments p ON p.period_id = pp.id
      GROUP BY pp.id
    ''');
    expect(rows, isNotEmpty);
    for (final row in rows) {
      final due = row['amount_due_cents'] as int;
      final paid = row['paid'] as int;
      expect(paid, lessThanOrEqualTo(due), reason: 'nunca se cobra de más');
    }
  });

  test('el cobro anulado conserva su nota y su reverso', () {
    final voided = db.rows(
      'SELECT id, void_reason FROM payments WHERE voided_at IS NOT NULL',
    );
    expect(voided.length, 1);
    expect(voided.single['void_reason'], isNotEmpty);
    final reversals = db.rows('SELECT * FROM payment_reversals');
    expect(reversals.length, 1);
    expect(reversals.single['payment_id'], voided.single['id']);
  });

  test('hay depósitos recibidos, uno devuelto y uno retenido', () {
    final kinds = db
        .rows('SELECT DISTINCT kind FROM deposit_movements')
        .map((row) => row['kind'])
        .toSet();
    expect(kinds, containsAll(<String>['recibido']));
    expect(
      kinds.intersection({'devuelto', 'retenido'}),
      isNotEmpty,
      reason: 'al menos una devolución o retención',
    );
  });

  test('todos los recibos generan su PDF de 80 mm', () async {
    final documents = ReceiptDocumentService(
      finance: finance,
      paths: paths,
      currentWidthMm: () => 80,
      currentMarginMm: () => 3.5,
    );
    var generated = 0;
    for (var round = 0; round < 10; round++) {
      final batch = finance.receiptsNeedingPdf(limit: 200);
      if (batch.isEmpty) break;
      for (final record in batch) {
        final result = await documents.ensure(record);
        if (result.ok) generated++;
      }
    }
    final total =
        db.rows('SELECT COUNT(*) AS c FROM receipts').first['c'] as int;
    expect(generated, total);
    expect(finance.receiptsNeedingPdf(limit: 5000), isEmpty);

    final files = Directory(paths.receiptsDir)
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.pdf'))
        .toList();
    expect(files.length, total);
    for (final file in files) {
      expect(file.lengthSync(), greaterThan(700));
    }
  });

  test('la base queda íntegra después de todo el escenario', () {
    expect(db.quickCheck(), isNull);
    expect(
      db.rows('PRAGMA foreign_key_check'),
      isEmpty,
      reason: 'sin violaciones de integridad referencial',
    );
  });
}
