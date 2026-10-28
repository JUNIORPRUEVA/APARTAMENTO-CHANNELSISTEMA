import 'dart:io';
import 'dart:typed_data';

import 'package:control_alquileres/src/core/app_failure.dart';
import 'package:control_alquileres/src/data/app_database.dart';
import 'package:control_alquileres/src/data/app_paths.dart';
import 'package:control_alquileres/src/data/data_location.dart';
import 'package:control_alquileres/src/data/finance_models.dart';
import 'package:control_alquileres/src/data/finance_repository.dart';
import 'package:control_alquileres/src/data/models.dart';
import 'package:control_alquileres/src/data/portfolio_repository.dart';
import 'package:control_alquileres/src/data/settings_repository.dart';
import 'package:control_alquileres/src/services/backup_service.dart';
import 'package:control_alquileres/src/services/print_service.dart';
import 'package:control_alquileres/src/services/printer_profile.dart';
import 'package:control_alquileres/src/services/receipt_document_service.dart';
import 'package:control_alquileres/src/services/serial_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Gateway de impresión falso: registra envíos sin tocar hardware.
class _FakeSerial implements SerialPrintGateway {
  final List<Uint8List> sent = [];

  @override
  Future<List<ComPort>> listPorts() async => const [
    ComPort(name: 'COM7', devicePath: r'\Device\BthModem0', baudRate: 9600),
  ];

  @override
  Future<PrintResult> printReceipt(
    ReceiptRecord record, {
    required String port,
    PrinterProfile profile = const PrinterProfile(),
  }) async {
    sent.add(Uint8List.fromList([1, 2, 3]));
    return const PrintResult(ok: true, message: 'Enviado (prueba).');
  }

  @override
  Future<PrintResult> printCalibration({
    required String port,
    PrinterProfile profile = const PrinterProfile(),
    String model = '',
    String note = '',
  }) async => const PrintResult(ok: true, message: 'Enviado (prueba).');
}

/// Secuencia funcional completa sobre un sandbox aislado, con cifras exactas:
/// residencial → apartamento → inquilino → contrato → depósito → abono →
/// saldo → adelanto → PDF → reimpresión → anulación → devolución del depósito →
/// fin de contrato → nuevo inquilino → PDF del inquilino anterior → copia y
/// restauración.
void main() {
  late Directory temp;
  late AppPaths paths;
  late AppDatabase db;
  late PortfolioRepository portfolio;
  late FinanceRepository finance;
  late ReceiptDocumentService documents;
  late _FakeSerial serial;
  late ReceiptPrintService printer;

  const rent = 850000; // RD$ 8,500.00 en centavos

  int count(String table) =>
      db.rows('SELECT COUNT(*) AS c FROM $table').first['c'] as int;

  int remainingOf(int leaseId, int year, int month) {
    final periods = finance.periodsFor(
      leaseId,
      from: DateTime(year, month),
      to: DateTime(year, month),
    );
    return periods.isEmpty ? -1 : periods.first.remainingCents;
  }

  setUp(() {
    temp = Directory.systemTemp.createTempSync('uat_seq_');
    // Se usa el guardián de sandbox: si alguien cambia esto por la carpeta
    // real, la prueba falla antes de escribir nada.
    paths = requireSandboxPaths(temp.path, tool: 'uat_sequence_test');
    db = AppDatabase.openAt(paths.databaseFile);
    portfolio = PortfolioRepository(db);
    finance = FinanceRepository(db);
    SettingsRepository(db).save(
      const OwnerSettings(
        issuerName: 'Inversiones Anamelia SRL',
        issuerId: '131-00000-1',
        issuerAddress: 'Av. 27 de Febrero 123',
        issuerPhone: '809-555-0101',
        printerName: null,
        receiptPrefix: 'REC',
        printerTransport: PrinterTransport.serial,
        printerTarget: 'COM7',
      ),
    );
    documents = ReceiptDocumentService(
      finance: finance,
      paths: paths,
      currentWidthMm: () => 80,
    );
    serial = _FakeSerial();
    printer = ReceiptPrintService(
      documents: documents,
      gateway: const _NoQueue(),
      serialGateway: serial,
    );
  });

  tearDown(() {
    try {
      db.close();
    } catch (_) {
      // Puede estar cerrada por una restauración.
    }
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('secuencia completa con conteos y saldos exactos', () async {
    // 1. Residencial y apartamento -------------------------------------------
    final groupId = portfolio.createGroup('Anamelia');
    final apartmentId = portfolio.createApartment(
      groupId: groupId,
      identifier: 'A-01',
      location: 'Bloque 1',
      rentCents: rent,
    );
    expect(count('apartment_groups'), 1);
    expect(count('apartments'), 1);
    expect(
      portfolio.findApartment(apartmentId)!.occupancy,
      OccupancyStatus.disponible,
    );

    // 2. Inquilino + contrato + depósito pactado ------------------------------
    final lease1 = portfolio.registerTenantAndLease(
      apartmentId: apartmentId,
      fullName: 'María Altagracia Peña',
      cedula: '00112345678',
      phone: '8095550123',
      moveInDate: DateTime(2026, 9, 1),
      rentCents: rent,
      dueDay: 5,
      depositRequiredCents: rent,
    );
    expect(count('tenants'), 1);
    expect(count('leases'), 1);
    expect(
      portfolio.findApartment(apartmentId)!.occupancy,
      OccupancyStatus.ocupado,
    );

    // 3. Depósito recibido (garantía, no es renta) ---------------------------
    final dep1 = finance.registerDeposit(
      requestId: 'dep-1',
      leaseId: lease1,
      kind: DepositKind.recibido,
      amountCents: rent,
      movementDate: DateTime(2026, 9, 1),
      reason: 'Garantía',
    );
    expect(dep1.duplicate, isFalse);
    expect(dep1.heldAfterCents, rent);
    expect(finance.depositSummary(lease1).heldCents, rent);
    expect(count('deposit_movements'), 1);
    expect(count('receipts'), 1);
    expect(count('payments'), 0);

    // No se puede devolver más de lo retenido.
    expect(
      () => finance.registerDeposit(
        requestId: 'dep-x',
        leaseId: lease1,
        kind: DepositKind.devuelto,
        amountCents: rent + 1,
        movementDate: DateTime(2026, 9, 10),
      ),
      throwsA(isA<AppFailure>()),
    );

    // 4. Abono parcial de septiembre ----------------------------------------
    final pay1 = finance.registerPayment(
      requestId: 'pay-1',
      leaseId: lease1,
      periodYear: 2026,
      periodMonth: 9,
      amountCents: 400000,
      paymentDate: DateTime(2026, 9, 5),
      method: PaymentMethod.efectivo,
      note: 'Abono',
    );
    expect(pay1.receiptNumber, greaterThan(0));
    expect(pay1.balanceAfterCents, rent - 400000);
    expect(remainingOf(lease1, 2026, 9), rent - 400000);
    expect(count('payments'), 1);
    expect(count('receipts'), 2);

    // Idempotencia: el mismo requestId no crea otro cobro.
    final again = finance.registerPayment(
      requestId: 'pay-1',
      leaseId: lease1,
      periodYear: 2026,
      periodMonth: 9,
      amountCents: 400000,
      paymentDate: DateTime(2026, 9, 5),
      method: PaymentMethod.efectivo,
    );
    expect(again.duplicate, isTrue);
    expect(count('payments'), 1);

    // No se puede cobrar más que el saldo del período.
    expect(
      () => finance.registerPayment(
        requestId: 'pay-over',
        leaseId: lease1,
        periodYear: 2026,
        periodMonth: 9,
        amountCents: rent,
        paymentDate: DateTime(2026, 9, 6),
        method: PaymentMethod.efectivo,
      ),
      throwsA(isA<AppFailure>()),
    );

    // 5. Resto de septiembre --------------------------------------------------
    final pay2 = finance.registerPayment(
      requestId: 'pay-2',
      leaseId: lease1,
      periodYear: 2026,
      periodMonth: 9,
      amountCents: rent - 400000,
      paymentDate: DateTime(2026, 9, 20),
      method: PaymentMethod.transferencia,
      reference: 'TRF-7788',
    );
    expect(pay2.balanceAfterCents, 0);
    expect(remainingOf(lease1, 2026, 9), 0);
    expect(count('payments'), 2);

    // 6. Adelanto de octubre --------------------------------------------------
    finance.registerPayment(
      requestId: 'pay-3',
      leaseId: lease1,
      periodYear: 2026,
      periodMonth: 10,
      amountCents: rent,
      paymentDate: DateTime(2026, 9, 25),
      method: PaymentMethod.transferencia,
      reference: 'TRF-ADEL-1',
      note: 'Pago adelantado',
    );
    expect(remainingOf(lease1, 2026, 10), 0);
    expect(count('payments'), 3);
    expect(count('receipts'), 4); // 1 depósito + 3 cobros

    // 7. PDF de cada movimiento (abrir/verificar no crea nada) ---------------
    final record1 = finance.receipt(pay1.receiptId)!;
    final firstPdf = await documents.ensure(record1);
    expect(firstPdf.ok, isTrue);
    // Abrir el mismo PDF otra vez no duplica ni reescribe.
    final stamp = File(firstPdf.path!).lastModifiedSync();
    final secondPdf = await documents.ensure(finance.receipt(pay1.receiptId)!);
    expect(secondPdf.path, firstPdf.path);
    expect(File(firstPdf.path!).lastModifiedSync(), stamp);
    expect(count('payments'), 3);
    expect(count('receipts'), 4);

    // Todos los recibos generan su PDF.
    for (final record in finance.receiptsNeedingPdf(limit: 100)) {
      expect((await documents.ensure(record)).ok, isTrue);
    }
    final pdfs = Directory(
      paths.receiptsDir,
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.pdf')).length;
    expect(pdfs, 4);

    // 8. Reimpresión (simulada) del recibo: no crea cobros ni recibos -------
    final reprint = await printer.printReceipt(
      finance.receipt(pay1.receiptId)!,
      settings: SettingsRepository(db).load(),
    );
    expect(reprint.ok, isTrue);
    expect(serial.sent.length, 1);
    expect(count('payments'), 3);
    expect(count('receipts'), 4);

    // 9. Anulación del segundo cobro (resto de septiembre) ------------------
    final reversed = finance.voidPayment(
      paymentId: pay2.paymentId,
      reason: 'Se cobró dos veces el resto',
    );
    expect(reversed.receiptNumber, greaterThan(0));
    expect(remainingOf(lease1, 2026, 9), rent - 400000);
    expect(count('payments'), 3); // el pago sigue existiendo (marcado)
    expect(count('payment_reversals'), 1);
    expect(count('receipts'), 5); // + nota de anulación
    final voided = finance
        .paymentsForLease(lease1)
        .firstWhere((row) => row.id == pay2.paymentId);
    expect(voided.isVoided, isTrue);
    expect(voided.voidReason, isNotEmpty);

    // No se puede anular dos veces el mismo pago.
    expect(
      () => finance.voidPayment(paymentId: pay2.paymentId, reason: 'otra vez'),
      throwsA(isA<AppFailure>()),
    );
    expect(count('payment_reversals'), 1);
    expect(count('receipts'), 5);

    // La nota de anulación tiene su propio PDF y su propio número.
    expect(
      (await documents.ensure(finance.receipt(reversed.receiptId)!)).ok,
      isTrue,
    );
    expect(count('receipts'), 5);

    // 10. Devolución del depósito y cierre de contrato ----------------------
    final dep2 = finance.registerDeposit(
      requestId: 'dep-2',
      leaseId: lease1,
      kind: DepositKind.devuelto,
      amountCents: rent,
      movementDate: DateTime(2026, 10, 31),
      reason: 'Salida del inquilino',
    );
    expect(dep2.heldAfterCents, 0);
    expect(finance.depositSummary(lease1).heldCents, 0);
    expect(count('deposit_movements'), 2);

    portfolio.endLease(
      leaseId: lease1,
      endDate: DateTime(2026, 10, 31),
      reason: 'Mudanza',
    );
    expect(
      portfolio.findApartment(apartmentId)!.occupancy,
      OccupancyStatus.disponible,
    );
    expect(count('leases'), 1); // el contrato no se borra

    // 11. Nuevo inquilino en el mismo apartamento ---------------------------
    final lease2 = portfolio.registerTenantAndLease(
      apartmentId: apartmentId,
      fullName: 'José Ramón Castillo',
      cedula: '40212345678',
      phone: '8095559999',
      moveInDate: DateTime(2026, 11, 1),
      rentCents: 900000,
      dueDay: 1,
    );
    expect(count('tenants'), 2);
    expect(count('leases'), 2);
    expect(lease2, isNot(lease1));
    final history = portfolio.leaseHistory(apartmentId);
    expect(history.length, 2);

    // 12. El inquilino anterior conserva sus recibos y su PDF ---------------
    final oldPayments = finance.paymentsForLease(lease1);
    expect(oldPayments.length, 3);
    final oldReceipt = finance.receipt(pay1.receiptId)!;
    expect(oldReceipt.number, pay1.receiptNumber);
    expect(oldReceipt.snapshot['tenantName'], 'María Altagracia Peña');
    final oldPdf = await documents.ensure(finance.receipt(pay1.receiptId)!);
    expect(oldPdf.ok, isTrue);
    // El número del recibo no cambia al regenerar.
    expect(finance.receipt(pay1.receiptId)!.number, pay1.receiptNumber);
    // Los recibos nuevos siguen una numeración correlativa distinta.
    final newPay = finance.registerPayment(
      requestId: 'pay-new',
      leaseId: lease2,
      periodYear: 2026,
      periodMonth: 11,
      amountCents: 900000,
      paymentDate: DateTime(2026, 11, 1),
      method: PaymentMethod.efectivo,
    );
    expect(newPay.receiptNumber, greaterThan(reversed.receiptNumber));

    // 13. Copia de seguridad y restauración ---------------------------------
    final backup = BackupService(database: db, paths: paths);
    final report = backup.runNow();
    expect(
      File(p.join(report.path, 'control_alquileres.sqlite')).existsSync(),
      isTrue,
    );
    // La copia incluye la base **y** los PDF que existen en disco.
    final pdfsOnDisk = Directory(
      paths.receiptsDir,
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.pdf')).length;
    expect(
      Directory(p.join(report.path, 'recibos'))
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.pdf'))
          .length,
      pdfsOnDisk,
    );
    final paymentsAtBackup = count('payments');
    final receiptsAtBackup = count('receipts');

    // Se altera la base DESPUÉS de la copia (debe desaparecer al restaurar).
    finance.registerPayment(
      requestId: 'pay-after-backup',
      leaseId: lease2,
      periodYear: 2026,
      periodMonth: 12,
      amountCents: 900000,
      paymentDate: DateTime(2026, 12, 1),
      method: PaymentMethod.efectivo,
    );
    expect(count('payments'), paymentsAtBackup + 1);

    final entries = backup.list();
    final error = backup.restore(entries.first);
    expect(error, isNull);
    // La restauración deja la base cerrada: se reabre como hace la aplicación.
    db = AppDatabase.openAt(paths.databaseFile);
    finance = FinanceRepository(db);
    portfolio = PortfolioRepository(db);
    expect(count('payments'), paymentsAtBackup);
    expect(count('receipts'), receiptsAtBackup);
    expect(db.quickCheck(), isNull);
    // Se conservó la copia previa a la restauración.
    expect(
      Directory(paths.backupsDir)
          .listSync()
          .whereType<Directory>()
          .where((d) => p.basename(d.path).startsWith('pre-restauracion-'))
          .isNotEmpty,
      isTrue,
    );
  });

  test('una copia dañada se rechaza sin tocar los datos', () async {
    final groupId = portfolio.createGroup('Anamelia');
    portfolio.createApartment(
      groupId: groupId,
      identifier: 'A-01',
      location: '',
      rentCents: rent,
    );
    final backup = BackupService(database: db, paths: paths);
    final report = backup.runNow();
    final dbFile = File(p.join(report.path, 'control_alquileres.sqlite'));
    dbFile.writeAsBytesSync(<int>[0, 1, 2, 3, 4, 5], flush: true);

    final before = count('apartments');
    final error = backup.restore(backup.list().first);
    expect(error, contains('dañada'));
    expect(count('apartments'), before);
    expect(db.quickCheck(), isNull);
  });
}

class _NoQueue implements PrintGateway {
  const _NoQueue();

  @override
  Future<List<PrinterRef>> listPrinters() async => const [];

  @override
  Future<PrintResult> print({
    required Uint8List pdfBytes,
    required String? printerName,
    required String jobName,
  }) async => PrintResult.success;
}
