import 'package:flutter/material.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_scope.dart';
import '../../../core/formatters.dart';
import '../../../core/notice_center.dart';
import '../../../data/finance_models.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../../dialogs/dialogs.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/common.dart';

/// Historial real de pagos del apartamento, con apertura de PDF, reimpresión y
/// anulación auditada. No hay una pantalla aparte de recibos.
class PaymentHistoryCard extends StatefulWidget {
  const PaymentHistoryCard({super.key, this.bounded = true});

  final bool bounded;

  @override
  State<PaymentHistoryCard> createState() => _PaymentHistoryCardState();
}

class _PaymentHistoryCardState extends State<PaymentHistoryCard> {
  int? _leaseFilter;
  bool _working = false;

  Future<void> _openPdf(int receiptId) async {
    final controller = AppScope.read(context);
    final notices = NoticesScope.maybeOf(context);
    final error = await controller.openReceipt(receiptId);
    if (error != null) notices?.show(error, tone: NoticeTone.error);
  }

  Future<void> _print(int receiptId) async {
    if (_working) return;
    setState(() => _working = true);
    final controller = AppScope.read(context);
    final notices = NoticesScope.maybeOf(context);
    try {
      final result = await controller.printReceipt(receiptId);
      if (!mounted) return;
      notices?.show(
        result.ok ? 'Recibo enviado a la impresora.' : result.message,
        tone: result.ok ? NoticeTone.success : NoticeTone.warning,
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final apartment = controller.selectedApartment;
    final all = controller.payments;
    final filters = controller.paymentLeaseFilters;
    final payments = _leaseFilter == null
        ? all
        : all.where((p) => p.leaseId == _leaseFilter).toList(growable: false);
    final total = payments
        .where((p) => !p.isVoided)
        .fold<int>(0, (sum, p) => sum + p.amountCents);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: apartment == null
                ? 'Pagos realizados'
                : 'Pagos realizados - Apartamento ${apartment.identifier}',
            icon: Icons.receipt_long_rounded,
            trailing: filters.length > 1
                ? _LeaseFilter(
                    filters: filters,
                    value: _leaseFilter,
                    onChanged: (value) => setState(() => _leaseFilter = value),
                  )
                : null,
          ),
          const SizedBox(height: 10),
          if (widget.bounded)
            Expanded(child: _body(context, controller, payments, total))
          else
            _body(context, controller, payments, total),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AppController controller,
    List<PaymentRecord> payments,
    int total,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 470;
        final columns = <ColumnSpec>[
          const ColumnSpec('Fecha', 14),
          const ColumnSpec('Período', 14),
          if (!compact) const ColumnSpec('Concepto', 13),
          const ColumnSpec('Monto', 15),
          const ColumnSpec('Método', 14),
          const ColumnSpec('Recibo', 16, align: Alignment.center),
          const ColumnSpec('Acciones', 14, align: Alignment.center),
        ];

        final rows = <TableRowData>[
          for (final payment in payments)
            TableRowData(
              cells: <Widget>[
                Text(
                  formatDate(payment.paymentDate),
                  style: appText.bodyCell.copyWith(fontSize: 11.5),
                ),
                Text(
                  payment.periodLabel,
                  style: appText.bodyCell.copyWith(fontSize: 11.5),
                ),
                if (!compact)
                  Text(
                    payment.concept,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appText.bodyCell.copyWith(fontSize: 11.5),
                  ),
                Text(
                  formatMoney(payment.amountCents),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appText.bodyCell.copyWith(
                    fontSize: 11.5,
                    color: payment.isVoided
                        ? AppColors.textFaint
                        : AppColors.textBody,
                    decoration: payment.isVoided
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                Text(
                  payment.method.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appText.bodyCell.copyWith(fontSize: 11.5),
                ),
                _ReceiptBadge(
                  label: payment.receiptLabel,
                  voided: payment.isVoided,
                  pdfStatus: payment.pdfStatus,
                  onTap: payment.receiptId == null
                      ? null
                      : () => _openPdf(payment.receiptId!),
                ),
                _RowActions(
                  enabled: payment.receiptId != null,
                  onPrint: payment.receiptId == null
                      ? null
                      : () => _print(payment.receiptId!),
                  onOpen: payment.receiptId == null
                      ? null
                      : () => _openPdf(payment.receiptId!),
                  onVoid: payment.isVoided ? null : () => _void(payment),
                ),
              ],
            ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TableHeaderBand(columns: columns),
            if (rows.isEmpty)
              const EmptyState(
                message: 'Todavía no hay pagos registrados.',
                icon: Icons.receipt_long_outlined,
              )
            else if (widget.bounded)
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: rows.length,
                padding: EdgeInsets.zero,
                itemBuilder: (context, index) => TableDataRow(
                  columns: columns,
                  row: rows[index],
                  height: 34,
                ),
              )
            else
              for (final row in rows)
                TableDataRow(columns: columns, row: row, height: 34),
            const SizedBox(height: 8),
            Text(
              'Total cobrado: ${formatMoney(total)} · '
              'Recibos guardados en la carpeta de recibos.',
              style: const TextStyle(
                fontSize: 10.5,
                color: AppColors.textFaint,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _void(PaymentRecord payment) async {
    final error = await showVoidPaymentDialog(context, payment: payment);
    if (!mounted) return;
    if (error != null) {
      NoticesScope.maybeOf(context)?.show(error, tone: NoticeTone.error);
    }
  }
}

class _LeaseFilter extends StatelessWidget {
  const _LeaseFilter({
    required this.filters,
    required this.value,
    required this.onChanged,
  });

  final List<({int leaseId, String label, int count})> filters;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int?>(
      tooltip: 'Filtrar por contrato',
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (context) => [
        const PopupMenuItem<int?>(
          value: null,
          child: Text('Todos los contratos'),
        ),
        for (final filter in filters)
          PopupMenuItem<int?>(
            value: filter.leaseId,
            child: Text('${filter.label} (${filter.count})'),
          ),
      ],
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.filter_alt_outlined,
              size: 14,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              value == null ? 'Todos' : 'Contrato',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptBadge extends StatelessWidget {
  const _ReceiptBadge({
    required this.label,
    required this.voided,
    required this.pdfStatus,
    required this.onTap,
  });

  final String label;
  final bool voided;
  final String pdfStatus;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final missing = pdfStatus == 'fallido' || pdfStatus == 'faltante';
    return Tooltip(
      message: 'Ver PDF del recibo $label',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: voided
                    ? AppColors.textFaint
                    : (missing ? AppColors.amberFg : AppColors.red),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                voided ? 'ANUL' : 'PDF',
                style: TextStyle(
                  fontSize: voided ? 4.6 : 5.6,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.1,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: appText.bodyCell.copyWith(
                  fontSize: 9.5,
                  color: voided ? AppColors.textFaint : AppColors.textBody,
                  decoration: voided ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowActions extends StatelessWidget {
  const _RowActions({
    required this.enabled,
    required this.onPrint,
    required this.onOpen,
    required this.onVoid,
  });

  final bool enabled;
  final VoidCallback? onPrint;
  final VoidCallback? onOpen;
  final VoidCallback? onVoid;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? AppColors.primary
        : AppColors.primary.withValues(alpha: 0.4);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Reimprimir recibo',
          child: InkWell(
            onTap: onPrint,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: AppIconView(AppIcon.print, size: 16, color: color),
            ),
          ),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<String>(
          tooltip: 'Más acciones',
          position: PopupMenuPosition.under,
          padding: EdgeInsets.zero,
          icon: const Icon(
            Icons.more_vert_rounded,
            size: 15,
            color: AppColors.textFaint,
          ),
          onSelected: (value) {
            if (value == 'pdf') onOpen?.call();
            if (value == 'reimprimir') onPrint?.call();
            if (value == 'anular') onVoid?.call();
          },
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              value: 'pdf',
              enabled: enabled,
              child: const Row(
                children: [
                  AppIconView(AppIcon.receipt, size: 15),
                  SizedBox(width: 8),
                  Text('Ver PDF'),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'reimprimir',
              enabled: onPrint != null,
              child: const Row(
                children: [
                  AppIconView(AppIcon.print, size: 15),
                  SizedBox(width: 8),
                  Text('Reimprimir'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'anular',
              enabled: onVoid != null,
              child: const Row(
                children: [
                  AppIconView(AppIcon.delete, size: 15),
                  SizedBox(width: 8),
                  Text('Anular pago'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
