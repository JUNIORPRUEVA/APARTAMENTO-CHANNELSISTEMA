import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_scope.dart';
import '../../theme/app_colors.dart';
import '../pages/apartments/apartments_page.dart';
import '../pages/cobros/cobros_page.dart';
import '../pages/home/home_page.dart';
import '../pages/settings/settings_page.dart';
import 'sidebar.dart';
import 'title_bar.dart';

/// Estructura de escritorio: barra azul fina, barra lateral de tres iconos y
/// contenido. No hay inicio de sesión ni navegación adicional.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Column(
        children: [
          AppTitleBar(onSettings: () => showSettingsDialog(context)),
          Expanded(
            child: Row(
              children: [
                AppSidebar(
                  current: controller.section,
                  onSelect: controller.setSection,
                ),
                Expanded(
                  child: switch (controller.section) {
                    AppSection.inicio => const HomePage(),
                    AppSection.apartamentos => const ApartmentsPage(),
                    AppSection.cobros => const CobrosPage(),
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
