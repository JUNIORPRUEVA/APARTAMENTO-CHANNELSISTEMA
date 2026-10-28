import 'package:control_alquileres/src/core/formatters.dart';
import 'package:control_alquileres/src/core/validators.dart';
import 'package:control_alquileres/src/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dinero', () {
    test('formatea con coma de miles y RD\$', () {
      expect(formatMoney(850000), 'RD\$ 8,500');
      expect(formatMoney(850050), 'RD\$ 8,500.50');
      expect(formatMoney(0), 'RD\$ 0');
      expect(formatMoney(123456789), 'RD\$ 1,234,567.89');
    });

    test('formato de entrada con dos decimales', () {
      expect(formatAmountInput(850000), '8,500.00');
      expect(formatAmountInput(9500), '95.00');
    });

    test('interpreta montos escritos por el usuario', () {
      expect(parseAmountToCents('8,500.00'), 850000);
      expect(parseAmountToCents('RD\$ 8,500'), 850000);
      expect(parseAmountToCents('8500.5'), 850050);
      expect(parseAmountToCents('  9000 '), 900000);
      expect(parseAmountToCents(''), isNull);
      expect(parseAmountToCents('abc'), isNull);
      expect(parseAmountToCents('-5'), isNull);
    });
  });

  group('fechas', () {
    test('DD/MM/AAAA y almacenamiento ISO', () {
      final date = DateTime(2026, 11, 5);
      expect(formatDate(date), '05/11/2026');
      expect(toIsoDate(date), '2026-11-05');
      expect(parseIsoDate('2026-11-05'), date);
      expect(parseIsoDate(null), isNull);
      expect(formatDateOrDash(null), '—');
    });

    test('nombre de período en español', () {
      expect(formatPeriodShort(2026, 11), 'Nov 2026');
      expect(formatPeriodLong(2026, 11), 'noviembre 2026');
      expect(formatPeriodShort(2026, 1), 'Ene 2026');
    });

    test('cédula con separadores cuando tiene 11 dígitos', () {
      expect(formatCedula('00112345678'), '001-1234567-8');
      expect(formatCedula('sin-digitos'), 'sin-digitos');
    });
  });

  group('vencimiento y días del mes', () {
    test('próxima fecha de pago en el mismo mes o el siguiente', () {
      expect(
        formatDate(nextDueDateFor(DateTime(2026, 10, 27), 5)),
        '05/11/2026',
      );
      expect(
        formatDate(nextDueDateFor(DateTime(2026, 10, 3), 5)),
        '05/10/2026',
      );
      expect(
        formatDate(nextDueDateFor(DateTime(2026, 10, 5), 5)),
        '05/10/2026',
      );
    });

    test('ajusta el día 31 a meses cortos', () {
      expect(formatDate(dayInMonth(2026, 2, 31)), '28/02/2026');
      expect(formatDate(dayInMonth(2026, 4, 31)), '30/04/2026');
    });
  });

  group('validaciones', () {
    test('identificador de apartamento', () {
      expect(validateApartmentIdentifier('101'), isNull);
      expect(validateApartmentIdentifier('A-1'), isNull);
      expect(validateApartmentIdentifier('  '), isNotNull);
      expect(validateApartmentIdentifier('x' * 21), isNotNull);
    });

    test('nombre de residencial y de persona', () {
      expect(validateGroupName('Anamelia'), isNull);
      expect(validateGroupName('A'), isNotNull);
      expect(validatePersonName('María Pérez'), isNull);
      expect(validatePersonName(''), isNotNull);
    });

    test('cédula y teléfono toleran formatos normales', () {
      expect(validateCedula('001-1234567-8'), isNull);
      expect(validateCedula('00112345678'), isNull);
      expect(validateCedula('123'), isNotNull);
      expect(validateCedula(''), isNull);
      expect(validatePhone('809-555-0123'), isNull);
      expect(validatePhone('8095550123'), isNull);
      expect(validatePhone('123'), isNotNull);
    });

    test('monto y día de pago', () {
      expect(validateAmount('8,500.00'), isNull);
      expect(validateAmount('0'), isNotNull);
      expect(validateAmount('abc'), isNotNull);
      expect(validateDueDay('5'), isNull);
      expect(validateDueDay('32'), isNotNull);
      expect(validateDueDay(''), isNotNull);
    });
  });

  group('búsqueda de la tabla', () {
    ApartmentRow build({String identifier = '101', String? tenant}) {
      return ApartmentRow(
        id: 1,
        groupId: 1,
        groupName: 'Anamelia',
        identifier: identifier,
        location: 'Primer nivel',
        rentCents: 850000,
        occupancy: OccupancyStatus.ocupado,
        isDemo: true,
        tenant: tenant == null
            ? null
            : TenantInfo(
                id: 1,
                fullName: tenant,
                cedula: '00112345678',
                phone: '8095550123',
              ),
      );
    }

    test('encuentra por número, residencial y inquilino', () {
      final row = build(tenant: 'María Pérez');
      expect(row.matches(''), isTrue);
      expect(row.matches('101'), isTrue);
      expect(row.matches('anamelia'), isTrue);
      expect(row.matches('perez'), isFalse); // sin acento no coincide
      expect(row.matches('Pérez'), isTrue);
      expect(row.matches('zzz'), isFalse);
    });
  });
}
