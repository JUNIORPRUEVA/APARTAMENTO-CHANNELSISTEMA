import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/formatters.dart';
import '../../../core/notice_center.dart';
import '../../../data/finance_models.dart';
import '../../../data/models.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../../dialogs/dialogs.dart';
import '../../widgets/common.dart';

/// Panel derecho: Información, Pagos (estado de cuenta) y Depósito.
class ApartmentDetailCard extends StatefulWidget {
  const ApartmentDetailCard({super.key, this.bounded = true});

  final bool bounded;

  @override
  State<ApartmentDetailCard> createState() => _ApartmentDetailCardState();
}

class _ApartmentDetailCardState extends State<ApartmentDetailCard> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final apartment = controller.selectedApartment;

    if (apartment == null) {
      return const SectionCard(
        child: EmptyState(
          message: 'Seleccione un apartamento para ver su ficha.',
          icon: Icons.apartment_rounded,
        ),
      );
    }

    final content = switch (_tab) {
      1 => _accountTab(apartment),
      2 => _depositTab(apartment),
      _ => _informationTab(context, apartment),
    };

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.apartment_rounded,
                size: 26,
                color: AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  apartment.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appText.pageTitle.copyWith(fontSize: 20),
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(
                label: apartment.rentStatus.label,
                tone: toneForStatus(apartment.rentStatus),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TabStrip(
            active: _tab,
            onChanged: (value) => setState(() => _tab = value),
          ),
          const SizedBox(height: 4),
          if (widget.bounded)
            Expanded(child: SingleChildScrollView(child: content))
          else
            content,
        ],
      ),
    );
  }

  // ------------------------------------------------------------ información

  Widget _informationTab(BuildContext context, ApartmentRow apartment) {
    final lease = apartment.lease;
    final controller = AppScope.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InfoRow(label: 'Residencial', value: apartment.groupName),
          _InfoRow(label: 'Número', value: apartment.identifier),
          _InfoRow(
            label: 'Ubicación',
            value: apartment.location.isEmpty ? '—' : apartment.location,
          ),
          _InfoRow(
            label: 'Alquiler mensual',
            value: formatMoney(apartment.effectiveRentCents),
          ),
          _InfoRow(
            label: 'Día de vencimiento',
            value: lease == null ? '—' : '${lease.dueDay}',
          ),
          _InfoRow(
            label: 'Depósito acordado',
            value: lease == null
                ? '—'
                : formatMoney(lease.depositRequiredCents),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.person_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 7),
                  Text('Inquilino', style: appText.sectionTitle),
                ],
              ),
              if (lease != null) ...[
                OutlineButton(
                  label: 'Editar',
                  icon: Icons.edit_outlined,
                  dense: true,
                  height: 30,
                  onPressed: () =>
                      showTenantDialog(context, apartment: apartment),
                ),
                OutlineButton(
                  label: 'Condiciones',
                  icon: Icons.tune_rounded,
                  dense: true,
                  height: 30,
                  onPressed: () =>
                      showLeaseTermsDialog(context, apartment: apartment),
                ),
                OutlineButton(
                  label: 'Finalizar',
                  dense: true,
                  height: 30,
                  tone: OutlineTone.danger,
                  onPressed: () =>
                      showEndLeaseDialog(context, apartment: apartment),
                ),
              ] else
                OutlineButton(
                  label: 'Registrar inquilino',
                  icon: Icons.person_add_alt_1_outlined,
                  dense: true,
                  height: 30,
                  onPressed: () =>
                      showTenantDialog(context, apartment: apartment),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (lease != null && apartment.tenant != null) ...[
            _InfoRow(label: 'Nombre', value: apartment.tenant!.fullName),
            _InfoRow(label: 'Cédula', value: apartment.tenant!.cedulaDisplay),
            _InfoRow(label: 'Teléfono', value: apartment.tenant!.phoneDisplay),
            _InfoRow(
              label: 'Fecha de ingreso',
              value: formatDate(lease.startDate),
            ),
            _InfoRow(
              label: 'Fecha de salida',
              value: lease.actualEndDate != null
                  ? formatDate(lease.actualEndDate!)
                  : lease.plannedEndDate != null
                  ? 'Prevista: ${formatDate(lease.plannedEndDate!)}'
                  : '—',
            ),
            if (lease.notes.isNotEmpty)
              _InfoRow(label: 'Notas', value: lease.notes),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Estado: ${apartment.rentStatus.label} · '
                    'Próximo vencimiento: '
                    '${formatDateOrDash(apartment.nextDueDate)}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                controller.selectedApartment == null
                    ? 'Sin inquilino.'
                    : 'Sin inquilino. Use "Registrar inquilino" para crear el '
                          'contrato.',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------- estado de cuenta (meses)

  Widget _accountTab(ApartmentRow apartment) {
    final controller = AppScope.of(context);
    final periods = controller.periods;

    if (periods.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 16),
        child: EmptyState(
          message:
              'Sin contrato activo. Registre un inquilino para comenzar a '
              'controlar el alquiler.',
          icon: Icons.receipt_long_outlined,
        ),
      );
    }

    final list = periods.reversed.toList(growable: false);
    const columns = <ColumnSpec>[
      ColumnSpec('Período', 20),
      ColumnSpec('Vence', 17),
      ColumnSpec('Monto', 18),
      ColumnSpec('Pagado', 17),
      ColumnSpec('Estado', 20, align: Alignment.centerRight),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TableHeaderBand(columns: columns),
          for (final period in list)
            TableDataRow(
              columns: columns,
              height: 36,
              row: TableRowData(
                onTap: () => controller.selectPeriod(period),
                cells: [
                  Text(
                    period.label,
                    style: appText.bodyCell.copyWith(fontSize: 11.5),
                  ),
                  Text(
                    formatDate(period.dueDate),
                    style: appText.bodyCell.copyWith(fontSize: 11.5),
                  ),
                  Text(
                    formatMoney(period.amountDueCents),
                    style: appText.bodyCell.copyWith(fontSize: 11.5),
                  ),
                  Text(
                    formatMoney(period.paidCents),
                    style: appText.bodyCell.copyWith(fontSize: 11.5),
                  ),
                  StatusPill(
                    label: period.statusAt(DateTime.now()).label,
                    tone: toneForStatus(period.statusAt(DateTime.now())),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Toque un mes para cobrarlo abajo. No se aplican recargos ni '
            'prorrateos automáticos.',
            style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- depósito

  Widget _depositTab(ApartmentRow apartment) {
    final controller = AppScope.of(context);
    final summary = controller.deposit;
    final lease = apartment.lease;

    if (summary == null || summary.leaseId == 0) {
      return const Padding(
        padding: EdgeInsets.only(top: 16),
        child: EmptyState(
          message:
              'No hay un contrato con depósito registrado. El depósito se '
              'registra aquí y nunca se cuenta como ingreso de alquiler.',
          icon: Icons.savings_outlined,
        ),
      );
    }

    final closed = lease == null;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.headerBand,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Depósito retenido', style: appText.fieldLabel),
                      const SizedBox(height: 2),
                      Text(
                        formatMoney(summary.heldCents),
                        style: appText.pageTitle.copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Acordado: ${formatMoney(summary.requiredCents)} · '
                        'Devuelto: ${formatMoney(summary.refundedCents)} · '
                        'Retenido por daños: ${formatMoney(summary.retainedCents)}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(
                  label: closed ? 'Contrato finalizado' : 'Contrato activo',
                  tone: closed ? PillTone.gray : PillTone.success,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (!closed)
                OutlineButton(
                  label: 'Registrar depósito',
                  icon: Icons.add_card_rounded,
                  dense: true,
                  onPressed: () => showDepositDialog(
                    context,
                    kind: DepositKind.recibido,
                    heldCents: summary.heldCents,
                    requiredCents: summary.requiredCents,
                  ),
                ),
              if (summary.heldCents > 0) ...[
                OutlineButton(
                  label: 'Devolver',
                  icon: Icons.undo_rounded,
                  dense: true,
                  onPressed: () => showDepositDialog(
                    context,
                    kind: DepositKind.devuelto,
                    heldCents: summary.heldCents,
                    requiredCents: summary.requiredCents,
                  ),
                ),
                OutlineButton(
                  label: 'Retener',
                  tone: OutlineTone.danger,
                  dense: true,
                  onPressed: () => showDepositDialog(
                    context,
                    kind: DepositKind.retenido,
                    heldCents: summary.heldCents,
                    requiredCents: summary.requiredCents,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (summary.movements.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Sin movimientos de depósito.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            )
          else ...[
            const TableHeaderBand(
              columns: <ColumnSpec>[
                ColumnSpec('Fecha', 18),
                ColumnSpec('Movimiento', 34),
                ColumnSpec('Monto', 20),
                ColumnSpec('Recibo', 14, align: Alignment.center),
                ColumnSpec('', 14, align: Alignment.center),
              ],
            ),
            for (final movement in summary.movements)
              TableDataRow(
                columns: const <ColumnSpec>[
                  ColumnSpec('Fecha', 18),
                  ColumnSpec('Movimiento', 34),
                  ColumnSpec('Monto', 20),
                  ColumnSpec('Recibo', 14, align: Alignment.center),
                  ColumnSpec('', 14, align: Alignment.center),
                ],
                height: 34,
                row: TableRowData(
                  cells: [
                    Text(
                      formatDate(movement.movementDate),
                      style: appText.bodyCell.copyWith(fontSize: 11.5),
                    ),
                    Text(
                      movement.kind == DepositKind.retenido &&
                              movement.reason.isNotEmpty
                          ? '${movement.kind.label} · ${movement.reason}'
                          : movement.kind.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: appText.bodyCell.copyWith(fontSize: 11.5),
                    ),
                    Text(
                      formatMoney(movement.amountCents),
                      style: appText.bodyCell.copyWith(fontSize: 11.5),
                    ),
                    movement.receiptId == null
                        ? const Text('—')
                        : _MiniReceiptButton(
                            onOpen: () async {
                              // El centro de notificaciones se captura antes del
                              // await para no usar el context después.
                              final notices = NoticesScope.maybeOf(context);
                              final error = await controller.openReceipt(
                                movement.receiptId!,
                              );
                              if (error != null) {
                                notices?.show(error, tone: NoticeTone.error);
                              }
                            },
                            onPrint: () async {
                              final notices = NoticesScope.maybeOf(context);
                              final result = await controller.printReceipt(
                                movement.receiptId!,
                              );
                              notices?.show(
                                result.ok
                                    ? 'Recibo enviado a la impresora.'
                                    : result.message,
                                tone: result.ok
                                    ? NoticeTone.success
                                    : NoticeTone.warning,
                              );
                            },
                          ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _MiniReceiptButton extends StatelessWidget {
  const _MiniReceiptButton({required this.onOpen, required this.onPrint});

  final Future<void> Function() onOpen;
  final Future<void> Function() onPrint;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Abrir recibo',
          child: InkWell(
            onTap: onOpen,
            child: Container(
              width: 18,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                'PDF',
                style: TextStyle(
                  fontSize: 5.2,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        InkWell(
          onTap: onPrint,
          borderRadius: BorderRadius.circular(4),
          child: const Padding(
            padding: EdgeInsets.all(2),
            child: Icon(
              Icons.print_outlined,
              size: 14,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 132, child: Text(label, style: appText.infoLabel)),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: appText.infoValue,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.active, required this.onChanged});

  final int active;
  final ValueChanged<int> onChanged;

  static const List<String> _labels = ['Información', 'Pagos', 'Depósito'];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.tabIdleBg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++)
            Expanded(
              child: _TabItem(
                label: _labels[i],
                active: i == active,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverRegion(
      builder: (hovered) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: active
              ? Colors.white
              : hovered
              ? Colors.white.withValues(alpha: 0.6)
              : Colors.transparent,
          child: Stack(
            children: [
              Center(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                    color: active ? AppColors.primary : AppColors.textStrong,
                  ),
                ),
              ),
              if (active)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(height: 3, color: AppColors.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
