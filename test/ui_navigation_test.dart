import 'dart:io';

import 'package:control_alquileres/app.dart';
import 'package:control_alquileres/src/app/app_controller.dart';
import 'package:control_alquileres/src/data/app_database.dart';
import 'package:control_alquileres/src/data/app_paths.dart';
import 'package:control_alquileres/src/data/finance_models.dart';
import 'package:control_alquileres/src/data/portfolio_repository.dart';
import 'package:control_alquileres/src/data/settings_repository.dart';
import 'package:control_alquileres/src/services/print_service.dart';
import 'package:control_alquileres/src/services/printer_profile.dart';
import 'package:control_alquileres/src/services/serial_transport.dart';
import 'package:control_alquileres/src/ui/pages/home/payment_card.dart';
import 'package:control_alquileres/src/ui/pages/home/payment_history_card.dart';
import 'package:control_alquileres/src/ui/shell/sidebar.dart';
import 'package:control_alquileres/src/ui/widgets/app_icon.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

class _SinPuertos implements SerialPrintGateway {
  const _SinPuertos();

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

/// Navegación, iconos aprobados y responsabilidad única de cada vista.
void main() {
  late AppDatabase db;
  late Directory tempDir;
  late AppController controller;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    db = AppDatabase.inMemory();
    tempDir = Directory.systemTemp.createTempSync('ui_nav_');
    controller = AppController(
      database: db,
      portfolio: PortfolioRepository(db),
      settings: SettingsRepository(db),
      paths: AppPaths.create(tempDir.path),
      printGateway: const _SinCola(),
      serialPrintGateway: const _SinPuertos(),
    )..initialize();
  });

  tearDown(() {
    db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ControlAlquileresApp(controller: controller));
    await tester.pumpAndSettle();
  }

  group('Iconos aprobados', () {
    test('los 11 PNG existen y se pueden cargar', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      expect(AppIcon.values.length, 11);
      for (final icon in AppIcon.values) {
        final data = await rootBundle.load(icon.assetPath);
        expect(
          data.lengthInBytes,
          greaterThan(1000),
          reason: '${icon.file} debería ser un PNG real',
        );
        // Todos son PNG (firma 89 50 4E 47).
        final bytes = data.buffer.asUint8List();
        expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      }
    });

    test('las etiquetas semánticas están en español', () {
      expect(AppIcon.home.label, 'Inicio');
      expect(AppIcon.apartments.label, 'Apartamentos');
      expect(AppIcon.payments.label, 'Cobros');
      expect(AppIcon.settings.label, 'Configuración');
      expect(AppIcon.search.label, 'Buscar');
      expect(AppIcon.back.label, 'Volver');
      expect(AppIcon.add.label, 'Agregar');
      expect(AppIcon.receipt.label, 'Recibo');
      expect(AppIcon.edit.label, 'Editar');
      expect(AppIcon.delete.label, 'Eliminar');
      expect(AppIcon.print.label, 'Imprimir');
    });
  });

  group('Navegación', () {
    testWidgets('Cobrar en Inicio abre Cobros con el apartamento elegido', (
      tester,
    ) async {
      await pumpAt(tester, const Size(1366, 768));
      // Se pulsa el botón Cobrar de la primera fila.
      final before = controller.selectedApartmentId;
      await tester.tap(find.text('Cobrar').first);
      await tester.pumpAndSettle();

      expect(controller.section, AppSection.cobros);
      expect(controller.selectedApartmentId, isNotNull);
      // Cobrar nunca cambia de apartamento en silencio: usa el de la fila.
      expect(controller.selectedApartmentId, before);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cada vista tiene una sola versión del cobro y el historial', (
      tester,
    ) async {
      await pumpAt(tester, const Size(1536, 1024));

      // Inicio: solo lista + ficha (sin formulario ni historial).
      expect(find.byType(PaymentCard), findsNothing);
      expect(find.byType(PaymentHistoryCard), findsNothing);

      // Cobros: exactamente uno de cada.
      controller.startPaymentFor(controller.selectedApartmentId!);
      await tester.pumpAndSettle();
      expect(find.byType(PaymentCard), findsOneWidget);
      expect(find.byType(PaymentHistoryCard), findsOneWidget);

      // Apartamentos: datos maestros, sin formulario de cobro.
      controller.setSection(AppSection.apartamentos);
      await tester.pumpAndSettle();
      expect(find.byType(PaymentCard), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Cambiar apartamento regresa a la selección', (tester) async {
      await pumpAt(tester, const Size(1366, 768));
      controller.startPaymentFor(controller.visibleApartments.first.id);
      await tester.pumpAndSettle();
      expect(find.text('Cobrar e imprimir'), findsWidgets);

      await tester.tap(find.text('Cambiar').first);
      await tester.pumpAndSettle();

      expect(controller.selectedApartmentId, isNull);
      expect(find.text('Elija el apartamento a cobrar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('los iconos de la barra lateral tienen tooltip al pasar', (
      tester,
    ) async {
      await pumpAt(tester, const Size(1366, 768));
      final first = find.descendant(
        of: find.byType(AppSidebar),
        matching: find.byType(SidebarTooltip),
      );
      expect(first, findsNWidgets(4));

      // Al entrar con el mouse aparece el tooltip en español.
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(first.first));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Inicio'), findsWidgets);
      await gesture.moveTo(const Offset(600, 400));
      await tester.pump(const Duration(milliseconds: 200));
    });
  });

  group('Responsividad', () {
    for (final size in const [
      Size(1366, 768),
      Size(1280, 720),
      Size(1093, 578),
      Size(1024, 576),
      Size(960, 540),
    ]) {
      testWidgets('Cobros sin desbordes en ${size.width.toInt()}x'
          '${size.height.toInt()}', (tester) async {
        await pumpAt(tester, size);
        controller.startPaymentFor(controller.visibleApartments.first.id);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Acciones esenciales alcanzables (aunque requieran scroll).
        expect(find.text('No imprimir ticket'), findsWidgets);
        expect(find.text('Cobrar e imprimir'), findsWidgets);
      });
    }
  });
}
