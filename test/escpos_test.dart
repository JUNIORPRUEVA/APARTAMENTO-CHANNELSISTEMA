import 'dart:typed_data';

import 'package:control_alquileres/src/core/formatters.dart';
import 'package:control_alquileres/src/data/finance_models.dart';
import 'package:control_alquileres/src/services/escpos.dart';
import 'package:control_alquileres/src/services/serial_transport.dart';
import 'package:flutter_test/flutter_test.dart';

ReceiptRecord _record({
  ReceiptKind kind = ReceiptKind.alquiler,
  String tenant = 'José Ramón Núñez',
  String cedula = '001-1234567-8',
  String reference = 'TRF-99881',
}) {
  return ReceiptRecord(
    id: 1,
    series: 'REC',
    number: 7,
    kind: kind,
    issuedAt: DateTime(2026, 8, 18, 9, 5),
    totalCents: 850000,
    snapshot: <String, Object?>{
      'kind': kind.dbValue,
      'series': 'REC',
      'number': 7,
      'issuedAt': '2026-08-18T09:05:00.000',
      'issuerName': 'Anamelia Rentas',
      'issuerId': '131-00000-1',
      'issuerAddress': 'Av. 27 de Febrero 123, Santo Domingo',
      'issuerPhone': '809-555-0101',
      'tenantName': tenant,
      'tenantCedula': cedula,
      'tenantPhone': '809-555-2020',
      'groupName': 'Anamelia',
      'apartmentIdentifier': 'A-04',
      'apartmentLocation': 'Anamelia · bloque 2',
      'periodLabel': 'Agosto 2026',
      'dueDate': '2026-08-05',
      'concept': 'Alquiler',
      'amountCents': 850000,
      'amountDueCents': 850000,
      'balanceAfterCents': 0,
      'method': 'Transferencia',
      'paymentDate': '2026-08-05',
      'reference': reference,
      'note': 'Transferencia bancaria',
    },
    pdfPath: null,
    pdfStatus: 'pendiente',
    attempts: 0,
  );
}

/// Texto reconstruido desde CP850, descartando los comandos ESC/POS.
///
/// Se conocen las secuencias que emite [EscPosReceipt]: si aparece una nueva
/// hay que agregarla aquí, de lo contrario los bytes de sus parámetros se
/// confundirían con texto.
String _decodeCp850(Uint8List bytes) {
  const high = <int, String>{
    0x82: 'é',
    0xA4: 'ñ',
    0xA0: 'á',
    0xA2: 'ó',
    0xA3: 'ú',
    0xA1: 'í',
    0xA5: 'Ñ',
    0xA9: '⌐',
    0x07: '•',
  };
  // Longitud total (incluido el prefijo) de cada comando usado.
  final lengths = <String, int>{
    '\x1B@': 2, // ESC @
    '\x1Bt': 3, // ESC t n  (página de códigos)
    '\x1Ba': 3, // ESC a n  (alineación)
    '\x1BE': 3, // ESC E n  (negrita)
    '\x1Bd': 3, // ESC d n  (avance)
    '\x1D!': 3, // GS ! n   (tamaño)
    '\x1DV': 4, // GS V m n (corte)
  };
  final buffer = StringBuffer();
  var i = 0;
  while (i < bytes.length) {
    final byte = bytes[i];
    if (byte == 0x1B || byte == 0x1D) {
      final key = String.fromCharCodes(bytes.sublist(i, i + 2));
      final skip = lengths[key];
      if (skip == null) {
        throw StateError('Comando ESC/POS desconocido: $key');
      }
      i += skip;
      continue;
    }
    if (byte == 0x0A) {
      buffer.write('\n');
    } else if (byte >= 0x20 || byte == 0x07) {
      buffer.write(high[byte] ?? String.fromCharCode(byte));
    }
    i++;
  }
  return buffer.toString();
}

void main() {
  group('ESC/POS', () {
    test('inicia, selecciona CP850, imprime el monto y corta el papel', () {
      final bytes = EscPosReceipt.build(_record());
      expect(bytes.sublist(0, 2), [0x1B, 0x40]);
      expect(bytes.sublist(2, 5), [0x1B, 0x74, 0x02]);
      final text = _decodeCp850(bytes);
      expect(text, contains('Anamelia Rentas'));
      expect(text, contains('A-04'));
      expect(text, contains('REC-000007'));
      expect(text, contains('RD\$ 8,500'));
      // Avance + corte completo al final.
      expect(bytes.sublist(bytes.length - 4), [0x1D, 0x56, 0x42, 0x00]);
    });

    test('los acentos viajan en CP850 y no como mojibake', () {
      final bytes = EscPosText.encode('José Núñez');
      expect(bytes.contains(0xC3), isFalse, reason: 'no debe ser UTF-8');
      expect(bytes, contains(0x82)); // é
      expect(bytes, contains(0xA4)); // ñ
      expect(bytes, contains(0xA3)); // ú
    });

    test('modo sin acentos translitera a ASCII', () {
      final bytes = EscPosText.encode('José Núñez', asciiOnly: true);
      expect(String.fromCharCodes(bytes), 'Jose Nunez');
      for (final byte in bytes) {
        expect(byte, lessThan(0x80));
      }
    });

    test('la cédula sale enmascarada también en el papel térmico', () {
      final text = _decodeCp850(EscPosReceipt.build(_record()));
      expect(text, contains('001-•••••••-78'));
      expect(text, isNot(contains('1234567')));
    });

    test('incluye la referencia de la transferencia y omite la vacía', () {
      expect(
        _decodeCp850(EscPosReceipt.build(_record())),
        contains('TRF-99881'),
      );
      final withoutRef = _decodeCp850(
        EscPosReceipt.build(_record(reference: '')),
      );
      expect(withoutRef, isNot(contains('Referencia')));
    });

    test('ninguna línea supera el ancho del papel', () {
      for (final width in [80, 58]) {
        final cols = EscPosReceipt.columnsFor(width);
        final lines = _decodeCp850(
          EscPosReceipt.build(
            _record(
              tenant:
                  'María Altagracia Peña Fernández de la Cruz y Villanueva '
                  'Rodríguez',
            ),
            widthMm: width,
          ),
        ).split('\n');
        for (final line in lines) {
          final clean = line;
          expect(
            clean.length,
            lessThanOrEqualTo(cols),
            reason: 'línea demasiado larga ($width mm): $clean',
          );
        }
      }
    });

    test('el recibo de depósito cambia el concepto, no el monto', () {
      final text = _decodeCp850(
        EscPosReceipt.build(_record(kind: ReceiptKind.deposito)),
      );
      expect(text, contains('Depósito'));
      expect(text, contains('RD\$ 8,500'));
    });
  });

  group('puertos serie', () {
    test('lee los puertos del registro y detecta Bluetooth', () {
      const output = r'''
HKEY_LOCAL_MACHINE\HARDWARE\DEVICEMAP\SERIALCOMM
    \Device\BthModem0    REG_SZ    COM5
    \Device\Serial0      REG_SZ    COM1
''';
      final ports = Win32SerialTransport.parseSerialMap(output);
      expect(ports.map((p) => p.name), ['COM1', 'COM5']);
      expect(ports.first.likelyBluetooth, isFalse);
      expect(ports.last.likelyBluetooth, isTrue);
    });

    test('un registro vacío o ilegible no rompe nada', () {
      expect(Win32SerialTransport.parseSerialMap(''), isEmpty);
      expect(Win32SerialTransport.parseSerialMap('basura'), isEmpty);
    });
  });

  group('formato de cédula', () {
    test('enmascara dejando prefijo y dos últimos dígitos', () {
      expect(maskCedula('001-1234567-8'), '001-•••••••-78');
      expect(maskCedula('00112345678'), '001-•••••••-78');
      expect(maskCedula(''), '');
      expect(maskCedula('12345'), '••••45');
      expect(maskCedula('7'), '••••7');
    });
  });
}
