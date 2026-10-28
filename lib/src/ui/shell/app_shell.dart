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

/// Estructura de escritorio: barra de marca fina, barra lateral de iconos,
/// contenido y pie discreto.
///
/// El marco de la ventana (minimizar, maximizar, cerrar) es el **nativo** de
/// Windows; aquí solo se dibuja el contenido.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final apartment = controller.selectedApartment;

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: Column(
        children: [
          AppTitleBar(
            subtitle: apartment == null
                ? null
                : '${apartment.groupName} · Apartamento ${apartment.identifier}',
          ),
          Expanded(
            child: Row(
              children: [
                AppSidebar(
                  current: controller.section,
                  onSelect: controller.setSection,
                  onSettings: () => showSettingsDialog(context),
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
          const AppFooter(),
        ],
      ),
    );
  }
}

/// Pie discreto: solo estado útil (funciona sin internet y dónde están los
/// datos). Sin registros técnicos ni relleno.
class AppFooter extends StatelessWidget {
  const AppFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.greenFg,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'Funciona sin internet · los datos se guardan en este equipo',
            style: TextStyle(fontSize: 12, color: AppColors.textFaint),
          ),
          const Spacer(),
          const Text(
            'Versión 1.2.0',
            style: TextStyle(fontSize: 12, color: AppColors.textFaint),
          ),
        ],
      ),
    );
  }
}
