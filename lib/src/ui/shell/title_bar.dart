import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// Barra de título propia (ventana sin borde nativo): azul fina, título a la
/// izquierda, botones de ventana y SOLO el engranaje de ajustes al extremo
/// derecho, tal como en la referencia aprobada.
class AppTitleBar extends StatefulWidget {
  const AppTitleBar({super.key, required this.onSettings});

  final VoidCallback onSettings;

  @override
  State<AppTitleBar> createState() => _AppTitleBarState();
}

class _AppTitleBarState extends State<AppTitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncMaximized();
  }

  Future<void> _syncMaximized() async {
    try {
      final value = await windowManager.isMaximized();
      if (mounted && value != _maximized) setState(() => _maximized = value);
    } catch (_) {
      // Sin plataforma de ventana (pruebas): se mantiene el estado por defecto.
    }
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _maximized = false);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Si no hay ventana nativa disponible se ignora el clic.
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppMetrics.appBarHeight,
      child: Material(
        color: AppColors.appBar,
        child: Row(
          children: [
            Expanded(
              child: DragToMoveArea(
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.apartment_rounded,
                        size: 21,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Control de Alquileres',
                        style: TextStyle(
                          fontFamily: kAppFontFamily,
                          fontFamilyFallback: kAppFontFallback,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _CaptionButton(
              icon: Icons.remove_rounded,
              tooltip: 'Minimizar',
              onTap: () => _guard(windowManager.minimize),
            ),
            _CaptionButton(
              icon: _maximized
                  ? Icons.filter_none_rounded
                  : Icons.crop_square_rounded,
              tooltip: _maximized ? 'Restaurar' : 'Maximizar',
              size: _maximized ? 13 : 15,
              onTap: () => _guard(() async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              }),
            ),
            _CaptionButton(
              icon: Icons.close_rounded,
              tooltip: 'Cerrar',
              isClose: true,
              onTap: () => _guard(windowManager.close),
            ),
            const SizedBox(width: 2),
            _SettingsButton(onTap: widget.onSettings),
          ],
        ),
      ),
    );
  }
}

class _CaptionButton extends StatelessWidget {
  const _CaptionButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.isClose = false,
    this.size = 14,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool isClose;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: SizedBox(
        width: 42,
        height: AppMetrics.appBarHeight,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            hoverColor: isClose
                ? const Color(0xFFC42B1C)
                : Colors.white.withValues(alpha: 0.14),
            child: Center(
              child: Icon(icon, size: size, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Ajustes',
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: Color(0x33FFFFFF))),
        ),
        child: SizedBox(
          width: 44,
          height: AppMetrics.appBarHeight,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              hoverColor: Colors.white.withValues(alpha: 0.14),
              child: const Center(
                child: Icon(
                  Icons.settings_outlined,
                  size: 19,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
