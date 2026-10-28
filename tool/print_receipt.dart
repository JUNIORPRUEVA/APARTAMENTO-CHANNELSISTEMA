// Imprime un recibo REAL (ya guardado) por un puerto COM, y deja los bytes en
// un archivo `.bin` para poder inspeccionarlos.
//
// Pensado para la prueba de aceptación en el sitio: demuestra que el recibo que
// ve el dueño en PDF es el mismo snapshot que sale por la impresora térmica.
//
//   dart run tool/print_receipt.dart COM5                       (último recibo)
//   dart run tool/print_receipt.dart COM5 REC-00000123
//   dart run tool/print_receipt.dart COM5 REC-00000123 9600 576
//   dart run tool/print_receipt.dart --solo-bin REC-00000123   (no imprime)
//
// La base se lee de `CONTROL_ALQUILERES_DATA_DIR` si está definida (sandbox) o
// de la carpeta real de datos. **Nunca escribe** en la base.
import 'dart:io';

import 'package:control_alquileres/src/data/app_database.dart';
import 'package:control_alquileres/src/data/finance_models.dart';
import 'package:control_alquileres/src/data/finance_repository.dart';
import 'package:control_alquileres/src/data/settings_repository.dart';
import 'package:control_alquileres/src/services/escpos.dart';
import 'package:control_alquileres/src/services/printer_profile.dart';
import 'package:control_alquileres/src/services/serial_transport.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final onlyBin = args.isNotEmpty && args.first == '--solo-bin';
  final rest = onlyBin ? args.sublist(1) : args;
  if (rest.isEmpty && !onlyBin) {
    stderr.writeln(
      'Uso: dart run tool/print_receipt.dart <COMn> [REC-00000001] '
      '[baudios] [puntos]\n'
      '     dart run tool/print_receipt.dart --solo-bin [REC-00000001]',
    );
    exitCode = 64;
    return;
  }

  final port = onlyBin ? '' : rest[0].toUpperCase();
  final label = onlyBin
      ? (rest.isEmpty ? '' : rest[0])
      : (rest.length > 1 && rest[1].toUpperCase().startsWith('REC')
            ? rest[1]
            : '');
  final baud =
      int.tryParse(
        onlyBin
            ? (rest.length > 1 ? rest[1] : '')
            : (rest.length > 2 ? rest[2] : ''),
      ) ??
      9600;
  final dots =
      int.tryParse(
        onlyBin
            ? (rest.length > 2 ? rest[2] : '')
            : (rest.length > 3 ? rest[3] : ''),
      ) ??
      0;

  final dataDir =
      Platform.environment['CONTROL_ALQUILERES_DATA_DIR']?.trim() ?? '';
  final dbPath = dataDir.isNotEmpty
      ? p.join(dataDir, 'control_alquileres.sqlite')
      : p.join(
          Platform.environment['APPDATA'] ?? '',
          'do.channelsistema',
          'Control de Alquileres',
          'datos',
          'control_alquileres.sqlite',
        );
  if (!File(dbPath).existsSync()) {
    stderr.writeln('No se encontró la base: $dbPath');
    exitCode = 1;
    return;
  }

  final db = AppDatabase.openAt(dbPath);
  try {
    final finance = FinanceRepository(db);
    final settings = SettingsRepository(db).load();
    final records = _pick(finance, label);
    if (records.isEmpty) {
      stderr.writeln('No hay recibos en la base (o el número no existe).');
      exitCode = 2;
      return;
    }
    final record = records.first;
    final profile = PrinterProfile(
      paperWidthMm: settings.receiptWidthMm,
      printableDots: dots > 0 ? dots : settings.printerPrintableDots,
      marginDots: settings.printerMarginDots,
      baudRate: baud,
      asciiOnly: settings.asciiOnly,
    );
    final bytes = EscPosReceipt.build(record, profile: profile);

    final binPath = p.join(Directory.systemTemp.path, '${record.label}.bin');
    File(binPath).writeAsBytesSync(bytes, flush: true);
    stdout
      ..writeln('Recibo: ${record.label} · ${record.kind.title}')
      ..writeln('Total : ${record.totalCents / 100}')
      ..writeln('Perfil: $profile')
      ..writeln('Bytes : ${bytes.length} → $binPath');

    if (onlyBin) {
      stdout.writeln('Modo --solo-bin: no se envió nada a la impresora.');
      return;
    }

    const transport = Win32SerialTransport();
    await transport.send(port, bytes, baudRate: baud);
    stdout.writeln('Enviado a $port. Revise el ticket y rasgue el papel.');
  } catch (error) {
    stderr.writeln('Falló: $error');
    exitCode = 1;
  } finally {
    db.close();
  }
}

List<ReceiptRecord> _pick(FinanceRepository finance, String label) {
  if (label.isEmpty) {
    final ids = finance.receiptsWithGeneratedPdf(limit: 1);
    if (ids.isNotEmpty) return ids;
    return finance.receiptsNeedingPdf(limit: 1);
  }
  final rows = label.split('-');
  final number = int.tryParse(rows.last.padLeft(1, '0'));
  if (number == null) return const [];
  for (final record in finance.receiptsNeedingPdf(limit: 5000)) {
    if (record.number == number) return [record];
  }
  for (final record in finance.receiptsWithGeneratedPdf(limit: 5000)) {
    if (record.number == number) return [record];
  }
  return const [];
}
