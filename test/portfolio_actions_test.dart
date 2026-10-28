import 'dart:io';

import 'package:control_alquileres/src/core/app_failure.dart';
import 'package:control_alquileres/src/data/app_database.dart';
import 'package:control_alquileres/src/data/app_paths.dart';
import 'package:control_alquileres/src/data/data_location.dart';
import 'package:control_alquileres/src/data/finance_models.dart';
import 'package:control_alquileres/src/data/finance_repository.dart';
import 'package:control_alquileres/src/data/models.dart';
import 'package:control_alquileres/src/data/portfolio_repository.dart';
import 'package:control_alquileres/src/data/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Acciones de mantenimiento que la dueña usa a diario: residenciales,
/// apartamentos, inquilinos y condiciones del contrato.
void main() {
  late Directory temp;
  late AppPaths paths;
  late AppDatabase db;
  late PortfolioRepository portfolio;
  late FinanceRepository finance;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('acciones_');
    paths = requireSandboxPaths(temp.path, tool: 'portfolio_actions_test');
    db = AppDatabase.openAt(paths.databaseFile);
    portfolio = PortfolioRepository(db);
    finance = FinanceRepository(db);
    SettingsRepository(db).save(
      const OwnerSettings(
        issuerName: 'Anamelia Rentas',
        issuerId: '',
        issuerAddress: '',
        issuerPhone: '',
        printerName: null,
        receiptPrefix: 'REC',
      ),
    );
  });

  tearDown(() {
    db.close();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('Residenciales', () {
    test('crear, renombrar y rechazar nombres repetidos', () {
      final id = portfolio.createGroup('Anamelia');
      expect(portfolio.groups().single.name, 'Anamelia');

      portfolio.renameGroup(id, 'Anamelia II');
      expect(portfolio.groups().single.name, 'Anamelia II');

      portfolio.createGroup('Villa Cerro');
      expect(portfolio.groups().length, 2);
      // Sin distinguir mayúsculas.
      expect(
        () => portfolio.createGroup('villa cerro'),
        throwsA(isA<AppFailure>()),
      );
      expect(
        () => portfolio.renameGroup(id, 'VILLA CERRO'),
        throwsA(isA<AppFailure>()),
      );
    });

    test('no se puede borrar un residencial con apartamentos', () {
      final id = portfolio.createGroup('Anamelia');
      portfolio.createApartment(
        groupId: id,
        identifier: 'A-01',
        location: '',
        rentCents: 850000,
      );
      expect(() => portfolio.deleteGroup(id), throwsA(isA<AppFailure>()));
      expect(portfolio.groups().length, 1);
    });

    test('un residencial vacío sí se puede borrar', () {
      final id = portfolio.createGroup('Temporal');
      portfolio.deleteGroup(id);
      expect(portfolio.groups(), isEmpty);
    });
  });

  group('Apartamentos', () {
    test('el número no se repite dentro del residencial, sí entre otros', () {
      final a = portfolio.createGroup('Anamelia');
      final b = portfolio.createGroup('Villa Cerro');
      portfolio.createApartment(
        groupId: a,
        identifier: 'A-01',
        location: '',
        rentCents: 850000,
      );
      expect(
        () => portfolio.createApartment(
          groupId: a,
          identifier: 'a-01',
          location: '',
          rentCents: 850000,
        ),
        throwsA(isA<AppFailure>()),
      );
      // En otro residencial el mismo número es válido.
      portfolio.createApartment(
        groupId: b,
        identifier: 'A-01',
        location: '',
        rentCents: 900000,
      );
      expect(portfolio.countApartments(), 2);
    });

    test('editar apartamento no toca contratos y evita estados imposibles', () {
      final groupId = portfolio.createGroup('Anamelia');
      final apartmentId = portfolio.createApartment(
        groupId: groupId,
        identifier: 'A-01',
        location: 'Planta baja',
        rentCents: 850000,
      );
      portfolio.updateApartment(
        id: apartmentId,
        identifier: 'A-02',
        location: 'Planta alta',
        rentCents: 900000,
        occupancy: OccupancyStatus.disponible,
      );
      final updated = portfolio.findApartment(apartmentId)!;
      expect(updated.identifier, 'A-02');
      expect(updated.rentCents, 900000);

      portfolio.registerTenantAndLease(
        apartmentId: apartmentId,
        fullName: 'María Peña',
        cedula: '00112345678',
        phone: '8095550123',
        moveInDate: DateTime(2026, 9, 1),
        rentCents: 900000,
        dueDay: 5,
      );
      // Con contrato activo no se puede marcar "disponible".
      expect(
        () => portfolio.updateApartment(
          id: apartmentId,
          identifier: 'A-02',
          location: 'Planta alta',
          rentCents: 900000,
          occupancy: OccupancyStatus.disponible,
        ),
        throwsA(isA<AppFailure>()),
      );
    });

    test('un apartamento libre no cuenta como ocupado', () {
      final groupId = portfolio.createGroup('Anamelia');
      portfolio.createApartment(
        groupId: groupId,
        identifier: 'A-01',
        location: '',
        rentCents: 850000,
      );
      final row = portfolio.listApartments().single;
      expect(row.occupancy, OccupancyStatus.disponible);
      expect(row.hasActiveLease, isFalse);
      expect(row.rentStatus, RentStatus.disponible);
      expect(row.tenantName, isNull);
    });
  });

  group('Inquilinos y contratos', () {
    late int apartmentId;

    setUp(() {
      final groupId = portfolio.createGroup('Anamelia');
      apartmentId = portfolio.createApartment(
        groupId: groupId,
        identifier: 'A-01',
        location: '',
        rentCents: 850000,
      );
    });

    test('la cédula y el teléfono se validan al registrar', () {
      expect(
        () => portfolio.registerTenantAndLease(
          apartmentId: apartmentId,
          fullName: 'María Peña',
          cedula: '123', // inválida
          phone: '8095550123',
          moveInDate: DateTime(2026, 9, 1),
          rentCents: 850000,
          dueDay: 5,
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(portfolio.countApartments(), 1);
      expect(db.rows('SELECT COUNT(*) AS c FROM tenants').first['c'], 0);
    });

    test('no se puede registrar un segundo contrato activo', () {
      portfolio.registerTenantAndLease(
        apartmentId: apartmentId,
        fullName: 'María Peña',
        cedula: '00112345678',
        phone: '8095550123',
        moveInDate: DateTime(2026, 9, 1),
        rentCents: 850000,
        dueDay: 5,
      );
      expect(
        () => portfolio.registerTenantAndLease(
          apartmentId: apartmentId,
          fullName: 'José Castillo',
          cedula: '40212345678',
          phone: '8095559999',
          moveInDate: DateTime(2026, 10, 1),
          rentCents: 850000,
          dueDay: 5,
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(db.rows('SELECT COUNT(*) AS c FROM leases').first['c'], 1);
    });

    test('editar el inquilino no cambia el contrato', () {
      final leaseId = portfolio.registerTenantAndLease(
        apartmentId: apartmentId,
        fullName: 'María Peña',
        cedula: '00112345678',
        phone: '8095550123',
        moveInDate: DateTime(2026, 9, 1),
        rentCents: 850000,
        dueDay: 5,
      );
      final tenantId = portfolio.findApartment(apartmentId)!.tenant!.id;
      portfolio.updateTenant(
        tenantId: tenantId,
        fullName: 'María A. Peña',
        cedula: '00112345678',
        phone: '8095557777',
      );
      final row = portfolio.findApartment(apartmentId)!;
      expect(row.tenant!.fullName, 'María A. Peña');
      expect(row.lease!.id, leaseId);
      expect(row.lease!.rentCents, 850000);
    });

    test('cambiar la renta no altera los meses ya cobrados', () {
      final leaseId = portfolio.registerTenantAndLease(
        apartmentId: apartmentId,
        fullName: 'María Peña',
        cedula: '00112345678',
        phone: '8095550123',
        moveInDate: DateTime(2026, 9, 1),
        rentCents: 850000,
        dueDay: 5,
      );
      finance.registerPayment(
        requestId: 'p-1',
        leaseId: leaseId,
        periodYear: 2026,
        periodMonth: 9,
        amountCents: 850000,
        paymentDate: DateTime(2026, 9, 5),
        method: PaymentMethod.efectivo,
      );
      portfolio.updateLeaseTerms(
        leaseId: leaseId,
        monthlyRentCents: 950000,
        dueDay: 10,
        depositRequiredCents: 0,
      );

      final row = portfolio.findApartment(apartmentId)!;
      expect(row.lease!.rentCents, 950000);
      expect(row.lease!.dueDay, 10);
      // El período de septiembre ya emitido conserva su monto original.
      final september = finance
          .periodsFor(leaseId, from: DateTime(2026, 9), to: DateTime(2026, 9))
          .single;
      expect(september.amountDueCents, 850000);
      expect(september.remainingCents, 0);
      // Octubre ya usa la renta nueva.
      final october = finance
          .periodsFor(leaseId, from: DateTime(2026, 10), to: DateTime(2026, 10))
          .single;
      expect(october.amountDueCents, 950000);
    });

    test('finalizar un contrato conserva historial y recibos', () {
      final leaseId = portfolio.registerTenantAndLease(
        apartmentId: apartmentId,
        fullName: 'María Peña',
        cedula: '00112345678',
        phone: '8095550123',
        moveInDate: DateTime(2026, 9, 1),
        rentCents: 850000,
        dueDay: 5,
      );
      final outcome = finance.registerPayment(
        requestId: 'p-1',
        leaseId: leaseId,
        periodYear: 2026,
        periodMonth: 9,
        amountCents: 850000,
        paymentDate: DateTime(2026, 9, 5),
        method: PaymentMethod.efectivo,
      );
      portfolio.endLease(
        leaseId: leaseId,
        endDate: DateTime(2026, 10, 31),
        reason: 'Mudanza',
      );
      final history = portfolio.leaseHistory(apartmentId);
      expect(history.length, 1);
      expect(history.single.isActive, isFalse);
      expect(history.single.endDate, DateTime(2026, 10, 31));
      // El recibo del contrato terminado sigue existiendo.
      expect(finance.receipt(outcome.receiptId)!.number, outcome.receiptNumber);
      expect(finance.paymentsForLease(leaseId).length, 1);

      // No se puede finalizar dos veces.
      expect(
        () => portfolio.endLease(
          leaseId: leaseId,
          endDate: DateTime(2026, 11, 1),
        ),
        throwsA(isA<AppFailure>()),
      );
    });

    test('la salida no puede ser anterior al ingreso', () {
      final leaseId = portfolio.registerTenantAndLease(
        apartmentId: apartmentId,
        fullName: 'María Peña',
        cedula: '00112345678',
        phone: '8095550123',
        moveInDate: DateTime(2026, 9, 1),
        rentCents: 850000,
        dueDay: 5,
      );
      expect(
        () =>
            portfolio.endLease(leaseId: leaseId, endDate: DateTime(2026, 8, 1)),
        throwsA(isA<AppFailure>()),
      );
      expect(portfolio.findApartment(apartmentId)!.hasActiveLease, isTrue);
    });
  });

  group('Búsqueda y filtros', () {
    test('encuentra por número, residencial o inquilino', () {
      final groupId = portfolio.createGroup('Villa Cerro');
      portfolio.createApartment(
        groupId: groupId,
        identifier: 'B-14',
        location: 'Bloque 3',
        rentCents: 800000,
      );
      final apartmentId = portfolio.listApartments().single.id;
      portfolio.registerTenantAndLease(
        apartmentId: apartmentId,
        fullName: 'Yudelka Marte',
        cedula: '00112345678',
        phone: '8095550123',
        moveInDate: DateTime(2026, 9, 1),
        rentCents: 800000,
        dueDay: 5,
      );
      final row = portfolio.listApartments().single;
      expect(row.matches('B-14'), isTrue);
      expect(row.matches('villa'), isTrue);
      expect(row.matches('yudelka'), isTrue);
      expect(row.matches('zzz'), isFalse);
      expect(row.matches('  '), isTrue);
    });
  });
}
