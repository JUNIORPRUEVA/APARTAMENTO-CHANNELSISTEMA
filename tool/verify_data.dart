// Diagnóstico de una copia de la base real (no modifica el original).
//
// Copia `control_alquileres.sqlite` (con su WAL) a una carpeta temporal, la
// abre con el esquema actual (aplicando migraciones sobre la COPIA), y reporta
// versión, conteos e integridad. Sirve para verificar que la próxima apertura
// de la aplicación funcionará antes de tocar los datos de la dueña.
//
//   dart run tool/verify_data.dart
//   dart run tool/verify_data.dart "D:\ruta\control_alquileres.sqlite"
import 'dart:io';

import 'package:control_alquileres/src/data/app_database.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final source = args.isNotEmpty
      ? args.first
      : p.join(
          Platform.environment['APPDATA'] ?? '',
          'do.channelsistema',
          'Control de Alquileres',
          'datos',
          'control_alquileres.sqlite',
        );

  final original = File(source);
  if (!original.existsSync()) {
    stderr.writeln('No se encontró la base: $source');
    exitCode = 1;
    return;
  }

  final work = Directory.systemTemp.createTempSync('ca_verificar_');
  final copy = p.join(work.path, 'copia.sqlite');
  try {
    original.copySync(copy);
    for (final suffix in ['-wal', '-shm']) {
      final side = File('${original.path}$suffix');
      if (side.existsSync()) side.copySync('$copy$suffix');
    }

    final before = _peekVersion(copy);
    stdout.writeln('Archivo original : $source');
    stdout.writeln(
      'Versión de origen : ${before >= 0 ? before : 'en WAL (se resuelve al abrir)'}',
    );

    final db = AppDatabase.openAt(copy);
    try {
      stdout
        ..writeln('Versión en la copia: ${db.userVersion}')
        ..writeln('Integridad        : ${db.quickCheck() ?? 'correcta'}')
        ..writeln('Residenciales     : ${_count(db, 'apartment_groups')}')
        ..writeln('Apartamentos      : ${_count(db, 'apartments')}')
        ..writeln('Inquilinos        : ${_count(db, 'tenants')}')
        ..writeln('Contratos         : ${_count(db, 'leases')}')
        ..writeln('Cobros            : ${_count(db, 'payments')}')
        ..writeln('Recibos           : ${_count(db, 'receipts')}')
        ..writeln('Depósitos         : ${_count(db, 'deposit_movements')}');
      final pendingPdf = db.rows(
        'SELECT COUNT(*) AS c FROM receipts WHERE pdf_status <> ?',
        ['generado'],
      ).first['c'];
      stdout.writeln('Recibos sin PDF   : $pendingPdf');
      final withPdf = db
          .rows('SELECT COUNT(*) AS c FROM receipts WHERE pdf_path IS NOT NULL')
          .first['c'];
      stdout.writeln('Recibos con PDF   : $withPdf');
      stdout.writeln(
        'Resultado: la copia se abrió en la versión ${db.userVersion} '
        'sin errores. El original no se modificó.',
      );
    } finally {
      db.close();
    }
  } finally {
    try {
      work.deleteSync(recursive: true);
    } catch (_) {
      // Windows puede mantener el archivo bloqueado un instante.
    }
  }
}

int _count(AppDatabase db, String table) =>
    db.rows('SELECT COUNT(*) AS c FROM $table').first['c'] as int;

int _peekVersion(String path) {
  // La cabecera SQLite guarda `user_version` en los bytes 80–83 (big-endian),
  // pero en modo WAL el valor puede vivir todavía en el `-wal`. Por eso esto es
  // solo informativo: la versión real es la que reporta el cliente al abrir.
  try {
    final bytes = File(path).readAsBytesSync();
    if (bytes.length < 100) return -1;
    return (bytes[80] << 24) | (bytes[81] << 16) | (bytes[82] << 8) | bytes[83];
  } catch (_) {
    return -1;
  }
}
