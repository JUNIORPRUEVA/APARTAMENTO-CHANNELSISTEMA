import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/formatters.dart';
import '../../../core/notice_center.dart';
import '../../../data/finance_models.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/common.dart';

/// Formulario de cobro del diseño aprobado, ahora operativo.
///
/// Un solo botón: **Cobrar e imprimir** guarda el pago (transacción atómica) y
/// manda el ticket a la impresora automáticamente. Si el cliente no quiere
/// ticket, **No imprimir ticket** guarda igual sin imprimir. La impresión
/// nunca revierte el cobro.
class PaymentCard extends StatefulWidget {
  const PaymentCard({super.key, this.bounded = true});

  final bool bounded;

  @override
  State<PaymentCard> createState() => _PaymentCardState();
}

class _PaymentCardState extends State<PaymentCard> {
  final TextEditingController _note = TextEditingController();
  final TextEditingController _reference = TextEditingController();
  TextEditingController _amount = TextEditingController();
  PaymentMethod _method = PaymentMethod.efectivo;
  DateTime _paymentDate = DateTime.now();
  String? _error;
  bool _busy = false;
  String? _periodKey;

  @override
  void dispose() {
    _note.dispose();
    _reference.dispose();
    _amount.dispose();
    super.dispose();
  }

  /// Al cambiar de período se propone el saldo pendiente exacto.
  void _syncPeriod(PaymentPeriod? period) {
    final key = period == null ? null : '${period.year}-${period.month}';
    if (key == _periodKey) return;
    _periodKey = key;
    _amount.dispose();
    _amount = TextEditingController(
      text: period == null ? '' : formatAmountInput(period.remainingCents),
    );
    _error = null;
  }

  Future<void> _submit({required bool print}) async {
    if (_busy) return;
    final controller = AppScope.read(context);
    final notices = NoticesScope.maybeOf(context);
    final period = controller.selectedPeriod;
    if (period == null) {
      setState(() => _error = 'Seleccione un apartamento con contrato activo.');
      return;
    }

    final cents = parseAmountToCents(_amount.text);
    if (cents == null || cents <= 0) {
      setState(() => _error = 'Revise el monto: debe ser mayor que cero.');
      notices?.show('Revise el monto.', tone: NoticeTone.warning);
      return;
    }
    if (cents > period.remainingCents) {
      final message =
          'El monto supera el saldo del período '
          '(${formatMoney(period.remainingCents)}).';
      setState(() => _error = message);
      notices?.show(message, tone: NoticeTone.warning);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await controller.submitPayment(
      amountCents: cents,
      paymentDate: _paymentDate,
      method: _method,
      reference: _method == PaymentMethod.transferencia ? _reference.text : '',
      note: _note.text,
      printAfterSave: print,
    );

    if (!mounted) return;
    setState(() => _busy = false);

    if (!result.ok) {
      setState(() => _error = result.error);
      notices?.show(result.error!, tone: NoticeTone.error);
      return;
    }

    notices?.show(
      result.notice,
      tone: result.printMessage != null
          ? NoticeTone.warning
          : NoticeTone.success,
    );
    _note.clear();
    _reference.clear();
    _paymentDate = DateTime.now();

    // Si el período quedó saldado, se avanza al siguiente pendiente.
    final updated = controller.selectedPeriod;
    if (updated != null &&
        updated.remainingCents == 0 &&
        controller.hasNextPeriod) {
      controller.shiftPeriod(1);
    } else if (updated != null) {
      _amount.text = formatAmountInput(updated.remainingCents);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final apartment = controller.selectedApartment;
    final period = controller.selectedPeriod;
    _syncPeriod(period);

    final entered = parseAmountToCents(_amount.text) ?? 0;
    final remaining = period?.remainingCents ?? 0;
    final rest = (remaining - entered).clamp(0, remaining);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (apartment == null || apartment.lease == null)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: EmptyState(
              message:
                  'Seleccione un apartamento con contrato activo para '
                  'registrar un pago.',
              icon: Icons.account_balance_wallet_outlined,
            ),
          )
        else ...[
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 520;
              final concepto = LabeledField(
                label: 'Concepto',
                child: const DisplayBox(text: 'Alquiler mensual', muted: false),
              );
              final periodo = LabeledField(
                label: 'Período',
                child: _PeriodStepper(
                  label: period?.label ?? '—',
                  enabled: !_busy && period != null,
                  onPrevious: controller.hasPreviousPeriod
                      ? () => controller.shiftPeriod(-1)
                      : null,
                  onNext: controller.hasNextPeriod
                      ? () => controller.shiftPeriod(1)
                      : null,
                ),
              );
              final monto = LabeledField(
                label: 'Monto a pagar (RD\$)',
                child: _amountField(),
              );
              final metodo = LabeledField(
                label: 'Método de pago',
                child: DropdownButtonFormField<PaymentMethod>(
                  initialValue: _method,
                  isExpanded: true,
                  items: [
                    for (final method in PaymentMethod.values)
                      DropdownMenuItem(
                        value: method,
                        child: Text(method.label),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(
                          () => _method = value ?? PaymentMethod.efectivo,
                        ),
                  decoration: const InputDecoration(),
                ),
              );
              final fecha = LabeledField(
                label: 'Fecha de pago',
                child: AppDateField(
                  value: _paymentDate,
                  onPick: (date) => setState(() => _paymentDate = date),
                ),
              );
              final observacion = LabeledField(
                label: 'Observación (opcional)',
                child: TextField(
                  controller: _note,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    hintText: 'Ej. Pago en efectivo',
                  ),
                ),
              );
              // La referencia solo tiene sentido si el dinero llegó por banco.
              final referencia = LabeledField(
                label: 'Referencia (opcional)',
                child: TextField(
                  controller: _reference,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    hintText: 'Ej. No. de transferencia o comprobante',
                  ),
                ),
              );

              if (stacked) {
                return Column(
                  children: [
                    concepto,
                    const SizedBox(height: 10),
                    periodo,
                    const SizedBox(height: 10),
                    monto,
                    const SizedBox(height: 10),
                    metodo,
                    if (_method == PaymentMethod.transferencia) ...[
                      const SizedBox(height: 10),
                      referencia,
                    ],
                    const SizedBox(height: 10),
                    fecha,
                    const SizedBox(height: 10),
                    observacion,
                  ],
                );
              }
              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(flex: 26, child: concepto),
                      const SizedBox(width: 10),
                      Expanded(flex: 32, child: periodo),
                      const SizedBox(width: 10),
                      Expanded(flex: 30, child: monto),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(flex: 26, child: metodo),
                      const SizedBox(width: 10),
                      Expanded(flex: 26, child: fecha),
                      const SizedBox(width: 10),
                      Expanded(flex: 36, child: observacion),
                    ],
                  ),
                  if (_method == PaymentMethod.transferencia) ...[
                    const SizedBox(height: 10),
                    referencia,
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          _summary(period, entered: entered, rest: rest),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 11.5, color: AppColors.redFg),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlineButton(
                label: 'No imprimir ticket',
                icon: Icons.print_disabled_outlined,
                height: 40,
                onPressed: _busy || period == null
                    ? null
                    : () => _submit(print: false),
              ),
              PrimaryButton(
                label: _busy ? 'Guardando…' : 'Cobrar e imprimir',
                appIcon: AppIcon.print,
                height: 40,
                onPressed: _busy || period == null
                    ? null
                    : () => _submit(print: true),
              ),
            ],
          ),
        ],
      ],
    );

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: apartment == null
                ? 'Registrar pago'
                : 'Registrar pago - Apartamento ${apartment.identifier}',
            icon: Icons.account_balance_wallet_rounded,
            iconColor: AppColors.navy,
            trailing: period == null
                ? null
                : StatusPill(
                    label: period.statusAt(DateTime.now()).label,
                    tone: toneForStatus(period.statusAt(DateTime.now())),
                  ),
          ),
          if (widget.bounded)
            Expanded(child: SingleChildScrollView(child: body))
          else
            body,
        ],
      ),
    );
  }

  Widget _amountField() {
    return SizedBox(
      height: 38,
      child: TextField(
        controller: _amount,
        enabled: !_busy,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 13, color: AppColors.textStrong),
        decoration: const InputDecoration(hintText: '8,500.00'),
      ),
    );
  }

  Widget _summary(
    PaymentPeriod? period, {
    required int entered,
    required int rest,
  }) {
    if (period == null) return const SizedBox.shrink();
    final style = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: AppColors.textMuted,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.headerBand,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          Text('Vence: ${formatDate(period.dueDate)}', style: style),
          Text('Debe: ${formatMoney(period.remainingCents)}', style: style),
          Text('Recibido: ${formatMoney(entered)}', style: style),
          Text(
            'Restará: ${formatMoney(rest)}',
            style: style.copyWith(
              color: rest == 0 ? AppColors.greenFg : AppColors.textStrong,
            ),
          ),
        ],
      ),
    );
  }
}

/// Grupo visual "‹ Período ›" con los períodos reales del contrato.
class _PeriodStepper extends StatelessWidget {
  const _PeriodStepper({
    required this.label,
    required this.enabled,
    this.onPrevious,
    this.onNext,
  });

  final String label;
  final bool enabled;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _Arrow(
            icon: Icons.chevron_left_rounded,
            onTap: enabled ? onPrevious : null,
            tooltip: 'Mes anterior',
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textStrong,
              ),
            ),
          ),
          _Arrow(
            icon: Icons.chevron_right_rounded,
            onTap: enabled ? onNext : null,
            tooltip: 'Mes siguiente',
          ),
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 26,
          height: 36,
          child: Icon(
            icon,
            size: 18,
            color: onTap == null ? AppColors.textFaint : AppColors.primary,
          ),
        ),
      ),
    );
  }
}
