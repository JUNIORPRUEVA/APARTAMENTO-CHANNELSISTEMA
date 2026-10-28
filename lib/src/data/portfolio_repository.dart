import 'package:sqlite3/sqlite3.dart';

import '../core/app_failure.dart';
import '../core/formatters.dart';
import '../core/validators.dart';
import 'app_database.dart';
import 'finance_models.dart';
import 'models.dart';

/// Acceso a residenciales, apartamentos, inquilinos y contratos.
///
/// Todas las escrituras van en transacción y traducen los errores de SQLite a
/// mensajes en español aptos para el usuario final.
class PortfolioRepository {
  PortfolioRepository(this._db);

  final AppDatabase _db;

  String get _now => DateTime.now().toIso8601String();

  // ---------------------------------------------------------------- grupos

  List<ApartmentGroup> groups() {
    return _db
        .rows(
          'SELECT id, name, sort_order, is_demo FROM apartment_groups '
          'ORDER BY sort_order, name COLLATE NOCASE',
        )
        .map(
          (row) => ApartmentGroup(
            id: row['id'] as int,
            name: row['name'] as String,
            sortOrder: row['sort_order'] as int,
            isDemo: (row['is_demo'] as int) == 1,
          ),
        )
        .toList(growable: false);
  }

  int createGroup(String name, {bool isDemo = false}) {
    final clean = name.trim();
    final error = validateGroupName(clean);
    if (error != null) throw AppFailure(error);

    try {
      _db.run(
        'INSERT INTO apartment_groups (name, sort_order, is_demo, created_at) '
        'VALUES (?, (SELECT COALESCE(MAX(sort_order), 0) + 1 FROM apartment_groups), ?, ?)',
        [clean, isDemo ? 1 : 0, _now],
      );
      return _db.lastInsertId;
    } on SqliteException catch (error) {
      if (isUniqueViolation(error)) {
        throw AppFailure(
          'Ya existe un residencial con el nombre "$clean".',
          cause: error,
        );
      }
      throw AppFailure('No se pudo crear el residencial.', cause: error);
    }
  }

  void renameGroup(int groupId, String name) {
    final clean = name.trim();
    final error = validateGroupName(clean);
    if (error != null) throw AppFailure(error);

    try {
      _db.run('UPDATE apartment_groups SET name = ? WHERE id = ?', [
        clean,
        groupId,
      ]);
    } on SqliteException catch (error) {
      if (isUniqueViolation(error)) {
        throw AppFailure(
          'Ya existe un residencial con el nombre "$clean".',
          cause: error,
        );
      }
      throw AppFailure('No se pudo renombrar el residencial.', cause: error);
    }
  }

  /// Elimina un residencial **solo si está vacío**.
  ///
  /// Sirve para corregir un nombre escrito por error sin dejar basura en la
  /// lista. Si tiene apartamentos se rechaza: nunca se borra en cascada un
  /// apartamento con historial de cobros.
  void deleteGroup(int groupId) {
    _db.tx(() {
      final rows = _db.rows(
        'SELECT name FROM apartment_groups WHERE id = ? LIMIT 1',
        [groupId],
      );
      if (rows.isEmpty) {
        throw const AppFailure('Ese residencial ya no existe.');
      }
      final name = (rows.first['name'] as String?) ?? '';
      final count =
          _db.rows('SELECT COUNT(*) AS c FROM apartments WHERE group_id = ?', [
                groupId,
              ]).first['c']
              as int;
      if (count > 0) {
        throw AppFailure(
          'El residencial "$name" todavía tiene $count apartamento'
          '${count == 1 ? '' : 's'}. Muévalos o elimínelos antes de borrarlo.',
        );
      }
      try {
        _db.run('DELETE FROM apartment_groups WHERE id = ?', [groupId]);
      } on SqliteException catch (error) {
        throw AppFailure('No se pudo eliminar el residencial.', cause: error);
      }
    });
  }

  // ----------------------------------------------------------- apartamentos

  List<ApartmentRow> listApartments() {
    final rows = _db.rows('''
      SELECT a.id, a.group_id, g.name AS group_name, a.identifier, a.location,
             a.rent_cents, a.status, a.is_demo,
             l.id AS lease_id, l.tenant_id AS lease_tenant_id,
             l.monthly_rent_cents, l.due_day, l.start_date,
             l.planned_end_date, l.actual_end_date, l.end_reason,
             l.deposit_required_cents, l.notes AS lease_notes,
             t.id AS tenant_id, t.full_name, t.cedula, t.phone
      FROM apartments a
      JOIN apartment_groups g ON g.id = a.group_id
      LEFT JOIN leases l ON l.apartment_id = a.id AND l.status = 'activo'
      LEFT JOIN tenants t ON t.id = l.tenant_id
      ORDER BY g.sort_order, g.name COLLATE NOCASE, a.identifier COLLATE NOCASE
    ''');
    final statuses = _rentStatuses();
    return rows
        .map((row) => _mapApartment(row, statuses[row['lease_id'] as int?]))
        .toList(growable: false);
  }

  ApartmentRow? findApartment(int id) {
    final rows = _db.rows(
      '''
      SELECT a.id, a.group_id, g.name AS group_name, a.identifier, a.location,
             a.rent_cents, a.status, a.is_demo,
             l.id AS lease_id, l.tenant_id AS lease_tenant_id,
             l.monthly_rent_cents, l.due_day, l.start_date,
             l.planned_end_date, l.actual_end_date, l.end_reason,
             l.deposit_required_cents, l.notes AS lease_notes,
             t.id AS tenant_id, t.full_name, t.cedula, t.phone
      FROM apartments a
      JOIN apartment_groups g ON g.id = a.group_id
      LEFT JOIN leases l ON l.apartment_id = a.id AND l.status = 'activo'
      LEFT JOIN tenants t ON t.id = l.tenant_id
      WHERE a.id = ?
      LIMIT 1
    ''',
      [id],
    );
    if (rows.isEmpty) return null;
    final statuses = _rentStatuses();
    return _mapApartment(rows.first, statuses[rows.first['lease_id'] as int?]);
  }

  /// Estado de la renta por contrato activo, derivado de pagos reales.
  ///
  /// Una sola consulta agregada + cálculo en memoria (sin prorrateos).
  Map<int, RentStatus> _rentStatuses({DateTime? today}) {
    final now = today ?? DateTime.now();
    final leases = _db.rows('''
      SELECT l.id, l.start_date, l.monthly_rent_cents, l.due_day
      FROM leases l
      WHERE l.status = 'activo'
    ''');
    if (leases.isEmpty) return const {};

    final aggregate = _db.rows('''
      SELECT pp.lease_id, pp.period_year, pp.period_month, pp.amount_due_cents,
             COALESCE(SUM(CASE WHEN p.voided_at IS NULL THEN p.amount_cents ELSE 0 END), 0) AS paid
      FROM payment_periods pp
      LEFT JOIN payments p ON p.period_id = pp.id
      GROUP BY pp.id
    ''');

    final paidByLease = <int, Map<int, int>>{};
    final dueByLease = <int, Map<int, int>>{};
    for (final row in aggregate) {
      final leaseId = row['lease_id'] as int;
      final key =
          (row['period_year'] as int) * 100 + (row['period_month'] as int);
      paidByLease.putIfAbsent(leaseId, () => {})[key] = row['paid'] as int;
      dueByLease.putIfAbsent(leaseId, () => {})[key] =
          row['amount_due_cents'] as int;
    }

    final result = <int, RentStatus>{};
    for (final lease in leases) {
      final leaseId = lease['id'] as int;
      result[leaseId] = RentLedger.statusFor(
        startDate: parseIsoDate(lease['start_date'] as String) ?? now,
        monthlyRentCents: lease['monthly_rent_cents'] as int,
        dueDay: lease['due_day'] as int,
        paidByMonth: paidByLease[leaseId] ?? const {},
        dueByMonth: dueByLease[leaseId] ?? const {},
        today: now,
      );
    }
    return result;
  }

  ApartmentRow _mapApartment(Map<String, Object?> row, RentStatus? rentStatus) {
    final leaseId = row['lease_id'] as int?;
    LeaseInfo? lease;
    TenantInfo? tenant;
    if (leaseId != null) {
      lease = LeaseInfo(
        id: leaseId,
        apartmentId: row['id'] as int,
        tenantId: row['lease_tenant_id'] as int,
        rentCents: row['monthly_rent_cents'] as int,
        dueDay: row['due_day'] as int,
        startDate: parseIsoDate(row['start_date'] as String)!,
        plannedEndDate: parseIsoDate(row['planned_end_date'] as String?),
        actualEndDate: parseIsoDate(row['actual_end_date'] as String?),
        isActive: true,
        endReason: (row['end_reason'] as String?) ?? '',
        depositRequiredCents: (row['deposit_required_cents'] as int?) ?? 0,
        notes: (row['lease_notes'] as String?) ?? '',
      );
      tenant = TenantInfo(
        id: row['tenant_id'] as int,
        fullName: row['full_name'] as String,
        cedula: (row['cedula'] as String?) ?? '',
        phone: (row['phone'] as String?) ?? '',
      );
    }

    return ApartmentRow(
      id: row['id'] as int,
      groupId: row['group_id'] as int,
      groupName: row['group_name'] as String,
      identifier: row['identifier'] as String,
      location: (row['location'] as String?) ?? '',
      rentCents: row['rent_cents'] as int,
      occupancy: OccupancyStatus.fromDb(row['status'] as String),
      isDemo: (row['is_demo'] as int) == 1,
      lease: lease,
      tenant: tenant,
      rentStatus: lease == null
          ? RentStatus.disponible
          : (rentStatus ?? RentStatus.pendiente),
    );
  }

  int createApartment({
    required int groupId,
    required String identifier,
    required String location,
    required int rentCents,
    bool isDemo = false,
  }) {
    final clean = identifier.trim();
    final error = validateApartmentIdentifier(clean);
    if (error != null) throw AppFailure(error);
    if (rentCents < 0) {
      throw const AppFailure('El alquiler no puede ser negativo.');
    }

    try {
      _db.run(
        'INSERT INTO apartments '
        '(group_id, identifier, location, rent_cents, status, is_demo, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          groupId,
          clean,
          location.trim(),
          rentCents,
          OccupancyStatus.disponible.dbValue,
          isDemo ? 1 : 0,
          _now,
          _now,
        ],
      );
      return _db.lastInsertId;
    } on SqliteException catch (error) {
      if (isUniqueViolation(error)) {
        throw AppFailure(
          'El apartamento "$clean" ya existe en este residencial.',
          cause: error,
        );
      }
      if (isForeignKeyViolation(error)) {
        throw AppFailure(
          'El residencial seleccionado ya no existe.',
          cause: error,
        );
      }
      throw AppFailure('No se pudo crear el apartamento.', cause: error);
    }
  }

  void updateApartment({
    required int id,
    required String identifier,
    required String location,
    required int rentCents,
    required OccupancyStatus occupancy,
  }) {
    final clean = identifier.trim();
    final error = validateApartmentIdentifier(clean);
    if (error != null) throw AppFailure(error);
    if (rentCents < 0) {
      throw const AppFailure('El alquiler no puede ser negativo.');
    }

    final hasActiveLease = _db.rows(
      "SELECT 1 FROM leases WHERE apartment_id = ? AND status = 'activo' LIMIT 1",
      [id],
    ).isNotEmpty;

    if (hasActiveLease && occupancy == OccupancyStatus.disponible) {
      throw const AppFailure(
        'Este apartamento tiene un contrato activo. Finalice el contrato '
        'antes de marcarlo como disponible.',
      );
    }

    try {
      _db.run(
        'UPDATE apartments SET identifier = ?, location = ?, rent_cents = ?, '
        'status = ?, updated_at = ? WHERE id = ?',
        [clean, location.trim(), rentCents, occupancy.dbValue, _now, id],
      );
    } on SqliteException catch (error) {
      if (isUniqueViolation(error)) {
        throw AppFailure(
          'El apartamento "$clean" ya existe en este residencial.',
          cause: error,
        );
      }
      throw AppFailure('No se pudo guardar el apartamento.', cause: error);
    }
  }

  // ------------------------------------------------- inquilinos y contratos

  /// Registra un inquilino y su contrato activo en una sola transacción.
  /// El índice único parcial impide dos contratos activos en el mismo
  /// apartamento y el contrato anterior nunca se borra.
  int registerTenantAndLease({
    required int apartmentId,
    required String fullName,
    required String cedula,
    required String phone,
    required DateTime moveInDate,
    DateTime? plannedMoveOut,
    required int rentCents,
    required int dueDay,
    bool isDemo = false,
    int depositRequiredCents = 0,
  }) {
    final nameError = validatePersonName(fullName);
    if (nameError != null) throw AppFailure(nameError);
    final cedulaError = validateCedula(cedula);
    if (cedulaError != null) throw AppFailure(cedulaError);
    final phoneError = validatePhone(phone);
    if (phoneError != null) throw AppFailure(phoneError);
    if (rentCents <= 0) {
      throw const AppFailure('El alquiler mensual debe ser mayor que cero.');
    }
    if (dueDay < 1 || dueDay > 31) {
      throw const AppFailure('El día de vencimiento debe estar entre 1 y 31.');
    }
    if (plannedMoveOut != null && plannedMoveOut.isBefore(moveInDate)) {
      throw const AppFailure(
        'La fecha de salida no puede ser anterior al ingreso.',
      );
    }
    if (depositRequiredCents < 0) {
      throw const AppFailure('El depósito no puede ser negativo.');
    }

    return _db.tx(() {
      final apartment = findApartment(apartmentId);
      if (apartment == null) {
        throw const AppFailure('El apartamento ya no existe.');
      }
      if (apartment.hasActiveLease) {
        throw AppFailure(
          'El apartamento ${apartment.identifier} ya tiene un contrato activo. '
          'Finalícelo antes de registrar otro inquilino.',
        );
      }

      _db.run(
        'INSERT INTO tenants (full_name, cedula, phone, notes, is_demo, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [
          fullName.trim(),
          cedula.replaceAll(RegExp(r'[^0-9]'), ''),
          phone.trim(),
          '',
          isDemo ? 1 : 0,
          _now,
        ],
      );
      final tenantId = _db.lastInsertId;

      try {
        _db.run(
          'INSERT INTO leases (apartment_id, tenant_id, monthly_rent_cents, due_day, '
          'start_date, planned_end_date, actual_end_date, status, end_reason, '
          'deposit_required_cents, created_at) '
          "VALUES (?, ?, ?, ?, ?, ?, NULL, 'activo', '', ?, ?)",
          [
            apartmentId,
            tenantId,
            rentCents,
            dueDay,
            toIsoDate(moveInDate),
            plannedMoveOut == null ? null : toIsoDate(plannedMoveOut),
            depositRequiredCents,
            _now,
          ],
        );
      } on SqliteException catch (error) {
        if (isUniqueViolation(error)) {
          throw AppFailure(
            'El apartamento ya tiene un contrato activo.',
            cause: error,
          );
        }
        rethrow;
      }
      final leaseId = _db.lastInsertId;

      _db.run(
        "UPDATE apartments SET status = 'ocupado', rent_cents = ?, updated_at = ? WHERE id = ?",
        [rentCents, _now, apartmentId],
      );

      return leaseId;
    });
  }

  /// Actualiza datos de contacto del inquilino (no toca el contrato).
  void updateTenant({
    required int tenantId,
    required String fullName,
    required String cedula,
    required String phone,
  }) {
    final nameError = validatePersonName(fullName);
    if (nameError != null) throw AppFailure(nameError);
    final cedulaError = validateCedula(cedula);
    if (cedulaError != null) throw AppFailure(cedulaError);
    final phoneError = validatePhone(phone);
    if (phoneError != null) throw AppFailure(phoneError);

    _db.run(
      'UPDATE tenants SET full_name = ?, cedula = ?, phone = ? WHERE id = ?',
      [
        fullName.trim(),
        cedula.replaceAll(RegExp(r'[^0-9]'), ''),
        phone.trim(),
        tenantId,
      ],
    );
  }

  /// Cambia condiciones del contrato activo (renta, día de pago, salida
  /// prevista, depósito pactado y notas).
  ///
  /// Los períodos ya materializados conservan su monto (`amount_due_cents`), de
  /// modo que un cambio de renta no altera meses anteriores ni recibos.
  void updateLeaseTerms({
    required int leaseId,
    required int monthlyRentCents,
    required int dueDay,
    DateTime? plannedEndDate,
    required int depositRequiredCents,
    String notes = '',
  }) {
    if (monthlyRentCents <= 0) {
      throw const AppFailure('El alquiler mensual debe ser mayor que cero.');
    }
    if (dueDay < 1 || dueDay > 31) {
      throw const AppFailure('El día de vencimiento debe estar entre 1 y 31.');
    }
    if (depositRequiredCents < 0) {
      throw const AppFailure('El depósito no puede ser negativo.');
    }

    _db.tx(() {
      final rows = _db.rows(
        'SELECT apartment_id, start_date, status FROM leases WHERE id = ? LIMIT 1',
        [leaseId],
      );
      if (rows.isEmpty) throw const AppFailure('El contrato ya no existe.');
      if ((rows.first['status'] as String) != 'activo') {
        throw const AppFailure('Solo se puede editar un contrato activo.');
      }
      final start = parseIsoDate(rows.first['start_date'] as String);
      if (start != null &&
          plannedEndDate != null &&
          plannedEndDate.isBefore(start)) {
        throw const AppFailure(
          'La fecha de salida no puede ser anterior al ingreso.',
        );
      }

      _db.run(
        'UPDATE leases SET monthly_rent_cents = ?, due_day = ?, '
        'planned_end_date = ?, deposit_required_cents = ?, notes = ? WHERE id = ?',
        [
          monthlyRentCents,
          dueDay,
          plannedEndDate == null ? null : toIsoDate(plannedEndDate),
          depositRequiredCents,
          notes.trim(),
          leaseId,
        ],
      );
      _db.run(
        'UPDATE apartments SET rent_cents = ?, updated_at = ? WHERE id = ?',
        [monthlyRentCents, _now, rows.first['apartment_id'] as int],
      );
    });
  }

  /// Finaliza un contrato conservando el historial (nunca se borra).
  void endLease({
    required int leaseId,
    required DateTime endDate,
    String reason = '',
  }) {
    _db.tx(() {
      final rows = _db.rows(
        'SELECT apartment_id, start_date, status FROM leases WHERE id = ? LIMIT 1',
        [leaseId],
      );
      if (rows.isEmpty) throw const AppFailure('El contrato ya no existe.');
      final row = rows.first;
      if ((row['status'] as String) != 'activo') {
        throw const AppFailure('Ese contrato ya estaba finalizado.');
      }
      final start = parseIsoDate(row['start_date'] as String);
      if (start != null && endDate.isBefore(start)) {
        throw const AppFailure(
          'La fecha de salida no puede ser anterior al ingreso.',
        );
      }

      _db.run(
        "UPDATE leases SET status = 'finalizado', actual_end_date = ?, "
        "end_reason = ? WHERE id = ?",
        [toIsoDate(endDate), reason.trim(), leaseId],
      );
      _db.run(
        "UPDATE apartments SET status = 'disponible', updated_at = ? WHERE id = ?",
        [_now, row['apartment_id'] as int],
      );
    });
  }

  List<LeaseHistoryRow> leaseHistory(int apartmentId) {
    return _db
        .rows(
          '''
          SELECT l.id, t.full_name, l.start_date, l.actual_end_date,
                 l.planned_end_date, l.monthly_rent_cents, l.status
          FROM leases l
          JOIN tenants t ON t.id = l.tenant_id
          WHERE l.apartment_id = ?
          ORDER BY l.start_date DESC, l.id DESC
        ''',
          [apartmentId],
        )
        .map(
          (row) => LeaseHistoryRow(
            leaseId: row['id'] as int,
            tenantName: row['full_name'] as String,
            startDate: parseIsoDate(row['start_date'] as String)!,
            endDate: parseIsoDate(row['actual_end_date'] as String?),
            plannedEndDate: parseIsoDate(row['planned_end_date'] as String?),
            rentCents: row['monthly_rent_cents'] as int,
            isActive: (row['status'] as String) == 'activo',
          ),
        )
        .toList(growable: false);
  }

  // -------------------------------------------------------------- auxiliares

  bool get hasGroups =>
      _db.rows('SELECT 1 FROM apartment_groups LIMIT 1').isNotEmpty;

  int countApartments() =>
      _db.rows('SELECT COUNT(*) AS c FROM apartments').first['c'] as int;

  bool get hasDemoData =>
      _db.rows('SELECT 1 FROM apartments WHERE is_demo = 1 LIMIT 1').isNotEmpty;

  /// Elimina únicamente los registros marcados como demostración.
  /// No toca datos reales (los pagos nunca se crean en la Fase 1).
  void purgeDemoData() {
    _db.tx(() {
      // Nunca se borran movimientos de dinero: si la demostración ya tiene
      // cobros o depósitos, se conserva todo y se avisa al usuario.
      final money =
          _db.rows('''
        SELECT
          (SELECT COUNT(*) FROM payments p
             WHERE p.lease_id IN (SELECT id FROM leases
                                   WHERE apartment_id IN (SELECT id FROM apartments WHERE is_demo = 1)))
        + (SELECT COUNT(*) FROM deposit_movements d
             WHERE d.lease_id IN (SELECT id FROM leases
                                   WHERE apartment_id IN (SELECT id FROM apartments WHERE is_demo = 1)))
        AS c
      ''').first['c']
              as int;
      if (money > 0) {
        throw const AppFailure(
          'Los datos de demostración ya tienen cobros o depósitos registrados. '
          'No se eliminan para no borrar movimientos de dinero.',
        );
      }

      _db.run(
        'DELETE FROM leases WHERE apartment_id IN '
        '(SELECT id FROM apartments WHERE is_demo = 1)',
      );
      _db.run('DELETE FROM apartments WHERE is_demo = 1');
      _db.run('DELETE FROM tenants WHERE is_demo = 1');
      _db.run(
        'DELETE FROM apartment_groups WHERE is_demo = 1 '
        'AND id NOT IN (SELECT group_id FROM apartments)',
      );
      _db.setMeta('demo_seed', 'removed');
    });
  }
}
