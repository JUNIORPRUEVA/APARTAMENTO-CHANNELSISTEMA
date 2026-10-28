import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/app_scope.dart';
import '../../core/formatters.dart';
import '../../core/notice_center.dart';
import '../../core/validators.dart';
import '../../data/finance_models.dart';
import '../../data/models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../pages/home/payment_card.dart';
import '../widgets/common.dart';

/// Publica el resultado de una operación en el sistema de notificaciones.
void reportOutcome(
  BuildContext context,
  String? error, {
  required String successMessage,
}) {
  final notices = NoticesScope.maybeOf(context);
  if (notices == null) return;
  if (error != null) {
    notices.show(error, tone: NoticeTone.error);
  } else {
    notices.show(successMessage, tone: NoticeTone.success);
  }
}

Future<T?> _showShell<T>(
  BuildContext context, {
  required String title,
  required String subtitle,
  required Widget content,
  required List<Widget> actions,
  double width = 470,
}) {
  return showDialog<T>(
    context: context,
    barrierColor: const Color(0x660B1733),
    builder: (context) => Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: 580),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: appText.cardTitle.copyWith(fontSize: 17)),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: content,
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ------------------------------------------------------------------ grupos

Future<void> showGroupDialog(
  BuildContext context, {
  ApartmentGroup? existing,
}) async {
  final controller = AppScope.read(context);
  final nameController = TextEditingController(text: existing?.name ?? '');
  String? error;

  await showDialog<void>(
    context: context,
    barrierColor: const Color(0x660B1733),
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  existing == null
                      ? 'Nuevo residencial'
                      : 'Renombrar residencial',
                  style: appText.cardTitle.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Los apartamentos se agrupan por residencial.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                LabeledField(
                  label: 'Nombre del residencial',
                  child: TextField(
                    controller: nameController,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submitGroup(
                      context,
                      controller,
                      nameController.text,
                      existing,
                      onError: (message) => setState(() => error = message),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Ej. Anamelia',
                      errorText: error,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlineButton(
                      label: 'Cancelar',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 10),
                    PrimaryButton(
                      label: 'Guardar',
                      onPressed: () => _submitGroup(
                        context,
                        controller,
                        nameController.text,
                        existing,
                        onError: (message) => setState(() => error = message),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  nameController.dispose();
}

void _submitGroup(
  BuildContext context,
  AppController controller,
  String name,
  ApartmentGroup? existing, {
  required void Function(String) onError,
}) {
  final message = existing == null
      ? controller.addGroup(name)
      : controller.renameGroup(existing.id, name);
  if (message != null) {
    onError(message);
    return;
  }
  final navigator = Navigator.of(context);
  reportOutcome(
    context,
    null,
    successMessage: existing == null
        ? 'Residencial creado.'
        : 'Residencial actualizado.',
  );
  navigator.pop();
}

// -------------------------------------------------------------- apartamento

Future<void> showApartmentDialog(
  BuildContext context, {
  ApartmentRow? existing,
}) {
  final controller = AppScope.read(context);
  final groups = controller.groups;
  final state = _ApartmentFormData(
    groupId:
        existing?.groupId ??
        controller.selectedGroupId ??
        (groups.isEmpty ? null : groups.first.id),
    identifier: existing?.identifier ?? '',
    location: existing?.location ?? '',
    amount: existing == null ? '' : formatAmountInput(existing.rentCents),
    occupancy: existing?.occupancy ?? OccupancyStatus.disponible,
  );

  return _showShell<void>(
    context,
    title: existing == null ? 'Nuevo apartamento' : 'Editar apartamento',
    subtitle: existing == null
        ? 'Registre el número, la ubicación y el alquiler mensual.'
        : 'Los cambios se guardan de inmediato en este equipo.',
    content: StatefulBuilder(
      builder: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledField(
            label: 'Residencial',
            child: DropdownButtonFormField<int>(
              initialValue: state.groupId,
              isExpanded: true,
              items: [
                for (final group in groups)
                  DropdownMenuItem(value: group.id, child: Text(group.name)),
              ],
              onChanged: existing != null
                  ? null
                  : (value) => setState(() => state.groupId = value),
              decoration: const InputDecoration(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LabeledField(
                  label: 'Número / identificador',
                  child: TextField(
                    controller: state.identifierController,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Ej. 101'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LabeledField(
                  label: 'Alquiler mensual (RD\$)',
                  child: TextField(
                    controller: state.amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '8,500.00'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LabeledField(
            label: 'Ubicación (opcional)',
            child: TextField(
              controller: state.locationController,
              decoration: const InputDecoration(hintText: 'Ej. Primer nivel'),
            ),
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
              selected: {state.occupancy},
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStateProperty.all(
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              onSelectionChanged: existing?.hasActiveLease ?? false
                  ? null
                  : (value) => setState(() => state.occupancy = value.first),
            ),
          ),
          if (existing?.hasActiveLease ?? false)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'El estado se controla con el contrato activo.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
              ),
            ),
          ValueListenableBuilder<String?>(
            valueListenable: state.error,
            builder: (context, message, _) {
              if (message == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 12, color: AppColors.redFg),
                ),
              );
            },
          ),
        ],
      ),
    ),
    actions: [
      OutlineButton(
        label: 'Cancelar',
        onPressed: () => Navigator.of(context).pop(),
      ),
      const SizedBox(width: 10),
      PrimaryButton(
        label: 'Guardar',
        onPressed: () => _submitApartment(context, controller, state, existing),
      ),
    ],
  );
}

void _submitApartment(
  BuildContext context,
  AppController controller,
  _ApartmentFormData state,
  ApartmentRow? existing,
) {
  final validation =
      validateApartmentIdentifier(state.identifier) ??
      validateAmount(state.amount);
  final groupId = state.groupId;
  if (validation != null) {
    state.error.value = validation;
    return;
  }
  if (groupId == null) {
    state.error.value = 'Seleccione un residencial.';
    return;
  }

  final cents = parseAmountToCents(state.amount) ?? 0;
  final message = existing == null
      ? controller.addApartment(
          groupId: groupId,
          identifier: state.identifier,
          location: state.location,
          rentCents: cents,
        )
      : controller.updateApartment(
          apartmentId: existing.id,
          identifier: state.identifier,
          location: state.location,
          rentCents: cents,
          occupancy: state.occupancy,
        );

  if (message != null) {
    state.error.value = message;
    return;
  }

  final navigator = Navigator.of(context);
  reportOutcome(
    context,
    null,
    successMessage: existing == null
        ? 'Apartamento creado.'
        : 'Apartamento actualizado.',
  );
  navigator.pop();
}

class _ApartmentFormData {
  _ApartmentFormData({
    required this.groupId,
    required String identifier,
    required String location,
    required String amount,
    required this.occupancy,
  }) : identifierController = TextEditingController(text: identifier),
       locationController = TextEditingController(text: location),
       amountController = TextEditingController(text: amount);

  int? groupId;
  OccupancyStatus occupancy;
  final TextEditingController identifierController;
  final TextEditingController locationController;
  final TextEditingController amountController;
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  String get identifier => identifierController.text;
  String get location => locationController.text;
  String get amount => amountController.text;
}

// ----------------------------------------------------- inquilino y contrato

Future<void> showTenantDialog(
  BuildContext context, {
  required ApartmentRow apartment,
}) {
  final controller = AppScope.read(context);
  final editing = apartment.tenant;
  final form = _TenantFormData(
    name: editing?.fullName ?? '',
    cedula: editing?.cedula ?? '',
    phone: editing?.phone ?? '',
    moveIn: apartment.lease?.startDate ?? DateTime.now(),
    plannedMoveOut: apartment.lease?.plannedEndDate,
    amount: formatAmountInput(
      apartment.lease?.rentCents ?? apartment.rentCents,
    ),
    dueDay: '${apartment.lease?.dueDay ?? 5}',
  );

  return _showShell<void>(
    context,
    title: editing == null ? 'Registrar inquilino' : 'Editar inquilino',
    subtitle: editing == null
        ? 'Se creará el contrato activo del apartamento ${apartment.identifier}.'
        : 'Corrija los datos de contacto del inquilino actual.',
    width: 520,
    content: StatefulBuilder(
      builder: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledField(
            label: 'Nombre completo',
            child: TextField(
              controller: form.nameController,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Ej. María Pérez'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: LabeledField(
                  label: 'Cédula',
                  child: TextField(
                    controller: form.cedulaController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: '001-1234567-8',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LabeledField(
                  label: 'Teléfono',
                  child: TextField(
                    controller: form.phoneController,
                    decoration: const InputDecoration(hintText: '809-555-0123'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: LabeledField(
                  label: 'Alquiler mensual (RD\$)',
                  child: TextField(
                    controller: form.amountController,
                    enabled: editing == null,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '8,500.00'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: LabeledField(
                  label: 'Día de pago',
                  child: TextField(
                    controller: form.dueDayController,
                    enabled: editing == null,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '5'),
                  ),
                ),
              ),
            ],
          ),
          if (editing == null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: LabeledField(
                    label: 'Fecha de ingreso',
                    child: AppDateField(
                      value: form.moveIn,
                      onPick: (date) => setState(() => form.moveIn = date),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LabeledField(
                    label: 'Salida prevista (opcional)',
                    child: AppDateField(
                      value: form.plannedMoveOut,
                      hint: 'Sin fecha',
                      onPick: (date) =>
                          setState(() => form.plannedMoveOut = date),
                      onClear: () => setState(() => form.plannedMoveOut = null),
                    ),
                  ),
                ),
              ],
            ),
          ],
          ValueListenableBuilder<String?>(
            valueListenable: form.error,
            builder: (context, message, _) {
              if (message == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 12, color: AppColors.redFg),
                ),
              );
            },
          ),
        ],
      ),
    ),
    actions: [
      OutlineButton(
        label: 'Cancelar',
        onPressed: () => Navigator.of(context).pop(),
      ),
      const SizedBox(width: 10),
      PrimaryButton(
        label: editing == null ? 'Registrar' : 'Guardar cambios',
        onPressed: () =>
            _submitTenant(context, controller, form, apartment, editing),
      ),
    ],
  );
}

void _submitTenant(
  BuildContext context,
  AppController controller,
  _TenantFormData form,
  ApartmentRow apartment,
  TenantInfo? editing,
) {
  final validation =
      validatePersonName(form.name) ??
      validateCedula(form.cedula) ??
      validatePhone(form.phone);
  if (validation != null) {
    form.error.value = validation;
    return;
  }

  final String? message;
  if (editing == null) {
    final amountError = validateAmount(form.amount);
    final dueDayError = validateDueDay(form.dueDay);
    final combined = amountError ?? dueDayError;
    if (combined != null) {
      form.error.value = combined;
      return;
    }
    message = controller.registerTenant(
      apartmentId: apartment.id,
      fullName: form.name,
      cedula: form.cedula,
      phone: form.phone,
      moveInDate: form.moveIn,
      plannedMoveOut: form.plannedMoveOut,
      rentCents: parseAmountToCents(form.amount) ?? 0,
      dueDay: int.tryParse(form.dueDay.trim()) ?? 5,
    );
  } else {
    message = controller.updateTenant(
      tenantId: editing.id,
      fullName: form.name,
      cedula: form.cedula,
      phone: form.phone,
    );
  }

  if (message != null) {
    form.error.value = message;
    return;
  }

  final navigator = Navigator.of(context);
  reportOutcome(
    context,
    null,
    successMessage: editing == null
        ? 'Inquilino registrado y contrato iniciado.'
        : 'Datos del inquilino actualizados.',
  );
  navigator.pop();
}

class _TenantFormData {
  _TenantFormData({
    required String name,
    required String cedula,
    required String phone,
    required this.moveIn,
    required this.plannedMoveOut,
    required String amount,
    required String dueDay,
  }) : nameController = TextEditingController(text: name),
       cedulaController = TextEditingController(text: cedula),
       phoneController = TextEditingController(text: phone),
       amountController = TextEditingController(text: amount),
       dueDayController = TextEditingController(text: dueDay);

  final TextEditingController nameController;
  final TextEditingController cedulaController;
  final TextEditingController phoneController;
  final TextEditingController amountController;
  final TextEditingController dueDayController;
  DateTime moveIn;
  DateTime? plannedMoveOut;
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  String get name => nameController.text;
  String get cedula => cedulaController.text;
  String get phone => phoneController.text;
  String get amount => amountController.text;
  String get dueDay => dueDayController.text;
}

Future<void> showEndLeaseDialog(
  BuildContext context, {
  required ApartmentRow apartment,
}) async {
  final controller = AppScope.read(context);
  var endDate = DateTime.now();
  final reasonController = TextEditingController();
  final lease = apartment.lease;
  final pending = lease == null
      ? (cents: 0, months: 0)
      : controller.outstandingForLease(lease.id);
  final heldDeposit = lease == null
      ? 0
      : controller.depositForLease(lease.id).heldCents;

  await showDialog<void>(
    context: context,
    barrierColor: const Color(0x660B1733),
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Finalizar contrato',
                  style: appText.cardTitle.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 6),
                Text(
                  'El apartamento ${apartment.identifier} quedará disponible. '
                  'El historial del inquilino y los recibos se conservan.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
                if (pending.cents > 0) ...[
                  const SizedBox(height: 10),
                  InlineNotice(
                    text:
                        'Renta pendiente: ${formatMoney(pending.cents)} en '
                        '${pending.months} mes(es). Puede finalizar dejando el '
                        'saldo registrado para cobrarlo después.',
                    tone: PillTone.warning,
                  ),
                ],
                if (heldDeposit > 0) ...[
                  const SizedBox(height: 8),
                  InlineNotice(
                    text:
                        'Depósito retenido: ${formatMoney(heldDeposit)}. '
                        'Devuélvalo o reténgalo desde la pestaña Depósito; si no, '
                        'quedará registrado como pendiente de liquidar.',
                    tone: PillTone.info,
                  ),
                ],
                const SizedBox(height: 16),
                LabeledField(
                  label: 'Fecha de salida',
                  child: AppDateField(
                    value: endDate,
                    onPick: (date) => setState(() => endDate = date),
                  ),
                ),
                const SizedBox(height: 12),
                LabeledField(
                  label: 'Motivo (opcional)',
                  child: TextField(
                    controller: reasonController,
                    decoration: const InputDecoration(
                      hintText: 'Ej. Mudanza del inquilino',
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlineButton(
                      label: 'Cancelar',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 10),
                    PrimaryButton(
                      label: 'Finalizar contrato',
                      onPressed: () {
                        final lease = apartment.lease;
                        if (lease == null) return;
                        final message = controller.endLease(
                          leaseId: lease.id,
                          endDate: endDate,
                          reason: reasonController.text,
                        );
                        if (message != null) {
                          reportOutcome(context, message, successMessage: '');
                          return;
                        }
                        final navigator = Navigator.of(context);
                        reportOutcome(
                          context,
                          null,
                          successMessage:
                              'Contrato finalizado. Apartamento disponible.',
                        );
                        navigator.pop();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  reasonController.dispose();
}

/// Cobro en ventana compacta: reutiliza el formulario real dentro de un
/// diálogo, para no perder el botón de guardar en pantallas pequeñas.
Future<void> showPaymentDialog(BuildContext context) {
  final apartment = AppScope.read(context).selectedApartment;
  if (apartment == null || apartment.lease == null) return Future.value();
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x660B1733),
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: const PaymentCard(),
      ),
    ),
  );
}

// ------------------------------------------------------ anulación de pago

/// Anular un pago es una acción financiera destructiva: se confirma con motivo
/// y queda auditada. Devuelve el mensaje de error o null si se anuló.
Future<String?> showVoidPaymentDialog(
  BuildContext context, {
  required PaymentRecord payment,
}) async {
  final controller = AppScope.read(context);
  final reasonController = TextEditingController();
  final form = _FormState();

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Anular pago',
                  style: appText.cardTitle.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 8),
                Text(
                  'Se anulará el pago de ${formatMoney(payment.amountCents)} del '
                  'período ${payment.periodLabel} (recibo ${payment.receiptLabel}). '
                  'El recibo original se conserva y se emitirá una nota de '
                  'anulación. El saldo del período se restaura.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                LabeledField(
                  label: 'Motivo de la anulación',
                  child: TextField(
                    controller: reasonController,
                    autofocus: true,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Ej. Se cobró dos veces',
                      errorText: form.error,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlineButton(
                      label: 'Cancelar',
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                    const SizedBox(width: 10),
                    PrimaryButton(
                      label: form.busy ? 'Anulando…' : 'Anular pago',
                      onPressed: form.busy
                          ? null
                          : () async {
                              if (reasonController.text.trim().isEmpty) {
                                setState(
                                  () => form.error = 'Escriba el motivo.',
                                );
                                return;
                              }
                              setState(() {
                                form.busy = true;
                                form.error = null;
                              });
                              final message = await controller.voidPayment(
                                payment.id,
                                reasonController.text,
                              );
                              if (!context.mounted) return;
                              if (message != null) {
                                setState(() {
                                  form.busy = false;
                                  form.error = message;
                                });
                                return;
                              }
                              Navigator.of(context).pop(true);
                            },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  reasonController.dispose();
  return ok == true ? null : null;
}

// -------------------------------------------------------------- depósitos

/// Registra un movimiento de depósito (recibir, devolver o retener).
Future<void> showDepositDialog(
  BuildContext context, {
  required DepositKind kind,
  required int heldCents,
  required int requiredCents,
}) async {
  final controller = AppScope.read(context);
  final amountController = TextEditingController(
    text: formatAmountInput(
      kind == DepositKind.recibido
          ? (requiredCents - heldCents).clamp(0, requiredCents)
          : heldCents,
    ),
  );
  final reasonController = TextEditingController();
  var date = DateTime.now();
  final form = _FormState();

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 470),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  kind.label,
                  style: appText.cardTitle.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 6),
                Text(
                  kind == DepositKind.recibido
                      ? 'Dinero de garantía recibido. No cuenta como pago de '
                            'alquiler.'
                      : 'Dinero de garantía que se devuelve o se retiene. '
                            'Máximo disponible: ${formatMoney(heldCents)}.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: LabeledField(
                        label: 'Monto (RD\$)',
                        child: TextField(
                          controller: amountController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: '8,000.00',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: LabeledField(
                        label: 'Fecha',
                        child: AppDateField(
                          value: date,
                          onPick: (value) => setState(() => date = value),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LabeledField(
                  label: kind == DepositKind.retenido
                      ? 'Motivo de la retención (obligatorio)'
                      : 'Nota (opcional)',
                  child: TextField(
                    controller: reasonController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: kind == DepositKind.retenido
                          ? 'Ej. Daños en la pintura'
                          : 'Ej. Devolución al finalizar el contrato',
                      errorText: form.error,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlineButton(
                      label: 'Cancelar',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    OutlineButton(
                      label: 'Guardar',
                      icon: Icons.save_outlined,
                      onPressed: form.busy
                          ? null
                          : () => _submitDeposit(
                              context,
                              controller,
                              form,
                              setState,
                              kind: kind,
                              amountController: amountController,
                              reasonController: reasonController,
                              date: date,
                              print: false,
                            ),
                    ),
                    PrimaryButton(
                      label: form.busy ? 'Guardando…' : 'Guardar e imprimir',
                      icon: Icons.print_outlined,
                      onPressed: form.busy
                          ? null
                          : () => _submitDeposit(
                              context,
                              controller,
                              form,
                              setState,
                              kind: kind,
                              amountController: amountController,
                              reasonController: reasonController,
                              date: date,
                              print: true,
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  amountController.dispose();
  reasonController.dispose();
}

Future<void> _submitDeposit(
  BuildContext context,
  AppController controller,
  _FormState form,
  StateSetter setState, {
  required DepositKind kind,
  required TextEditingController amountController,
  required TextEditingController reasonController,
  required DateTime date,
  required bool print,
}) async {
  final cents = parseAmountToCents(amountController.text);
  if (cents == null || cents <= 0) {
    setState(() => form.error = 'Revise el monto.');
    return;
  }
  if (kind == DepositKind.retenido && reasonController.text.trim().isEmpty) {
    setState(() => form.error = 'Escriba el motivo de la retención.');
    return;
  }

  setState(() {
    form.busy = true;
    form.error = null;
  });

  final result = await controller.submitDeposit(
    kind: kind,
    amountCents: cents,
    movementDate: date,
    reason: reasonController.text,
    printAfterSave: print,
  );

  if (!context.mounted) return;
  if (!result.ok) {
    setState(() {
      form.busy = false;
      form.error = result.error;
    });
    return;
  }
  final navigator = Navigator.of(context);
  reportOutcome(
    context,
    null,
    successMessage: result.printMessage ?? result.notice,
  );
  navigator.pop();
}

// ------------------------------------------------- condiciones del contrato

/// Edita renta, día de pago, salida prevista, depósito pactado y notas.
/// Los recibos y períodos ya emitidos no cambian.
Future<void> showLeaseTermsDialog(
  BuildContext context, {
  required ApartmentRow apartment,
}) async {
  final controller = AppScope.read(context);
  final lease = apartment.lease;
  if (lease == null) return;

  final rentController = TextEditingController(
    text: formatAmountInput(lease.rentCents),
  );
  final dueDayController = TextEditingController(text: '${lease.dueDay}');
  final depositController = TextEditingController(
    text: formatAmountInput(lease.depositRequiredCents),
  );
  final notesController = TextEditingController(text: lease.notes);
  var plannedEnd = lease.plannedEndDate;
  final form = _FormState();

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 580),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Condiciones del contrato',
                  style: appText.cardTitle.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Los meses ya cobrados conservan su monto original.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: LabeledField(
                        label: 'Alquiler mensual (RD\$)',
                        child: TextField(
                          controller: rentController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 110,
                      child: LabeledField(
                        label: 'Día de pago',
                        child: TextField(
                          controller: dueDayController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: LabeledField(
                        label: 'Depósito acordado (RD\$)',
                        child: TextField(
                          controller: depositController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: LabeledField(
                        label: 'Salida prevista (opcional)',
                        child: AppDateField(
                          value: plannedEnd,
                          hint: 'Sin fecha',
                          onPick: (value) => setState(() => plannedEnd = value),
                          onClear: () => setState(() => plannedEnd = null),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LabeledField(
                  label: 'Notas (opcional)',
                  child: TextField(
                    controller: notesController,
                    maxLines: 2,
                    decoration: InputDecoration(errorText: form.error),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlineButton(
                      label: 'Cancelar',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 10),
                    PrimaryButton(
                      label: 'Guardar',
                      onPressed: form.busy
                          ? null
                          : () {
                              final rentError = validateAmount(
                                rentController.text,
                              );
                              final dayError = validateDueDay(
                                dueDayController.text,
                              );
                              final depositError =
                                  depositController.text.trim().isEmpty
                                  ? null
                                  : validateAmount(depositController.text);
                              final error =
                                  rentError ?? dayError ?? depositError;
                              if (error != null) {
                                setState(() => form.error = error);
                                return;
                              }
                              final message = controller.updateLeaseTerms(
                                leaseId: lease.id,
                                monthlyRentCents:
                                    parseAmountToCents(rentController.text) ??
                                    0,
                                dueDay:
                                    int.tryParse(
                                      dueDayController.text.trim(),
                                    ) ??
                                    5,
                                plannedEndDate: plannedEnd,
                                depositRequiredCents:
                                    depositController.text.trim().isEmpty
                                    ? 0
                                    : parseAmountToCents(
                                            depositController.text,
                                          ) ??
                                          0,
                                notes: notesController.text,
                              );
                              if (message != null) {
                                setState(() => form.error = message);
                                return;
                              }
                              final navigator = Navigator.of(context);
                              reportOutcome(
                                context,
                                null,
                                successMessage: 'Contrato actualizado.',
                              );
                              navigator.pop();
                            },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  rentController.dispose();
  dueDayController.dispose();
  depositController.dispose();
  notesController.dispose();
}

class _FormState {
  String? error;
  bool busy = false;
}
