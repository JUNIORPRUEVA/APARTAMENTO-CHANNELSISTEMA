import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_paths.dart';

/// Variable de entorno para **aislar** los datos (pruebas y aceptación).
///
/// La aplicación real nunca la usa: sus datos viven en las carpetas conocidas
/// de Windows. Sirve para ejecutar el binario contra una carpeta temporal y no
/// tocar jamás la base de la dueña:
///
/// ```powershell
/// $env:CONTROL_ALQUILERES_DATA_DIR = "$env:TEMP\ca-sandbox\datos"
/// .\control_alquileres.exe
/// ```
const String kDataDirEnvVar = 'CONTROL_ALQUILERES_DATA_DIR';

/// Resuelve las rutas persistentes de la aplicación en Windows.
///
/// Vive en un archivo aparte para que el resto de la capa de datos siga siendo
/// Dart puro (testeable y utilizable desde herramientas de línea de comandos).
///
/// Orden de decisión:
/// 1. `CONTROL_ALQUILERES_DATA_DIR` (solo para pruebas: sandbox explícito).
/// 2. Carpeta de soporte de la aplicación (`%APPDATA%\…\datos`).
Future<AppPaths> resolveAppPaths() async {
  final override = Platform.environment[kDataDirEnvVar]?.trim();
  if (override != null && override.isNotEmpty) {
    return AppPaths.create(p.normalize(override));
  }
  final support = await getApplicationSupportDirectory();
  return AppPaths.create(p.join(support.path, 'datos'));
}
