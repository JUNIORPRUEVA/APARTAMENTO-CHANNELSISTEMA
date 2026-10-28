import 'package:flutter/material.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/formatters.dart';
import '../../../core/validators.dart';
import '../../../data/models.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../../dialogs/dialogs.dart';
import '../../widgets/common.dart';

/// Gestión real (Fase 1) de residenciales, apartamentos, inquilinos y
/// contratos. Todas las operaciones escriben en la base local.
class ApartmentsPage extends StatelessWidget {
  const ApartmentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final apartment = controller.selectedApartment;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1080;
        final picker = _PickerCard(bounded: wide);
        final ficha = apartment == null
            ? const SectionCard(
                child: EmptyState(
                  message: 'Seleccione un apartamento para editarlo.',
                  icon: Icons.apartment_rounded,
                ),
              )
            : _FichaCard(
                key: ValueKey<int>(apartment.id),
                apartment: apartment,
                bounded: wide,
              );

        if (wide) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(flex: 44, child: picker),
                const SizedBox(width: 14),
                Expanded(flex: 56, child: ficha),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _PickerCard(bounded: false),
              const SizedBox(height: 14),
              ficha,
            ],
          ),
        );
      },
    );
  }
}

class _PickerCard extends StatelessWidget {
  const _PickerCard({required this.bounded});

  final bool bounded;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final apartments = controller.visibleApartments;

    final rows = <Widget>[
      for (final apartment in apartments)
        _PickerRow(
          apartment: apartment,
          selected: apartment.id == controller.selectedApartmentId,
          onTap: () => controller.selectApartment(apartment.id),
        ),
    ];

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Apartamentos', style: appText.pageTitle)),
              const SizedBox(width: 10),
              PrimaryButton(
                label: 'Nuevo',
                icon: Icons.add_rounded,
                onPressed: () => showApartmentDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _GroupSelector(controller: controller),
          const SizedBox(height: 12),
          const Divider(height: 1),
          if (bounded)
            Expanded(
              child: rows.isEmpty
                  ? const EmptyState(message: 'No hay apartamentos.')
                  : ListView(padding: EdgeInsets.zero, children: rows),
            )
          else
            Column(
              children: rows.isEmpty
                  ? const [EmptyState(message: 'No hay apartamentos.')]
                  : rows,
            ),
        ],
      ),
    );
  }
}

class _GroupSelector extends StatelessWidget {
  const _GroupSelector({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
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
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.apartment,
    required this.selected,
    required this.onTap,
  });

  final ApartmentRow apartment;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverRegion(
      builder: (hovered) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primarySoft.withValues(alpha: 0.7)
                : hovered
                ? AppColors.headerBand.withValues(alpha: 0.6)
                : null,
            border: const Border(bottom: BorderSide(color: AppColors.divider)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 54,
                child: Text(
                  apartment.identifier,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appText.bodyCell.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textStrong,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  apartment.groupName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appText.bodyCell.copyWith(color: AppColors.textMuted),
                ),
              ),
              Text(
                formatMoney(apartment.effectiveRentCents),
                style: appText.bodyCell,
              ),
              const SizedBox(width: 10),
              StatusPill(
                label: apartment.occupancy.label,
                tone: apartment.hasActiveLease
                    ? PillTone.success
                    : PillTone.gray,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FichaCard extends StatefulWidget {
  const _FichaCard({super.key, required this.apartment, required this.bounded});

  final ApartmentRow apartment;
  final bool bounded;

  @override
  State<_FichaCard> createState() => _FichaCardState();
}

class _FichaCardState extends State<_FichaCard> {
  late TextEditingController _identifier;
  late TextEditingController _location;
  late TextEditingController _rent;
  late OccupancyStatus _occupancy;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final apartment = widget.apartment;
    _identifier = TextEditingController(text: apartment.identifier);
    _location = TextEditingController(text: apartment.location);
    _rent = TextEditingController(text: formatAmountInput(apartment.rentCents));
    _occupancy = apartment.occupancy;
    _error = null;
  }

  @override
  void dispose() {
    _identifier.dispose();
    _location.dispose();
    _rent.dispose();
    super.dispose();
  }

  void _save() {
    final controller = AppScope.read(context);
    final validation =
        validateApartmentIdentifier(_identifier.text) ??
        validateAmount(_rent.text);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    final message = controller.updateApartment(
      apartmentId: widget.apartment.id,
      identifier: _identifier.text,
      location: _location.text,
      rentCents: parseAmountToCents(_rent.text) ?? 0,
      occupancy: _occupancy,
    );
    setState(() => _error = message);
    reportOutcome(context, message, successMessage: 'Apartamento actualizado.');
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final apartment = widget.apartment;
    final history = controller.leaseHistoryFor(apartment.id);
    final lease = apartment.lease;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Datos del apartamento'),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 520;
            final number = LabeledField(
              label: 'Número / identificador',
              child: TextField(controller: _identifier),
            );
            final location = LabeledField(
              label: 'Ubicación',
              child: TextField(
                controller: _location,
                decoration: const InputDecoration(hintText: 'Ej. Primer nivel'),
              ),
            );
            final rent = LabeledField(
              label: 'Alquiler mensual (RD\$)',
              child: TextField(
                controller: _rent,
                keyboardType: TextInputType.number,
              ),
            );
            if (stacked) {
              return Column(
                children: [
                  number,
                  const SizedBox(height: 10),
                  location,
                  const SizedBox(height: 10),
                  rent,
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 28, child: number),
                const SizedBox(width: 10),
                Expanded(flex: 38, child: location),
                const SizedBox(width: 10),
                Expanded(flex: 34, child: rent),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        LabeledField(
          label: 'Estado',
          child: SegmentedButton<OccupancyStatus>(
            segments: const [
              ButtonSegment(
                value: OccupancyStatus.disponible,
                label: Text('Disponible'),
              ),
              ButtonSegment(
                value: OccupancyStatus.ocupado,
                label: Text('Ocupado'),
              ),
            ],
            selected: {_occupancy},
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStateProperty.all(
                const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
            onSelectionChanged: lease != null
                ? null
                : (value) => setState(() => _occupancy = value.first),
          ),
        ),
        if (lease != null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'El estado se controla con el contrato activo.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: AppColors.redFg),
            ),
          ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: PrimaryButton(
            label: 'Guardar cambios',
            icon: Icons.save_outlined,
            onPressed: _save,
          ),
        ),
        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 14),
        Row(
          children: [
            const Icon(
              Icons.person_rounded,
              size: 18,
              color: AppColors.primary,
            ),
            const SizedBox(width: 7),
            Text('Inquilino y contrato', style: appText.sectionTitle),
            const Spacer(),
            if (lease == null)
              OutlineButton(
                label: 'Registrar inquilino',
                icon: Icons.person_add_alt_1_outlined,
                dense: true,
                height: 32,
                onPressed: () =>
                    showTenantDialog(context, apartment: apartment),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (lease != null && apartment.tenant != null) ...[
          _infoRow(label: 'Inquilino', value: apartment.tenant!.fullName),
          _infoRow(label: 'Cédula', value: apartment.tenant!.cedulaDisplay),
          _infoRow(label: 'Teléfono', value: apartment.tenant!.phoneDisplay),
          _infoRow(label: 'Desde', value: formatDate(lease.startDate)),
          _infoRow(label: 'Día de pago', value: '${lease.dueDay}'),
          _infoRow(
            label: 'Salida prevista',
            value: formatDateOrDash(lease.plannedEndDate),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlineButton(
                label: 'Editar inquilino',
                icon: Icons.edit_outlined,
                dense: true,
                onPressed: () =>
                    showTenantDialog(context, apartment: apartment),
              ),
              OutlineButton(
                label: 'Finalizar contrato',
                dense: true,
                tone: OutlineTone.danger,
                onPressed: () =>
                    showEndLeaseDialog(context, apartment: apartment),
              ),
            ],
          ),
        ] else
          const Text(
            'Sin contrato activo. Registre un inquilino para comenzar a '
            'controlar el alquiler.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 14),
        _sectionTitle('Historial de contratos'),
        const SizedBox(height: 8),
        if (history.isEmpty)
          const Text(
            'Sin contratos registrados.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          )
        else
          for (final item in history)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.tenantName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: appText.bodyCell.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textStrong,
                      ),
                    ),
                  ),
                  Text(
                    '${formatDate(item.startDate)} — '
                    '${item.endDate == null ? 'actual' : formatDate(item.endDate!)}',
                    style: appText.bodyCell.copyWith(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 10),
                  StatusPill(
                    label: item.isActive ? 'Activo' : 'Finalizado',
                    tone: item.isActive ? PillTone.success : PillTone.gray,
                  ),
                ],
              ),
            ),
      ],
    );

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.apartment_rounded,
                size: 24,
                color: AppColors.primary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '${apartment.displayName} · ${apartment.groupName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appText.cardTitle.copyWith(fontSize: 17),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (widget.bounded)
            Expanded(child: SingleChildScrollView(child: content))
          else
            content,
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(text, style: appText.sectionTitle);

  Widget _infoRow({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(width: 130, child: Text(label, style: appText.infoLabel)),
          Expanded(child: Text(value, style: appText.infoValue)),
        ],
      ),
    );
  }
}
