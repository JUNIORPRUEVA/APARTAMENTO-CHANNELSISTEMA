import 'dart:io';
import 'dart:typed_data';

import 'package:control_alquileres/src/core/app_failure.dart';
import 'package:control_alquileres/src/data/app_database.dart';
import 'package:control_alquileres/src/data/app_paths.dart';
import 'package:control_alquileres/src/data/finance_models.dart';
import 'package:control_alquileres/src/data/finance_repository.dart';
import 'package:control_alquileres/src/data/models.dart';
import 'package:control_alquileres/src/data/portfolio_repository.dart';
import 'package:control_alquileres/src/data/settings_repository.dart';
import 'package:control_alquileres/src/services/print_service.dart';
import 'package:control_alquileres/src/services/receipt_document_service.dart';
import 'package:control_alquileres/src/services/serial_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeSerialTransport implements SerialTransport {
  final List<({String port, Uint8List bytes})> sent = [];
  List<ComPort> ports = const [
    ComPort(name: 'COM3', devicePath: r'\Device\BthModem0', baudRate: 9600),
    ComPort(name: 'COM4', devicePath: r'\Device\Serial1', baudRate: 9600),
  ];
  Object? failure;

  @override
  Future<List<ComPort>> listPorts() async => ports;

  @override
  Future<void> send(
    String port,
    Uint8List bytes, {
    int baudRate = 9600,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (failure != null) throw failure!;
    sent.add((port: port, bytes: bytes));
  }
}

class _FakeWindowsGateway implements PrintGateway {
  final List<String?> jobs = [];
  Object? failure;
  bool reject = false;

  @override
  Future<List<PrinterRef>> listPrinters() async => const [
    PrinterRef(name: 'EPSON TM-T20', isDefault: true, target: 'EPSON TM-T20'),
    PrinterRef(
      name: 'Microsoft Print to PDF',
      isDefault: false,
      target: 'Microsoft Print to PDF',
    ),
  ];

  @override
  Future<PrintResult> print({
    required Uint8List pdfBytes,
    required String? printerName,
    required String jobName,
  }) async {
    if (failure != null) throw failure!;
    if (reject) {
      return const PrintResult(
        ok: false,
        message: 'La impresora no aceptó el trabajo. El cobro está guardado.',
      );
    }
    jobs.add(printerName);
    return PrintResult.success;
  }
}

void main() {
  late Directory temp;
  late AppDatabase db;
  late AppPaths paths;
  late FinanceRepository finance;
  late ReceiptDocumentService documents;
  late _FakeWindowsGateway windows;
  late _FakeSerialTransport serial;
  late ReceiptPrintService service;
  late ReceiptRecord record;

  OwnerSettings serialSettings({String port = 'COM3'}) => OwnerSettings(
    issuerName: 'Anamelia Rentas',
    issuerId: '',
    issuerAddress: '',
    issuerPhone: '',
    printerName: port,
    receiptPrefix: 'REC',
    printerTransport: PrinterTransport.serial,
    printerTarget: port,
  );

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('printer_matrix_');
    paths = AppPaths.create(p.join(temp.path, 'datos'));
    db = AppDatabase.openAt(paths.databaseFile);
    finance = FinanceRepository(db);
    final portfolio = PortfolioRepository(db);
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
    final leaseId = portfolio.registerTenantAndLease(
      apartmentId: apartmentId,
      fullName: 'María Peña',
      cedula: '00112345678',
      phone: '8095552020',
      moveInDate: DateTime(2026, 1, 5),
      rentCents: 850000,
      dueDay: 5,
    );
    final outcome = finance.registerPayment(
      requestId: 'matrix-1',
      leaseId: leaseId,
      periodYear: 2026,
      periodMonth: 8,
      amountCents: 850000,
      paymentDate: DateTime(2026, 8, 5),
      method: PaymentMethod.efectivo,
    );
    record = finance.receipt(outcome.receiptId)!;

    documents = ReceiptDocumentService(
      finance: finance,
      paths: paths,
      currentWidthMm: () => 80,
    );
    windows = _FakeWindowsGateway();
    serial = _FakeSerialTransport();
    service = ReceiptPrintService(
      documents: documents,
      gateway: windows,
      serialGateway: Win32SerialPrintGateway(transport: serial),
    );
    await documents.ensure(record);
  });

  tearDown(() {
    db.close();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('impresora no disponible', () {
    test('la lista combina colas de Windows y puertos serie', () async {
      final printers = await service.printers();
      expect(printers.map((p) => p.endpoint), contains('EPSON TM-T20'));
      expect(printers.map((p) => p.endpoint), contains('COM3'));
      final bt = printers.firstWhere((p) => p.endpoint == 'COM3');
      expect(bt.kind, PrinterKind.serialCom);
      expect(bt.detail, 'Bluetooth probable');
    });

    test('sin destino configurado se avisa y no se pierde el cobro', () async {
      final result = await service.printReceipt(
        record,
        settings: const OwnerSettings.empty(),
      );
      expect(result.ok, isTrue); // abre el diálogo de Windows
      expect(windows.jobs.length, 1);
      expect(windows.jobs.first, isNull);

      final serialResult = await service.printReceipt(
        record,
        settings: const OwnerSettings(
          issuerName: 'X',
          issuerId: '',
          issuerAddress: '',
          issuerPhone: '',
          printerName: null,
          receiptPrefix: 'REC',
          printerTransport: PrinterTransport.serial,
          printerTarget: null,
        ),
      );
      expect(serialResult.ok, isFalse);
      expect(serialResult.message, contains('puerto serie'));
      expect(serial.sent, isEmpty);
    });

    test('el driver rechaza el trabajo: mensaje claro y PDF intacto', () async {
      windows.reject = true;
      final result = await service.printReceipt(
        record,
        settings: const OwnerSettings(
          issuerName: 'X',
          issuerId: '',
          issuerAddress: '',
          issuerPhone: '',
          printerName: 'EPSON TM-T20',
          receiptPrefix: 'REC',
          printerTarget: 'EPSON TM-T20',
        ),
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('El cobro está guardado'));
      expect(finance.receipt(record.id)!.pdfStatus, 'generado');
    });
  });

  group('Bluetooth / puerto serie', () {
    test('envía bytes ESC/POS al puerto configurado', () async {
      final result = await service.printReceipt(
        record,
        settings: serialSettings(),
      );
      expect(result.ok, isTrue);
      expect(serial.sent.length, 1);
      expect(serial.sent.first.port, 'COM3');
      expect(serial.sent.first.bytes.sublist(0, 2), [0x1B, 0x40]);
    });

    test('Bluetooth apagado (puerto inexistente) no tumba el cobro', () async {
      serial.failure = const AppFailure(
        'El puerto COM3 no existe. Empareje la impresora Bluetooth.',
      );
      final result = await service.printReceipt(
        record,
        settings: serialSettings(),
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('COM3'));
      expect(result.message, contains('guardado'));
      expect(finance.receipt(record.id)!.pdfStatus, 'generado');
    });

    test('desconexión a mitad del trabajo reporta trabajo incompleto', () async {
      serial.failure = const AppFailure(
        'La conexión con la impresora se interrumpió durante el envío (COM3). '
        'El trabajo quedó incompleto: reimprima.',
      );
      final result = await service.printReceipt(
        record,
        settings: serialSettings(),
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('incompleto'));
    });

    test('tiempo de espera agotado se informa como tal', () async {
      serial.failure = const AppFailure(
        'La impresora no aceptó los datos en COM3 (tiempo de espera agotado).',
      );
      final result = await service.printReceipt(
        record,
        settings: serialSettings(port: 'COM3'),
      );
      expect(result.ok, isFalse);
      expect(result.message.toLowerCase(), contains('tiempo de espera'));
    });

    test('reimprimir dos veces produce dos trabajos idénticos', () async {
      final settings = serialSettings();
      await service.printReceipt(record, settings: settings);
      await service.printReceipt(record, settings: settings);
      expect(serial.sent.length, 2);
      expect(serial.sent[0].bytes, serial.sent[1].bytes);
      // Un solo recibo en la base: reimprimir no crea documentos nuevos.
      expect(db.rows('SELECT COUNT(*) AS c FROM receipts').first['c'], 1);
      expect(
        Directory(paths.receiptsDir).listSync().whereType<File>().length,
        1,
      );
    });

    test('la hoja de prueba informa el puerto y los acentos', () async {
      final result = await service.printTestPage(serialSettings());
      expect(result.ok, isTrue);
      final text = String.fromCharCodes(serial.sent.first.bytes);
      expect(text, contains('COM3'));
      expect(text, contains('Prueba de impresora'));
    });

    test('sin acentos la prueba sale en ASCII puro', () async {
      final result = await service.printTestPage(
        serialSettings().copyWith(asciiOnly: true),
      );
      expect(result.ok, isTrue);
      final bytes = serial.sent.first.bytes;
      // Los únicos bytes altos permitidos son los de los comandos ESC/POS.
      expect(bytes.contains(0xC3), isFalse);
    });
  });
}
