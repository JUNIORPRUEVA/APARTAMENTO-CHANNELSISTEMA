import '../core/formatters.dart';
import 'finance_models.dart';

export '../core/formatters.dart' show dayInMonth, nextDueDateFor;

/// Estado de ocupación de un apartamento.
enum OccupancyStatus {
  disponible('disponible', 'Disponible'),
  ocupado('ocupado', 'Ocupado');

  const OccupancyStatus(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static OccupancyStatus fromDb(String value) =>
      OccupancyStatus.values.firstWhere(
        (s) => s.dbValue == value,
        orElse: () => OccupancyStatus.disponible,
      );
}

class ApartmentGroup {
  const ApartmentGroup({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.isDemo,
  });

  final int id;
  final String name;
  final int sortOrder;
  final bool isDemo;
}

class TenantInfo {
  const TenantInfo({
    required this.id,
    required this.fullName,
    required this.cedula,
    required this.phone,
  });

  final int id;
  final String fullName;
  final String cedula;
  final String phone;

  String get cedulaDisplay => cedula.isEmpty ? '—' : formatCedula(cedula);
  String get phoneDisplay => phone.isEmpty ? '—' : phone;
}

class LeaseInfo {
  const LeaseInfo({
    required this.id,
    required this.apartmentId,
    required this.tenantId,
    required this.rentCents,
    required this.dueDay,
    required this.startDate,
    required this.plannedEndDate,
    required this.actualEndDate,
    required this.isActive,
    required this.endReason,
    this.depositRequiredCents = 0,
    this.notes = '',
  });

  final int id;
  final int apartmentId;
  final int tenantId;
  final int rentCents;
  final int dueDay;
  final DateTime startDate;
  final DateTime? plannedEndDate;
  final DateTime? actualEndDate;
  final bool isActive;
  final String endReason;
  final int depositRequiredCents;
  final String notes;
}

/// Fila de la tabla principal: apartamento + grupo + contrato activo + inquilino.
class ApartmentRow {
  const ApartmentRow({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.identifier,
    required this.location,
    required this.rentCents,
    required this.occupancy,
    required this.isDemo,
    this.lease,
    this.tenant,
    this.rentStatus = RentStatus.disponible,
  });

  final int id;
  final int groupId;
  final String groupName;
  final String identifier;
  final String location;
  final int rentCents;
  final OccupancyStatus occupancy;
  final bool isDemo;
  final LeaseInfo? lease;
  final TenantInfo? tenant;

  /// Estado de la renta derivado de contratos y pagos reales.
  final RentStatus rentStatus;

  String get displayName => 'Apartamento $identifier';
  String? get tenantName => tenant?.fullName;
  bool get hasActiveLease => lease != null;
  int get effectiveRentCents => lease?.rentCents ?? rentCents;

  /// Próxima fecha de pago según el día de vencimiento del contrato.
  DateTime? get nextDueDate {
    final active = lease;
    if (active == null) return null;
    return nextDueDateFor(DateTime.now(), active.dueDay);
  }

  /// Búsqueda tolerante: número de apartamento, residencial o inquilino.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return identifier.toLowerCase().contains(q) ||
        groupName.toLowerCase().contains(q) ||
        location.toLowerCase().contains(q) ||
        (tenant?.fullName.toLowerCase().contains(q) ?? false);
  }
}

class LeaseHistoryRow {
  const LeaseHistoryRow({
    required this.leaseId,
    required this.tenantName,
    required this.startDate,
    required this.endDate,
    required this.plannedEndDate,
    required this.rentCents,
    required this.isActive,
  });

  final int leaseId;
  final String tenantName;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime? plannedEndDate;
  final int rentCents;
  final bool isActive;
}

/// Cómo se entrega el recibo a la impresora.
///
/// * [windows]: la impresora está instalada en Windows y se envía el PDF a su
///   cola de impresión (una sola llamada al driver, sin diálogos).
/// * [serial]: la impresora Bluetooth está emparejada como puerto serie (SPP /
///   RFCOMM) y se envían comandos ESC/POS por ese puerto COM.
///
/// No se cubre Bluetooth LE (BLE): esas impresoras no exponen un puerto serie y
/// requieren GATT, que esta versión no implementa.
enum PrinterTransport {
  windows,
  serial;

  static PrinterTransport parse(String? raw) {
    return PrinterTransport.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => PrinterTransport.windows,
    );
  }

  String get label => switch (this) {
    PrinterTransport.windows => 'Cola de impresión de Windows',
    PrinterTransport.serial => 'Puerto serie (Bluetooth SPP)',
  };
}

class OwnerSettings {
  const OwnerSettings({
    required this.issuerName,
    required this.issuerId,
    required this.issuerAddress,
    required this.issuerPhone,
    required this.printerName,
    required this.receiptPrefix,
    this.receiptWidthMm = 80,
    this.receiptMarginMm = 3.5,
    this.asciiOnly = false,
    this.printerTransport = PrinterTransport.windows,
    this.printerTarget,
    this.backupExportDir = '',
  });

  const OwnerSettings.empty()
    : issuerName = '',
      issuerId = '',
      issuerAddress = '',
      issuerPhone = '',
      printerName = null,
      receiptPrefix = 'REC',
      receiptWidthMm = 80,
      receiptMarginMm = 3.5,
      asciiOnly = false,
      printerTransport = PrinterTransport.windows,
      printerTarget = null,
      backupExportDir = '';

  final String issuerName;
  final String issuerId;
  final String issuerAddress;
  final String issuerPhone;

  /// Nombre visible de la impresora elegida (etiqueta del desplegable).
  final String? printerName;

  /// Cómo se entrega el trabajo a la impresora.
  final PrinterTransport printerTransport;

  /// Destino real: nombre de la cola de Windows o nombre del puerto (`COM5`).
  final String? printerTarget;

  final String receiptPrefix;

  /// Ancho del papel térmico en milímetros (58 u 80).
  final int receiptWidthMm;

  /// Margen imprimible a cada lado, en milímetros.
  final double receiptMarginMm;

  /// Imprime sin acentos (para impresoras que no respetan la página CP850).
  final bool asciiOnly;

  /// Carpeta (por ejemplo una memoria USB) para exportar copias.
  final String backupExportDir;

  bool get isComplete => issuerName.trim().isNotEmpty;

  OwnerSettings copyWith({
    String? issuerName,
    String? issuerId,
    String? issuerAddress,
    String? issuerPhone,
    String? printerName,
    PrinterTransport? printerTransport,
    String? printerTarget,
    bool clearPrinter = false,
    String? receiptPrefix,
    int? receiptWidthMm,
    double? receiptMarginMm,
    bool? asciiOnly,
    String? backupExportDir,
  }) {
    return OwnerSettings(
      issuerName: issuerName ?? this.issuerName,
      issuerId: issuerId ?? this.issuerId,
      issuerAddress: issuerAddress ?? this.issuerAddress,
      issuerPhone: issuerPhone ?? this.issuerPhone,
      printerName: clearPrinter ? null : (printerName ?? this.printerName),
      printerTransport: printerTransport ?? this.printerTransport,
      printerTarget: clearPrinter
          ? null
          : (printerTarget ?? this.printerTarget),
      receiptPrefix: receiptPrefix ?? this.receiptPrefix,
      receiptWidthMm: receiptWidthMm ?? this.receiptWidthMm,
      receiptMarginMm: receiptMarginMm ?? this.receiptMarginMm,
      asciiOnly: asciiOnly ?? this.asciiOnly,
      backupExportDir: backupExportDir ?? this.backupExportDir,
    );
  }
}
