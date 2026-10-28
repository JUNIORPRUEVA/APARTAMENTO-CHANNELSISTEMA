import 'dart:io';

import 'package:control_alquileres/app.dart';
import 'package:control_alquileres/src/app/app_controller.dart';
import 'package:control_alquileres/src/data/app_database.dart';
import 'package:control_alquileres/src/data/app_paths.dart';
import 'package:control_alquileres/src/data/finance_models.dart';
import 'package:control_alquileres/src/data/models.dart';
import 'package:control_alquileres/src/data/portfolio_repository.dart';
import 'package:control_alquileres/src/data/settings_repository.dart';
import 'package:control_alquileres/src/services/print_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Flujo real de cobro desde la interfaz: guardar, generar recibo, evitar
/// dobles envíos e imprimir con una impresora simulada.
void main() {
  late AppDatabase db;
  late Directory tempDir;
  late AppController controller;
  late _FakeGateway gateway;

  setUpAll(() async {
    for (final name in ['segoeui.ttf', 'segoeuib.ttf']) {
      final file = File('C:\\Windows\\Fonts\\$name');
      if (!file.existsSync()) continue;
      final data = ByteData.sublistView(file.readAsBytesSync());
      final loader = FontLoader('Segoe UI')..addFont(Future.value(data));
      await loader.load();
    }
  });

  setUp(() {
    db = AppDatabase.inMemory();
    tempDir = Directory.systemTemp.createTempSync('ca_flow');
    gateway = _FakeGateway();
    controller = AppController(
      database: db,
      portfolio: PortfolioRepository(db),
      settings: SettingsRepository(db),
      paths: AppPaths.create(tempDir.path),
      printGateway: gateway,
    )..initialize();
    // Datos del emisor para que el recibo salga completo.
    controller.saveOwner(
      const OwnerSettings(
        issuerName: 'Inversiones Anamelia SRL',
        issuerId: '1-31-12345-6',
        issuerAddress: 'Av. Independencia 45',
        issuerPhone: '809-555-0000',
        printerName: 'EPSON TM-T20',
        printerTarget: 'EPSON TM-T20',
        printerTransport: PrinterTransport.windows,
        receiptPrefix: 'REC',
      ),
    );
  });

  tearDown(() {
    db.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1536, 1024);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ControlAlquileresApp(controller: controller));
    await tester.pumpAndSettle();
  }

  testWidgets('guardar un pago crea el cobro, el recibo y su PDF', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(controller.selectedPeriod, isNotNull);
    final before = controller.selectedPeriod!.remainingCents;

    await tester.runAsync(() async {
      await tester.tap(find.text('Guardar (sin imprimir)').first);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(controller.payments.length, 1);
    final payment = controller.payments.single;
    expect(payment.amountCents, before);
    expect(payment.isVoided, isFalse);

    final receipt = controller.finance.receipt(payment.receiptId!)!;
    expect(receipt.pdfStatus, 'generado');
    expect(File(receipt.pdfPath!).existsSync(), isTrue);
    expect(File(receipt.pdfPath!).path.startsWith(tempDir.path), isTrue);

    // La tabla del historial muestra el movimiento real.
    expect(find.textContaining('Total cobrado'), findsOneWidget);
    expect(find.text('RD\$ 8,500'), findsWidgets);
  });

  test('dos cobros simultáneos (doble clic) crean un solo pago', () async {
    final period = controller.selectedPeriod!;
    final results = await Future.wait([
      controller.submitPayment(
        amountCents: period.remainingCents,
        paymentDate: DateTime.now(),
        method: PaymentMethod.efectivo,
      ),
      controller.submitPayment(
        amountCents: period.remainingCents,
        paymentDate: DateTime.now(),
        method: PaymentMethod.efectivo,
      ),
    ]);

    expect(results.where((r) => r.ok).length, 1);
    expect(results.where((r) => r.error != null).length, 1);
    expect(db.rows('SELECT COUNT(*) AS c FROM payments').first['c'], 1);
    expect(db.rows('SELECT COUNT(*) AS c FROM receipts').first['c'], 1);
    expect(controller.payments.length, 1);
  });

  testWidgets('guardar e imprimir envía el recibo a la impresora', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Guardar e imprimir recibo').first);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pumpAndSettle();

    expect(controller.payments.length, 1);
    expect(gateway.printedBytes, isNotNull);
    expect(gateway.lastPrinter, 'EPSON TM-T20');
    expect(find.textContaining('enviado a la impresora'), findsWidgets);
  });

  testWidgets('si la impresora falla el pago queda guardado', (tester) async {
    gateway.fail = true;
    await pumpApp(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Guardar e imprimir recibo').first);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pumpAndSettle();

    expect(controller.payments.length, 1);
    final receipt = controller.finance.receipt(
      controller.payments.single.receiptId!,
    )!;
    expect(receipt.pdfStatus, 'generado');
    expect(find.textContaining('El pago está guardado'), findsWidgets);
  });

  testWidgets('depósito: recibir, devolver con tope y no contarlo como renta', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Depósito').first);
    await tester.pumpAndSettle();
    expect(find.text('Depósito retenido'), findsOneWidget);

    // Sin movimientos todavía.
    expect(controller.deposit!.heldCents, 0);

    final leaseId = controller.selectedApartment!.lease!.id;
    final held = controller.finance.registerDeposit(
      requestId: 'd-manual',
      leaseId: leaseId,
      kind: DepositKind.recibido,
      amountCents: 800000,
      movementDate: DateTime.now(),
    );
    expect(held.heldAfterCents, 800000);
    controller.reload();
    await tester.pumpAndSettle();

    expect(controller.deposit!.heldCents, 800000);
    expect(controller.payments, isEmpty);
    expect(find.text('RD\$ 8,000'), findsWidgets);
  });
}

class _FakeGateway implements PrintGateway {
  bool fail = false;
  Uint8List? printedBytes;
  String? lastPrinter;

  @override
  Future<List<PrinterRef>> listPrinters() async => const [
    PrinterRef(name: 'EPSON TM-T20', isDefault: true),
  ];

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
