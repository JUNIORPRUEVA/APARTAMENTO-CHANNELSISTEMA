import 'dart:io';

import 'package:path/path.dart' as p;

/// Rutas persistentes de la aplicación. Nunca se usa la carpeta del
/// ejecutable (`build`/instalación): los datos viven en
/// `%APPDATA%\<empresa>\<producto>\datos`.
class AppPaths {
  const AppPaths({
    required this.dataDir,
    required this.databaseFile,
    required this.receiptsDir,
    required this.backupsDir,
  });

  final String dataDir;
  final String databaseFile;
  final String receiptsDir;
  final String backupsDir;

  /// Construye (sin plataforma) una estructura de carpetas concreta.
  static AppPaths create(String dataDir) {
    final receipts = p.join(dataDir, 'recibos');
    final backups = p.join(dataDir, 'copias');
    Directory(dataDir).createSync(recursive: true);
    Directory(receipts).createSync(recursive: true);
    Directory(backups).createSync(recursive: true);
    return AppPaths(
      dataDir: dataDir,
      databaseFile: p.join(dataDir, 'control_alquileres.sqlite'),
      receiptsDir: receipts,
      backupsDir: backups,
    );
  }
}
