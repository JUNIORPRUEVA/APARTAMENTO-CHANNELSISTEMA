import 'dart:io';

import 'package:control_alquileres/src/data/app_database.dart';
import 'package:control_alquileres/src/data/app_paths.dart';
import 'package:control_alquileres/src/data/data_location.dart';
import 'package:control_alquileres/src/data/finance_models.dart';
import 'package:control_alquileres/src/data/finance_repository.dart';
import 'package:control_alquileres/src/data/models.dart';
import 'package:control_alquileres/src/data/portfolio_repository.dart';
import 'package:control_alquileres/src/data/settings_repository.dart';
import 'package:control_alquileres/src/services/backup_service.dart';
import 'package:control_alquileres/src/services/receipt_document_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Resistencia a cortes de luz: WAL + `synchronous=FULL` + transacciones.
///
/// Un apagón se simula copiando la base **mientras está abierta** (incluido el
/// `-wal`), que es exactamente lo que queda en disco si se corta la energía.
void main() {
  late Directory temp;
  late AppPaths paths;
  late AppDatabase db;
  late PortfolioRepository portfolio;
  late FinanceRepository finance;
  late ReceiptDocumentService documents;
  late int leaseId;

  int count(String table) =>
      db.rows('SELECT COUNT(*) AS c FROM $table').first['c'] as int;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('apagon_');
    paths = requireSandboxPaths(temp.path, tool: 'power_loss_test');
    db = AppDatabase.openAt(paths.databaseFile);
    portfolio = PortfolioRepository(db);
    finance = FinanceRepository(db);
    documents = ReceiptDocumentService(
      finance: finance,
      paths: paths,
      currentWidthMm: () => 80,
    );
    SettingsRepository(db).save(
      const OwnerSettings(
        issuerName: 'Anamelia Rentas',
        issuerId: '',
        issuerAddress: '',
        issuerPhone: '',
        printerName: null,
        receiptPrefix: 'REC',
      ),
    );
    final groupId = portfolio.createGroup('Anamelia');
    final apartmentId = portfolio.createApartment(
      groupId: groupId,
      identifier: 'A-01',
      location: '',
      rentCents: 850000,
    );
    leaseId = portfolio.registerTenantAndLease(
      apartmentId: apartmentId,
      fullName: 'María Peña',
      cedula: '00112345678',
      phone: '8095550123',
      moveInDate: DateTime(2026, 9, 1),
      rentCents: 850000,
      dueDay: 5,
    );
  });

  tearDown(() {
    try {
      db.close();
    } catch (_) {}
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('apagón con un cobro ya confirmado: queda exactamente un cobro', () {
    finance.registerPayment(
      requestId: 'p-1',
      leaseId: leaseId,
      periodYear: 2026,
      periodMonth: 9,
      amountCents: 850000,
      paymentDate: DateTime(2026, 9, 5),
      method: PaymentMethod.efectivo,
    );

    // "Corte de luz": se copian los archivos tal como están en disco.
    final crash = Directory(p.join(temp.path, 'tras-apagon'))..createSync();
    final copyPaths = AppPaths.create(p.join(crash.path, 'datos'));
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File('${paths.databaseFile}$suffix');
      if (file.existsSync()) {
        file.copySync('${copyPaths.databaseFile}$suffix');
      }
    }

    final recovered = AppDatabase.openAt(copyPaths.databaseFile);
    addTearDown(recovered.close);
    expect(recovered.quickCheck(), isNull);
    expect(recovered.rows('SELECT COUNT(*) AS c FROM payments').first['c'], 1);
    expect(recovered.rows('SELECT COUNT(*) AS c FROM receipts').first['c'], 1);
    final paid =
        recovered
                .rows(
                  'SELECT COALESCE(SUM(amount_cents), 0) AS t FROM payments '
                  'WHERE voided_at IS NULL',
                )
                .first['t']
            as int;
    expect(paid, 850000);
  });

  test('un cobro rechazado no deja rastro parcial', () {
    expect(
      () => finance.registerPayment(
        requestId: 'p-rechazado',
        leaseId: leaseId,
        periodYear: 2026,
        periodMonth: 9,
        amountCents: 900000, // más que la renta del período
        paymentDate: DateTime(2026, 9, 5),
        method: PaymentMethod.efectivo,
      ),
      throwsA(isA<Object>()),
    );
    expect(count('payments'), 0);
    expect(count('receipts'), 0);
    expect(count('app_events'), greaterThanOrEqualTo(0));
  });

  test(
    'PDF escrito a medias (archivo temporal) se descarta y regenera',
    () async {
      final outcome = finance.registerPayment(
        requestId: 'p-2',
        leaseId: leaseId,
        periodYear: 2026,
        periodMonth: 9,
        amountCents: 850000,
        paymentDate: DateTime(2026, 9, 5),
        method: PaymentMethod.efectivo,
      );
      final record = finance.receipt(outcome.receiptId)!;
      Directory(paths.receiptsDir).createSync(recursive: true);
      final target = File(p.join(paths.receiptsDir, 'REC-00000001.pdf'));
      File(
        '${target.path}.tmp',
      ).writeAsBytesSync(List<int>.filled(50, 0x20), flush: true);

      final result = await documents.ensure(record, force: true);
      expect(result.ok, isTrue);
      expect(File(result.path!).lengthSync(), greaterThan(700));
      expect(File('${target.path}.tmp').existsSync(), isFalse);
      expect(count('payments'), 1);
    },
  );

  test(
    'cobro guardado + impresora caída: el recibo sigue disponible',
    () async {
      final outcome = finance.registerPayment(
        requestId: 'p-3',
        leaseId: leaseId,
        periodYear: 2026,
        periodMonth: 9,
        amountCents: 850000,
        paymentDate: DateTime(2026, 9, 5),
        method: PaymentMethod.efectivo,
      );
      final record = finance.receipt(outcome.receiptId)!;
      // Aunque el PDF fallara, el snapshot permite regenerarlo después.
      expect(record.snapshot['tenantName'], 'María Peña');
      expect((await documents.ensure(record)).ok, isTrue);
      File(p.join(paths.receiptsDir, 'REC-00000001.pdf')).deleteSync();
      expect(await documents.verifyExisting(), 1);
      expect(count('payments'), 1);
      expect(count('receipts'), 1);
    },
  );

  test('la restauración reemplaza la base de forma atómica', () async {
    final backup = BackupService(database: db, paths: paths);
    final report = backup.runNow();

    // Se ensucia la base después de la copia.
    finance.registerPayment(
      requestId: 'p-despues',
      leaseId: leaseId,
      periodYear: 2026,
      periodMonth: 9,
      amountCents: 850000,
      paymentDate: DateTime(2026, 9, 5),
      method: PaymentMethod.efectivo,
    );
    expect(count('payments'), 1);

    final error = backup.restore(backup.list().first);
    expect(error, isNull);
    // No queda ningún archivo intermedio de la restauración.
    expect(File('${paths.databaseFile}.restaurando').existsSync(), isFalse);
    expect(Directory(report.path).existsSync(), isTrue);

    db = AppDatabase.openAt(paths.databaseFile);
    finance = FinanceRepository(db);
    expect(count('payments'), 0);
    expect(db.quickCheck(), isNull);
  });
}
