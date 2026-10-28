import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_paths.dart';

/// Se lanza cuando una herramienta o prueba intenta escribir en la carpeta de
/// datos **real** de la dueña.
///
/// Es deliberadamente una excepción y no un aviso: un script que creía estar en
/// un sandbox y termina migrando o sembrando datos de prueba sobre la base real
/// es el peor fallo posible. Se prefiere abortar.
class SandboxViolation implements Exception {
  SandboxViolation(this.message);
  final String message;

  @override
  String toString() => 'SandboxViolation: $message';
}

/// Carpeta de datos de **producción** (la que usa la aplicación instalada).
///
/// Se calcula sin `path_provider` para poder usarla desde herramientas de
/// consola y pruebas. En Windows es
/// `%APPDATA%\do.channelsistema\Control de Alquileres\datos`.
String productionDataDir() {
  final appData =
      Platform.environment['APPDATA'] ??
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '';
  return p.join(appData, 'do.channelsistema', 'Control de Alquileres', 'datos');
}

/// `true` si [path] es exactamente la carpeta de datos real.
bool isProductionDataDir(String path) {
  final candidate = p.normalize(p.absolute(path));
  final production = p.normalize(p.absolute(productionDataDir()));
  return p.equals(candidate, production);
}

/// `true` si [path] está dentro de la carpeta de datos real (o es ella).
bool isInsideProductionData(String path) {
  final candidate = p.normalize(p.absolute(path));
  final production = p.normalize(p.absolute(productionDataDir()));
  return p.equals(candidate, production) || p.isWithin(production, candidate);
}

/// Rutas de trabajo **aisladas** para herramientas y pruebas.
///
/// Reglas (fallar cerrado):
/// 1. La ruta debe venir indicada de forma explícita (argumento o variable de
///    entorno). Si falta, se aborta: no se asume la carpeta real.
/// 2. La ruta no puede ser la carpeta de producción ni estar dentro de ella.
/// 3. Se crea la estructura pero se comprueba que se puede escribir de verdad.
AppPaths requireSandboxPaths(
  String? requested, {
  required String tool,
  String? hint,
}) {
  final raw = (requested ?? '').trim();
  if (raw.isEmpty) {
    throw SandboxViolation(
      '$tool necesita una carpeta de trabajo aislada.\n'
      'Ejemplo: control_alquileres DATA_DIR="%TEMP%\\ca-sandbox\\datos"\n'
      '${hint ?? ''}',
    );
  }
  if (isInsideProductionData(raw)) {
    throw SandboxViolation(
      '$tool se negó a escribir en la carpeta de datos real:\n  $raw\n'
      'Use una carpeta temporal (sandbox) y vuelva a intentarlo.',
    );
  }

  final AppPaths paths;
  try {
    paths = AppPaths.create(raw);
  } catch (error) {
    throw SandboxViolation(
      'La carpeta de trabajo no se pudo preparar ($raw): $error',
    );
  }

  // Comprobación real de escritura: si el sandbox no es utilizable, se aborta
  // en vez de caer silenciosamente en otra carpeta.
  final probe = File(p.join(paths.dataDir, '.sandbox-probe'));
  try {
    probe.writeAsStringSync('ok', flush: true);
    probe.deleteSync();
  } catch (error) {
    throw SandboxViolation(
      'La carpeta de trabajo no se puede escribir ($raw): $error',
    );
  }
  return paths;
}

/// Resuelve la carpeta indicada por `CONTROL_ALQUILERES_DATA_DIR`, exigiendo
/// que exista y sea un sandbox válido.
AppPaths requireSandboxFromEnv({required String tool, String? hint}) {
  final env = Platform.environment['CONTROL_ALQUILERES_DATA_DIR'];
  return requireSandboxPaths(env, tool: tool, hint: hint);
}
