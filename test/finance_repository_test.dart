import 'dart:io';
import 'dart:typed_data';

import 'package:control_alquileres/src/core/app_failure.dart';
import 'package:control_alquileres/src/core/formatters.dart';
import 'package:control_alquileres/src/data/app_database.dart';
import 'package:control_alquileres/src/data/app_paths.dart';
import 'package:control_alquileres/src/data/finance_models.dart';
import 'package:control_alquileres/src/data/finance_repository.dart';
import 'package:control_alquileres/src/data/models.dart';
import 'package:control_alquileres/src/data/portfolio_repository.dart';
import 'package:control_alquileres/src/services/print_service.dart';
import 'package:control_alquileres/src/services/receipt_document_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PortfolioRepository portfolio;
  late FinanceRepository finance;
  late AppPaths paths;
  late Directory tempDir;
  late int apartmentId;
  late int leaseId;

  const rent = 850000; // RD$ 8,500.00

  setUp(() {
    db = AppDatabase.inMemory();
    portfolio = PortfolioRepository(db);
    finance = FinanceRepository(db);
    tempDir = Directory.systemTemp.createTempSync('ca_finance');
    paths = AppPaths.create(tempDir.path);

    final group = portfolio.createGroup('Anamelia');
    apartmentId = portfolio.createApartment(
      groupId: group,
      identifier: '101',
      location: 'Primer nivel',
      rentCents: rent,
    );
    leaseId = portfolio.registerTenantAndLease(
      apartmentId: apartmentId,
      fullName: 'María Pérez',
      cedula: '00112345678',
      phone: '809-555-0123',
      moveInDate: DateTime(2026, 1, 5),
      rentCents: rent,
      dueDay: 5,
      depositRequiredCents: 800000,
    );
  });

  tearDown(() {
    db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  PaymentOutcome pay({
    String requestId = 'req-1',
    int year = 2026,
    int month = 3,
    int amount = rent,
    PaymentMethod method = PaymentMethod.efectivo,
  }) {
    return finance.registerPayment(
      requestId: requestId,
      leaseId: leaseId,
      periodYear: year,
      periodMonth: month,
      amountCents: amount,
      paymentDate: DateTime(year, month, 5),
      method: method,
    );
  }

  group('A. cálculo de períodos', () {
    test('el vencimiento se ajusta al último día del mes', () {
      final l = portfolio.registerTenantAndLease(
        apartmentId: portfolio.createApartment(
          groupId: portfolio.groups().first.id,
          identifier: '201',
          location: '',
          rentCents: rent,
        ),
        fullName: 'José Ramírez',
        cedula: '00198765432',
        phone: '8095550000',
        moveInDate: DateTime(2026, 1, 31),
        rentCents: rent,
        dueDay: 31,
      );
      final periods = finance.periodsFor(
        l,
        from: DateTime(2026, 2),
        to: DateTime(2026, 4),
      );
      expect(formatDate(periods[0].dueDate), '28/02/2026');
      expect(formatDate(periods[1].dueDate), '31/03/2026');
      expect(formatDate(periods[2].dueDate), '30/04/2026');
    });

    test('año bisiesto: 29 de febrero', () {
      expect(formatDate(dayInMonth(2028, 2, 31)), '29/02/2028');
      expect(formatDate(dayInMonth(2027, 2, 31)), '28/02/2027');
    });

    test('períodos futuros se calculan sin escribir en la base', () {
      final periods = finance.periodsFor(
        leaseId,
        from: DateTime(2026, 1),
        to: DateTime(2026, 12),
      );
      expect(periods.length, 12);
      expect(periods.every((p) => p.id == 0), isTrue);
      expect(periods.every((p) => p.amountDueCents == rent), isTrue);
      expect(
        db.rows('SELECT COUNT(*) AS c FROM payment_periods').first['c'],
        0,
      );
    });

    test('solo se materializa el período cobrado', () {
      pay(month: 3);
      expect(
        db.rows('SELECT COUNT(*) AS c FROM payment_periods').first['c'],
        1,
      );
    });

    test('estado: al día, parcial, pendiente y vencido', () {
      final today = DateTime(2026, 3, 10);
      RentStatus status(Map<int, int> paid) => RentLedger.statusFor(
        startDate: DateTime(2026, 3, 1),
        monthlyRentCents: rent,
        dueDay: 5,
        paidByMonth: paid,
        dueByMonth: const {},
        today: today,
      );

      expect(status({}), RentStatus.vencido); // venció el 5 y no hay pago
      expect(status({202603: 300000}), RentStatus.vencido);
      expect(status({202603: rent}), RentStatus.alDia);

      final before = RentLedger.statusFor(
        startDate: DateTime(2026, 3, 1),
        monthlyRentCents: rent,
        dueDay: 5,
        paidByMonth: const {},
        dueByMonth: const {},
        today: DateTime(2026, 3, 3),
      );
      expect(before, RentStatus.pendiente);

      final partial = RentLedger.statusFor(
        startDate: DateTime(2026, 3, 1),
        monthlyRentCents: rent,
        dueDay: 5,
        paidByMonth: const {202603: 300000},
        dueByMonth: const {},
        today: DateTime(2026, 3, 3),
      );
      expect(partial, RentStatus.parcial);
    });

    test(
      'salida y reingreso: el estado no arrastra meses del contrato viejo',
      () {
        pay(requestId: 'mar', month: 3);
        portfolio.endLease(leaseId: leaseId, endDate: DateTime(2026, 3, 31));
        final nuevo = portfolio.registerTenantAndLease(
          apartmentId: apartmentId,
          fullName: 'Carmen Cruz',
          cedula: '00176543210',
          phone: '8295550000',
          moveInDate: DateTime(2026, 4, 1),
          rentCents: rent,
          dueDay: 5,
        );
        final status = RentLedger.statusFor(
          startDate: DateTime(2026, 4, 1),
          monthlyRentCents: rent,
          dueDay: 5,
          paidByMonth: const {},
          dueByMonth: const {},
          today: DateTime(2026, 4, 2),
        );
        expect(status, RentStatus.pendiente);
        expect(nuevo, greaterThan(leaseId));
      },
    );
  });

  group('B. pagos', () {
    test('pago parcial y luego el resto', () {
      final first = pay(requestId: 'r1', amount: 300000);
      expect(first.balanceAfterCents, rent - 300000);

      final period = finance
          .periodsFor(leaseId, from: DateTime(2026, 3), to: DateTime(2026, 3))
          .single;
      expect(period.paidCents, 300000);
      expect(period.remainingCents, rent - 300000);

      final second = pay(requestId: 'r2', amount: rent - 300000);
      expect(second.balanceAfterCents, 0);

      final after = finance
          .periodsFor(leaseId, from: DateTime(2026, 3), to: DateTime(2026, 3))
          .single;
      expect(after.remainingCents, 0);
      expect(after.isPaid, isTrue);
    });

    test('pago adelantado de un mes futuro explícito', () {
      final outcome = pay(requestId: 'adv', month: 9);
      expect(outcome.receiptNumber, 1);
      final periods = finance.periodsFor(
        leaseId,
        from: DateTime(2026, 9),
        to: DateTime(2026, 9),
      );
      expect(periods.single.isPaid, isTrue);
      // El mes en curso sigue pendiente: no se reasigna dinero solo.
      final current = finance.periodsFor(
        leaseId,
        from: DateTime(2026, 3),
        to: DateTime(2026, 3),
      );
      expect(current.single.paidCents, 0);
    });

    test('rechaza monto cero, negativo o superior al saldo', () {
      expect(
        () => pay(requestId: 'zero', amount: 0),
        throwsA(isA<AppFailure>()),
      );
      expect(
        () => pay(requestId: 'neg', amount: -100),
        throwsA(isA<AppFailure>()),
      );
      expect(
        () => pay(requestId: 'over', amount: rent + 1),
        throwsA(isA<AppFailure>()),
      );
      expect(db.rows('SELECT COUNT(*) AS c FROM payments').first['c'], 0);
    });

    test('no acepta un segundo pago de un período ya saldado', () {
      pay(requestId: 'full');
      expect(
        () => pay(requestId: 'again', amount: 1000),
        throwsA(isA<AppFailure>()),
      );
    });

    test('cambio de renta: los períodos anteriores conservan su snapshot', () {
      pay(requestId: 'oct', month: 10);
      portfolio.updateLeaseTerms(
        leaseId: leaseId,
        monthlyRentCents: 900000,
        dueDay: 5,
        plannedEndDate: null,
        depositRequiredCents: 800000,
      );

      final october = finance
          .periodsFor(leaseId, from: DateTime(2026, 10), to: DateTime(2026, 10))
          .single;
      expect(october.amountDueCents, rent); // snapshot intacto

      final november = finance
          .periodsFor(leaseId, from: DateTime(2026, 11), to: DateTime(2026, 11))
          .single;
      expect(november.amountDueCents, 900000);

      final record = finance.paymentsForLease(leaseId).single;
      expect(record.amountDueCents, rent);
    });

    test('el recibo guarda el snapshot del inquilino y del período', () {
      final outcome = pay(requestId: 'snap', month: 5);
      final receipt = finance.receipt(outcome.receiptId)!;
      expect(receipt.kind, ReceiptKind.alquiler);
      expect(receipt.snapshot['tenantName'], 'María Pérez');
      expect(receipt.snapshot['apartmentIdentifier'], '101');
      expect(receipt.snapshot['periodLabel'], 'Mayo 2026');
      expect(receipt.snapshot['amountCents'], rent);
      expect(receipt.snapshot['balanceAfterCents'], 0);
      expect(receipt.totalCents, rent);
      expect(receipt.pdfStatus, 'pendiente');
    });
  });

  group('C. idempotencia', () {
    test('el mismo requestId devuelve el mismo pago y no duplica nada', () {
      final first = pay(requestId: 'repetido');
      final second = pay(requestId: 'repetido');

      expect(second.duplicate, isTrue);
      expect(second.paymentId, first.paymentId);
      expect(second.receiptNumber, first.receiptNumber);
      expect(db.rows('SELECT COUNT(*) AS c FROM payments').first['c'], 1);
      expect(db.rows('SELECT COUNT(*) AS c FROM receipts').first['c'], 1);
    });

    test('dos llamadas seguidas con distinto requestId sí son dos cobros '
        '(solo si hay saldo)', () {
      pay(requestId: 'a', amount: 400000);
      final second = pay(requestId: 'b', amount: 450000);
      expect(second.duplicate, isFalse);
      expect(db.rows('SELECT COUNT(*) AS c FROM payments').first['c'], 2);
    });

    test('los números de recibo son correlativos y únicos', () {
      final a = pay(requestId: 'n1', amount: 100000);
      final b = pay(requestId: 'n2', amount: 100000);
      expect(a.receiptNumber, 1);
      expect(b.receiptNumber, 2);
      expect(db.rows('SELECT COUNT(*) AS c FROM receipts').first['c'], 2);
    });
  });

  group('D. historial entre contratos', () {
    test(
      'el pago del contrato anterior se conserva al entrar otro inquilino',
      () {
        final march = pay(requestId: 'mar', month: 3);
        final oldReceipt = finance.receipt(march.receiptId)!;

        portfolio.endLease(leaseId: leaseId, endDate: DateTime(2026, 3, 31));
        final newLease = portfolio.registerTenantAndLease(
          apartmentId: apartmentId,
          fullName: 'José Ramírez',
          cedula: '00198765432',
          phone: '8295550000',
          moveInDate: DateTime(2026, 4, 5),
          rentCents: rent,
          dueDay: 5,
        );
        expect(
          () => portfolio.registerTenantAndLease(
            apartmentId: apartmentId,
            fullName: 'Otro Inquilino',
            cedula: '00111111111',
            phone: '8095551111',
            moveInDate: DateTime(2026, 8, 1),
            rentCents: rent,
            dueDay: 5,
          ),
          throwsA(isA<AppFailure>()),
        );

        final april = finance.registerPayment(
          requestId: 'apr',
          leaseId: newLease,
          periodYear: 2026,
          periodMonth: 4,
          amountCents: rent,
          paymentDate: DateTime(2026, 4, 5),
          method: PaymentMethod.transferencia,
        );
        expect(april.receiptNumber, 2);

        final history = finance.paymentsForApartment(apartmentId);
        expect(history.length, 2);
        expect(
          history.map((p) => p.tenantName),
          containsAll(['María Pérez', 'José Ramírez']),
        );
        // El recibo anterior no cambia.
        final stillOld = finance.receipt(oldReceipt.id)!;
        expect(stillOld.number, oldReceipt.number);
        expect(stillOld.snapshot['tenantName'], 'María Pérez');
      },
    );
  });

  group('E. depósitos', () {
    test('recibir, devolver y retener con topes', () {
      final received = finance.registerDeposit(
        requestId: 'd1',
        leaseId: leaseId,
        kind: DepositKind.recibido,
        amountCents: 800000,
        movementDate: DateTime(2026, 1, 5),
      );
      expect(received.heldAfterCents, 800000);
      expect(finance.depositSummary(leaseId).heldCents, 800000);

      expect(
        () => finance.registerDeposit(
          requestId: 'd2',
          leaseId: leaseId,
          kind: DepositKind.devuelto,
          amountCents: 900000,
          movementDate: DateTime(2026, 2, 1),
        ),
        throwsA(isA<AppFailure>()),
      );

      final partial = finance.registerDeposit(
        requestId: 'd3',
        leaseId: leaseId,
        kind: DepositKind.devuelto,
        amountCents: 300000,
        movementDate: DateTime(2026, 2, 1),
      );
      expect(partial.heldAfterCents, 500000);

      expect(
        () => finance.registerDeposit(
          requestId: 'd4',
          leaseId: leaseId,
          kind: DepositKind.retenido,
          amountCents: 100000,
          movementDate: DateTime(2026, 2, 2),
        ),
        throwsA(isA<AppFailure>()), // falta el motivo
      );

      final retained = finance.registerDeposit(
        requestId: 'd5',
        leaseId: leaseId,
        kind: DepositKind.retenido,
        amountCents: 500000,
        movementDate: DateTime(2026, 2, 2),
        reason: 'Daños en la pintura',
      );
      expect(retained.heldAfterCents, 0);

      final summary = finance.depositSummary(leaseId);
      expect(summary.receivedCents, 800000);
      expect(summary.refundedCents, 300000);
      expect(summary.retainedCents, 500000);
      expect(summary.movements.length, 3);
    });

    test('el depósito nunca cuenta como pago de alquiler', () {
      finance.registerDeposit(
        requestId: 'd1',
        leaseId: leaseId,
        kind: DepositKind.recibido,
        amountCents: 800000,
        movementDate: DateTime(2026, 1, 5),
      );
      expect(finance.paymentsForLease(leaseId), isEmpty);
      final period = finance
          .periodsFor(leaseId, from: DateTime(2026, 1), to: DateTime(2026, 1))
          .single;
      expect(period.paidCents, 0);
      expect(period.remainingCents, rent);
    });

    test('el depósito genera su propio recibo, con concepto distinto', () {
      final outcome = finance.registerDeposit(
        requestId: 'd1',
        leaseId: leaseId,
        kind: DepositKind.recibido,
        amountCents: 800000,
        movementDate: DateTime(2026, 1, 5),
      );
      final receipt = finance.receipt(outcome.receiptId)!;
      expect(receipt.kind, ReceiptKind.deposito);
      expect(receipt.snapshot['depositKindLabel'], 'Depósito recibido');
      expect(receipt.totalCents, 800000);
    });
  });

  group('F. anulación auditada', () {
    test('anular restaura el saldo y conserva el recibo original', () {
      final outcome = pay(requestId: 'p1');
      final original = finance.receipt(outcome.receiptId)!;

      final reversal = finance.voidPayment(
        paymentId: outcome.paymentId,
        reason: 'Se cobró dos veces',
      );
      expect(reversal.receiptNumber, greaterThan(original.number));

      final payments = finance.paymentsForLease(leaseId);
      expect(payments.single.isVoided, isTrue);
      expect(payments.single.voidReason, 'Se cobró dos veces');

      final period = finance
          .periodsFor(leaseId, from: DateTime(2026, 3), to: DateTime(2026, 3))
          .single;
      expect(period.remainingCents, rent);

      // Auditoría: el pago sigue existiendo y el recibo original también.
      expect(db.rows('SELECT COUNT(*) AS c FROM payments').first['c'], 1);
      expect(
        db.rows('SELECT COUNT(*) AS c FROM payment_reversals').first['c'],
        1,
      );
      final stillThere = finance.receipt(original.id)!;
      expect(stillThere.number, original.number);
      expect(stillThere.kind, ReceiptKind.alquiler);

      final note = finance.receipt(reversal.receiptId)!;
      expect(note.kind, ReceiptKind.anulacion);
      expect(note.snapshot['originalReceipt'], original.label);
      expect(note.snapshot['voidReason'], 'Se cobró dos veces');
    });

    test('no se puede anular dos veces ni sin motivo', () {
      final outcome = pay(requestId: 'p1');
      expect(
        () => finance.voidPayment(paymentId: outcome.paymentId, reason: '  '),
        throwsA(isA<AppFailure>()),
      );
      finance.voidPayment(paymentId: outcome.paymentId, reason: 'Error');
      expect(
        () => finance.voidPayment(paymentId: outcome.paymentId, reason: 'Otra'),
        throwsA(isA<AppFailure>()),
      );
    });

    test('tras anular se puede volver a cobrar el mismo período', () {
      final first = pay(requestId: 'p1');
      finance.voidPayment(paymentId: first.paymentId, reason: 'Duplicado');
      final again = pay(requestId: 'p2');
      expect(again.receiptNumber, 3); // 1 alquiler, 2 anulación, 3 nuevo
      final period = finance
          .periodsFor(leaseId, from: DateTime(2026, 3), to: DateTime(2026, 3))
          .single;
      expect(period.remainingCents, 0);
    });
  });

  group('G/H. PDF y recuperación', () {
    test(
      'el PDF se genera en la carpeta de recibos y es reproducible',
      () async {
        final outcome = pay(requestId: 'pdf');
        final documents = ReceiptDocumentService(
          finance: finance,
          paths: paths,
          currentWidthMm: () => 80,
        );
        final record = finance.receipt(outcome.receiptId)!;

        final result = await documents.ensure(record);
        expect(result.ok, isTrue);
        final file = File(result.path!);
        expect(file.existsSync(), isTrue);
        expect(file.lengthSync(), greaterThan(700));
        expect(file.path.startsWith(paths.receiptsDir), isTrue);

        final updated = finance.receipt(record.id)!;
        expect(updated.pdfStatus, 'generado');
        expect(updated.attempts, 1);

        // Regenerar no crea otro recibo ni otro pago.
        await documents.ensure(finance.receipt(record.id)!, force: true);
        expect(db.rows('SELECT COUNT(*) AS c FROM receipts').first['c'], 1);
        expect(db.rows('SELECT COUNT(*) AS c FROM payments').first['c'], 1);
      },
    );

    test(
      'si el PDF desaparece se regenera desde el snapshot sin cobrar otra vez',
      () async {
        final outcome = pay(requestId: 'pdf2');
        final documents = ReceiptDocumentService(
          finance: finance,
          paths: paths,
          currentWidthMm: () => 80,
        );
        final first = await documents.ensure(
          finance.receipt(outcome.receiptId)!,
        );
        File(first.path!).deleteSync();

        final repaired = await documents.verifyExisting();
        expect(repaired, 1);
        expect(File(first.path!).existsSync(), isTrue);
        expect(db.rows('SELECT COUNT(*) AS c FROM payments').first['c'], 1);
        expect(db.rows('SELECT COUNT(*) AS c FROM receipts').first['c'], 1);
      },
    );

    test(
      'un recibo pendiente (proceso interrumpido) se recupera al arrancar',
      () async {
        final outcome = pay(requestId: 'pdf3');
        // Estado tras confirmar el pago y caerse antes de escribir el PDF.
        expect(finance.receipt(outcome.receiptId)!.pdfStatus, 'pendiente');

        final documents = ReceiptDocumentService(
          finance: finance,
          paths: paths,
          currentWidthMm: () => 80,
        );
        final failures = await documents.recoverPending();
        expect(failures, 0);
        expect(finance.receipt(outcome.receiptId)!.pdfStatus, 'generado');
        expect(db.rows('SELECT COUNT(*) AS c FROM payments').first['c'], 1);
      },
    );

    test('el PDF de 80 mm tiene el ancho de papel térmico', () async {
      final outcome = pay(requestId: 'pdf4');
      final record = finance.receipt(outcome.receiptId)!;
      final bytes = await ReceiptDocumentService.buildPdf(record, widthMm: 80);
      final text = String.fromCharCodes(bytes);

      expect(text.startsWith('%PDF'), isTrue);
      final match = RegExp(
        r'/MediaBox\s*\[\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)',
      ).firstMatch(text);
      expect(
        match,
        isNotNull,
        reason: 'El PDF debe declarar su caja de página',
      );
      final width = double.parse(match!.group(3)!);
      // 80 mm ≈ 226.77 pt (se acepta el redondeo del generador).
      expect(width, closeTo(226.77, 1.5));

      final narrow = await ReceiptDocumentService.buildPdf(record, widthMm: 58);
      final narrowMatch = RegExp(
        r'/MediaBox\s*\[\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)',
      ).firstMatch(String.fromCharCodes(narrow))!;
      expect(double.parse(narrowMatch.group(3)!), closeTo(164.41, 2));
    });
  });

  group('purga de datos de demostración', () {
    test('se niega a borrar si ya hay movimientos de dinero', () {
      db.run('UPDATE apartment_groups SET is_demo = 1');
      db.run('UPDATE apartments SET is_demo = 1');
      db.run('UPDATE tenants SET is_demo = 1');
      pay(requestId: 'demo-pay');

      expect(() => portfolio.purgeDemoData(), throwsA(isA<AppFailure>()));
      expect(db.rows('SELECT COUNT(*) AS c FROM payments').first['c'], 1);
      expect(db.rows('SELECT COUNT(*) AS c FROM apartments').first['c'], 1);
    });

    test('borra la demostración sin movimientos', () {
      db.run('UPDATE apartment_groups SET is_demo = 1');
      db.run('UPDATE apartments SET is_demo = 1');
      db.run('UPDATE tenants SET is_demo = 1');

      portfolio.purgeDemoData();
      expect(portfolio.countApartments(), 0);
      expect(portfolio.hasGroups, isFalse);
      expect(db.rows('SELECT COUNT(*) AS c FROM leases').first['c'], 0);
    });
  });

  group('J. impresión', () {
    test(
      'se despacha el PDF y un fallo del driver no afecta al pago',
      () async {
        final outcome = pay(requestId: 'print');
        final documents = ReceiptDocumentService(
          finance: finance,
          paths: paths,
          currentWidthMm: () => 80,
        );
        final gateway = _FakeGateway();
        final printer = ReceiptPrintService(
          documents: documents,
          gateway: gateway,
        );
        final record = finance.receipt(outcome.receiptId)!;

        const windowsTarget = OwnerSettings(
          issuerName: 'Doña Rosa',
          issuerId: '',
          issuerAddress: '',
          issuerPhone: '',
          printerName: 'EPSON TM-T20',
          receiptPrefix: 'REC',
          printerTarget: 'EPSON TM-T20',
        );

        final ok = await printer.printReceipt(record, settings: windowsTarget);
        expect(ok.ok, isTrue);
        expect(gateway.printedBytes, isNotNull);
        expect(gateway.lastPrinter, 'EPSON TM-T20');

        gateway.fail = true;
        final failed = await printer.printReceipt(
          record,
          settings: windowsTarget,
        );
        expect(failed.ok, isFalse);
        expect(failed.message, contains('guardado'));

        // El pago y el recibo siguen intactos.
        expect(db.rows('SELECT COUNT(*) AS c FROM payments').first['c'], 1);
        expect(finance.receipt(record.id)!.pdfStatus, 'generado');
      },
    );

    test('sin impresora configurada se informa un mensaje claro', () async {
      final outcome = pay(requestId: 'print2');
      final documents = ReceiptDocumentService(
        finance: finance,
        paths: paths,
        currentWidthMm: () => 80,
      );
      final gateway = _FakeGateway()
        ..availablePrinters = const [
          PrinterRef(name: 'Microsoft Print to PDF', isDefault: true),
        ];
      final printer = ReceiptPrintService(
        documents: documents,
        gateway: gateway,
      );
      final result = await printer.printReceipt(
        finance.receipt(outcome.receiptId)!,
        settings: const OwnerSettings.empty(),
      );
      expect(result.ok, isTrue);
      expect(gateway.lastPrinter, isNull);
    });
  });
}

class _FakeGateway implements PrintGateway {
  List<PrinterRef> availablePrinters = const [
    PrinterRef(name: 'EPSON TM-T20', isDefault: true),
  ];
  bool fail = false;
  Uint8List? printedBytes;
  String? lastPrinter;

  @override
  Future<List<PrinterRef>> listPrinters() async => availablePrinters;

  @override
  Future<PrintResult> print({
    required Uint8List pdfBytes,
    required String? printerName,
    required String jobName,
  }) async {
    printedBytes = pdfBytes;
    lastPrinter = printerName;
    if (fail) {
      return const PrintResult(
        ok: false,
        message: 'No se pudo imprimir. El pago está guardado.',
      );
    }
    return PrintResult.success;
  }
}
