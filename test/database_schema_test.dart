import 'dart:io';

import 'package:control_alquileres/src/core/app_failure.dart';
import 'package:control_alquileres/src/data/app_database.dart';
import 'package:control_alquileres/src/data/models.dart';
import 'package:control_alquileres/src/data/portfolio_repository.dart';
import 'package:control_alquileres/src/data/schema.dart';
import 'package:control_alquileres/src/data/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late AppDatabase db;
  late PortfolioRepository repo;

  setUp(() {
    db = AppDatabase.inMemory();
    repo = PortfolioRepository(db);
  });

  tearDown(() => db.close());

  int newApartment(String identifier, {int? groupId}) {
    final group = groupId ?? repo.createGroup('Anamelia');
    return repo.createApartment(
      groupId: group,
      identifier: identifier,
      location: 'Primer nivel',
      rentCents: 850000,
    );
  }

  int newLease(int apartmentId, String name) => repo.registerTenantAndLease(
    apartmentId: apartmentId,
    fullName: name,
    cedula: '00112345678',
    phone: '809-555-0123',
    moveInDate: DateTime(2026, 1, 5),
    rentCents: 850000,
    dueDay: 5,
  );

  group('esquema', () {
    test('crea el esquema actual (versión 2)', () {
      expect(db.userVersion, kSchemaVersion);
      final tables = db
          .rows("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((row) => row['name'])
          .toSet();
      expect(
        tables.containsAll({
          'apartment_groups',
          'apartments',
          'tenants',
          'leases',
          'payment_periods',
          'payments',
          'receipts',
          'deposit_movements',
          'owner_settings',
          'app_meta',
          'app_events',
          'payment_reversals',
        }),
        isTrue,
      );
    });

    test('claves foráneas activas: no acepta un residencial inexistente', () {
      expect(
        () => repo.createApartment(
          groupId: 999,
          identifier: '101',
          location: '',
          rentCents: 100000,
        ),
        throwsA(isA<AppFailure>()),
      );
    });

    test('foreign_keys está encendido en la conexión', () {
      expect(db.rows('PRAGMA foreign_keys').first.values.first, 1);
    });
  });

  group('apartamentos', () {
    test('impide números repetidos dentro del mismo residencial '
        '(sin distinguir mayúsculas ni espacios)', () {
      final group = repo.createGroup('Anamelia');
      newApartment('101', groupId: group);

      expect(
        () => newApartment('101', groupId: group),
        throwsA(isA<AppFailure>()),
      );
      expect(
        () => newApartment(' 101 ', groupId: group),
        throwsA(isA<AppFailure>()),
      );
    });

    test('permite el mismo número en residenciales distintos', () {
      final anamelia = repo.createGroup('Anamelia');
      final villaCerro = repo.createGroup('Villa Cerro');
      newApartment('101', groupId: anamelia);
      newApartment('101', groupId: villaCerro);
      expect(repo.countApartments(), 2);
    });

    test('no permite dos residenciales con el mismo nombre', () {
      repo.createGroup('Anamelia');
      expect(() => repo.createGroup('anamelia'), throwsA(isA<AppFailure>()));
    });

    test('rechaza identificadores vacíos y montos negativos', () {
      final group = repo.createGroup('Anamelia');
      expect(
        () => newApartment('   ', groupId: group),
        throwsA(isA<AppFailure>()),
      );
      expect(
        () => repo.createApartment(
          groupId: group,
          identifier: '102',
          location: '',
          rentCents: -1,
        ),
        throwsA(isA<AppFailure>()),
      );
    });

    test('no deja marcar disponible un apartamento con contrato activo', () {
      final id = newApartment('101');
      newLease(id, 'María Pérez');

      expect(
        () => repo.updateApartment(
          id: id,
          identifier: '101',
          location: 'Primer nivel',
          rentCents: 850000,
          occupancy: OccupancyStatus.disponible,
        ),
        throwsA(isA<AppFailure>()),
      );
    });
  });

  group('contratos', () {
    test(
      'un solo contrato activo por apartamento y el historial se conserva',
      () {
        final id = newApartment('101');
        final firstLease = newLease(id, 'María Pérez');

        expect(() => newLease(id, 'José Ramírez'), throwsA(isA<AppFailure>()));

        repo.endLease(leaseId: firstLease, endDate: DateTime(2026, 6, 30));

        final secondLease = newLease(id, 'José Ramírez');
        expect(secondLease, isNot(firstLease));

        final history = repo.leaseHistory(id);
        expect(history.length, 2);
        expect(history.where((item) => item.isActive).length, 1);
        expect(history.map((item) => item.tenantName), contains('María Pérez'));
      },
    );

    test('al finalizar el contrato el apartamento queda disponible', () {
      final id = newApartment('101');
      final leaseId = newLease(id, 'María Pérez');
      expect(repo.findApartment(id)!.occupancy, OccupancyStatus.ocupado);

      repo.endLease(leaseId: leaseId, endDate: DateTime(2026, 6, 30));
      expect(repo.findApartment(id)!.occupancy, OccupancyStatus.disponible);
      expect(repo.findApartment(id)!.hasActiveLease, isFalse);
    });

    test('no acepta fecha de salida anterior al ingreso', () {
      final id = newApartment('101');
      final leaseId = newLease(id, 'María Pérez');
      expect(
        () => repo.endLease(leaseId: leaseId, endDate: DateTime(2025, 1, 1)),
        throwsA(isA<AppFailure>()),
      );
    });

    test('valida cédula y teléfono evidentemente incorrectos', () {
      final id = newApartment('101');
      expect(
        () => repo.registerTenantAndLease(
          apartmentId: id,
          fullName: 'Ana Rodríguez',
          cedula: '123',
          phone: '8095550000',
          moveInDate: DateTime(2026, 1, 5),
          rentCents: 850000,
          dueDay: 5,
        ),
        throwsA(isA<AppFailure>()),
      );
    });
  });

  group('transacciones e idempotencia', () {
    test('una transacción fallida no deja datos a medias', () {
      final id = newApartment('101');
      final before = db.rows('SELECT COUNT(*) AS c FROM tenants').first['c'];

      expect(
        () => db.tx(() {
          db.run(
            "INSERT INTO tenants (full_name, created_at) VALUES ('Temporal', 'x')",
          );
          throw StateError('fallo simulado');
        }),
        throwsA(isA<StateError>()),
      );

      expect(db.rows('SELECT COUNT(*) AS c FROM tenants').first['c'], before);
      expect(id, greaterThan(0));
    });

    test('request_id único en pagos (base de la idempotencia)', () {
      final id = newApartment('101');
      final leaseId = newLease(id, 'María Pérez');

      void insertPayment() => db.run(
        'INSERT INTO payments (request_id, lease_id, concept, payment_date, '
        'method, amount_cents, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          'req-0001',
          leaseId,
          'Alquiler',
          '2026-10-27',
          'efectivo',
          850000,
          'x',
        ],
      );

      insertPayment();
      expect(() => insertPayment(), throwsA(isA<SqliteException>()));
      expect(db.rows('SELECT COUNT(*) AS c FROM payments').first['c'], 1);
    });

    test('el número de recibo es único por serie y un pago tiene un recibo', () {
      final id = newApartment('101');
      final leaseId = newLease(id, 'María Pérez');
      db.run(
        'INSERT INTO payments (request_id, lease_id, concept, payment_date, '
        'method, amount_cents, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
        ['req-1', leaseId, 'Alquiler', '2026-10-27', 'efectivo', 850000, 'x'],
      );
      final paymentId = db.lastInsertId;

      void insertReceipt(String number) => db.run(
        'INSERT INTO receipts (series, number, payment_id, issued_at, total_cents, '
        'snapshot_json) VALUES (?, ?, ?, ?, ?, ?)',
        ['REC', number, paymentId, 'x', 850000, '{}'],
      );

      insertReceipt('1');
      expect(() => insertReceipt('1'), throwsA(isA<SqliteException>()));
      // Un segundo recibo para el mismo pago tampoco es válido.
      expect(() => insertReceipt('2'), throwsA(isA<SqliteException>()));
    });
  });

  group('persistencia y durabilidad', () {
    test('reabrir la base conserva los datos sin volver a migrar', () {
      final dir = Directory.systemTemp.createTempSync('control_alquileres');
      final file = p.join(dir.path, 'datos.sqlite');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final first = AppDatabase.openAt(file);
      final firstRepo = PortfolioRepository(first);
      final group = firstRepo.createGroup('Anamelia');
      firstRepo.createApartment(
        groupId: group,
        identifier: '101',
        location: 'Primer nivel',
        rentCents: 850000,
      );
      first.close();

      final second = AppDatabase.openAt(file);
      expect(second.userVersion, kSchemaVersion);
      expect(second.quickCheck(), isNull);
      expect(PortfolioRepository(second).listApartments().length, 1);
      second.close();
    });

    test('WAL y synchronous=FULL activos en archivo', () {
      final dir = Directory.systemTemp.createTempSync('control_alquileres_wal');
      final file = p.join(dir.path, 'datos.sqlite');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final database = AppDatabase.openAt(file);
      final journal = database.rows('PRAGMA journal_mode').first.values.first;
      final sync = database.rows('PRAGMA synchronous').first.values.first;
      database.close();

      expect(journal.toString().toLowerCase(), 'wal');
      // 2 = FULL
      expect(sync, 2);
    });
  });

  group('ajustes', () {
    test('guarda y recupera los datos del negocio', () {
      final settings = SettingsRepository(db);
      expect(settings.load().issuerName, isEmpty);

      settings.save(
        const OwnerSettings(
          issuerName: 'Inversiones Anamelia SRL',
          issuerId: '1-31-12345-6',
          issuerAddress: 'Av. Independencia 45',
          issuerPhone: '809-555-0000',
          printerName: 'EPSON TM-T20III',
          receiptPrefix: 'ALQ',
        ),
      );

      final loaded = settings.load();
      expect(loaded.issuerName, 'Inversiones Anamelia SRL');
      expect(loaded.printerName, 'EPSON TM-T20III');
      expect(loaded.receiptPrefix, 'ALQ');
    });
  });
}
