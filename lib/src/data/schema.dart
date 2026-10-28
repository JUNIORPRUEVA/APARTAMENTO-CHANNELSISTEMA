/// Esquema SQLite.
///
/// Decisiones relevantes:
/// * Los montos se guardan en **centavos enteros** (nunca `double`).
/// * Las fechas se guardan como texto ISO `AAAA-MM-DD`; los instantes como
///   ISO-8601 completo.
/// * `ux_leases_one_active` es un índice único **parcial**: garantiza un solo
///   contrato activo por apartamento sin impedir el historial de contratos
///   anteriores (no se sobrescribe nada).
/// * `ux_apartments_group_identifier` impide números repetidos dentro de un
///   mismo residencial, pero permite el mismo número en residenciales distintos.
/// * `payments.request_id` es único: base de la idempotencia de un cobro.
/// * `receipts` guarda un **snapshot JSON inmutable** de lo impreso, además de
///   la ruta del PDF: la base y el sistema de archivos son dominios de fallo
///   distintos y el documento debe poder regenerarse sin volver a cobrar.
/// * `payment_reversals` es el registro de auditoría de una anulación; nunca se
///   borra ni se edita un pago.
library;

const int kSchemaVersion = 3;

/// Esquema completo para una base nueva (versión actual).
const List<String> kSchemaStatements = <String>[
  '''
  CREATE TABLE app_meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE owner_settings (
    id                INTEGER PRIMARY KEY CHECK (id = 1),
    issuer_name       TEXT NOT NULL DEFAULT '',
    issuer_id         TEXT NOT NULL DEFAULT '',
    issuer_address    TEXT NOT NULL DEFAULT '',
    issuer_phone      TEXT NOT NULL DEFAULT '',
    printer_name      TEXT,
    printer_transport TEXT NOT NULL DEFAULT 'windows',
    printer_target    TEXT,
    receipt_prefix    TEXT NOT NULL DEFAULT 'REC',
    receipt_width_mm  INTEGER NOT NULL DEFAULT 80,
    receipt_margin_mm REAL NOT NULL DEFAULT 3.5,
    ascii_only        INTEGER NOT NULL DEFAULT 0 CHECK (ascii_only IN (0, 1)),
    backup_export_dir TEXT,
    updated_at        TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE apartment_groups (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT NOT NULL COLLATE NOCASE,
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_demo    INTEGER NOT NULL DEFAULT 0 CHECK (is_demo IN (0, 1)),
    created_at TEXT NOT NULL
  )
  ''',
  'CREATE UNIQUE INDEX ux_groups_name ON apartment_groups (name COLLATE NOCASE)',
  '''
  CREATE TABLE apartments (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    group_id   INTEGER NOT NULL REFERENCES apartment_groups (id) ON DELETE RESTRICT,
    identifier TEXT NOT NULL,
    location   TEXT NOT NULL DEFAULT '',
    rent_cents INTEGER NOT NULL DEFAULT 0 CHECK (rent_cents >= 0),
    status     TEXT NOT NULL DEFAULT 'disponible'
               CHECK (status IN ('disponible', 'ocupado')),
    is_demo    INTEGER NOT NULL DEFAULT 0 CHECK (is_demo IN (0, 1)),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE UNIQUE INDEX ux_apartments_group_identifier
    ON apartments (group_id, identifier COLLATE NOCASE)
  ''',
  'CREATE INDEX ix_apartments_group ON apartments (group_id)',
  '''
  CREATE TABLE tenants (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    full_name  TEXT NOT NULL,
    cedula     TEXT NOT NULL DEFAULT '',
    phone      TEXT NOT NULL DEFAULT '',
    notes      TEXT NOT NULL DEFAULT '',
    is_demo    INTEGER NOT NULL DEFAULT 0 CHECK (is_demo IN (0, 1)),
    created_at TEXT NOT NULL
  )
  ''',
  'CREATE INDEX ix_tenants_name ON tenants (full_name COLLATE NOCASE)',
  '''
  CREATE TABLE leases (
    id                     INTEGER PRIMARY KEY AUTOINCREMENT,
    apartment_id           INTEGER NOT NULL REFERENCES apartments (id) ON DELETE RESTRICT,
    tenant_id              INTEGER NOT NULL REFERENCES tenants (id) ON DELETE RESTRICT,
    monthly_rent_cents     INTEGER NOT NULL CHECK (monthly_rent_cents >= 0),
    due_day                INTEGER NOT NULL CHECK (due_day BETWEEN 1 AND 31),
    start_date             TEXT NOT NULL,
    planned_end_date       TEXT,
    actual_end_date        TEXT,
    status                 TEXT NOT NULL CHECK (status IN ('activo', 'finalizado')),
    end_reason             TEXT NOT NULL DEFAULT '',
    deposit_required_cents INTEGER NOT NULL DEFAULT 0 CHECK (deposit_required_cents >= 0),
    notes                  TEXT NOT NULL DEFAULT '',
    created_at             TEXT NOT NULL
  )
  ''',
  '''
  CREATE UNIQUE INDEX ux_leases_one_active
    ON leases (apartment_id) WHERE status = 'activo'
  ''',
  'CREATE INDEX ix_leases_apartment ON leases (apartment_id)',
  'CREATE INDEX ix_leases_tenant ON leases (tenant_id)',
  '''
  CREATE TABLE payment_periods (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    lease_id         INTEGER NOT NULL REFERENCES leases (id) ON DELETE CASCADE,
    period_year      INTEGER NOT NULL,
    period_month     INTEGER NOT NULL CHECK (period_month BETWEEN 1 AND 12),
    due_date         TEXT NOT NULL DEFAULT '',
    amount_due_cents INTEGER NOT NULL DEFAULT 0 CHECK (amount_due_cents >= 0)
  )
  ''',
  '''
  CREATE UNIQUE INDEX ux_payment_periods_unique
    ON payment_periods (lease_id, period_year, period_month)
  ''',
  '''
  CREATE TABLE payments (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    request_id          TEXT NOT NULL,
    lease_id            INTEGER NOT NULL REFERENCES leases (id) ON DELETE RESTRICT,
    period_id           INTEGER REFERENCES payment_periods (id) ON DELETE RESTRICT,
    concept             TEXT NOT NULL,
    payment_date        TEXT NOT NULL,
    method              TEXT NOT NULL CHECK (method IN ('efectivo', 'transferencia')),
    amount_cents        INTEGER NOT NULL CHECK (amount_cents > 0),
    balance_after_cents INTEGER NOT NULL DEFAULT 0,
    reference           TEXT NOT NULL DEFAULT '',
    note                TEXT NOT NULL DEFAULT '',
    voided_at           TEXT,
    void_reason         TEXT,
    created_at          TEXT NOT NULL
  )
  ''',
  'CREATE UNIQUE INDEX ux_payments_request ON payments (request_id)',
  'CREATE INDEX ix_payments_lease ON payments (lease_id)',
  'CREATE INDEX ix_payments_period ON payments (period_id)',
  'CREATE INDEX ix_payments_date ON payments (payment_date)',
  '''
  CREATE TABLE payment_reversals (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    payment_id  INTEGER NOT NULL UNIQUE REFERENCES payments (id) ON DELETE RESTRICT,
    request_id  TEXT NOT NULL UNIQUE,
    reason      TEXT NOT NULL,
    created_at  TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE deposit_movements (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    lease_id      INTEGER NOT NULL REFERENCES leases (id) ON DELETE RESTRICT,
    request_id    TEXT NOT NULL,
    kind          TEXT NOT NULL CHECK (kind IN ('recibido', 'devuelto', 'retenido')),
    amount_cents  INTEGER NOT NULL CHECK (amount_cents > 0),
    movement_date TEXT NOT NULL,
    reason        TEXT NOT NULL DEFAULT '',
    created_at    TEXT NOT NULL
  )
  ''',
  'CREATE UNIQUE INDEX ux_deposits_request ON deposit_movements (request_id)',
  'CREATE INDEX ix_deposits_lease ON deposit_movements (lease_id)',
  '''
  CREATE TABLE receipts (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    series        TEXT NOT NULL DEFAULT 'REC',
    number        INTEGER NOT NULL,
    kind          TEXT NOT NULL DEFAULT 'alquiler'
                  CHECK (kind IN ('alquiler', 'deposito', 'anulacion')),
    payment_id    INTEGER REFERENCES payments (id) ON DELETE RESTRICT,
    deposit_id    INTEGER REFERENCES deposit_movements (id) ON DELETE RESTRICT,
    issued_at     TEXT NOT NULL,
    total_cents   INTEGER NOT NULL CHECK (total_cents >= 0),
    snapshot_json TEXT NOT NULL,
    pdf_path      TEXT,
    pdf_status    TEXT NOT NULL DEFAULT 'pendiente'
                  CHECK (pdf_status IN ('pendiente', 'generado', 'fallido', 'faltante')),
    attempts      INTEGER NOT NULL DEFAULT 0,
    last_error    TEXT,
    CHECK (kind = 'anulacion' OR payment_id IS NOT NULL OR deposit_id IS NOT NULL)
  )
  ''',
  '''
  CREATE UNIQUE INDEX ux_receipts_series_number
    ON receipts (series, number)
  ''',
  '''
  CREATE UNIQUE INDEX ux_receipts_payment
    ON receipts (payment_id) WHERE payment_id IS NOT NULL
  ''',
  '''
  CREATE UNIQUE INDEX ux_receipts_deposit
    ON receipts (deposit_id) WHERE deposit_id IS NOT NULL
  ''',
  'CREATE INDEX ix_receipts_pdf_status ON receipts (pdf_status)',
  '''
  CREATE TABLE app_events (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    kind       TEXT NOT NULL,
    detail     TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL
  )
  ''',
  'CREATE INDEX ix_app_events_kind ON app_events (kind)',
];

/// Esquema tal como lo dejó la Fase 1. Se conserva para poder probar la
/// migración 1 → 2 sobre una base poblada real.
const List<String> kSchemaV1Statements = <String>[
  '''
  CREATE TABLE app_meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE owner_settings (
    id           INTEGER PRIMARY KEY CHECK (id = 1),
    issuer_name  TEXT NOT NULL DEFAULT '',
    issuer_id    TEXT NOT NULL DEFAULT '',
    issuer_address TEXT NOT NULL DEFAULT '',
    issuer_phone TEXT NOT NULL DEFAULT '',
    printer_name TEXT,
    receipt_prefix TEXT NOT NULL DEFAULT 'REC',
    updated_at   TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE apartment_groups (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT NOT NULL COLLATE NOCASE,
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_demo    INTEGER NOT NULL DEFAULT 0 CHECK (is_demo IN (0, 1)),
    created_at TEXT NOT NULL
  )
  ''',
  'CREATE UNIQUE INDEX ux_groups_name ON apartment_groups (name COLLATE NOCASE)',
  '''
  CREATE TABLE apartments (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    group_id   INTEGER NOT NULL REFERENCES apartment_groups (id) ON DELETE RESTRICT,
    identifier TEXT NOT NULL,
    location   TEXT NOT NULL DEFAULT '',
    rent_cents INTEGER NOT NULL DEFAULT 0 CHECK (rent_cents >= 0),
    status     TEXT NOT NULL DEFAULT 'disponible'
               CHECK (status IN ('disponible', 'ocupado')),
    is_demo    INTEGER NOT NULL DEFAULT 0 CHECK (is_demo IN (0, 1)),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE UNIQUE INDEX ux_apartments_group_identifier
    ON apartments (group_id, identifier COLLATE NOCASE)
  ''',
  'CREATE INDEX ix_apartments_group ON apartments (group_id)',
  '''
  CREATE TABLE tenants (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    full_name  TEXT NOT NULL,
    cedula     TEXT NOT NULL DEFAULT '',
    phone      TEXT NOT NULL DEFAULT '',
    notes      TEXT NOT NULL DEFAULT '',
    is_demo    INTEGER NOT NULL DEFAULT 0 CHECK (is_demo IN (0, 1)),
    created_at TEXT NOT NULL
  )
  ''',
  'CREATE INDEX ix_tenants_name ON tenants (full_name COLLATE NOCASE)',
  '''
  CREATE TABLE leases (
    id                 INTEGER PRIMARY KEY AUTOINCREMENT,
    apartment_id       INTEGER NOT NULL REFERENCES apartments (id) ON DELETE RESTRICT,
    tenant_id          INTEGER NOT NULL REFERENCES tenants (id) ON DELETE RESTRICT,
    monthly_rent_cents INTEGER NOT NULL CHECK (monthly_rent_cents >= 0),
    due_day            INTEGER NOT NULL CHECK (due_day BETWEEN 1 AND 31),
    start_date         TEXT NOT NULL,
    planned_end_date   TEXT,
    actual_end_date    TEXT,
    status             TEXT NOT NULL CHECK (status IN ('activo', 'finalizado')),
    end_reason         TEXT NOT NULL DEFAULT '',
    created_at         TEXT NOT NULL
  )
  ''',
  '''
  CREATE UNIQUE INDEX ux_leases_one_active
    ON leases (apartment_id) WHERE status = 'activo'
  ''',
  'CREATE INDEX ix_leases_apartment ON leases (apartment_id)',
  'CREATE INDEX ix_leases_tenant ON leases (tenant_id)',
  '''
  CREATE TABLE payment_periods (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    lease_id         INTEGER NOT NULL REFERENCES leases (id) ON DELETE CASCADE,
    period_year      INTEGER NOT NULL,
    period_month     INTEGER NOT NULL CHECK (period_month BETWEEN 1 AND 12),
    amount_due_cents INTEGER NOT NULL DEFAULT 0 CHECK (amount_due_cents >= 0)
  )
  ''',
  '''
  CREATE UNIQUE INDEX ux_payment_periods_unique
    ON payment_periods (lease_id, period_year, period_month)
  ''',
  '''
  CREATE TABLE payments (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    request_id   TEXT NOT NULL,
    lease_id     INTEGER NOT NULL REFERENCES leases (id) ON DELETE RESTRICT,
    period_id    INTEGER REFERENCES payment_periods (id) ON DELETE RESTRICT,
    concept      TEXT NOT NULL,
    payment_date TEXT NOT NULL,
    method       TEXT NOT NULL CHECK (method IN ('efectivo', 'transferencia')),
    amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
    note         TEXT NOT NULL DEFAULT '',
    voided_at    TEXT,
    void_reason  TEXT,
    created_at   TEXT NOT NULL
  )
  ''',
  'CREATE UNIQUE INDEX ux_payments_request ON payments (request_id)',
  'CREATE INDEX ix_payments_lease ON payments (lease_id)',
  'CREATE INDEX ix_payments_date ON payments (payment_date)',
  '''
  CREATE TABLE receipts (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    series      TEXT NOT NULL DEFAULT 'REC',
    number      INTEGER NOT NULL,
    payment_id  INTEGER NOT NULL UNIQUE REFERENCES payments (id) ON DELETE RESTRICT,
    issued_at   TEXT NOT NULL,
    total_cents INTEGER NOT NULL CHECK (total_cents >= 0),
    pdf_path    TEXT,
    pdf_status  TEXT NOT NULL DEFAULT 'pendiente'
                CHECK (pdf_status IN ('pendiente', 'generado', 'fallido', 'faltante')),
    attempts    INTEGER NOT NULL DEFAULT 0,
    last_error  TEXT
  )
  ''',
  '''
  CREATE UNIQUE INDEX ux_receipts_series_number
    ON receipts (series, number)
  ''',
  'CREATE INDEX ix_receipts_pdf_status ON receipts (pdf_status)',
  '''
  CREATE TABLE deposit_movements (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    lease_id      INTEGER NOT NULL REFERENCES leases (id) ON DELETE RESTRICT,
    request_id    TEXT NOT NULL,
    kind          TEXT NOT NULL CHECK (kind IN ('recibido', 'devuelto', 'retenido')),
    amount_cents  INTEGER NOT NULL CHECK (amount_cents > 0),
    movement_date TEXT NOT NULL,
    reason        TEXT NOT NULL DEFAULT '',
    created_at    TEXT NOT NULL
  )
  ''',
  'CREATE UNIQUE INDEX ux_deposits_request ON deposit_movements (request_id)',
  'CREATE INDEX ix_deposits_lease ON deposit_movements (lease_id)',
  '''
  CREATE TABLE app_events (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    kind       TEXT NOT NULL,
    detail     TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL
  )
  ''',
  'CREATE INDEX ix_app_events_kind ON app_events (kind)',
];

/// Pasos de la migración 1 → 2. Se ejecutan en una sola transacción.
///
/// `receipts` se reconstruye porque `payment_id` ya no puede ser obligatorio
/// (también hay recibos de depósito y notas de anulación) y porque se añade el
/// snapshot inmutable del documento.
const List<String> kMigrationV2Statements = <String>[
  'ALTER TABLE leases ADD COLUMN deposit_required_cents INTEGER NOT NULL DEFAULT 0',
  "ALTER TABLE leases ADD COLUMN notes TEXT NOT NULL DEFAULT ''",
  "ALTER TABLE payment_periods ADD COLUMN due_date TEXT NOT NULL DEFAULT ''",
  'ALTER TABLE payments ADD COLUMN balance_after_cents INTEGER NOT NULL DEFAULT 0',
  '''
  CREATE TABLE payment_reversals (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    payment_id  INTEGER NOT NULL UNIQUE REFERENCES payments (id) ON DELETE RESTRICT,
    request_id  TEXT NOT NULL UNIQUE,
    reason      TEXT NOT NULL,
    created_at  TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE receipts_v2 (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    series        TEXT NOT NULL DEFAULT 'REC',
    number        INTEGER NOT NULL,
    kind          TEXT NOT NULL DEFAULT 'alquiler'
                  CHECK (kind IN ('alquiler', 'deposito', 'anulacion')),
    payment_id    INTEGER REFERENCES payments (id) ON DELETE RESTRICT,
    deposit_id    INTEGER REFERENCES deposit_movements (id) ON DELETE RESTRICT,
    issued_at     TEXT NOT NULL,
    total_cents   INTEGER NOT NULL CHECK (total_cents >= 0),
    snapshot_json TEXT NOT NULL,
    pdf_path      TEXT,
    pdf_status    TEXT NOT NULL DEFAULT 'pendiente'
                  CHECK (pdf_status IN ('pendiente', 'generado', 'fallido', 'faltante')),
    attempts      INTEGER NOT NULL DEFAULT 0,
    last_error    TEXT,
    CHECK (kind = 'anulacion' OR payment_id IS NOT NULL OR deposit_id IS NOT NULL)
  )
  ''',
  '''
  INSERT INTO receipts_v2
    (id, series, number, kind, payment_id, deposit_id, issued_at, total_cents,
     snapshot_json, pdf_path, pdf_status, attempts, last_error)
  SELECT id, series, number, 'alquiler', payment_id, NULL, issued_at,
         total_cents, '{}', pdf_path, pdf_status, attempts, last_error
  FROM receipts
  ''',
  'DROP TABLE receipts',
  'ALTER TABLE receipts_v2 RENAME TO receipts',
  '''
  CREATE UNIQUE INDEX ux_receipts_series_number
    ON receipts (series, number)
  ''',
  '''
  CREATE UNIQUE INDEX ux_receipts_payment
    ON receipts (payment_id) WHERE payment_id IS NOT NULL
  ''',
  '''
  CREATE UNIQUE INDEX ux_receipts_deposit
    ON receipts (deposit_id) WHERE deposit_id IS NOT NULL
  ''',
  'CREATE INDEX ix_receipts_pdf_status ON receipts (pdf_status)',
  'CREATE INDEX ix_payments_period ON payments (period_id)',
  'ALTER TABLE owner_settings ADD COLUMN receipt_width_mm INTEGER NOT NULL DEFAULT 80',
  'ALTER TABLE owner_settings ADD COLUMN backup_export_dir TEXT',
];

/// Pasos de la migración 2 → 3.
///
/// * `payments.reference`: referencia opcional de la operación (número de
///   transferencia, comprobante, etc.). No se valida ni se deduce: si el dueño
///   no la escribe queda vacía.
/// * `owner_settings.printer_transport` / `printer_target`: cómo se entrega el
///   recibo a la impresora. `windows` = cola del sistema; `serial` = puerto COM
///   (impresora Bluetooth emparejada como puerto serie) con ESC/POS.
/// * `owner_settings.receipt_margin_mm`: margen imprimible configurable; el
///   ancho del papel sigue fijo en 80 mm por defecto.
const List<String> kMigrationV3Statements = <String>[
  "ALTER TABLE payments ADD COLUMN reference TEXT NOT NULL DEFAULT ''",
  "ALTER TABLE owner_settings ADD COLUMN printer_transport TEXT NOT NULL DEFAULT 'windows'",
  'ALTER TABLE owner_settings ADD COLUMN printer_target TEXT',
  'ALTER TABLE owner_settings ADD COLUMN receipt_margin_mm REAL NOT NULL DEFAULT 3.5',
  'ALTER TABLE owner_settings ADD COLUMN ascii_only INTEGER NOT NULL DEFAULT 0',
];
