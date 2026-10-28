import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/app_failure.dart';
import '../core/formatters.dart';
import '../data/app_database.dart';
import '../data/app_paths.dart';
import '../data/demo_seed.dart';
import '../data/finance_models.dart';
import '../data/finance_repository.dart';
import '../data/models.dart';
import '../data/portfolio_repository.dart';
import '../data/settings_repository.dart';
import '../services/print_service.dart';
import '../services/printer_profile.dart';
import '../services/receipt_document_service.dart';

enum AppSection {
  inicio('Inicio'),
  apartamentos('Apartamentos'),
  cobros('Cobros');

  const AppSection(this.label);

  final String label;
}

/// Resultado de un cobro tal como lo necesita la interfaz para notificar.
class PaymentSubmission {
  const PaymentSubmission({
    this.outcome,
    this.error,
    this.receiptReady = false,
    this.printed = false,
    this.printMessage,
  });

  final PaymentOutcome? outcome;
  final String? error;
  final bool receiptReady;
  final bool printed;
  final String? printMessage;

  bool get ok => outcome != null;

  String get notice {
    if (error != null) return error!;
    if (printMessage != null) return printMessage!;
    if (printed) return 'Pago guardado y recibo enviado a la impresora.';
    if (!receiptReady) {
      return 'Pago guardado. El recibo se generará en el próximo arranque.';
    }
    return 'Pago guardado. Recibo ${outcome?.receiptLabel ?? ''} listo.';
  }
}

class DepositSubmission {
  const DepositSubmission({
    this.outcome,
    this.error,
    this.receiptReady = false,
    this.printed = false,
    this.printMessage,
  });

  final DepositOutcome? outcome;
  final String? error;
  final bool receiptReady;
  final bool printed;
  final String? printMessage;

  bool get ok => outcome != null;

  String get notice {
    if (error != null) return error!;
    if (printMessage != null) return printMessage!;
    if (printed) return 'Depósito guardado y recibo enviado a la impresora.';
    if (!receiptReady) return 'Depósito guardado. El recibo se generará luego.';
    return 'Depósito guardado.';
  }
}

/// Estado compartido de la aplicación (ChangeNotifier sin dependencias).
class AppController extends ChangeNotifier {
  AppController({
    required this.database,
    required this.portfolio,
    required this.settings,
    required this.paths,
    PrintGateway? printGateway,
    SerialPrintGateway? serialPrintGateway,
  }) {
    finance = FinanceRepository(database);
    documents = ReceiptDocumentService(
      finance: finance,
      paths: paths,
      currentWidthMm: () => owner.receiptWidthMm,
      currentMarginMm: () => owner.receiptMarginMm,
      currentProfile: () => owner.printerProfile,
    );
    printerService = ReceiptPrintService(
      documents: documents,
      gateway: printGateway ?? const WindowsPrintGateway(),
      serialGateway: serialPrintGateway,
    );
  }

  final AppDatabase database;
  final PortfolioRepository portfolio;
  final SettingsRepository settings;
  final AppPaths paths;

  late final FinanceRepository finance;
  late final ReceiptDocumentService documents;
  late final ReceiptPrintService printerService;

  OwnerSettings owner = const OwnerSettings.empty();
  List<ApartmentGroup> groups = const <ApartmentGroup>[];
  List<ApartmentRow> _all = const <ApartmentRow>[];

  int? selectedGroupId;
  String query = '';
  int? selectedApartmentId;
  AppSection section = AppSection.inicio;
  bool bootstrapped = false;
  bool demoSeededNow = false;

  /// Períodos del contrato activo (incluye meses futuros para pago adelantado).
  List<PaymentPeriod> periods = const <PaymentPeriod>[];
  PaymentPeriod? selectedPeriod;

  /// Historial de pagos del apartamento (todos sus contratos).
  List<PaymentRecord> payments = const <PaymentRecord>[];
  DepositSummary? deposit;
  int? depositLeaseId;
  bool submitting = false;

  /// Carga inicial: ajustes, datos de demostración y listados.
  void initialize() {
    owner = settings.load();
    final hadGroups = portfolio.hasGroups;
    DemoSeed(portfolio).maybeSeed();
    demoSeededNow = !hadGroups && portfolio.hasGroups;
    bootstrapped = true;
    reload();
  }

  void reload() {
    groups = portfolio.groups();
    _all = portfolio.listApartments();
    if (selectedGroupId != null &&
        !groups.any((g) => g.id == selectedGroupId)) {
      selectedGroupId = null;
    }
    _ensureSelection();
    _reloadFinance();
    notifyListeners();
  }

  List<ApartmentRow> get allApartments => List.unmodifiable(_all);

  List<ApartmentRow> get visibleApartments => _all
      .where(
        (a) =>
            (selectedGroupId == null || a.groupId == selectedGroupId) &&
            a.matches(query),
      )
      .toList(growable: false);

  List<ApartmentRow> get occupiedApartments =>
      _all.where((a) => a.hasActiveLease).toList(growable: false);

  ApartmentRow? get selectedApartment {
    final id = selectedApartmentId;
    if (id == null) return null;
    for (final apartment in _all) {
      if (apartment.id == id) return apartment;
    }
    return null;
  }

  bool get hasDemoData => portfolio.hasDemoData;

  void _ensureSelection() {
    final visible = visibleApartments;
    if (visible.isEmpty) {
      selectedApartmentId = null;
      return;
    }
    if (selectedApartmentId != null &&
        visible.any((a) => a.id == selectedApartmentId)) {
      return;
    }
    selectedApartmentId = visible.first.id;
  }

  void setSection(AppSection value) {
    if (section == value) return;
    section = value;
    notifyListeners();
  }

  void selectGroup(int? groupId) {
    if (selectedGroupId == groupId) return;
    selectedGroupId = groupId;
    _ensureSelection();
    _reloadFinance();
    notifyListeners();
  }

  void setQuery(String value) {
    if (query == value) return;
    query = value;
    _ensureSelection();
    _reloadFinance();
    notifyListeners();
  }

  void selectApartment(int? apartmentId) {
    if (selectedApartmentId == apartmentId) return;
    selectedApartmentId = apartmentId;
    _reloadFinance();
    notifyListeners();
  }

  // ------------------------------------------------------ estado financiero

  void _reloadFinance() {
    final apartment = selectedApartment;
    if (apartment == null) {
      periods = const [];
      selectedPeriod = null;
      payments = const [];
      deposit = null;
      depositLeaseId = null;
      return;
    }

    payments = finance.paymentsForApartment(apartment.id);

    final lease = apartment.lease;
    if (lease == null) {
      periods = const [];
      selectedPeriod = null;
      // Depósito del último contrato (para poder devolverlo tras la salida).
      final history = portfolio.leaseHistory(apartment.id);
      if (history.isNotEmpty) {
        depositLeaseId = history.first.leaseId;
        deposit = finance.depositSummary(history.first.leaseId);
      } else {
        depositLeaseId = null;
        deposit = null;
      }
      return;
    }

    final now = DateTime.now();
    periods = finance.periodsFor(
      lease.id,
      from: DateTime(lease.startDate.year, lease.startDate.month),
      to: DateTime(now.year, now.month + 3),
    );
    selectedPeriod = _resolveSelectedPeriod(periods);
    depositLeaseId = lease.id;
    deposit = finance.depositSummary(lease.id);
  }

  PaymentPeriod? _resolveSelectedPeriod(List<PaymentPeriod> list) {
    if (list.isEmpty) return null;
    final keep = selectedPeriod;
    if (keep != null) {
      for (final period in list) {
        if (period.year == keep.year && period.month == keep.month) {
          return period;
        }
      }
    }
    for (final period in list) {
      if (period.remainingCents > 0) return period;
    }
    return list.last;
  }

  void selectPeriod(PaymentPeriod period) {
    selectedPeriod = period;
    notifyListeners();
  }

  /// Mueve la selección de período (para el control ‹ Período ›).
  void shiftPeriod(int delta) {
    if (periods.isEmpty) return;
    final current = selectedPeriod;
    final index = current == null ? 0 : periods.indexOf(current);
    final next = (index + delta).clamp(0, periods.length - 1);
    selectedPeriod = periods[next];
    notifyListeners();
  }

  bool get hasPreviousPeriod {
    final current = selectedPeriod;
    if (current == null || periods.isEmpty) return false;
    return periods.indexOf(current) > 0;
  }

  bool get hasNextPeriod {
    final current = selectedPeriod;
    if (current == null || periods.isEmpty) return false;
    return periods.indexOf(current) < periods.length - 1;
  }

  List<LeaseHistoryRow> leaseHistoryFor(int apartmentId) =>
      portfolio.leaseHistory(apartmentId);

  /// Cobros por contrato, para el filtro del historial.
  List<({int leaseId, String label, int count})> get paymentLeaseFilters {
    final map = <int, ({String label, int count})>{};
    for (final payment in payments) {
      final existing = map[payment.leaseId];
      map[payment.leaseId] = (
        label: payment.tenantName,
        count: (existing?.count ?? 0) + 1,
      );
    }
    return [
      for (final entry in map.entries)
        (
          leaseId: entry.key,
          label: entry.value.label,
          count: entry.value.count,
        ),
    ];
  }

  // ------------------------------------------------------------ cobros

  /// Cobra el período seleccionado. La escritura es atómica e idempotente; el
  /// PDF y la impresión ocurren después y nunca revierten el cobro.
  Future<PaymentSubmission> submitPayment({
    required int amountCents,
    required DateTime paymentDate,
    required PaymentMethod method,
    String reference = '',
    String note = '',
    bool printAfterSave = false,
  }) async {
    final lease = selectedApartment?.lease;
    final period = selectedPeriod;
    if (lease == null || period == null) {
      return const PaymentSubmission(
        error: 'Seleccione un apartamento con contrato activo.',
      );
    }
    if (submitting) {
      return const PaymentSubmission(error: 'Ya hay una operación en curso.');
    }

    submitting = true;
    notifyListeners();
    try {
      final PaymentOutcome outcome;
      try {
        outcome = finance.registerPayment(
          requestId: FinanceRepository.newRequestId(),
          leaseId: lease.id,
          periodYear: period.year,
          periodMonth: period.month,
          amountCents: amountCents,
          paymentDate: paymentDate,
          method: method,
          reference: reference,
          note: note,
        );
      } on AppFailure catch (error) {
        return PaymentSubmission(error: error.message);
      } catch (error) {
        database.logEvent('error_pago', error.toString());
        return const PaymentSubmission(
          error: 'No se registró el pago. Intente de nuevo.',
        );
      }

      final receipt = finance.receipt(outcome.receiptId);
      var ready = false;
      var printed = false;
      String? printMessage;
      if (receipt != null) {
        final document = await documents.ensure(receipt);
        ready = document.ok;
        if (printAfterSave) {
          if (ready) {
            final result = await printerService.printReceipt(
              receipt,
              settings: owner,
            );
            printed = result.ok;
            if (!result.ok) printMessage = result.message;
          } else {
            printMessage =
                'Cobro guardado, pero el recibo no se pudo generar. '
                'Podrá imprimirlo después.';
          }
        }
      }

      reload();
      return PaymentSubmission(
        outcome: outcome,
        receiptReady: ready,
        printed: printed,
        printMessage: printMessage,
      );
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  /// Anula un cobro con motivo. Devuelve null si se anuló correctamente.
  Future<String?> voidPayment(int paymentId, String reason) async {
    try {
      final outcome = finance.voidPayment(paymentId: paymentId, reason: reason);
      final receipt = finance.receipt(outcome.receiptId);
      if (receipt != null) await documents.ensure(receipt);
      reload();
      return null;
    } on AppFailure catch (error) {
      return error.message;
    } catch (error) {
      database.logEvent('error_anulacion', error.toString());
      return 'No se pudo anular el pago.';
    }
  }

  // --------------------------------------------------------- depósitos

  Future<DepositSubmission> submitDeposit({
    required DepositKind kind,
    required int amountCents,
    required DateTime movementDate,
    String reason = '',
    bool printAfterSave = false,
  }) async {
    final leaseId = depositLeaseId ?? selectedApartment?.lease?.id;
    if (leaseId == null) {
      return const DepositSubmission(
        error: 'No hay contrato para registrar el depósito.',
      );
    }
    if (submitting) {
      return const DepositSubmission(error: 'Ya hay una operación en curso.');
    }

    submitting = true;
    notifyListeners();
    try {
      final DepositOutcome outcome;
      try {
        outcome = finance.registerDeposit(
          requestId: FinanceRepository.newRequestId(),
          leaseId: leaseId,
          kind: kind,
          amountCents: amountCents,
          movementDate: movementDate,
          reason: reason,
        );
      } on AppFailure catch (error) {
        return DepositSubmission(error: error.message);
      } catch (error) {
        database.logEvent('error_deposito', error.toString());
        return const DepositSubmission(
          error: 'No se registró el depósito. Intente de nuevo.',
        );
      }

      final receipt = finance.receipt(outcome.receiptId);
      var ready = false;
      var printed = false;
      String? printMessage;
      if (receipt != null) {
        final document = await documents.ensure(receipt);
        ready = document.ok;
        if (printAfterSave) {
          if (ready) {
            final result = await printerService.printReceipt(
              receipt,
              settings: owner,
            );
            printed = result.ok;
            if (!result.ok) printMessage = result.message;
          } else {
            printMessage = 'Depósito guardado, pero el recibo no se generó.';
          }
        }
      }

      reload();
      return DepositSubmission(
        outcome: outcome,
        receiptReady: ready,
        printed: printed,
        printMessage: printMessage,
      );
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  // --------------------------------------------------------- documentos

  Future<PrintResult> printReceipt(int receiptId) async {
    final record = finance.receipt(receiptId);
    if (record == null) {
      return const PrintResult(ok: false, message: 'El recibo ya no existe.');
    }
    final result = await printerService.printReceipt(record, settings: owner);
    reload();
    return result;
  }

  /// Lista combinada de impresoras (colas de Windows y puertos serie).
  Future<List<PrinterRef>> listPrinters() => printerService.printers();

  /// Busca la impresora configurada (mensaje en español para la dueña).
  Future<PrinterDetection> detectPrinter([OwnerSettings? value]) =>
      printerService.detect(value ?? owner);

  /// Ticket de calibración con la configuración indicada (sin guardarla).
  Future<PrintResult> printCalibration(OwnerSettings value) =>
      printerService.printCalibration(value);

  /// Genera (si hace falta) y abre el PDF con el visor de Windows.
  Future<String?> openReceipt(int receiptId) async {
    final record = finance.receipt(receiptId);
    if (record == null) return 'El recibo ya no existe.';
    final document = await documents.ensure(record);
    if (!document.ok || document.path == null) {
      return 'No se pudo preparar el recibo.';
    }
    try {
      await Process.start('explorer.exe', [
        document.path!,
      ], mode: ProcessStartMode.detached);
      return null;
    } catch (_) {
      return 'No se pudo abrir el archivo. Está en la carpeta de recibos.';
    }
  }

  /// Regenera PDF pendientes o perdidos al arrancar. Nunca vuelve a cobrar.
  Future<({int failures, int repaired})> recoverDocuments() async {
    final failures = await documents.recoverPending();
    final repaired = await documents.verifyExisting();
    return (failures: failures, repaired: repaired);
  }

  // ------------------------------------------------------------ escrituras

  String? addGroup(String name) => _guard(() {
    portfolio.createGroup(name);
    reload();
    return null;
  });

  String? renameGroup(int groupId, String name) => _guard(() {
    portfolio.renameGroup(groupId, name);
    reload();
    return null;
  });

  String? deleteGroup(int groupId) => _guard(() {
    portfolio.deleteGroup(groupId);
    if (selectedGroupId == groupId) selectedGroupId = null;
    reload();
    return null;
  });

  String? addApartment({
    required int groupId,
    required String identifier,
    required String location,
    required int rentCents,
  }) => _guard(() {
    final id = portfolio.createApartment(
      groupId: groupId,
      identifier: identifier,
      location: location,
      rentCents: rentCents,
    );
    selectedGroupId = groupId;
    reload();
    selectedApartmentId = id;
    _reloadFinance();
    notifyListeners();
    return null;
  });

  String? updateApartment({
    required int apartmentId,
    required String identifier,
    required String location,
    required int rentCents,
    required OccupancyStatus occupancy,
  }) => _guard(() {
    portfolio.updateApartment(
      id: apartmentId,
      identifier: identifier,
      location: location,
      rentCents: rentCents,
      occupancy: occupancy,
    );
    reload();
    return null;
  });

  String? registerTenant({
    required int apartmentId,
    required String fullName,
    required String cedula,
    required String phone,
    required DateTime moveInDate,
    DateTime? plannedMoveOut,
    required int rentCents,
    required int dueDay,
    int depositRequiredCents = 0,
  }) => _guard(() {
    portfolio.registerTenantAndLease(
      apartmentId: apartmentId,
      fullName: fullName,
      cedula: cedula,
      phone: phone,
      moveInDate: moveInDate,
      plannedMoveOut: plannedMoveOut,
      rentCents: rentCents,
      dueDay: dueDay,
      depositRequiredCents: depositRequiredCents,
    );
    selectedApartmentId = apartmentId;
    reload();
    return null;
  });

  String? endLease({
    required int leaseId,
    required DateTime endDate,
    String reason = '',
  }) => _guard(() {
    portfolio.endLease(leaseId: leaseId, endDate: endDate, reason: reason);
    reload();
    return null;
  });

  String? updateTenant({
    required int tenantId,
    required String fullName,
    required String cedula,
    required String phone,
  }) => _guard(() {
    portfolio.updateTenant(
      tenantId: tenantId,
      fullName: fullName,
      cedula: cedula,
      phone: phone,
    );
    reload();
    return null;
  });

  String? updateLeaseTerms({
    required int leaseId,
    required int monthlyRentCents,
    required int dueDay,
    required DateTime? plannedEndDate,
    required int depositRequiredCents,
    String notes = '',
  }) => _guard(() {
    portfolio.updateLeaseTerms(
      leaseId: leaseId,
      monthlyRentCents: monthlyRentCents,
      dueDay: dueDay,
      plannedEndDate: plannedEndDate,
      depositRequiredCents: depositRequiredCents,
      notes: notes,
    );
    reload();
    return null;
  });

  String? saveOwner(OwnerSettings value) => _guard(() {
    settings.save(value);
    owner = settings.load();
    notifyListeners();
    return null;
  });

  String? purgeDemoData() => _guard(() {
    portfolio.purgeDemoData();
    reload();
    return null;
  });

  /// Saldo pendiente del contrato activo (suma de períodos atrasados).
  ({int cents, int months}) outstandingForActiveLease() {
    var cents = 0;
    var months = 0;
    for (final period in periods) {
      if (period.remainingCents > 0) {
        cents += period.remainingCents;
        months++;
      }
    }
    return (cents: cents, months: months);
  }

  /// Saldo pendiente de cualquier contrato (usado al finalizar).
  ({int cents, int months}) outstandingForLease(int leaseId) {
    for (final row in _all) {
      final lease = row.lease;
      if (lease == null || lease.id != leaseId) continue;
      final now = DateTime.now();
      final list = finance.periodsFor(
        leaseId,
        from: DateTime(lease.startDate.year, lease.startDate.month),
        to: DateTime(now.year, now.month),
      );
      var cents = 0;
      var months = 0;
      for (final period in list) {
        if (period.remainingCents > 0) {
          cents += period.remainingCents;
          months++;
        }
      }
      return (cents: cents, months: months);
    }
    return (cents: 0, months: 0);
  }

  /// Depósito de un contrato concreto.
  DepositSummary depositForLease(int leaseId) =>
      finance.depositSummary(leaseId);

  String? _guard(String? Function() action) {
    try {
      return action();
    } on AppFailure catch (error) {
      if (error.cause != null) {
        database.logEvent(
          'error_negocio',
          '${error.message} :: ${error.cause}',
        );
      }
      return error.message;
    } catch (error) {
      database.logEvent('error_inesperado', error.toString());
      return 'No se pudo completar la operación. Intente de nuevo.';
    }
  }
}

/// Utilidad compartida por la interfaz de cobros.
String periodRangeLabel(PaymentPeriod period) =>
    '${formatPeriodTitle(period.year, period.month)} · vence '
    '${formatDate(period.dueDate)}';
