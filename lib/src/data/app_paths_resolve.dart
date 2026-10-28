import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_paths.dart';

/// Resuelve las rutas persistentes de la aplicación en Windows.
///
/// Vive en un archivo aparte para que el resto de la capa de datos siga siendo
/// Dart puro (testeable y utilizable desde herramientas de línea de comandos).
Future<AppPaths> resolveAppPaths() async {
  final support = await getApplicationSupportDirectory();
  return AppPaths.create(p.join(support.path, 'datos'));
}
