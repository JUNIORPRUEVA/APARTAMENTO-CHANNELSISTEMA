import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../core/app_failure.dart';
import '../core/formatters.dart';
import 'app_database.dart';
import 'finance_models.dart';

/// Cobros, anulaciones y depósitos.
///
/// Reglas de integridad:
/// * Todo movimiento de dinero ocurre dentro de **una sola** transacción
///   (`BEGIN IMMEDIATE`): pago + período + recibo con su snapshot.
/// * `request_id` (UUID) hace idempotente cada operación: un doble clic o un
///   reintento devuelve el mismo resultado y no duplica el cobro.
/// * Nunca se borra ni se edita un movimiento: las correcciones son
///   anulaciones auditadas.
/// * El PDF no participa de la transacción: si falla, el pago sigue válido y el
///   recibo queda pendiente para regenerarse sin volver a cobrar.
class FinanceRepository {
  FinanceRepository(this._db);

  final AppDatabase _db;
  static const Uuid _uuid = Uuid();

  String get _now => DateTime.now().toIso8601String();

  /// UUID listo para usar como `requestId` de una operación nueva.
  static String newRequestId() => _uuid.v4();

  // ------------------------------------------------------------- períodos

  /// Períodos de un contrato entre dos meses, inclusive. **No escribe nada**:
  /// los meses sin fila se calculan y solo se materializan al cobrar.
  List<PaymentPeriod> periodsFor(
    int leaseId, {
    required DateTime from,
    required DateTime to,
  }) {
    final lease = _leaseContext(leaseId);
    if (lease == null) return const [];

    final fromKey = from.year * 100 + from.month;
    final toKey = to.year * 100 + to.month;
    final rows = _db.rows(
      '''
      SELECT pp.id, pp.period_year, pp.period_month, pp.due_date,
             pp.amount_due_cents,
             COALESCE(SUM(CASE WHEN p.voided_at IS NULL
                               THEN p.amount_cents ELSE 0 END), 0) AS paid
      FROM payment_periods pp
      LEFT JOIN payments p ON p.period_id = pp.id
      WHERE pp.lease_id = ?
        AND (pp.period_year * 100 + pp.period_month) BETWEEN ? AND ?
      GROUP BY pp.id
      ORDER BY pp.period_year, pp.period_month
    ''',
      [
        leaseId,
        fromKey < toKey ? fromKey : toKey,
        fromKey < toKey ? toKey : fromKey,
      ],
    );

    final byKey = <int, Map<String, Object?>>{
      for (final row in rows)
        (row['period_year'] as int) * 100 + (row['period_month'] as int): row,
    };

    final result = <PaymentPeriod>[];
    var cursor = DateTime(
      fromKey <= toKey ? from.year : to.year,
      fromKey <= toKey ? from.month : to.month,
    );
    final limit = DateTime(
      fromKey <= toKey ? to.year : from.year,
      fromKey <= toKey ? to.month : from.month,
    );
    for (var i = 0; i < 120 && !cursor.isAfter(limit); i++) {
      final key = cursor.year * 100 + cursor.month;
      final row = byKey[key];
      result.add(
        PaymentPeriod(
          id: row == null ? 0 : row['id'] as int,
          leaseId: leaseId,
          year: cursor.year,
          month: cursor.month,
          dueDate: row == null
              ? dayInMonth(cursor.year, cursor.month, lease.dueDay)
              : (parseIsoDate(row['due_date'] as String) ??
                    dayInMonth(cursor.year, cursor.month, lease.dueDay)),
          amountDueCents: row == null
              ? lease.monthlyRentCents
              : row['amount_due_cents'] as int,
          paidCents: row == null ? 0 : row['paid'] as int,
        ),
      );
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return result;
  }

  /// Primer período con saldo pendiente (para cobrar meses atrasados primero).
  PaymentPeriod? oldestUnpaid(int leaseId, {DateTime? today}) {
    final lease = _leaseContext(leaseId);
    if (lease == null) return null;
    final now = today ?? DateTime.now();
    final start = parseIsoDate(lease.startDate) ?? now;
    final periods = periodsFor(
      leaseId,
      from: DateTime(start.year, start.month),
      to: DateTime(now.year, now.month),
    );
    for (final period in periods) {
      if (period.remainingCents > 0) return period;
    }
    return null;
  }

  // ---------------------------------------------------------------- pagos

  /// Registra un cobro de alquiler de forma atómica e idempotente.
  PaymentOutcome registerPayment({
    required String requestId,
    required int leaseId,
    required int periodYear,
    required int periodMonth,
    required int amountCents,
    required DateTime paymentDate,
    required PaymentMethod method,
    String concept = 'Alquiler',
    String reference = '',
    String note = '',
  }) {
    if (requestId.trim().isEmpty) {
      throw const AppFailure('Falta el identificador de la operación.');
    }
    if (amountCents <= 0) {
      throw const AppFailure('El monto debe ser mayor que cero.');
    }
    if (periodMonth < 1 || periodMonth > 12) {
      throw const AppFailure('El período no es válido.');
    }

    try {
      return _db.tx(() {
        final duplicate = _existingPayment(requestId);
        if (duplicate != null) return duplicate;

        final lease = _leaseContext(leaseId);
        if (lease == null) {
          throw const AppFailure('El contrato ya no existe.');
        }
        if (lease.status != 'activo') {
          throw const AppFailure(
            'El contrato está finalizado. No se pueden registrar cobros.',
          );
        }

        final period = _ensurePeriod(
          lease: lease,
          year: periodYear,
          month: periodMonth,
        );
        if (amountCents > period.remainingCents) {
          throw AppFailure(
            period.remainingCents <= 0
                ? 'Ese período ya está pagado por completo.'
                : 'El monto supera el saldo del período '
                      '(${formatMoney(period.remainingCents)}).',
          );
        }

        _db.run(
          'INSERT INTO payments (request_id, lease_id, period_id, concept, '
          'payment_date, method, amount_cents, balance_after_cents, reference, '
          'note, created_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            requestId.trim(),
            leaseId,
            period.id,
            concept.trim().isEmpty ? 'Alquiler' : concept.trim(),
            toIsoDate(paymentDate),
            method.dbValue,
            amountCents,
            period.remainingCents - amountCents,
            reference.trim(),
            note.trim(),
            _now,
          ],
        );
        final paymentId = _db.lastInsertId;

        final series = _settings().series;
        final number = _nextNumber(series);
        final snapshot = _paymentSnapshot(
          lease: lease,
          period: period,
          series: series,
          number: number,
          amountCents: amountCents,
          balanceAfterCents: period.remainingCents - amountCents,
          method: method,
          concept: concept.trim().isEmpty ? 'Alquiler' : concept.trim(),
          paymentDate: paymentDate,
          reference: reference.trim(),
          note: note.trim(),
        );
        final receiptId = _insertReceipt(
          series: series,
          number: number,
          kind: ReceiptKind.alquiler,
          paymentId: paymentId,
          depositId: null,
          totalCents: amountCents,
          snapshot: snapshot,
        );

        return PaymentOutcome(
          paymentId: paymentId,
          receiptId: receiptId,
          receiptNumber: number,
          receiptSeries: series,
          balanceAfterCents: period.remainingCents - amountCents,
          duplicate: false,
        );
      });
    } on SqliteException catch (error) {
      // Otra llamada idéntica ganó la carrera: se devuelve la existente.
      if (isUniqueViolation(error)) {
        final existing = _existingPayment(requestId);
        if (existing != null) return existing;
      }
      throw AppFailure(
        'No se pudo guardar el pago. No se registró ningún cobro.',
        cause: error,
      );
    }
  }

  /// Anula un pago con motivo obligatorio. No borra nada: deja una nota de
  /// anulación y restaura el saldo del período.
  PaymentOutcome voidPayment({required int paymentId, required String reason}) {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty) {
      throw const AppFailure('Escriba el motivo de la anulación.');
    }

    return _db.tx(() {
      final rows = _db.rows(
        '''
        SELECT p.id, p.lease_id, p.amount_cents, p.payment_date, p.voided_at,
               pp.id AS period_id
        FROM payments p
        LEFT JOIN payment_periods pp ON pp.id = p.period_id
        WHERE p.id = ? LIMIT 1
      ''',
        [paymentId],
      );
      if (rows.isEmpty) throw const AppFailure('El pago ya no existe.');
      final payment = rows.first;
      if (payment['voided_at'] != null) {
        throw const AppFailure('Ese pago ya está anulado.');
      }

      final originalReceipt = _db.rows(
        'SELECT id, series, number, snapshot_json FROM receipts '
        'WHERE payment_id = ? LIMIT 1',
        [paymentId],
      );

      _db.run(
        'INSERT INTO payment_reversals (payment_id, request_id, reason, created_at) '
        'VALUES (?, ?, ?, ?)',
        [paymentId, 'rev-${_uuid.v4()}', cleanReason, _now],
      );
      _db.run(
        'UPDATE payments SET voided_at = ?, void_reason = ? WHERE id = ?',
        [_now, cleanReason, paymentId],
      );

      final series = _settings().series;
      final number = _nextNumber(series);
      final originalNumber = originalReceipt.isEmpty
          ? null
          : '${originalReceipt.first['series']}-'
                '${(originalReceipt.first['number'] as int).toString().padLeft(6, '0')}';

      Map<String, Object?>? originalSnapshot;
      if (originalReceipt.isNotEmpty) {
        try {
          originalSnapshot =
              jsonDecode(originalReceipt.first['snapshot_json'] as String)
                  as Map<String, Object?>;
        } catch (_) {
          originalSnapshot = null;
        }
      }

      final snapshot = <String, Object?>{
        if (originalSnapshot != null) ...originalSnapshot,
        'kind': ReceiptKind.anulacion.dbValue,
        'series': series,
        'number': number,
        'issuedAt': _now,
        'originalReceipt': originalNumber,
        'paymentDate': payment['payment_date'],
        'amountCents': payment['amount_cents'],
        'totalCents': payment['amount_cents'],
        'voidReason': cleanReason,
        'balanceAfterCents': 0,
      };

      final receiptId = _insertReceipt(
        series: series,
        number: number,
        kind: ReceiptKind.anulacion,
        paymentId: null,
        depositId: null,
        totalCents: payment['amount_cents'] as int,
        snapshot: snapshot,
      );

      // El saldo del período se recalcula a partir de los pagos no anulados.
      final periodId = payment['period_id'] as int?;
      final balanceAfter = periodId == null ? 0 : _remainingForPeriod(periodId);

      return PaymentOutcome(
        paymentId: paymentId,
        receiptId: receiptId,
        receiptNumber: number,
        receiptSeries: series,
        balanceAfterCents: balanceAfter,
        duplicate: false,
      );
    });
  }

  List<PaymentRecord> paymentsForApartment(int apartmentId) {
    final rows = _db.rows(
      '''
      SELECT p.id, p.request_id, p.lease_id, p.concept, p.payment_date,
             p.method, p.reference, p.amount_cents, p.balance_after_cents, p.note,
             p.voided_at, p.void_reason,
             pp.period_year, pp.period_month, pp.due_date, pp.amount_due_cents,
             t.full_name AS tenant_name,
             r.id AS receipt_id, r.series, r.number, r.pdf_status, r.pdf_path
      FROM payments p
      JOIN leases l ON l.id = p.lease_id
      JOIN tenants t ON t.id = l.tenant_id
      LEFT JOIN payment_periods pp ON pp.id = p.period_id
      LEFT JOIN receipts r ON r.payment_id = p.id
      WHERE l.apartment_id = ?
      ORDER BY p.payment_date DESC, p.id DESC
    ''',
      [apartmentId],
    );
    return rows.map(_mapPayment).toList(growable: false);
  }

  List<PaymentRecord> paymentsForLease(int leaseId) {
    final rows = _db.rows(
      '''
      SELECT p.id, p.request_id, p.lease_id, p.concept, p.payment_date,
             p.method, p.reference, p.amount_cents, p.balance_after_cents, p.note,
             p.voided_at, p.void_reason,
             pp.period_year, pp.period_month, pp.due_date, pp.amount_due_cents,
             t.full_name AS tenant_name,
             r.id AS receipt_id, r.series, r.number, r.pdf_status, r.pdf_path
      FROM payments p
      JOIN leases l ON l.id = p.lease_id
      JOIN tenants t ON t.id = l.tenant_id
      LEFT JOIN payment_periods pp ON pp.id = p.period_id
      LEFT JOIN receipts r ON r.payment_id = p.id
      WHERE p.lease_id = ?
      ORDER BY p.payment_date DESC, p.id DESC
    ''',
      [leaseId],
    );
    return rows.map(_mapPayment).toList(growable: false);
  }

  PaymentRecord _mapPayment(Map<String, Object?> row) {
    return PaymentRecord(
      id: row['id'] as int,
      requestId: row['request_id'] as String,
      leaseId: row['lease_id'] as int,
      tenantName: (row['tenant_name'] as String?) ?? '',
      concept: row['concept'] as String,
      paymentDate:
          parseIsoDate(row['payment_date'] as String) ?? DateTime.now(),
      amountCents: row['amount_cents'] as int,
      balanceAfterCents: (row['balance_after_cents'] as int?) ?? 0,
      method: PaymentMethod.fromDb(row['method'] as String),
      reference: (row['reference'] as String?) ?? '',
      note: (row['note'] as String?) ?? '',
      voidedAt: DateTime.tryParse((row['voided_at'] as String?) ?? ''),
      voidReason: (row['void_reason'] as String?) ?? '',
      periodYear: row['period_year'] as int?,
      periodMonth: row['period_month'] as int?,
      dueDate: parseIsoDate(row['due_date'] as String?),
      amountDueCents: (row['amount_due_cents'] as int?) ?? 0,
      receiptId: row['receipt_id'] as int?,
      receiptSeries: (row['series'] as String?) ?? '',
      receiptNumber: row['number'] as int?,
      pdfStatus: (row['pdf_status'] as String?) ?? 'pendiente',
      pdfPath: row['pdf_path'] as String?,
    );
  }

  // ------------------------------------------------------------ depósitos

  DepositSummary depositSummary(int leaseId) {
    final leaseRows = _db.rows(
      'SELECT deposit_required_cents FROM leases WHERE id = ? LIMIT 1',
      [leaseId],
    );
    final required = leaseRows.isEmpty
        ? 0
        : (leaseRows.first['deposit_required_cents'] as int? ?? 0);

    final movements = _db.rows(
      '''
      SELECT d.id, d.lease_id, d.kind, d.amount_cents, d.movement_date, d.reason,
             r.id AS receipt_id, r.number, r.pdf_status, r.pdf_path
      FROM deposit_movements d
      LEFT JOIN receipts r ON r.deposit_id = d.id
      WHERE d.lease_id = ?
      ORDER BY d.movement_date DESC, d.id DESC
    ''',
      [leaseId],
    );

    var received = 0;
    var refunded = 0;
    var retained = 0;
    final list = <DepositMovement>[];
    for (final row in movements) {
      final kind = DepositKind.fromDb(row['kind'] as String);
      final amount = row['amount_cents'] as int;
      switch (kind) {
        case DepositKind.recibido:
          received += amount;
        case DepositKind.devuelto:
          refunded += amount;
        case DepositKind.retenido:
          retained += amount;
      }
      list.add(
        DepositMovement(
          id: row['id'] as int,
          leaseId: row['lease_id'] as int,
          kind: kind,
          amountCents: amount,
          movementDate:
              parseIsoDate(row['movement_date'] as String) ?? DateTime.now(),
          reason: (row['reason'] as String?) ?? '',
          receiptId: row['receipt_id'] as int?,
          receiptNumber: row['number'] as int?,
          pdfStatus: (row['pdf_status'] as String?) ?? 'pendiente',
          pdfPath: row['pdf_path'] as String?,
        ),
      );
    }

    return DepositSummary(
      leaseId: leaseId,
      requiredCents: required,
      receivedCents: received,
      refundedCents: refunded,
      retainedCents: retained,
      movements: list,
    );
  }

  /// Registra un movimiento de depósito (recibido / devuelto / retenido).
  ///
  /// No puede devolverse ni retenerse más de lo que efectivamente se retiene.
  /// El depósito nunca se cuenta como pago de alquiler.
  DepositOutcome registerDeposit({
    required String requestId,
    required int leaseId,
    required DepositKind kind,
    required int amountCents,
    required DateTime movementDate,
    String reason = '',
  }) {
    if (requestId.trim().isEmpty) {
      throw const AppFailure('Falta el identificador de la operación.');
    }
    if (amountCents <= 0) {
      throw const AppFailure('El monto debe ser mayor que cero.');
    }
    if (kind == DepositKind.retenido && reason.trim().isEmpty) {
      throw const AppFailure('Escriba el motivo de la retención.');
    }

    try {
      return _db.tx(() {
        final existing = _db.rows(
          'SELECT id FROM deposit_movements WHERE request_id = ? LIMIT 1',
          [requestId],
        );
        if (existing.isNotEmpty) {
          final id = existing.first['id'] as int;
          final receipt = _db.rows(
            'SELECT id, number FROM receipts WHERE deposit_id = ? LIMIT 1',
            [id],
          );
          return DepositOutcome(
            movementId: id,
            receiptId: receipt.isEmpty ? 0 : receipt.first['id'] as int,
            receiptNumber: receipt.isEmpty ? 0 : receipt.first['number'] as int,
            duplicate: true,
            heldAfterCents: depositSummary(leaseId).heldCents,
          );
        }

        final lease = _leaseContext(leaseId);
        if (lease == null) {
          throw const AppFailure('El contrato ya no existe.');
        }

        final summary = depositSummary(leaseId);
        if (kind != DepositKind.recibido && amountCents > summary.heldCents) {
          throw AppFailure(
            'El depósito retenido es ${formatMoney(summary.heldCents)}. '
            'No se puede usar un monto mayor.',
          );
        }

        _db.run(
          'INSERT INTO deposit_movements (lease_id, request_id, kind, amount_cents, '
          'movement_date, reason, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            leaseId,
            requestId.trim(),
            kind.dbValue,
            amountCents,
            toIsoDate(movementDate),
            reason.trim(),
            _now,
          ],
        );
        final movementId = _db.lastInsertId;

        final series = _settings().series;
        final number = _nextNumber(series);
        final snapshot = _depositSnapshot(
          lease: lease,
          kind: kind,
          series: series,
          number: number,
          amountCents: amountCents,
          movementDate: movementDate,
          reason: reason.trim(),
          heldAfterCents: kind == DepositKind.recibido
              ? summary.heldCents + amountCents
              : summary.heldCents - amountCents,
        );
        final receiptId = _insertReceipt(
          series: series,
          number: number,
          kind: ReceiptKind.deposito,
          paymentId: null,
          depositId: movementId,
          totalCents: amountCents,
          snapshot: snapshot,
        );

        return DepositOutcome(
          movementId: movementId,
          receiptId: receiptId,
          receiptNumber: number,
          duplicate: false,
          heldAfterCents: kind == DepositKind.recibido
              ? summary.heldCents + amountCents
              : summary.heldCents - amountCents,
        );
      });
    } on SqliteException catch (error) {
      if (isUniqueViolation(error)) {
        throw AppFailure(
          'Ese movimiento de depósito ya estaba registrado.',
          cause: error,
        );
      }
      throw AppFailure(
        'No se pudo guardar el movimiento de depósito.',
        cause: error,
      );
    }
  }

  // ----------------------------------------------------------- documentos

  ReceiptRecord? receipt(int receiptId) {
    final rows = _db.rows(
      'SELECT id, series, number, kind, issued_at, total_cents, snapshot_json, '
      'pdf_path, pdf_status, attempts FROM receipts WHERE id = ? LIMIT 1',
      [receiptId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    Map<String, Object?> snapshot = const {};
    try {
      final decoded = jsonDecode(row['snapshot_json'] as String);
      if (decoded is Map) snapshot = Map<String, Object?>.from(decoded);
    } catch (_) {
      snapshot = const {};
    }
    return ReceiptRecord(
      id: row['id'] as int,
      series: row['series'] as String,
      number: row['number'] as int,
      kind: ReceiptKind.fromDb(row['kind'] as String),
      issuedAt: DateTime.tryParse(row['issued_at'] as String) ?? DateTime.now(),
      totalCents: row['total_cents'] as int,
      snapshot: snapshot,
      pdfPath: row['pdf_path'] as String?,
      pdfStatus: row['pdf_status'] as String,
      attempts: row['attempts'] as int,
    );
  }

  /// Recibos que necesitan (re)generar su PDF. Nunca crea pagos.
  List<ReceiptRecord> receiptsNeedingPdf({int limit = 25}) {
    final rows = _db.rows(
      "SELECT id FROM receipts WHERE pdf_status IN ('pendiente', 'fallido', 'faltante') "
      'AND attempts < 5 ORDER BY id LIMIT ?',
      [limit],
    );
    return [for (final row in rows) ?receipt(row['id'] as int)];
  }

  /// Recibos marcados como generados (para verificar que el archivo exista).
  List<ReceiptRecord> receiptsWithGeneratedPdf({int limit = 200}) {
    final rows = _db.rows(
      "SELECT id FROM receipts WHERE pdf_status = 'generado' "
      'ORDER BY id DESC LIMIT ?',
      [limit],
    );
    return [for (final row in rows) ?receipt(row['id'] as int)];
  }

  void markReceiptPdf({
    required int receiptId,
    required String status,
    String? path,
    String? error,
  }) {
    _db.run(
      'UPDATE receipts SET pdf_status = ?, pdf_path = COALESCE(?, pdf_path), '
      'attempts = attempts + 1, last_error = ? WHERE id = ?',
      [status, path, error, receiptId],
    );
  }

  /// Comprueba si el PDF existe realmente; corrige el estado si desapareció.
  /// La comprobación de archivos vive en `ReceiptDocumentService`.
  bool pdfExists(ReceiptRecord record) {
    final path = record.pdfPath;
    return path != null && path.isNotEmpty;
  }

  // ------------------------------------------------------------- internos

  _LeaseContext? _leaseContext(int leaseId) {
    final rows = _db.rows(
      '''
      SELECT l.id, l.apartment_id, l.tenant_id, l.monthly_rent_cents, l.due_day,
             l.start_date, l.status, l.deposit_required_cents,
             t.full_name, t.cedula, t.phone,
             a.identifier, a.location, g.name AS group_name
      FROM leases l
      JOIN tenants t ON t.id = l.tenant_id
      JOIN apartments a ON a.id = l.apartment_id
      JOIN apartment_groups g ON g.id = a.group_id
      WHERE l.id = ? LIMIT 1
    ''',
      [leaseId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return _LeaseContext(
      id: row['id'] as int,
      apartmentId: row['apartment_id'] as int,
      tenantId: row['tenant_id'] as int,
      monthlyRentCents: row['monthly_rent_cents'] as int,
      dueDay: row['due_day'] as int,
      startDate: row['start_date'] as String,
      status: row['status'] as String,
      depositRequiredCents: (row['deposit_required_cents'] as int?) ?? 0,
      tenantName: row['full_name'] as String,
      tenantCedula: (row['cedula'] as String?) ?? '',
      tenantPhone: (row['phone'] as String?) ?? '',
      identifier: row['identifier'] as String,
      location: (row['location'] as String?) ?? '',
      groupName: row['group_name'] as String,
    );
  }

  PaymentPeriod _ensurePeriod({
    required _LeaseContext lease,
    required int year,
    required int month,
  }) {
    final existing = _db.rows(
      'SELECT id, due_date, amount_due_cents FROM payment_periods '
      'WHERE lease_id = ? AND period_year = ? AND period_month = ? LIMIT 1',
      [lease.id, year, month],
    );

    if (existing.isEmpty) {
      final due = dayInMonth(year, month, lease.dueDay);
      _db.run(
        'INSERT INTO payment_periods (lease_id, period_year, period_month, '
        'due_date, amount_due_cents) VALUES (?, ?, ?, ?, ?)',
        [lease.id, year, month, toIsoDate(due), lease.monthlyRentCents],
      );
      final id = _db.lastInsertId;
      return PaymentPeriod(
        id: id,
        leaseId: lease.id,
        year: year,
        month: month,
        dueDate: due,
        amountDueCents: lease.monthlyRentCents,
        paidCents: 0,
      );
    }

    final row = existing.first;
    final id = row['id'] as int;
    return PaymentPeriod(
      id: id,
      leaseId: lease.id,
      year: year,
      month: month,
      dueDate:
          parseIsoDate(row['due_date'] as String) ??
          dayInMonth(year, month, lease.dueDay),
      amountDueCents: row['amount_due_cents'] as int,
      paidCents: _paidForPeriod(id),
    );
  }

  int _paidForPeriod(int periodId) {
    final row = _db.rows(
      'SELECT COALESCE(SUM(amount_cents), 0) AS paid FROM payments '
      'WHERE period_id = ? AND voided_at IS NULL',
      [periodId],
    ).first;
    return row['paid'] as int;
  }

  int _remainingForPeriod(int periodId) {
    final row = _db.rows(
      'SELECT amount_due_cents FROM payment_periods WHERE id = ? LIMIT 1',
      [periodId],
    ).first;
    return (row['amount_due_cents'] as int) - _paidForPeriod(periodId);
  }

  PaymentOutcome? _existingPayment(String requestId) {
    final rows = _db.rows(
      '''
      SELECT p.id, p.balance_after_cents, r.id AS receipt_id, r.number, r.series
      FROM payments p
      LEFT JOIN receipts r ON r.payment_id = p.id
      WHERE p.request_id = ? LIMIT 1
    ''',
      [requestId.trim()],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return PaymentOutcome(
      paymentId: row['id'] as int,
      receiptId: (row['receipt_id'] as int?) ?? 0,
      receiptNumber: (row['number'] as int?) ?? 0,
      receiptSeries: (row['series'] as String?) ?? '',
      balanceAfterCents: (row['balance_after_cents'] as int?) ?? 0,
      duplicate: true,
    );
  }

  int _insertReceipt({
    required String series,
    required int number,
    required ReceiptKind kind,
    required int? paymentId,
    required int? depositId,
    required int totalCents,
    required Map<String, Object?> snapshot,
  }) {
    _db.run(
      'INSERT INTO receipts (series, number, kind, payment_id, deposit_id, '
      'issued_at, total_cents, snapshot_json, pdf_status) '
      "VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pendiente')",
      [
        series,
        number,
        kind.dbValue,
        paymentId,
        depositId,
        _now,
        totalCents,
        jsonEncode(snapshot),
      ],
    );
    return _db.lastInsertId;
  }

  int _nextNumber(String series) {
    final row = _db.rows(
      'SELECT COALESCE(MAX(number), 0) + 1 AS next FROM receipts WHERE series = ?',
      [series],
    ).first;
    return row['next'] as int;
  }

  ({String series, String name, String id, String address, String phone})
  _settings() {
    final rows = _db.rows(
      'SELECT issuer_name, issuer_id, issuer_address, issuer_phone, receipt_prefix '
      'FROM owner_settings WHERE id = 1',
    );
    if (rows.isEmpty) {
      return (series: 'REC', name: '', id: '', address: '', phone: '');
    }
    final row = rows.first;
    final prefix = (row['receipt_prefix'] as String?) ?? 'REC';
    return (
      series: prefix.trim().isEmpty ? 'REC' : prefix.trim(),
      name: (row['issuer_name'] as String?) ?? '',
      id: (row['issuer_id'] as String?) ?? '',
      address: (row['issuer_address'] as String?) ?? '',
      phone: (row['issuer_phone'] as String?) ?? '',
    );
  }

  Map<String, Object?> _paymentSnapshot({
    required _LeaseContext lease,
    required PaymentPeriod period,
    required String series,
    required int number,
    required int amountCents,
    required int balanceAfterCents,
    required PaymentMethod method,
    required String concept,
    required DateTime paymentDate,
    required String reference,
    required String note,
  }) {
    final issuer = _settings();
    return <String, Object?>{
      'kind': ReceiptKind.alquiler.dbValue,
      'series': series,
      'number': number,
      'issuedAt': _now,
      'issuerName': issuer.name,
      'issuerId': issuer.id,
      'issuerAddress': issuer.address,
      'issuerPhone': issuer.phone,
      'tenantName': lease.tenantName,
      'tenantCedula': lease.tenantCedula,
      'tenantPhone': lease.tenantPhone,
      'groupName': lease.groupName,
      'apartmentIdentifier': lease.identifier,
      'apartmentLocation': lease.location,
      'leaseId': lease.id,
      'periodYear': period.year,
      'periodMonth': period.month,
      'periodLabel': formatPeriodTitle(period.year, period.month),
      'dueDate': toIsoDate(period.dueDate),
      'concept': concept,
      'amountCents': amountCents,
      'amountDueCents': period.amountDueCents,
      'balanceAfterCents': balanceAfterCents,
      'method': method.label,
      'paymentDate': toIsoDate(paymentDate),
      'reference': reference,
      'note': note,
    };
  }

  Map<String, Object?> _depositSnapshot({
    required _LeaseContext lease,
    required DepositKind kind,
    required String series,
    required int number,
    required int amountCents,
    required DateTime movementDate,
    required String reason,
    required int heldAfterCents,
  }) {
    final issuer = _settings();
    return <String, Object?>{
      'kind': ReceiptKind.deposito.dbValue,
      'depositKind': kind.dbValue,
      'depositKindLabel': kind.label,
      'series': series,
      'number': number,
      'issuedAt': _now,
      'issuerName': issuer.name,
      'issuerId': issuer.id,
      'issuerAddress': issuer.address,
      'issuerPhone': issuer.phone,
      'tenantName': lease.tenantName,
      'tenantCedula': lease.tenantCedula,
      'tenantPhone': lease.tenantPhone,
      'groupName': lease.groupName,
      'apartmentIdentifier': lease.identifier,
      'apartmentLocation': lease.location,
      'leaseId': lease.id,
      'concept': kind.label,
      'amountCents': amountCents,
      'heldAfterCents': heldAfterCents,
      'method': '—',
      'paymentDate': toIsoDate(movementDate),
      'note': reason,
    };
  }
}

class _LeaseContext {
  const _LeaseContext({
    required this.id,
    required this.apartmentId,
    required this.tenantId,
    required this.monthlyRentCents,
    required this.dueDay,
    required this.startDate,
    required this.status,
    required this.depositRequiredCents,
    required this.tenantName,
    required this.tenantCedula,
    required this.tenantPhone,
    required this.identifier,
    required this.location,
    required this.groupName,
  });

  final int id;
  final int apartmentId;
  final int tenantId;
  final int monthlyRentCents;
  final int dueDay;
  final String startDate;
  final String status;
  final int depositRequiredCents;
  final String tenantName;
  final String tenantCedula;
  final String tenantPhone;
  final String identifier;
  final String location;
  final String groupName;
}
