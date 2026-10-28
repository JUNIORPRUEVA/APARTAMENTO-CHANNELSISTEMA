import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/app_failure.dart';
import '../data/app_database.dart';
import '../data/app_paths.dart';

class BackupEntry {
  const BackupEntry({
    required this.path,
    required this.createdAt,
    required this.bytes,
  });

  final String path;
  final DateTime createdAt;
  final int bytes;
}

class BackupReport {
  const BackupReport({
    required this.path,
    required this.createdAt,
    required this.bytes,
    required this.copiedReceipts,
  });

  final String path;
  final DateTime createdAt;
  final int bytes;
  final int copiedReceipts;
}

/// Copias de seguridad locales automáticas.
///
/// La base no se copia "en caliente" con una copia de archivo (podría quedar
/// inconsistente con WAL). Se usa `VACUUM INTO`, que genera una base completa y
/// consistente en un único archivo, y luego se copian los PDF de recibos.
class BackupService {
  BackupService({required this.database, required this.paths});

  final AppDatabase database;
  final AppPaths paths;

  static const Duration _minimumInterval = Duration(hours: 24);
  static const int _keep = 14;
  static const String _metaKey = 'ultima_copia';

  DateTime? get lastRun {
    final value = database.meta(_metaKey);
    return value == null ? null : DateTime.tryParse(value);
  }

  bool get isDue {
    final last = lastRun;
    if (last == null) return true;
    return DateTime.now().difference(last) >= _minimumInterval;
  }

  /// Ejecuta la copia si corresponde. Nunca lanza: los fallos se registran en
  /// el historial interno y no interrumpen el trabajo del usuario.
  BackupReport? runIfDue() {
    if (!isDue) return null;
    try {
      return runNow();
    } catch (error) {
      database.logEvent('copia_error', error.toString());
      return null;
    }
  }

  BackupReport runNow() {
    final stamp = _stamp(DateTime.now());
    final folder = Directory(p.join(paths.backupsDir, 'copia-$stamp'))
      ..createSync(recursive: true);
    final target = p.join(folder.path, 'control_alquileres.sqlite');

    database.run('VACUUM INTO ?', [target]);

    var copied = 0;
    final receipts = Directory(paths.receiptsDir);
    if (receipts.existsSync()) {
      final destination = Directory(p.join(folder.path, 'recibos'))
        ..createSync(recursive: true);
      for (final entity in receipts.listSync()) {
        if (entity is File) {
          entity.copySync(p.join(destination.path, p.basename(entity.path)));
          copied++;
        }
      }
    }

    final size = File(target).lengthSync();
    final createdAt = DateTime.now();
    database.setMeta(_metaKey, createdAt.toIso8601String());
    database.logEvent('copia', '$target ($size bytes, $copied recibos)');
    _pruneOld();

    return BackupReport(
      path: folder.path,
      createdAt: createdAt,
      bytes: size,
      copiedReceipts: copied,
    );
  }

  /// Exporta la copia más reciente a otra carpeta (por ejemplo una memoria
  /// USB). Devuelve la ruta creada.
  String exportLatestTo(String targetDir) {
    final entries = list();
    if (entries.isEmpty) {
      throw const AppFailure('Todavía no hay copias para exportar.');
    }
    final source = Directory(entries.first.path);
    final destination = Directory(p.join(targetDir, 'control-alquileres-copia'))
      ..createSync(recursive: true);
    for (final entity in source.listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: source.path);
      final target = File(p.join(destination.path, relative));
      target.parent.createSync(recursive: true);
      entity.copySync(target.path);
    }
    database.logEvent('exportacion', destination.path);
    return destination.path;
  }

  /// Restaura una copia sobre la base en uso.
  ///
  /// Antes de tocar nada crea una copia de seguridad del estado actual y
  /// verifica la integridad del archivo de origen. Deja la base cerrada: la
  /// aplicación debe reiniciarse inmediatamente después.
  String? restore(BackupEntry entry) {
    final source = File(p.join(entry.path, 'control_alquileres.sqlite'));
    if (!source.existsSync()) {
      return 'La copia seleccionada está incompleta.';
    }
    final problem = AppDatabase.checkFile(source.path);
    if (problem != null) {
      return 'La copia está dañada y no se puede restaurar.';
    }

    final stamp = _stamp(DateTime.now());
    final safety = Directory(
      p.join(paths.backupsDir, 'pre-restauracion-$stamp'),
    )..createSync(recursive: true);
    database.run('VACUUM INTO ?', [
      p.join(safety.path, 'control_alquileres.sqlite'),
    ]);

    database.close();
    for (final suffix in ['-wal', '-shm']) {
      final file = File('${paths.databaseFile}$suffix');
      if (file.existsSync()) file.deleteSync();
    }
    // Reemplazo atómico: se copia a un temporal y se renombra. Si se corta la
    // luz a mitad de la copia, la base de trabajo sigue siendo la anterior
    // (nunca queda un archivo truncado en su lugar).
    final staging = File('${paths.databaseFile}.restaurando');
    if (staging.existsSync()) staging.deleteSync();
    source.copySync(staging.path);
    staging.renameSync(paths.databaseFile);

    // Copia los recibos incluidos en la copia, si existen.
    final receipts = Directory(p.join(entry.path, 'recibos'));
    if (receipts.existsSync()) {
      for (final entity in receipts.listSync()) {
        if (entity is! File) continue;
        entity.copySync(p.join(paths.receiptsDir, p.basename(entity.path)));
      }
    }
    return null;
  }

  List<BackupEntry> list() {
    final dir = Directory(paths.backupsDir);
    if (!dir.existsSync()) return const [];
    final entries = <BackupEntry>[];
    for (final entity in dir.listSync()) {
      if (entity is! Directory) continue;
      final file = File(p.join(entity.path, 'control_alquileres.sqlite'));
      if (!file.existsSync()) continue;
      entries.add(
        BackupEntry(
          path: entity.path,
          createdAt: file.lastModifiedSync(),
          bytes: file.lengthSync(),
        ),
      );
    }
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }

  void _pruneOld() {
    final entries = list();
    for (final entry in entries.skip(_keep)) {
      try {
        Directory(entry.path).deleteSync(recursive: true);
      } catch (_) {
        // Si Windows mantiene un archivo abierto, se reintenta en la próxima.
      }
    }
  }

  static String _stamp(DateTime date) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${date.year}${two(date.month)}${two(date.day)}-'
        '${two(date.hour)}${two(date.minute)}${two(date.second)}';
  }
}
