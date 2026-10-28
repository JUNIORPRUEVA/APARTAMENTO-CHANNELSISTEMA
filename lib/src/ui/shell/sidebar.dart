import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../theme/app_colors.dart';

/// Barra lateral oscura con exactamente tres iconos y tooltips al pasar el
/// puntero (sin texto permanente).
class AppSidebar extends StatelessWidget {
  const AppSidebar({super.key, required this.current, required this.onSelect});

  final AppSection current;
  final ValueChanged<AppSection> onSelect;

  static const Map<AppSection, IconData> _icons = {
    AppSection.inicio: Icons.home_rounded,
    AppSection.apartamentos: Icons.apartment_rounded,
    AppSection.cobros: Icons.account_balance_wallet_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      color: AppColors.navy,
      child: Column(
        children: [
          const SizedBox(height: 10),
          for (final section in AppSection.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: SidebarTooltip(
                label: section.label,
                child: _SidebarTile(
                  icon: _icons[section]!,
                  active: section == current,
                  onTap: () => onSelect(section),
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
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: active ? AppColors.activeTile : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            icon,
            size: 22,
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.88),
          ),
        ),
      ),
    );
  }
}

/// Tooltip oscuro con flecha hacia la izquierda, idéntico al de la referencia.
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
    _timer = Timer(const Duration(milliseconds: 220), _show);
  }

  void _show() {
    if (!mounted || _entry != null) return;
    _entry = OverlayEntry(
      builder: (context) => CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.centerRight,
        followerAnchor: Alignment.centerLeft,
        offset: const Offset(11, 0),
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
