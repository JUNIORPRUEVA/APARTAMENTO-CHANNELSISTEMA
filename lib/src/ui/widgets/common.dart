import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../data/finance_models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import 'app_icon.dart';

/// Tarjeta blanca base del diseño aprobado.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D1B2A4A),
            blurRadius: 14,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Devuelve si el puntero está encima, sin crear estados extra.
class HoverRegion extends StatefulWidget {
  const HoverRegion({
    super.key,
    required this.builder,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget Function(bool hovered) builder;
  final MouseCursor cursor;

  @override
  State<HoverRegion> createState() => _HoverRegionState();
}

class _HoverRegionState extends State<HoverRegion> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(_hovered),
    );
  }
}

enum PillTone { success, warning, gray, danger, info, successStrong }

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.tone = PillTone.gray});

  final String label;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color foreground) = switch (tone) {
      PillTone.success => (AppColors.greenBg, AppColors.greenFg),
      PillTone.successStrong => (AppColors.greenStrongBg, AppColors.greenFg),
      PillTone.warning => (AppColors.amberBg, AppColors.amberFg),
      PillTone.danger => (AppColors.redBg, AppColors.redFg),
      PillTone.info => (AppColors.primarySoft, AppColors.primary),
      PillTone.gray => (AppColors.grayBg, AppColors.grayFg),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: foreground,
          height: 1.35,
        ),
      ),
    );
  }
}

/// Botón principal (azul). `onPressed == null` lo deja claramente inhabilitado.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.appIcon,
    this.onPressed,
    this.height = 38,
    this.dense = false,
  });

  final String label;
  final IconData? icon;

  /// Icono PNG aprobado (se dibuja teñido de blanco).
  final AppIcon? appIcon;
  final VoidCallback? onPressed;
  final double height;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return HoverRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      builder: (hovered) => Semantics(
        button: true,
        enabled: enabled,
        child: GestureDetector(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: height,
            padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 16),
            decoration: BoxDecoration(
              color: !enabled
                  ? AppColors.grayBg
                  : hovered
                  ? AppColors.primaryHover
                  : AppColors.primary,
              borderRadius: BorderRadius.circular(AppMetrics.fieldRadius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (appIcon != null) ...[
                  AppIconView(
                    appIcon!,
                    size: dense ? 14 : 15,
                    color: enabled ? Colors.white : AppColors.textFaint,
                  ),
                  const SizedBox(width: 7),
                ] else if (icon != null) ...[
                  Icon(
                    icon,
                    size: dense ? 15 : 17,
                    color: enabled ? Colors.white : AppColors.textFaint,
                  ),
                  const SizedBox(width: 7),
                ],
                // Flexible: si el espacio es justo, el texto se acorta con
                // puntos suspensivos en vez de desbordar el botón.
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: dense ? 12 : 13,
                      fontWeight: FontWeight.w700,
                      color: enabled ? Colors.white : AppColors.textFaint,
                      height: 1.1,
                    ),
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

/// Botón secundario (blanco con borde azul).
class OutlineButton extends StatelessWidget {
  const OutlineButton({
    super.key,
    required this.label,
    this.icon,
    this.appIcon,
    this.onPressed,
    this.height = 38,
    this.dense = false,
    this.tone = OutlineTone.primary,
  });

  final String label;
  final IconData? icon;

  /// Icono PNG aprobado (se dibuja teñido con el color del tono).
  final AppIcon? appIcon;
  final VoidCallback? onPressed;
  final double height;
  final bool dense;
  final OutlineTone tone;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final accent = switch (tone) {
      OutlineTone.primary => AppColors.primary,
      OutlineTone.danger => AppColors.redFg,
    };
    return HoverRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      builder: (hovered) => Semantics(
        button: true,
        enabled: enabled,
        child: GestureDetector(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: height,
            padding: EdgeInsets.symmetric(horizontal: dense ? 11 : 15),
            decoration: BoxDecoration(
              color: hovered && enabled ? AppColors.primarySoft : Colors.white,
              borderRadius: BorderRadius.circular(AppMetrics.fieldRadius),
              border: Border.all(
                color: enabled
                    ? accent.withValues(alpha: 0.55)
                    : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (appIcon != null) ...[
                  AppIconView(
                    appIcon!,
                    size: dense ? 14 : 15,
                    color: enabled ? accent : AppColors.textFaint,
                  ),
                  const SizedBox(width: 7),
                ] else if (icon != null) ...[
                  Icon(
                    icon,
                    size: dense ? 15 : 17,
                    color: enabled ? accent : AppColors.textFaint,
                  ),
                  const SizedBox(width: 7),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: dense ? 12 : 13,
                      fontWeight: FontWeight.w700,
                      color: enabled ? accent : AppColors.textFaint,
                      height: 1.1,
                    ),
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

enum OutlineTone { primary, danger }

/// Chip de filtro (residenciales).
class FilterChipButton extends StatelessWidget {
  const FilterChipButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverRegion(
      builder: (hovered) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary
                : hovered
                ? AppColors.primarySoft
                : Colors.white,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.textStrong,
            ),
          ),
        ),
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    this.hint = 'Buscar apartamento o inquilino...',
    this.onChanged,
    this.width,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 38,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13, color: AppColors.textStrong),
        decoration: InputDecoration(
          hintText: hint,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 10, right: 6),
            child: AppIconView(AppIcon.search, size: 16),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 38),
        ),
      ),
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: appText.fieldLabel),
    );
  }
}

/// Campo de formulario con etiqueta pequeña arriba.
class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [FieldLabel(label), child],
    );
  }
}

/// Caja de solo lectura con aspecto de campo (formulario de cobro, Fase 1).
class DisplayBox extends StatelessWidget {
  const DisplayBox({
    super.key,
    required this.text,
    this.trailingIcon,
    this.height = 38,
    this.muted = true,
  });

  final String text;
  final IconData? trailingIcon;
  final double height;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: muted ? const Color(0xFFFAFBFD) : Colors.white,
        borderRadius: BorderRadius.circular(AppMetrics.fieldRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: muted ? AppColors.textMuted : AppColors.textStrong,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (trailingIcon != null)
            Icon(trailingIcon, size: 17, color: AppColors.textFaint),
        ],
      ),
    );
  }
}

/// Campo de fecha (dd/MM/aaaa) con calendario en español.
class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.value,
    required this.onPick,
    this.hint = 'Seleccionar',
    this.onClear,
    this.enabled = true,
  });

  final DateTime? value;
  final ValueChanged<DateTime> onPick;
  final String hint;
  final VoidCallback? onClear;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled
          ? () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? now,
                firstDate: DateTime(now.year - 10),
                lastDate: DateTime(now.year + 12),
                helpText: 'Seleccione la fecha',
                cancelText: 'Cancelar',
                confirmText: 'Aceptar',
              );
              if (picked != null) onPick(picked);
            }
          : null,
      borderRadius: BorderRadius.circular(AppMetrics.fieldRadius),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: enabled ? Colors.white : const Color(0xFFFAFBFD),
          borderRadius: BorderRadius.circular(AppMetrics.fieldRadius),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value == null ? hint : formatDate(value!),
                style: TextStyle(
                  fontSize: 13,
                  color: value == null
                      ? AppColors.textFaint
                      : AppColors.textStrong,
                ),
              ),
            ),
            if (value != null && onClear != null && enabled)
              InkWell(
                onTap: onClear,
                child: const Icon(
                  Icons.close_rounded,
                  size: 15,
                  color: AppColors.textFaint,
                ),
              )
            else
              const Icon(
                Icons.calendar_today_rounded,
                size: 15,
                color: AppColors.textFaint,
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- tablas

class ColumnSpec {
  const ColumnSpec(this.label, this.flex, {this.align = Alignment.centerLeft});
  final String label;
  final int flex;
  final AlignmentGeometry align;
}

class TableRowData {
  const TableRowData({required this.cells, this.onTap, this.selected = false});

  final List<Widget> cells;
  final VoidCallback? onTap;
  final bool selected;
}

/// Banda de encabezado de tabla, con las mismas proporciones que las filas.
class TableHeaderBand extends StatelessWidget {
  const TableHeaderBand({
    super.key,
    required this.columns,
    this.padding = const EdgeInsets.symmetric(horizontal: 14),
  });

  final List<ColumnSpec> columns;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: padding,
      decoration: const BoxDecoration(
        color: AppColors.headerBand,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(9),
          topRight: Radius.circular(9),
        ),
      ),
      child: Row(
        children: [
          for (final column in columns)
            Expanded(
              flex: column.flex,
              child: Align(
                alignment: column.align,
                child: Text(
                  column.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appText.tableHead,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class TableDataRow extends StatelessWidget {
  const TableDataRow({
    super.key,
    required this.columns,
    required this.row,
    this.padding = const EdgeInsets.symmetric(horizontal: 14),
    this.height = AppMetrics.rowHeight,
  });

  final List<ColumnSpec> columns;
  final TableRowData row;
  final EdgeInsetsGeometry padding;
  final double height;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: row.selected
            ? AppColors.primarySoft.withValues(alpha: 0.55)
            : null,
        border: const Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < columns.length; i++)
            Expanded(
              flex: columns[i].flex,
              child: Align(
                alignment: columns[i].align,
                child: i < row.cells.length ? row.cells[i] : const SizedBox(),
              ),
            ),
        ],
      ),
    );

    if (row.onTap == null) return content;
    return HoverRegion(
      builder: (hovered) => GestureDetector(
        onTap: row.onTap,
        child: Container(
          color: hovered && !row.selected
              ? AppColors.headerBand.withValues(alpha: 0.5)
              : Colors.transparent,
          child: content,
        ),
      ),
    );
  }
}

/// Estado vacío sobrio y centrado.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: AppColors.textFaint),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textMuted,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}

/// Aviso corto y discreto dentro de una tarjeta.
class InlineNotice extends StatelessWidget {
  const InlineNotice({
    super.key,
    required this.text,
    this.tone = PillTone.info,
  });

  final String text;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color foreground, IconData icon) = switch (tone) {
      PillTone.warning => (
        const Color(0xFFFEF6E7),
        AppColors.amberFg,
        Icons.info_outline_rounded,
      ),
      PillTone.danger => (
        AppColors.redBg,
        AppColors.redFg,
        Icons.error_outline_rounded,
      ),
      _ => (
        AppColors.primarySoft,
        AppColors.primary,
        Icons.info_outline_rounded,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Encabezado de sección con icono (patrón del diseño de referencia).
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
    this.iconColor = AppColors.primary,
    this.iconSize = 22,
  });

  final String title;
  final IconData? icon;
  final Widget? trailing;
  final Color iconColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: iconSize, color: iconColor),
          const SizedBox(width: 9),
        ],
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: appText.cardTitle,
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Color de la pill para el estado de la renta.
PillTone toneForStatus(RentStatus status) => switch (status) {
  RentStatus.alDia => PillTone.success,
  RentStatus.parcial => PillTone.info,
  RentStatus.pendiente => PillTone.warning,
  RentStatus.vencido => PillTone.danger,
  RentStatus.disponible => PillTone.gray,
};
