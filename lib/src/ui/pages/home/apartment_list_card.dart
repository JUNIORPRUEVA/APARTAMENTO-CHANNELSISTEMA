import 'package:flutter/material.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/formatters.dart';
import '../../../data/models.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../../dialogs/dialogs.dart';
import '../../widgets/common.dart';

/// Tarjeta "Mis Apartamentos": filtros por residencial, búsqueda y tabla.
class ApartmentListCard extends StatefulWidget {
  const ApartmentListCard({
    super.key,
    required this.onCobrar,
    this.bounded = true,
    this.title = 'Mis Apartamentos',
    this.showCreate = true,
  });

  final ValueChanged<ApartmentRow> onCobrar;

  /// `true` cuando la tarjeta tiene altura acotada (tabla con scroll interno).
  final bool bounded;

  final String title;
  final bool showCreate;

  @override
  State<ApartmentListCard> createState() => _ApartmentListCardState();
}

class _ApartmentListCardState extends State<ApartmentListCard> {
  final TextEditingController _search = TextEditingController();

  static const List<ColumnSpec> _columns = <ColumnSpec>[
    ColumnSpec('No.', 7, align: Alignment.center),
    ColumnSpec('Apartamento', 16),
    ColumnSpec('Inquilino', 23),
    ColumnSpec('Alquiler', 15),
    ColumnSpec('Próximo pago', 15),
    ColumnSpec('Estado', 13, align: Alignment.center),
    ColumnSpec('Acción', 13, align: Alignment.center),
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final apartments = controller.visibleApartments;

    final rows = <TableRowData>[
      for (var i = 0; i < apartments.length; i++)
        _buildRow(context, controller, apartments[i], i),
    ];

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appText.pageTitle,
                ),
              ),
              const SizedBox(width: 10),
              if (widget.showCreate)
                PrimaryButton(
                  label: 'Nuevo Apartamento',
                  icon: Icons.add_rounded,
                  onPressed: () => showApartmentDialog(context),
                ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final searchWidth = (constraints.maxWidth * 0.32).clamp(
                170.0,
                280.0,
              );
              return Row(
                children: [
                  Expanded(child: _filters(context, controller)),
                  const SizedBox(width: 12),
                  SearchField(
                    controller: _search,
                    width: searchWidth,
                    onChanged: controller.setQuery,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          const TableHeaderBand(columns: _columns),
          if (widget.bounded)
            Expanded(
              child: rows.isEmpty
                  ? const EmptyState(
                      message: 'No hay apartamentos que coincidan.',
                    )
                  : ListView.builder(
                      itemCount: rows.length,
                      padding: EdgeInsets.zero,
                      itemBuilder: (context, index) =>
                          TableDataRow(columns: _columns, row: rows[index]),
                    ),
            )
          else
            Column(
              children: [
                if (rows.isEmpty)
                  const EmptyState(
                    message: 'No hay apartamentos que coincidan.',
                  )
                else
                  for (final row in rows)
                    TableDataRow(columns: _columns, row: row),
              ],
            ),
          if (controller.portfolio.hasDemoData)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Datos de demostración. Puede eliminarlos desde Ajustes.',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textFaint,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Elimina un residencial vacío, con confirmación explícita.
  ///
  /// Si todavía tiene apartamentos el sistema no borra nada y explica el
  /// motivo en un aviso corto (nunca se borra en cascada un historial).
  Future<void> _deleteGroup(
    BuildContext context,
    AppController controller,
    ApartmentGroup group,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Eliminar residencial'),
        content: Text(
          'Se eliminará el residencial «${group.name}». '
          'Solo es posible si no tiene apartamentos.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          OutlineButton(
            label: 'Cancelar',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          const SizedBox(width: 10),
          PrimaryButton(
            label: 'Eliminar',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final message = controller.deleteGroup(group.id);
    reportOutcome(context, message, successMessage: 'Residencial eliminado.');
  }

  Widget _filters(BuildContext context, AppController controller) {
    final groups = controller.groups;
    final selectedGroupId = controller.selectedGroupId;
    ApartmentGroup? selectedGroup;
    for (final group in groups) {
      if (group.id == selectedGroupId) selectedGroup = group;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          FilterChipButton(
            label: 'Todos',
            selected: selectedGroupId == null,
            onTap: () => controller.selectGroup(null),
          ),
          for (final group in groups) ...[
            const SizedBox(width: 8),
            FilterChipButton(
              label: group.name,
              selected: group.id == selectedGroupId,
              onTap: () => controller.selectGroup(group.id),
            ),
          ],
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: 'Residenciales',
            position: PopupMenuPosition.under,
            onSelected: (value) {
              if (value == 'nuevo') {
                showGroupDialog(context);
              } else if (value == 'renombrar' && selectedGroup != null) {
                showGroupDialog(context, existing: selectedGroup);
              } else if (value == 'eliminar' && selectedGroup != null) {
                _deleteGroup(context, controller, selectedGroup);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'nuevo',
                child: Text('Nuevo residencial'),
              ),
              PopupMenuItem<String>(
                value: 'renombrar',
                enabled: selectedGroup != null,
                child: const Text('Renombrar residencial'),
              ),
              PopupMenuItem<String>(
                value: 'eliminar',
                // Solo tiene sentido si el residencial está vacío: si tiene
                // apartamentos, el sistema explica por qué no se puede.
                enabled: selectedGroup != null,
                child: const Text('Eliminar residencial'),
              ),
            ],
            child: Container(
              height: 38,
              width: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.more_horiz_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  TableRowData _buildRow(
    BuildContext context,
    AppController controller,
    ApartmentRow apartment,
    int index,
  ) {
    final selected = apartment.id == controller.selectedApartmentId;

    return TableRowData(
      selected: selected,
      onTap: () => controller.selectApartment(apartment.id),
      cells: <Widget>[
        Text(
          '${index + 1}',
          style: appText.bodyCell.copyWith(color: AppColors.textMuted),
        ),
        Text(
          apartment.identifier,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: appText.bodyCell.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textStrong,
          ),
        ),
        Text(
          apartment.tenantName ?? '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: appText.bodyCell,
        ),
        Text(
          formatMoney(apartment.effectiveRentCents),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: appText.bodyCell,
        ),
        Text(
          formatDateOrDash(apartment.nextDueDate),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: appText.bodyCell,
        ),
        StatusPill(
          label: apartment.rentStatus.label,
          tone: toneForStatus(apartment.rentStatus),
        ),
        apartment.hasActiveLease
            ? PrimaryButton(
                label: 'Cobrar',
                dense: true,
                height: 27,
                onPressed: () => widget.onCobrar(apartment),
              )
            : Text(
                '—',
                style: appText.bodyCell.copyWith(color: AppColors.textFaint),
              ),
      ],
    );
  }
}
