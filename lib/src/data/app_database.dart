import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../core/app_failure.dart';
import 'schema.dart';

/// Base de datos local (SQLite embebido, sin red).
///
/// Durabilidad: se activa WAL (escrituras atómicas por página y lectores sin
/// bloqueo) y `synchronous = FULL`, de modo que una confirmación no se pierde
/// si se corta la energía justo después del COMMIT. `foreign_keys` se activa
/// por conexión, porque SQLite lo desactiva por defecto.
class AppDatabase {
  AppDatabase._(this._db, this.path);

  final Database _db;
  final String path;
  bool _inTransaction = false;
  bool _closed = false;

  static AppDatabase openAt(String filePath) {
    final raw = sqlite3.open(filePath);
    final database = AppDatabase._(raw, filePath);
    try {
      database._configure();
      database._migrate();
      return database;
    } catch (_) {
      raw.close();
      rethrow;
    }
  }

  /// Base de datos en memoria (pruebas y datos de demostración aislados).
  static AppDatabase inMemory() {
    final raw = sqlite3.openInMemory();
    final database = AppDatabase._(raw, ':memory:');
    database._configure();
    database._migrate();
    return database;
  }

  Database get raw => _db;

  void _configure() {
    _db.execute('PRAGMA foreign_keys = ON');
    _db.execute('PRAGMA busy_timeout = 5000');
    // En bases en memoria SQLite responde 'memory' sin error: es correcto.
    _db.execute('PRAGMA journal_mode = WAL');
    _db.execute('PRAGMA synchronous = FULL');
  }

  int get userVersion =>
      _db.select('PRAGMA user_version').first.columnAt(0) as int;

  void _migrate() {
    final version = userVersion;
    if (version == kSchemaVersion) return;

    if (version > kSchemaVersion) {
      throw const AppFailure(
        'Los datos fueron creados por una versión más nueva del sistema. '
        'Actualice la aplicación para abrirlos.',
      );
    }

    if (version == 0) {
      tx(() {
        for (final statement in kSchemaStatements) {
          _db.execute(statement);
        }
        _db.execute('PRAGMA user_version = $kSchemaVersion');
      });
      return;
    }

    // Cada paso se aplica en su propia transacción: si algo falla, la base
    // queda exactamente en la versión anterior (recuperable desde una copia).
    var current = version;
    while (current < kSchemaVersion) {
      if (current == 1) {
        _applyStep(kMigrationV2Statements, 2);
        current = 2;
      } else if (current == 2) {
        _applyStep(kMigrationV3Statements, 3);
        current = 3;
      } else if (current == 3) {
        _applyStep(kMigrationV4Statements, 4);
        current = 4;
      } else {
        throw AppFailure(
          'Falta una migración de la base de datos (versión $current).',
        );
      }
    }
  }

  void _applyStep(List<String> statements, int targetVersion) {
    tx(() {
      for (final statement in statements) {
        _db.execute(statement);
      }
      _db.execute('PRAGMA user_version = $targetVersion');
    });
    logEvent('migracion', 'Base actualizada a la versión $targetVersion.');
  }

  /// Transacción explícita. `BEGIN IMMEDIATE` toma el bloqueo de escritura de
  /// inmediato, lo que evita fallos a mitad de una operación financiera.
  T tx<T>(T Function() action) {
    if (_inTransaction) {
      // SQLite no admite transacciones anidadas: se reutiliza la externa.
      return action();
    }
    _db.execute('BEGIN IMMEDIATE');
    _inTransaction = true;
    try {
      final result = action();
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      try {
        _db.execute('ROLLBACK');
      } catch (_) {
        // El rollback automático ya ocurrió (p. ej. error fatal de E/S).
      }
      rethrow;
    } finally {
      _inTransaction = false;
    }
  }

  List<Map<String, Object?>> rows(
    String sql, [
    List<Object?> params = const [],
  ]) {
    final result = _db.select(sql, params);
    return result.map((row) => row.map((k, v) => MapEntry(k, v))).toList();
  }

  void run(String sql, [List<Object?> params = const []]) =>
      _db.execute(sql, params);

  int get lastInsertId => _db.lastInsertRowId;

  String? meta(String key) {
    final result = _db.select(
      'SELECT value FROM app_meta WHERE key = ? LIMIT 1',
      [key],
    );
    return result.isEmpty ? null : result.first['value'] as String;
  }

  void setMeta(String key, String value) {
    _db.execute(
      'INSERT INTO app_meta (key, value) VALUES (?, ?) '
      'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
      [key, value],
    );
  }

  void logEvent(String kind, String detail) {
    _db.execute(
      'INSERT INTO app_events (kind, detail, created_at) VALUES (?, ?, ?)',
      [kind, detail, DateTime.now().toIso8601String()],
    );
  }

  /// Integridad rápida al arrancar. Devuelve null si todo está bien.
  String? quickCheck() {
    final result = _db.select('PRAGMA quick_check');
    if (result.isEmpty) return 'Sin respuesta de la verificación.';
    final value = result.first.columnAt(0)?.toString() ?? '';
    return value.toLowerCase() == 'ok' ? null : value;
  }

  /// Verifica un archivo de base sin abrirlo para la aplicación.
  static String? checkFile(String path) {
    if (!File(path).existsSync()) return 'El archivo no existe.';
    Database? handle;
    try {
      handle = sqlite3.open(path);
      final result = handle.select('PRAGMA quick_check');
      final value = result.isEmpty
          ? ''
          : (result.first.columnAt(0)?.toString() ?? '');
      return value.toLowerCase() == 'ok' ? null : value;
    } catch (error) {
      return error.toString();
    } finally {
      handle?.close();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _db.close();
  }
}

/// Detecta violaciones de restricción UNIQUE / PRIMARY KEY.
bool isUniqueViolation(Object error) {
  if (error is! SqliteException) return false;
  // 19 = SQLITE_CONSTRAINT; 2067 = SQLITE_CONSTRAINT_UNIQUE;
  // 1555 = SQLITE_CONSTRAINT_PRIMARYKEY
  return error.resultCode == 19 ||
      error.extendedResultCode == 2067 ||
      error.extendedResultCode == 1555;
}

bool isForeignKeyViolation(Object error) =>
    error is SqliteException &&
    (error.resultCode == 19 || error.extendedResultCode == 787);
