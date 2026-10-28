// Siembra un conjunto UAT aislado (~70 apartamentos) para pruebas manuales.
//
// Nunca toca la base real: escribe en una carpeta aparte, por defecto
// `%TEMP%\alquileres-uat`. Uso:
//
//   dart run tool/uat_seed.dart
//   dart run tool/uat_seed.dart "D:\otra\carpeta"
//
// Luego abra la aplicación con esa carpeta de datos si desea revisar el
// escenario completo: los recibos se generan en `<carpeta>\recibos`.
import 'dart:io';

import 'package:control_alquileres/src/core/formatters.dart';
import 'package:control_alquileres/src/data/app_database.dart';
import 'package:control_alquileres/src/data/app_paths.dart';
import 'package:control_alquileres/src/data/data_location.dart';
import 'package:control_alquileres/src/data/finance_repository.dart';
import 'package:control_alquileres/src/data/portfolio_repository.dart';
import 'package:control_alquileres/src/dev/uat_fixture.dart';
import 'package:control_alquileres/src/services/receipt_document_service.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final base = args.isNotEmpty
      ? args.first
      : p.join(Directory.systemTemp.path, 'alquileres-uat');
  final AppPaths paths;
  try {
    paths = requireSandboxPaths(
      base,
      tool: 'uat_seed',
      hint:
          'Siembra un escenario de prueba; nunca debe apuntar a datos reales.',
    );
  } on SandboxViolation catch (error) {
    stderr.writeln(error.message);
    exitCode = 4;
    return;
  }
  final dataDir = paths.dataDir;

  final dbPath = paths.databaseFile;
  if (File(dbPath).existsSync()) {
    stdout.writeln('La base ya existía; se usa la existente: $dbPath');
  }

  final database = AppDatabase.openAt(dbPath);
  try {
    final existing = PortfolioRepository(database).countApartments();
    if (existing > 0) {
      stdout.writeln(
        'La base ya tiene $existing apartamentos. '
        'No se vuelve a sembrar (borre la carpeta para empezar de cero).',
      );
      return;
    }

    final summary = UatFixture(database).seed();
    stdout.writeln(summary);

    final finance = FinanceRepository(database);
    final documents = ReceiptDocumentService(
      finance: finance,
      paths: paths,
      currentWidthMm: () => 80,
      currentMarginMm: () => 3.5,
    );
    var generated = 0;
    // Se procesa por lotes hasta que no queden pendientes.
    for (var round = 0; round < 40; round++) {
      final batch = finance.receiptsNeedingPdf(limit: 200);
      if (batch.isEmpty) break;
      for (final record in batch) {
        final result = await documents.ensure(record);
        if (result.ok) generated++;
      }
    }

    final pending = finance.receiptsNeedingPdf(limit: 5000).length;
    final integrity = database.quickCheck();
    stdout
      ..writeln('PDF generados: $generated')
      ..writeln('Recibos pendientes: $pending')
      ..writeln('Integridad de la base: ${integrity ?? 'correcta'}')
      ..writeln('Carpeta de datos: $dataDir');

    final totals = database
        .rows(
          'SELECT COUNT(*) AS c, COALESCE(SUM(amount_cents), 0) AS t FROM payments',
        )
        .first;
    stdout.writeln(
      'Cobros en base: ${totals['c']} por ${formatMoney(totals['t'] as int)}',
    );
  } finally {
    database.close();
  }
}
