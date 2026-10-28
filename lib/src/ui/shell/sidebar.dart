import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../theme/app_colors.dart';
import '../widgets/app_icon.dart';

/// Barra lateral delgada, **siempre** solo iconos (nunca se expande).
///
/// * Arriba: los tres destinos principales (Inicio, Apartamentos, Cobros).
/// * Abajo, separado: Configuración (único lugar desde donde se abre).
/// * Cada icono tiene tooltip en español y etiqueta de accesibilidad, y se
///   puede activar con el teclado (Tab + Enter/Espacio).
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.current,
    required this.onSelect,
    required this.onSettings,
  });

  final AppSection current;
  final ValueChanged<AppSection> onSelect;
  final VoidCallback onSettings;

  static const double width = 54;

  static const Map<AppSection, AppIcon> _icons = {
    AppSection.inicio: AppIcon.home,
    AppSection.apartamentos: AppIcon.apartments,
    AppSection.cobros: AppIcon.payments,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          for (final section in AppSection.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: SidebarTooltip(
                label: section.label,
                child: _SidebarTile(
                  icon: _icons[section]!,
                  label: section.label,
                  active: section == current,
                  onTap: () => onSelect(section),
                ),
              ),
            ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Divider(height: 1, color: AppColors.divider),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 10),
            child: SidebarTooltip(
              label: AppIcon.settings.label,
              child: _SidebarTile(
                icon: AppIcon.settings,
                label: AppIcon.settings.label,
                active: false,
                onTap: onSettings,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final AppIcon icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? AppColors.primarySoft : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? AppColors.primarySoft : Colors.transparent,
              ),
            ),
            child: Padding(
              // 22 px de arte dentro de un área de 40 px: el icono respira y
              // el área de clic sigue siendo cómoda.
              padding: const EdgeInsets.all(9),
              child: AppIconView(
                icon,
                size: 22,
                // El PNG original es negro: en el elemento activo se tiñe de
                // azul para que se distinga sin fondo oscuro.
                color: active ? AppColors.primary : AppColors.textStrong,
                semanticLabel: label,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tooltip oscuro con flecha hacia la izquierda, igual al de la referencia.
class SidebarTooltip extends StatefulWidget {
  const SidebarTooltip({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  State<SidebarTooltip> createState() => _SidebarTooltipState();
}

class _SidebarTooltipState extends State<SidebarTooltip> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  Timer? _timer;

  void _scheduleShow() {
    _timer?.cancel();
    // Rápido, pero no instantáneo: evita parpadeos al pasar el mouse por la
    // barra camino a otro control.
    _timer = Timer(const Duration(milliseconds: 120), _show);
  }

  void _show() {
    if (!mounted || _entry != null) return;
    _entry = OverlayEntry(
      builder: (context) => CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.centerRight,
        followerAnchor: Alignment.centerLeft,
        offset: const Offset(10, 0),
        // IgnorePointer: el tooltip nunca bloquea clics ni tapa datos.
        child: IgnorePointer(child: _Tip(widget.label)),
      ),
    );
    Overlay.of(context).insert(_entry!);
  }

  void _hide() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        onEnter: (_) => _scheduleShow(),
        onExit: (_) => _hide(),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: _hide, child: widget.child),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.label);

  final String label;

  static const Color _bg = AppColors.tooltipBg;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              height: 1.2,
            ),
          ),
        ),
        Positioned(
          left: -3,
          top: 0,
          bottom: 0,
          child: Center(
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(width: 6, height: 6, color: _bg),
            ),
          ),
        ),
      ],
    );
  }
}
