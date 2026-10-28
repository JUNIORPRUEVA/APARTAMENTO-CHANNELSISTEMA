import 'dart:io';
import 'dart:typed_data';

import 'package:control_alquileres/src/data/app_database.dart';
import 'package:control_alquileres/src/data/app_paths.dart';
import 'package:control_alquileres/src/data/data_location.dart';
import 'package:control_alquileres/src/data/finance_models.dart';
import 'package:control_alquileres/src/data/finance_repository.dart';
import 'package:control_alquileres/src/data/models.dart';
import 'package:control_alquileres/src/data/portfolio_repository.dart';
import 'package:control_alquileres/src/data/settings_repository.dart';
import 'package:control_alquileres/src/services/escpos.dart';
import 'package:control_alquileres/src/services/print_service.dart';
import 'package:control_alquileres/src/services/printer_profile.dart';
import 'package:control_alquileres/src/services/receipt_document_service.dart';
import 'package:control_alquileres/src/services/serial_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Captura implements SerialPrintGateway {
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
    sent.add(EscPosReceipt.build(record, profile: profile));
    return PrintResult.success;
  }

  @override
  Future<PrintResult> printCalibration({
    required String port,
    PrinterProfile profile = const PrinterProfile(),
    String model = '',
    String note = '',
  }) async {
    sent.add(EscPosReceipt.buildCalibration(profile: profile, model: model));
    return PrintResult.success;
  }
}

/// Integridad de documentos: abrir/regenerar/reimprimir nunca debe crear dinero
/// ni cambiar números, y la prueba de impresora no puede tocar la numeración.
void main() {
  late Directory temp;
  late AppPaths paths;
  late AppDatabase db;
  late PortfolioRepository portfolio;
  late FinanceRepository finance;
  late ReceiptDocumentService documents;
  late SettingsRepository settings;
  late _Captura serial;
  late ReceiptPrintService printer;
  late int receiptId;

  int count(String table) =>
      db.rows('SELECT COUNT(*) AS c FROM $table').first['c'] as int;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('integridad_');
    paths = requireSandboxPaths(temp.path, tool: 'receipt_integrity_test');
    db = AppDatabase.openAt(paths.databaseFile);
    portfolio = PortfolioRepository(db);
    finance = FinanceRepository(db);
    settings = SettingsRepository(db);
    settings.save(
      const OwnerSettings(
        issuerName: 'Anamelia Rentas',
        issuerId: '131-00000-1',
        issuerAddress: 'Calle 1',
        issuerPhone: '809-555-0000',
        printerName: '2C-P80-C',
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
    serial = _Captura();
    printer = ReceiptPrintService(
      documents: documents,
      gateway: const _SinCola(),
      serialGateway: serial,
    );

    final groupId = portfolio.createGroup('Anamelia');
    final apartmentId = portfolio.createApartment(
      groupId: groupId,
      identifier: 'A-01',
      location: '',
      rentCents: 850000,
    );
    final leaseId = portfolio.registerTenantAndLease(
      apartmentId: apartmentId,
      fullName: 'María Peña',
      cedula: '00112345678',
      phone: '8095550123',
      moveInDate: DateTime(2026, 9, 1),
      rentCents: 850000,
      dueDay: 5,
    );
    final outcome = finance.registerPayment(
      requestId: 'p-1',
      leaseId: leaseId,
      periodYear: 2026,
      periodMonth: 9,
      amountCents: 850000,
      paymentDate: DateTime(2026, 9, 5),
      method: PaymentMethod.efectivo,
    );
    receiptId = outcome.receiptId;
  });

  tearDown(() {
    db.close();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('ver el PDF o reimprimirlo no crea cobros ni recibos', () async {
    final before = (count('payments'), count('receipts'));
    final first = await documents.ensure(finance.receipt(receiptId)!);
    final second = await documents.ensure(finance.receipt(receiptId)!);
    expect(first.ok && second.ok, isTrue);
    final result = await printer.printReceipt(
      finance.receipt(receiptId)!,
      settings: settings.load(),
    );
    expect(result.ok, isTrue);
    expect((count('payments'), count('receipts')), before);
    expect(Directory(paths.receiptsDir).listSync().length, 1);
  });

  test('regenerar un PDF borrado conserva número, nombre y snapshot', () async {
    final original = await documents.ensure(finance.receipt(receiptId)!);
    final snapshotBefore = finance.receipt(receiptId)!.snapshot;
    File(original.path!).deleteSync();

    final repaired = await documents.verifyExisting();
    expect(repaired, 1);
    final record = finance.receipt(receiptId)!;
    expect(record.number, 1);
    expect(record.label, 'REC-000001');
    expect(record.snapshot, snapshotBefore);
    expect(p.basename(original.path!), 'REC-00000001.pdf');
    expect(File(original.path!).existsSync(), isTrue);
    expect(count('receipts'), 1);
    expect(count('payments'), 1);
  });

  test('la prueba de impresora no afecta recibos ni numeración', () async {
    final before = (count('payments'), count('receipts'));
    final result = await printer.printCalibration(settings.load());
    expect(result.ok, isTrue);
    expect(serial.sent.single, contains(0x1B));
    // Marcado inequívoco de prueba en el ticket.
    final text = String.fromCharCodes(
      serial.sent.single.where((b) => b >= 0x20 || b == 0x0A),
    );
    expect(text, contains('NO ES UN PAGO'));
    expect(text, contains('PRUEBA DE IMPRESORA'));
    expect((count('payments'), count('receipts')), before);

    // Un cobro posterior sigue la numeración normal (no se consumió número).
    final order =
        db
                .rows(
                  'SELECT number FROM receipts ORDER BY number DESC LIMIT 1',
                )
                .first['number']
            as int;
    expect(order, 1);
  });

  test('sin acentos no se corrompen montos ni comandos', () async {
    final record = finance.receipt(receiptId)!;
    final profile = const PrinterProfile(asciiOnly: true);
    final bytes = EscPosReceipt.build(record, profile: profile);
    final text = String.fromCharCodes(
      bytes.where((b) => b >= 0x20 || b == 0x0A),
    );
    expect(text, contains('RD\$ 8,500'));
    expect(text, contains('Cedula')); // etiqueta sin acento
    expect(text, isNot(contains('RD\$\x00')));
    // Estructura intacta: inicialización y avance de papel.
    expect(bytes.sublist(0, 2), [0x1B, 0x40]);
    expect(bytes.sublist(bytes.length - 3), [0x1B, 0x64, 0x04]);
    // Ningún byte alto (todo ASCII).
    expect(bytes.any((b) => b >= 0x80), isFalse);
  });

  test('un recibo con snapshot dañado no crea nada y queda marcado', () async {
    db.run("UPDATE receipts SET snapshot_json = '{no es json' WHERE id = ?", [
      receiptId,
    ]);
    final result = await documents.ensure(finance.receipt(receiptId)!);
    expect(result.ok, isFalse);
    expect(count('payments'), 1);
    expect(count('receipts'), 1);
    final row = db.rows('SELECT pdf_status FROM receipts WHERE id = ?', [
      receiptId,
    ]).first;
    expect(row['pdf_status'], anyOf('fallido', 'pendiente'));
    // No queda archivo a medias.
    expect(
      Directory(paths.receiptsDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.pdf'))
          .isEmpty,
      isTrue,
    );
  });
}

class _SinCola implements PrintGateway {
  const _SinCola();

  @override
  Future<List<PrinterRef>> listPrinters() async => const [];

  @override
  Future<PrintResult> print({
    required Uint8List pdfBytes,
    required String? printerName,
    required String jobName,
  }) async => PrintResult.success;
}
