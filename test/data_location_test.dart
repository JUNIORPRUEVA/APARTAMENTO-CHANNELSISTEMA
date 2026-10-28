import 'dart:io';

import 'package:control_alquileres/src/data/data_location.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// El sandbox debe **fallar cerrado**: si le falta la carpeta o apunta a los
/// datos reales, la herramienta aborta en vez de escribir donde no debe.
void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('sandbox_guard_');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('la carpeta de producción se reconoce por su ruta', () {
    final production = productionDataDir();
    expect(production, contains('do.channelsistema'));
    expect(production, endsWith(p.join('Control de Alquileres', 'datos')));

    expect(isProductionDataDir(production), isTrue);
    // Mayúsculas/separadores distintos siguen siendo la misma carpeta.
    expect(isProductionDataDir(production.toUpperCase()), isTrue);
    expect(isProductionDataDir(p.join(production, '.')), isTrue);
    // Una subcarpeta también está protegida.
    expect(isInsideProductionData(p.join(production, 'recibos')), isTrue);
    expect(isInsideProductionData(temp.path), isFalse);
  });

  test('sin carpeta indicada se niega (no asume la real)', () {
    expect(
      () => requireSandboxPaths(null, tool: 'prueba'),
      throwsA(isA<SandboxViolation>()),
    );
    expect(
      () => requireSandboxPaths('   ', tool: 'prueba'),
      throwsA(isA<SandboxViolation>()),
    );
  });

  test('se niega a usar la carpeta real o algo dentro de ella', () {
    final production = productionDataDir();
    expect(
      () => requireSandboxPaths(production, tool: 'prueba'),
      throwsA(
        isA<SandboxViolation>().having(
          (e) => e.message,
          'mensaje',
          contains('se negó a escribir en la carpeta de datos real'),
        ),
      ),
    );
    expect(
      () => requireSandboxPaths(p.join(production, 'copias'), tool: 'prueba'),
      throwsA(isA<SandboxViolation>()),
    );
  });

  test('una carpeta temporal válida devuelve la estructura completa', () {
    final paths = requireSandboxPaths(temp.path, tool: 'prueba');
    expect(paths.dataDir, p.normalize(p.absolute(temp.path)));
    expect(Directory(paths.receiptsDir).existsSync(), isTrue);
    expect(Directory(paths.backupsDir).existsSync(), isTrue);
    expect(p.basename(paths.databaseFile), 'control_alquileres.sqlite');
    // La sonda de escritura no deja basura.
    expect(File(p.join(paths.dataDir, '.sandbox-probe')).existsSync(), isFalse);
  });

  test('una ruta que no se puede escribir aborta', () {
    final blocked = File(p.join(temp.path, 'archivo.txt'))
      ..writeAsStringSync('x');
    expect(
      () => requireSandboxPaths(p.join(blocked.path, 'datos'), tool: 'prueba'),
      throwsA(isA<SandboxViolation>()),
    );
  });
}
