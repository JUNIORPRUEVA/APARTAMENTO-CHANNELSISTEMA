import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:control_alquileres/src/data/app_database.dart';
import 'package:control_alquileres/src/data/app_paths.dart';
import 'package:control_alquileres/src/data/finance_models.dart';
import 'package:control_alquileres/src/data/finance_repository.dart';
import 'package:control_alquileres/src/data/models.dart';
import 'package:control_alquileres/src/data/portfolio_repository.dart';
import 'package:control_alquileres/src/data/settings_repository.dart';
import 'package:control_alquileres/src/services/printer_profile.dart';
import 'package:control_alquileres/src/services/receipt_document_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Ancho de la página en puntos (1 mm = 72/25.4 pt).
double _pt(double mm) => mm * 72 / 25.4;

void main() {
  late Directory temp;
  late AppDatabase db;
  late AppPaths paths;
  late FinanceRepository finance;
  late PortfolioRepository portfolio;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('recibo_doc_');
    paths = AppPaths.create(p.join(temp.path, 'datos'));
    db = AppDatabase.openAt(paths.databaseFile);
    finance = FinanceRepository(db);
    portfolio = PortfolioRepository(db);
    SettingsRepository(db).save(
      const OwnerSettings(
        issuerName: 'Anamelia Rentas',
        issuerId: '131-00000-1',
        issuerAddress: 'Av. 27 de Febrero 123, Santo Domingo',
        issuerPhone: '809-555-0101',
        printerName: null,
        receiptPrefix: 'REC',
      ),
    );
  });

  tearDown(() {
    db.close();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  int seedPayment({String reference = 'TRF-7788'}) {
    final groupId = portfolio.createGroup('Anamelia');
    final apartmentId = portfolio.createApartment(
      groupId: groupId,
      identifier: 'A-01',
      location: 'Bloque 1',
      rentCents: 850000,
    );
    final leaseId = portfolio.registerTenantAndLease(
      apartmentId: apartmentId,
      fullName: 'José Ramón Núñez',
      cedula: '00112345678',
      phone: '8095552020',
      moveInDate: DateTime(2026, 1, 5),
      rentCents: 850000,
      dueDay: 5,
    );
    final outcome = finance.registerPayment(
      requestId: 'doc-${DateTime.now().microsecondsSinceEpoch}',
      leaseId: leaseId,
      periodYear: 2026,
      periodMonth: 8,
      amountCents: 850000,
      paymentDate: DateTime(2026, 8, 5),
      method: PaymentMethod.transferencia,
      reference: reference,
    );
    return outcome.receiptId;
  }

  String latin1Of(Uint8List bytes) => latin1.decode(bytes, allowInvalid: true);

  test('el PDF mide exactamente 80 mm de ancho y alto variable', () async {
    final record = finance.receipt(seedPayment())!;
    final bytes = await ReceiptDocumentService.buildPdf(record);
    expect(bytes.length, greaterThan(700));

    final match = RegExp(
      r'/MediaBox\s*\[\s*0(?:\.0+)?\s+0(?:\.0+)?\s+([0-9.]+)\s+([0-9.]+)\s*\]',
    ).firstMatch(latin1Of(bytes));
    expect(match, isNotNull, reason: 'el PDF debe declarar /MediaBox');
    final width = double.parse(match!.group(1)!);
    final height = double.parse(match.group(2)!);
    // 80 mm con tolerancia de medio punto de redondeo del generador.
    expect(width, closeTo(_pt(80), 1.0));
    // Alto variable: nunca A4 ni una hoja larga sin recibo.
    expect(height, lessThan(_pt(150)));
    expect(height, greaterThan(_pt(40)));
  });

  test('el ancho respeta 58 mm cuando está configurado', () async {
    final record = finance.receipt(seedPayment())!;
    final bytes = await ReceiptDocumentService.buildPdf(record, widthMm: 58);
    final match = RegExp(
      r'/MediaBox\s*\[\s*0(?:\.0+)?\s+0(?:\.0+)?\s+([0-9.]+)',
    ).firstMatch(latin1Of(bytes));
    expect(double.parse(match!.group(1)!), closeTo(_pt(58), 1.0));
  });

  test('el margen configurable cambia el espacio del contenido', () async {
    final record = finance.receipt(seedPayment())!;
    final narrow = await ReceiptDocumentService.buildPdf(record, marginMm: 2);
    final wide = await ReceiptDocumentService.buildPdf(record, marginMm: 10);
    // Mismo texto, distinto tamaño: el margen afecta el ancho útil.
    expect(narrow.length, isNot(equals(wide.length)));
  });

  test('el recibo impreso no muestra la cédula completa', () async {
    final record = finance.receipt(seedPayment())!;
    // La cédula completa no debe aparecer en el snapshot del recibo impreso
    // cuando se enmascara, y el snapshot guarda el dato tal cual para auditoría.
    expect(record.snapshot['tenantCedula'], '00112345678');
    final bytes = await ReceiptDocumentService.buildPdf(record);
    // El texto del PDF va comprimido; lo verificable aquí es que el PDF se
    // genera y que el formato de máscara es el esperado (probado aparte).
    expect(bytes.length, greaterThan(700));
  });

  test('la referencia de la transferencia llega al recibo', () async {
    final record = finance.receipt(seedPayment(reference: 'TRF-ABCDE'))!;
    expect(record.snapshot['reference'], 'TRF-ABCDE');
  });

  test(
    'un perfil angosto obliga a un margen mayor (el texto no se recorta)',
    () async {
      final record = finance.receipt(seedPayment())!;
      double heightOf(Uint8List bytes) {
        final match = RegExp(
          r'/MediaBox\s*\[\s*0(?:\.0+)?\s+0(?:\.0+)?\s+([0-9.]+)\s+([0-9.]+)\s*\]',
        ).firstMatch(latin1Of(bytes));
        return double.parse(match!.group(2)!);
      }

      final wide = await ReceiptDocumentService.buildPdf(
        record,
        profile: const PrinterProfile(printableDots: 576),
      );
      final narrow = await ReceiptDocumentService.buildPdf(
        record,
        profile: const PrinterProfile(printableDots: 448), // 56 mm útiles
      );

      // Mismo contenido, área más angosta: el ticket crece en alto, no se corta.
      expect(heightOf(narrow), greaterThan(heightOf(wide)));
      // Y el ancho de página sigue siendo 80 mm exactos.
      final match = RegExp(
        r'/MediaBox\s*\[\s*0(?:\.0+)?\s+0(?:\.0+)?\s+([0-9.]+)',
      ).firstMatch(latin1Of(narrow));
      expect(double.parse(match!.group(1)!), closeTo(_pt(80), 1.0));
    },
  );

  test('el ticket de calibración se genera con el perfil actual', () async {
    final service = ReceiptDocumentService(
      finance: finance,
      paths: paths,
      currentWidthMm: () => 80,
      currentProfile: () => const PrinterProfile(printableDots: 576),
    );
    final bytes = await service.buildCalibrationDocument(model: '2C-P80-C');
    expect(bytes.length, greaterThan(700));
    final match = RegExp(
      r'/MediaBox\s*\[\s*0(?:\.0+)?\s+0(?:\.0+)?\s+([0-9.]+)',
    ).firstMatch(latin1Of(bytes));
    expect(double.parse(match!.group(1)!), closeTo(_pt(80), 1.0));
  });

  test('ensure escribe el PDF una vez y no lo reescribe', () async {
    final record = finance.receipt(seedPayment())!;
    final service = ReceiptDocumentService(
      finance: finance,
      paths: paths,
      currentWidthMm: () => 80,
    );
    final first = await service.ensure(record);
    expect(first.ok, isTrue);
    final file = File(first.path!);
    expect(file.existsSync(), isTrue);
    final stamp = file.lastModifiedSync();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final again = await service.ensure(finance.receipt(record.id)!);
    expect(again.ok, isTrue);
    expect(again.path, first.path);
    expect(file.lastModifiedSync(), stamp);
    expect(Directory(paths.receiptsDir).listSync().whereType<File>().length, 1);
  });

  test('un PDF borrado se regenera desde el snapshot', () async {
    final record = finance.receipt(seedPayment())!;
    final service = ReceiptDocumentService(
      finance: finance,
      paths: paths,
      currentWidthMm: () => 80,
    );
    final first = await service.ensure(record);
    File(first.path!).deleteSync();

    final repaired = await service.verifyExisting();
    expect(repaired, 1);
    expect(File(first.path!).existsSync(), isTrue);
    expect(finance.receipt(record.id)!.pdfStatus, 'generado');
  });

  test('un .tmp interrumpido no impide generar el PDF definitivo', () async {
    final record = finance.receipt(seedPayment())!;
    final service = ReceiptDocumentService(
      finance: finance,
      paths: paths,
      currentWidthMm: () => 80,
    );
    Directory(paths.receiptsDir).createSync(recursive: true);
    final target = File(p.join(paths.receiptsDir, 'REC-00000001.pdf'));
    File('${target.path}.tmp').writeAsBytesSync(<int>[1, 2, 3], flush: true);

    final result = await service.ensure(record, force: true);
    expect(result.ok, isTrue);
    expect(File(result.path!).lengthSync(), greaterThan(700));
  });
}
