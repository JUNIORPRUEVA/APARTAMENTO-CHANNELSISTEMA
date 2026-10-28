import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../widgets/app_icon.dart';

/// Barra de marca de la aplicación, **debajo** del marco nativo de Windows.
///
/// El marco (minimizar, maximizar/restaurar, cerrar, arrastre, DPI) lo dibuja
/// el sistema operativo. Aquí no hay botones de ventana falsos ni engranaje:
/// Ajustes vive en la barra lateral. Solo se muestra el nombre de la aplicación
/// y, si hay espacio, el residencial activo.
class AppTitleBar extends StatelessWidget {
  const AppTitleBar({super.key, this.subtitle});

  /// Texto secundario opcional (por ejemplo el residencial seleccionado).
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppMetrics.appBarHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          const AppIconView(AppIcon.apartments, size: 20),
          const SizedBox(width: 10),
          Text(
            'Control de Alquileres',
            style: TextStyle(
              fontFamily: kAppFontFamily,
              fontFamilyFallback: kAppFontFallback,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textStrong,
              letterSpacing: 0.1,
            ),
          ),
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(width: 10),
            const Text(
              '·',
              style: TextStyle(fontSize: 13, color: AppColors.textFaint),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
  }
}
