import 'dart:math' as math;

import '../core/formatters.dart';

/// Estado de la renta de un apartamento, siempre derivado de datos reales.
enum RentStatus {
  alDia('Al día', 'success'),
  parcial('Parcial', 'info'),
  pendiente('Pendiente', 'warning'),
  vencido('Vencido', 'danger'),
  disponible('Disponible', 'gray');

  const RentStatus(this.label, this.toneKey);

  final String label;

  /// Clave usada por la interfaz para elegir el color de la pill.
  final String toneKey;
}

enum PaymentMethod {
  efectivo('efectivo', 'Efectivo'),
  transferencia('transferencia', 'Transferencia');

  const PaymentMethod(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static PaymentMethod fromDb(String value) => PaymentMethod.values.firstWhere(
    (m) => m.dbValue == value,
    orElse: () => PaymentMethod.efectivo,
  );
}

enum DepositKind {
  recibido('recibido', 'Depósito recibido'),
  devuelto('devuelto', 'Depósito devuelto'),
  retenido('retenido', 'Depósito retenido');

  const DepositKind(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static DepositKind fromDb(String value) => DepositKind.values.firstWhere(
    (d) => d.dbValue == value,
    orElse: () => DepositKind.recibido,
  );
}

enum ReceiptKind {
  alquiler('alquiler', 'RECIBO DE ALQUILER'),
  deposito('deposito', 'RECIBO DE DEPÓSITO'),
  anulacion('anulacion', 'NOTA DE ANULACIÓN');

  const ReceiptKind(this.dbValue, this.title);

  final String dbValue;
  final String title;

  static ReceiptKind fromDb(String value) => ReceiptKind.values.firstWhere(
    (k) => k.dbValue == value,
    orElse: () => ReceiptKind.alquiler,
  );
}

/// Un período de facturación mensual de un contrato.
///
/// `id == 0` significa período calculado (todavía no existe fila en la base):
/// se usa solo para mostrar y se materializa al cobrar.
class PaymentPeriod {
  const PaymentPeriod({
    required this.id,
    required this.leaseId,
    required this.year,
    required this.month,
    required this.dueDate,
    required this.amountDueCents,
    required this.paidCents,
  });

  final int id;
  final int leaseId;
  final int year;
  final int month;
  final DateTime dueDate;
  final int amountDueCents;
  final int paidCents;

  bool get materialized => id != 0;
  int get remainingCents => math.max(0, amountDueCents - paidCents);
  bool get isPaid => remainingCents == 0 && amountDueCents > 0;
  bool get hasPartial => paidCents > 0 && remainingCents > 0;

  String get label => formatPeriodTitle(year, month);

  /// Estado del período en una fecha dada.
  RentStatus statusAt(DateTime today) {
    final day = DateTime(today.year, today.month, today.day);
    if (amountDueCents == 0) return RentStatus.alDia;
    if (remainingCents == 0) return RentStatus.alDia;
    if (paidCents > 0 && day.isAfter(dueDate)) return RentStatus.vencido;
    if (day.isAfter(dueDate)) return RentStatus.vencido;
    if (paidCents > 0) return RentStatus.parcial;
    return RentStatus.pendiente;
  }
}

/// Cálculo determinista del estado de la renta a partir de los períodos.
///
/// Reglas (sin prorrateos ni recargos automáticos):
/// * Se revisa mes por mes desde el inicio del contrato hasta el mes actual.
/// * El primer mes con saldo pendiente define el estado (vencido si su fecha de
///   vencimiento ya pasó, parcial si hay abono, pendiente si no).
/// * Si no queda saldo pendiente en ese rango, el contrato está al día.
abstract final class RentLedger {
  /// Meses (año, mes) desde [start] hasta [today], ambos inclusive.
  static List<({int year, int month})> monthsBetween(
    DateTime start,
    DateTime today,
  ) {
    final result = <({int year, int month})>[];
    var cursor = DateTime(start.year, start.month);
    final limit = DateTime(today.year, today.month);
    // Tope de seguridad: 40 años de meses.
    for (var i = 0; i < 480 && !cursor.isAfter(limit); i++) {
      result.add((year: cursor.year, month: cursor.month));
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return result;
  }

  /// [paidByMonth] usa la clave `año * 100 + mes`.
  static RentStatus statusFor({
    required DateTime startDate,
    required int monthlyRentCents,
    required int dueDay,
    required Map<int, int> paidByMonth,
    required Map<int, int> dueByMonth,
    required DateTime today,
  }) {
    final day = DateTime(today.year, today.month, today.day);
    if (!day.isBefore(DateTime(startDate.year, startDate.month))) {
      for (final month in monthsBetween(startDate, day)) {
        final key = month.year * 100 + month.month;
        final due = dueByMonth[key] ?? monthlyRentCents;
        final paid = paidByMonth[key] ?? 0;
        final remaining = due - paid;
        if (remaining <= 0) continue;
        final dueDate = dayInMonth(month.year, month.month, dueDay);
        if (day.isAfter(dueDate)) return RentStatus.vencido;
        if (paid > 0) return RentStatus.parcial;
        return RentStatus.pendiente;
      }
    }
    return RentStatus.alDia;
  }

  /// Períodos con saldo pendiente hasta [today], del más antiguo al más nuevo.
  static List<({int year, int month, int remainingCents, DateTime dueDate})>
  pendingMonths({
    required DateTime startDate,
    required int monthlyRentCents,
    required int dueDay,
    required Map<int, int> paidByMonth,
    required Map<int, int> dueByMonth,
    required DateTime today,
  }) {
    final day = DateTime(today.year, today.month, today.day);
    final result =
        <({int year, int month, int remainingCents, DateTime dueDate})>[];
    if (day.isBefore(DateTime(startDate.year, startDate.month))) return result;
    for (final month in monthsBetween(startDate, day)) {
      final key = month.year * 100 + month.month;
      final due = dueByMonth[key] ?? monthlyRentCents;
      final paid = paidByMonth[key] ?? 0;
      final remaining = due - paid;
      if (remaining <= 0) continue;
      result.add((
        year: month.year,
        month: month.month,
        remainingCents: remaining,
        dueDate: dayInMonth(month.year, month.month, dueDay),
      ));
    }
    return result;
  }
}

class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.requestId,
    required this.leaseId,
    required this.tenantName,
    required this.concept,
    required this.paymentDate,
    required this.amountCents,
    required this.balanceAfterCents,
    required this.method,
    required this.reference,
    required this.note,
    required this.voidedAt,
    required this.voidReason,
    required this.periodYear,
    required this.periodMonth,
    required this.dueDate,
    required this.amountDueCents,
    required this.receiptId,
    required this.receiptSeries,
    required this.receiptNumber,
    required this.pdfStatus,
    required this.pdfPath,
  });

  final int id;
  final String requestId;
  final int leaseId;
  final String tenantName;
  final String concept;
  final DateTime paymentDate;
  final int amountCents;
  final int balanceAfterCents;
  final PaymentMethod method;

  /// Referencia opcional de la operación (número de transferencia, comprobante).
  final String reference;
  final String note;
  final DateTime? voidedAt;
  final String voidReason;
  final int? periodYear;
  final int? periodMonth;
  final DateTime? dueDate;
  final int amountDueCents;
  final int? receiptId;
  final String receiptSeries;
  final int? receiptNumber;
  final String pdfStatus;
  final String? pdfPath;

  bool get isVoided => voidedAt != null;
  String get periodLabel => periodYear == null || periodMonth == null
      ? '—'
      : formatPeriodShort(periodYear!, periodMonth!);
  String get receiptLabel => receiptNumber == null
      ? '—'
      : '$receiptSeries-${receiptNumber!.toString().padLeft(6, '0')}';
}

class DepositMovement {
  const DepositMovement({
    required this.id,
    required this.leaseId,
    required this.kind,
    required this.amountCents,
    required this.movementDate,
    required this.reason,
    required this.receiptId,
    required this.receiptNumber,
    required this.pdfStatus,
    required this.pdfPath,
  });

  final int id;
  final int leaseId;
  final DepositKind kind;
  final int amountCents;
  final DateTime movementDate;
  final String reason;
  final int? receiptId;
  final int? receiptNumber;
  final String pdfStatus;
  final String? pdfPath;
}

class DepositSummary {
  const DepositSummary({
    required this.leaseId,
    required this.requiredCents,
    required this.receivedCents,
    required this.refundedCents,
    required this.retainedCents,
    required this.movements,
  });

  final int leaseId;
  final int requiredCents;
  final int receivedCents;
  final int refundedCents;
  final int retainedCents;
  final List<DepositMovement> movements;

  /// Dinero de garantía que la aplicación todavía tiene registrado.
  int get heldCents => receivedCents - refundedCents - retainedCents;

  bool get isEmpty => movements.isEmpty;
}

/// Resultado de un cobro (o de un intento repetido con el mismo requestId).
class PaymentOutcome {
  const PaymentOutcome({
    required this.paymentId,
    required this.receiptId,
    required this.receiptNumber,
    required this.receiptSeries,
    required this.balanceAfterCents,
    required this.duplicate,
  });

  final int paymentId;
  final int receiptId;
  final int receiptNumber;
  final String receiptSeries;
  final int balanceAfterCents;

  /// `true` cuando la petición ya se había registrado antes (idempotencia).
  final bool duplicate;

  String get receiptLabel =>
      '$receiptSeries-${receiptNumber.toString().padLeft(6, '0')}';
}

class DepositOutcome {
  const DepositOutcome({
    required this.movementId,
    required this.receiptId,
    required this.receiptNumber,
    required this.duplicate,
    required this.heldAfterCents,
  });

  final int movementId;
  final int receiptId;
  final int receiptNumber;
  final bool duplicate;
  final int heldAfterCents;
}

/// Documento (recibo o nota) con su snapshot inmutable.
class ReceiptRecord {
  const ReceiptRecord({
    required this.id,
    required this.series,
    required this.number,
    required this.kind,
    required this.issuedAt,
    required this.totalCents,
    required this.snapshot,
    required this.pdfPath,
    required this.pdfStatus,
    required this.attempts,
  });

  final int id;
  final String series;
  final int number;
  final ReceiptKind kind;
  final DateTime issuedAt;
  final int totalCents;
  final Map<String, Object?> snapshot;
  final String? pdfPath;
  final String pdfStatus;
  final int attempts;

  String get label => '$series-${number.toString().padLeft(6, '0')}';
}
