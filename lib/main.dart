import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'src/app/app_controller.dart';
import 'src/data/app_database.dart';
import 'src/data/app_paths.dart';
import 'src/data/app_paths_resolve.dart';
import 'src/data/portfolio_repository.dart';
import 'src/data/settings_repository.dart';
import 'src/services/backup_service.dart';
import 'src/services/startup_service.dart';
import 'src/theme/app_colors.dart';
import 'src/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await windowManager.ensureInitialized();
  } catch (_) {
    // Sin gestor de ventanas disponible: la app puede abrirse igual.
  }

  final AppPaths paths;
  final AppDatabase database;
  try {
    paths = await resolveAppPaths();
    database = AppDatabase.openAt(paths.databaseFile);
  } catch (error) {
    runApp(_StartupErrorApp(detail: error.toString()));
    return;
  }

  final controller = AppController(
    database: database,
    portfolio: PortfolioRepository(database),
    settings: SettingsRepository(database),
    paths: paths,
  )..initialize();

  final startup = StartupService(database).run();
  final backup = BackupService(database: database, paths: paths);

  final notices = <String>[];
  if (controller.demoSeededNow) {
    notices.add(
      'Se cargaron datos de demostración para revisar el diseño. '
      'Puede eliminarlos desde Ajustes.',
    );
  }
  if (startup.hasIntegrityIssue) {
    notices.add(
      'La verificación de los datos encontró un problema. '
      'Revise las copias de seguridad en Ajustes.',
    );
  } else if (startup.pendingDocuments > 0) {
    notices.add(
      'Hay ${startup.pendingDocuments} recibo(s) con PDF pendiente. '
      'Se regenerarán sin volver a cobrar.',
    );
  }

  try {
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: const Size(1366, 768),
        // En un portátil de 1366x768 al 125 % el área lógica útil ronda
        // 1093x578, por eso el mínimo debe quedar por debajo de eso.
        minimumSize: const Size(960, 540),
        center: true,
        backgroundColor: AppColors.pageBg,
        titleBarStyle: TitleBarStyle.hidden,
        title: 'Control de Alquileres',
      ),
      () async {
        await windowManager.maximize();
        await windowManager.show();
        await windowManager.focus();
      },
    );
  } catch (_) {
    // Si el entorno no permite gestionar la ventana, se continúa igual.
  }

  runApp(ControlAlquileresApp(controller: controller, startupNotices: notices));

  // Copia de seguridad silenciosa, después del primer fotograma.
  WidgetsBinding.instance.addPostFrameCallback((_) => backup.runIfDue());
}

/// Pantalla mínima de error de arranque: nunca muestra una traza técnica.
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.detail});

  final String detail;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: AppColors.pageBg,
        body: Center(
          child: Container(
            width: 460,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AppColors.redFg,
                    ),
                    const SizedBox(width: 9),
                    Text(
                      'No se pudieron abrir los datos',
                      style: appText.cardTitle.copyWith(fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Cierre la aplicación e intente de nuevo. Si el problema '
                  'continúa, restaure la copia de seguridad más reciente de la '
                  'carpeta de copias.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  detail,
                  maxLines: 4,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textFaint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
