import 'dart:io';
import 'dart:typed_data';

import 'package:control_alquileres/app.dart';
import 'package:control_alquileres/src/app/app_controller.dart';
import 'package:control_alquileres/src/data/app_database.dart';
import 'package:control_alquileres/src/data/app_paths.dart';
import 'package:control_alquileres/src/data/finance_models.dart';
import 'package:control_alquileres/src/data/models.dart';
import 'package:control_alquileres/src/data/portfolio_repository.dart';
import 'package:control_alquileres/src/data/settings_repository.dart';
import 'package:control_alquileres/src/services/print_service.dart';
import 'package:control_alquileres/src/services/printer_profile.dart';
import 'package:control_alquileres/src/services/serial_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SinColas implements PrintGateway {
  @override
  Future<List<PrinterRef>> listPrinters() async => const [];

  @override
  Future<PrintResult> print({
    required Uint8List pdfBytes,
    required String? printerName,
    required String jobName,
  }) async => PrintResult.success;
}

class _SinPuertos implements SerialPrintGateway {
  @override
  Future<List<ComPort>> listPorts() async => const [];

  @override
  Future<PrintResult> printReceipt(
    ReceiptRecord record, {
    required String port,
    PrinterProfile profile = const PrinterProfile(),
  }) async => PrintResult.success;

  @override
  Future<PrintResult> printCalibration({
    required String port,
    PrinterProfile profile = const PrinterProfile(),
    String model = '',
    String note = '',
  }) async => PrintResult.success;
}

/// La pantalla de Ajustes debe abrirse siempre: también cuando la impresora
/// guardada ya no existe (apagada, desemparejada, otro equipo). Antes eso podía
/// romper el desplegable y dejar al dueño sin poder configurar nada.
void main() {
  late AppDatabase db;
  late Directory tempDir;
  late AppController controller;

  setUp(() {
    db = AppDatabase.inMemory();
    tempDir = Directory.systemTemp.createTempSync('ajustes_ui');
    controller = AppController(
      database: db,
      portfolio: PortfolioRepository(db),
      settings: SettingsRepository(db),
      paths: AppPaths.create(tempDir.path),
      printGateway: _SinColas(),
      serialPrintGateway: _SinPuertos(),
    )..initialize();
  });

  tearDown(() {
    db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> abrirAjustes(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1366, 768);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ControlAlquileresApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
  }

  testWidgets('abre con una impresora configurada que ya no está', (
    tester,
  ) async {
    controller.saveOwner(
      const OwnerSettings(
        issuerName: 'Anamelia Rentas',
        issuerId: '',
        issuerAddress: '',
        issuerPhone: '',
        printerName: '2C-P80-C',
        receiptPrefix: 'REC',
        printerTransport: PrinterTransport.serial,
        printerTarget: 'COM9',
      ),
    );
    await abrirAjustes(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Impresora'), findsOneWidget);
    // La selección guardada se conserva y se avisa que no está disponible.
    expect(
      find.textContaining('no disponible'),
      findsOneWidget,
      reason: 'debe conservar la selección aunque el puerto no exista',
    );
    // El estado también lo explica en español, sin trazas.
    expect(find.textContaining('COM9'), findsWidgets);
  });

  testWidgets('abre sin ninguna impresora y con el modo automático', (
    tester,
  ) async {
    controller.saveOwner(
      const OwnerSettings(
        issuerName: 'Anamelia Rentas',
        issuerId: '',
        issuerAddress: '',
        issuerPhone: '',
        printerName: null,
        receiptPrefix: 'REC',
      ),
    );
    await abrirAjustes(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Impresora'), findsOneWidget);
    expect(controller.owner.printerTransport, PrinterTransport.auto);
    expect(
      find.textContaining('No se encontró la impresora'),
      findsWidgets,
      reason: 'aviso claro para la dueña',
    );
  });
}
