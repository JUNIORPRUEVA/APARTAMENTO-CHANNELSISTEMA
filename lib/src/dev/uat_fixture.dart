import 'dart:math';

import '../data/app_database.dart';
import '../data/finance_models.dart';
import '../data/finance_repository.dart';
import '../data/models.dart';
import '../data/portfolio_repository.dart';
import '../data/settings_repository.dart';

/// Datos de prueba end-to-end (UAT) aislados del sistema real.
///
/// Se usan **solo** sobre una base temporal (`%TEMP%` o memoria): nunca sobre
/// la base de la dueña. Genera un conjunto realista de ~70 apartamentos con
/// todos los estados financieros que el sistema debe soportar:
///
/// * apartamentos ocupados, disponibles y con contrato ya finalizado;
/// * inquilinos que se mudaron (dos contratos en el mismo apartamento);
/// * renta del mes al día, parcial, vencida y pagada por adelantado;
/// * un cobro anulado (nota de anulación) y su reverso;
/// * depósitos recibidos, uno devuelto y uno retenido;
/// * una transferencia con referencia y otra en efectivo.
///
/// Es determinista (semilla fija): la misma corrida produce los mismos datos,
/// de modo que una prueba puede afirmar cifras exactas.
class UatFixture {
  UatFixture(this.database, {this.today});

  final AppDatabase database;
  final DateTime? today;

  static const int targetApartments = 70;

  late final PortfolioRepository portfolio = PortfolioRepository(database);
  late final FinanceRepository finance = FinanceRepository(database);
  late final SettingsRepository settings = SettingsRepository(database);

  /// Siembra el escenario completo. Devuelve un resumen verificable.
  UatSummary seed() {
    final now = today ?? DateTime.now();
    final monthStart = DateTime(now.year, now.month);

    settings.save(
      const OwnerSettings(
        issuerName: 'Anamelia Rentas',
        issuerId: '131-00000-1',
        issuerAddress: 'Av. 27 de Febrero 123, Santo Domingo',
        issuerPhone: '809-555-0101',
        printerName: null,
        receiptPrefix: 'REC',
        receiptWidthMm: 80,
      ),
    );

    final random = Random(20260818);
    final groups = <String, int>{
      'Anamelia': 28,
      'Villa Cerro': 24,
      'Anamulla': 18,
    };

    var apartmentsCreated = 0;
    var occupied = 0;
    var available = 0;
    var leases = 0;
    var endedLeases = 0;
    var payments = 0;
    var voided = 0;
    var deposits = 0;
    final receipts = <int>[];
    final cedulas = <String>{};

    for (final entry in groups.entries) {
      final groupId = portfolio.createGroup(entry.key);
      for (var index = 1; index <= entry.value; index++) {
        final identifier = 'A-${index.toString().padLeft(2, '0')}';
        final rentCents = (8500 + random.nextInt(41) * 100) * 100;
        final apartmentId = portfolio.createApartment(
          groupId: groupId,
          identifier: identifier,
          location: '${entry.key} · bloque ${(index % 4) + 1}',
          rentCents: rentCents,
        );
        apartmentsCreated++;

        // 1 de cada 8 queda libre: el dueño debe poder cobrar, asignar y ver
        // apartamentos sin contrato.
        final isFree = index % 8 == 0;
        if (isFree) {
          available++;
          continue;
        }

        // Algunos apartamentos tuvieron un inquilino anterior que se mudó.
        final hadPreviousTenant = index % 11 == 0;
        if (hadPreviousTenant) {
          final previousLease = portfolio.registerTenantAndLease(
            apartmentId: apartmentId,
            fullName: 'Inquilino Anterior $identifier',
            cedula: _cedula(cedulas, 900000000 + apartmentsCreated),
            phone: '809-555-${(1000 + apartmentsCreated).toString()}',
            moveInDate: DateTime(now.year - 2, ((index % 12) + 1), 5),
            rentCents: rentCents - 50000,
            dueDay: 5,
            depositRequiredCents: rentCents,
          );
          portfolio.endLease(
            leaseId: previousLease,
            endDate: DateTime(now.year - 1, ((index % 12) + 1), 28),
            reason: 'Mudanza del inquilino',
          );
          endedLeases++;
          leases++;
        }

        final dueDay = 1 + (index % 10);
        // Ingreso reciente (0 a 2 meses atrás): así la cuenta mes a mes queda
        // con profundidad sin dejar a todos en mora por un año entero.
        final monthsBack = index % 3;
        final moveIn = DateTime(
          now.year,
          now.month - monthsBack,
          1 + index % 20,
        );
        final leaseId = portfolio.registerTenantAndLease(
          apartmentId: apartmentId,
          fullName: _tenantName(index),
          cedula: _cedula(cedulas, 100000000 + apartmentsCreated),
          phone: '809-555-${(2000 + apartmentsCreated).toString()}',
          moveInDate: moveIn,
          rentCents: rentCents,
          dueDay: dueDay,
          depositRequiredCents: rentCents,
        );
        leases++;
        occupied++;

        // Depósito: casi todos lo entregaron.
        if (index % 5 != 0) {
          finance.registerDeposit(
            requestId: 'uat-dep-$leaseId',
            leaseId: leaseId,
            kind: DepositKind.recibido,
            amountCents: rentCents,
            movementDate: moveIn,
            reason: 'Garantía al firmar el contrato',
          );
          deposits++;
        }

        // Estado de la renta del mes actual, con la historia coherente:
        // se cobran también los meses anteriores al actual.
        final bucket = index % 6;
        final periodYear = monthStart.year;
        final periodMonth = monthStart.month;
        final previousMonths = [
          for (var back = monthsBack; back >= 1; back--)
            DateTime(now.year, now.month - back),
        ];

        void payMonth(
          DateTime month, {
          required PaymentMethod method,
          required String tag,
          required int amount,
          String reference = '',
          String note = '',
          DateTime? date,
        }) {
          final outcome = finance.registerPayment(
            requestId: 'uat-pay-$leaseId-$tag-${month.year}-${month.month}',
            leaseId: leaseId,
            periodYear: month.year,
            periodMonth: month.month,
            amountCents: amount,
            paymentDate: date ?? dayInMonth(month.year, month.month, dueDay),
            method: method,
            reference: reference,
            note: note,
          );
          payments++;
          receipts.add(outcome.receiptId);
        }

        // Meses anteriores: se pagan en todos los casos menos el bucket 5
        // (inquilino en mora desde el ingreso).
        for (final month in previousMonths) {
          if (bucket == 5) break;
          payMonth(
            month,
            method: PaymentMethod.efectivo,
            tag: 'prev',
            amount: rentCents,
            note: 'Pago en efectivo',
          );
        }

        switch (bucket) {
          case 0: // al día, en efectivo
            payMonth(
              monthStart,
              method: PaymentMethod.efectivo,
              tag: 'full',
              amount: rentCents,
              note: 'Pago en efectivo',
            );
          case 1: // al día, por transferencia con referencia
            payMonth(
              monthStart,
              method: PaymentMethod.transferencia,
              tag: 'full',
              amount: rentCents,
              reference: 'TRF-${3000 + index}',
              note: 'Transferencia bancaria',
            );
          case 2: // pago parcial del mes (abono)
            payMonth(
              monthStart,
              method: PaymentMethod.efectivo,
              tag: 'partial',
              amount: (rentCents / 2).round(),
              note: 'Abono: queda saldo',
            );
          case 3: // pagó el mes siguiente por adelantado
            payMonth(
              monthStart,
              method: PaymentMethod.transferencia,
              tag: 'full',
              amount: rentCents,
              reference: 'TRF-${3000 + index}',
              note: 'Transferencia bancaria',
            );
            payMonth(
              DateTime(periodYear, periodMonth + 1),
              method: PaymentMethod.transferencia,
              tag: 'advance',
              amount: rentCents,
              reference: 'TRF-ADEL-${4000 + index}',
              note: 'Pago adelantado',
              date: monthStart,
            );
          case 4: // debiendo solo el mes actual
            break;
          default:
            // bucket 5: en mora desde el ingreso (no paga nada).
            break;
        }

        // Un cobro anulado con su nota de anulación (auditoría completa).
        // Solo tiene sentido si el período aún tenía saldo: si ya estaba
        // pagado por completo, el sistema (correctamente) lo rechaza.
        if (index % 13 == 0) {
          final periods = finance.periodsFor(
            leaseId,
            from: monthStart,
            to: monthStart,
          );
          final current = periods.where(
            (p) => p.year == periodYear && p.month == periodMonth,
          );
          final remaining = current.isEmpty ? 0 : current.first.remainingCents;
          if (remaining > 0) {
            final amount = remaining > 10000 ? 10000 : (remaining / 2).round();
            final wrong = finance.registerPayment(
              requestId: 'uat-pay-$leaseId-wrong',
              leaseId: leaseId,
              periodYear: periodYear,
              periodMonth: periodMonth,
              amountCents: amount.clamp(1, remaining),
              paymentDate: monthStart,
              method: PaymentMethod.efectivo,
              note: 'Cobro registrado por error',
            );
            finance.voidPayment(
              paymentId: wrong.paymentId,
              reason: 'Se registró en el apartamento equivocado',
            );
            payments++;
            voided++;
            receipts.add(wrong.receiptId);
          }
        }

        // Un depósito devuelto y uno retenido (sobre contratos finalizados).
        if (hadPreviousTenant) {
          final active = portfolio.findApartment(apartmentId);
          final activeLeaseId = active?.lease?.id;
          if (activeLeaseId != null) {
            if (index % 22 == 0) {
              finance.registerDeposit(
                requestId: 'uat-dep-return-$activeLeaseId',
                leaseId: activeLeaseId,
                kind: DepositKind.devuelto,
                amountCents: rentCents,
                movementDate: DateTime(now.year, now.month, 2),
                reason: 'Devolución de garantía',
              );
              deposits++;
            } else if (index % 22 == 11) {
              finance.registerDeposit(
                requestId: 'uat-dep-hold-$activeLeaseId',
                leaseId: activeLeaseId,
                kind: DepositKind.retenido,
                amountCents: rentCents,
                movementDate: DateTime(now.year, now.month, 3),
                reason: 'Daños en la pintura y limpieza',
              );
              deposits++;
            }
          }
        }
      }
    }

    // El PDF se genera fuera de la transacción; la prueba UAT lo comprueba
    // aparte con `ReceiptDocumentService`.
    return UatSummary(
      groups: groups.length,
      apartments: apartmentsCreated,
      occupied: occupied,
      available: available,
      leases: leases,
      endedLeases: endedLeases,
      payments: payments,
      voidedPayments: voided,
      deposits: deposits,
      receipts: receipts,
    );
  }

  static const List<String> _names = [
    'María Altagracia Peña',
    'José Ramón Castillo',
    'Yudelka Marte',
    'Pedro Antonio Reyes',
    'Ana Luisa Fernández',
    'Ramón Emilio Díaz',
    'Carmen Julia Santos',
    'Luis Manuel Beltré',
    'Rosa Elena Guzmán',
    'Francisco Alberto Núñez',
    'Ivelisse Contreras',
    'Juan Carlos Ramírez',
    'Solange Pérez',
    'Manuel de Jesús Herrera',
    'Wendy Rodríguez',
  ];

  static String _tenantName(int index) {
    final base = _names[index % _names.length];
    final rep = index ~/ _names.length;
    return rep == 0 ? base : '$base ($rep)';
  }

  /// Cédula sintética válida (11 dígitos, única). No corresponde a nadie real.
  static String _cedula(Set<String> used, int seed) {
    var value = 10000000000 + seed;
    while (used.contains(value.toString())) {
      value++;
    }
    used.add(value.toString());
    return value.toString();
  }
}

/// Resumen de lo sembrado, para afirmar cifras exactas en las pruebas.
class UatSummary {
  const UatSummary({
    required this.groups,
    required this.apartments,
    required this.occupied,
    required this.available,
    required this.leases,
    required this.endedLeases,
    required this.payments,
    required this.voidedPayments,
    required this.deposits,
    required this.receipts,
  });

  final int groups;
  final int apartments;
  final int occupied;
  final int available;
  final int leases;
  final int endedLeases;
  final int payments;
  final int voidedPayments;
  final int deposits;
  final List<int> receipts;

  @override
  String toString() =>
      'UAT: $groups residenciales, $apartments apartamentos '
      '($occupied ocupados / $available libres), $leases contratos '
      '($endedLeases finalizados), $payments cobros '
      '($voidedPayments anulados), $deposits movimientos de depósito, '
      '${receipts.length} recibos.';
}
