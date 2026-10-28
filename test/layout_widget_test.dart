import 'dart:io';

import 'package:control_alquileres/app.dart';
import 'package:control_alquileres/src/app/app_controller.dart';
import 'package:control_alquileres/src/data/app_database.dart';
import 'package:control_alquileres/src/data/app_paths.dart';
import 'package:control_alquileres/src/data/portfolio_repository.dart';
import 'package:control_alquileres/src/data/settings_repository.dart';
import 'package:control_alquileres/src/ui/shell/sidebar.dart';
import 'package:control_alquileres/src/ui/widgets/app_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifica que la interfaz no desborde ni recorte en los tamaños objetivo
/// (incluye el equivalente lógico de 125 % de escala).
void main() {
  late AppDatabase db;
  late Directory tempDir;
  late AppController controller;

  setUpAll(() async {
    // Se usa la tipografía real de Windows para que las medidas del texto en
    // las pruebas sean las mismas que en el equipo del cliente.
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
    tempDir = Directory.systemTemp.createTempSync('control_alquileres_ui');
    controller = AppController(
      database: db,
      portfolio: PortfolioRepository(db),
      settings: SettingsRepository(db),
      paths: AppPaths.create(tempDir.path),
    )..initialize();
  });

  tearDown(() {
    db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpAt(WidgetTester tester, Size logicalSize) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = logicalSize;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ControlAlquileresApp(controller: controller));
    await tester.pumpAndSettle();
  }

  const sizes = <String, Size>{
    '1366x768 (objetivo principal)': Size(1366, 768),
    '1280x720 (objetivo secundario)': Size(1280, 720),
    '1093x578 (1366x768 al 125 %)': Size(1093, 578),
    '1024x576 (1280x720 al 125 %)': Size(1024, 576),
    '960x540 (mínimo de ventana)': Size(960, 540),
    '1536x1024 (referencia)': Size(1536, 1024),
  };

  for (final entry in sizes.entries) {
    testWidgets('Inicio sin desbordes en ${entry.key}', (tester) async {
      await pumpAt(tester, entry.value);
      expect(tester.takeException(), isNull);
      expect(find.text('Mis Apartamentos'), findsOneWidget);
      // Inicio es el flujo del día: lista + ficha y un solo botón Cobrar por
      // fila. El formulario de cobro NO se duplica aquí.
      expect(find.text('Cobrar e imprimir'), findsNothing);
      expect(find.text('Pagos realizados - Apartamento 101'), findsNothing);
    });
  }

  testWidgets('barra lateral: 3 destinos + Configuración abajo, con tooltips', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1366, 768));
    // Tres destinos principales y el engranaje de ajustes al pie.
    expect(find.byType(SidebarTooltip), findsNWidgets(4));
    // 4 en la barra lateral (3 destinos + ajustes); el quinto es la marca de
    // la barra superior.
    expect(
      find.descendant(
        of: find.byType(AppSidebar),
        matching: find.byType(AppIconView),
      ),
      findsNWidgets(4),
    );
    expect(find.bySemanticsLabel('Inicio'), findsWidgets);
    expect(find.bySemanticsLabel('Apartamentos'), findsWidgets);
    expect(find.bySemanticsLabel('Cobros'), findsWidgets);
    expect(find.bySemanticsLabel('Configuración'), findsWidgets);
  });

  testWidgets('la barra superior no tiene botones de ventana ni engranaje', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1366, 768));
    // El marco (minimizar/maximizar/cerrar) lo dibuja Windows, no la app.
    expect(find.byIcon(Icons.remove_rounded), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    expect(find.byIcon(Icons.settings_outlined), findsNothing);
    expect(find.text('Control de Alquileres'), findsOneWidget);
    // Ajustes vive en un solo lugar: la barra lateral.
    expect(find.text('Configuración'), findsNothing);
  });

  testWidgets('seleccionar otra fila cambia la ficha del apartamento', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1536, 1024));
    expect(find.text('Apartamento 101'), findsWidgets);

    await tester.tap(find.text('102').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Apartamento 102'), findsWidgets);
  });

  testWidgets('la pestaña Pagos muestra el estado de cuenta por mes', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1536, 1024));
    await tester.tap(find.text('Pagos').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Toque un mes para cobrarlo'), findsOneWidget);
  });

  testWidgets('navegación a Apartamentos y Cobros sin errores', (tester) async {
    await pumpAt(tester, const Size(1366, 768));

    controller.setSection(AppSection.apartamentos);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Historial de contratos'), findsOneWidget);

    controller.setSection(AppSection.cobros);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Cobros'), findsWidgets);
  });

  testWidgets('el cobro rechaza un monto inválido sin guardar nada', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1536, 1024));
    // El formulario vive en Cobros: se navega como lo haría la dueña.
    controller.startPaymentFor(controller.selectedApartmentId!);
    await tester.pumpAndSettle();
    expect(find.text('Cobrar e imprimir'), findsWidgets);

    final amountField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.hintText == '8,500.00',
    );
    expect(amountField, findsOneWidget);
    await tester.enterText(amountField, '99999');
    await tester.pumpAndSettle();

    await tester.tap(find.text('No imprimir ticket').first);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('El monto supera el saldo del período'),
      findsWidgets,
    );
    expect(controller.payments, isEmpty);
  });

  testWidgets('sin datos: la app sigue abriendo', (tester) async {
    controller.purgeDemoData();
    await pumpAt(tester, const Size(1366, 768));
    expect(tester.takeException(), isNull);
    expect(find.text('Mis Apartamentos'), findsOneWidget);
  });
}
