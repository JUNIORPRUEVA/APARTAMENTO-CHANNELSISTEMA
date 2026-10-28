import 'dart:typed_data';

import '../core/formatters.dart';
import '../data/finance_models.dart';
import 'printer_profile.dart';

/// Genera los bytes ESC/POS del recibo para una impresora térmica conectada por
/// puerto serie (impresoras Bluetooth SPP / RFCOMM con driver de puerto COM).
///
/// Reglas importantes:
/// * Se escribe el **mismo contenido** que el PDF (`ReceiptRecord.snapshot`).
///   El snapshot es inmutable: reimprimir no vuelve a calcular nada.
/// * La cédula se imprime enmascarada, igual que en el papel PDF.
/// * El texto se codifica en **CP850** y se selecciona esa página de códigos
///   con `ESC t 2`, para que á é í ó ú ñ ¿ ¡ salgan legibles en la mayoría de
///   impresoras ESC/POS. Si una impresora ignora `ESC t`, los acentos pueden
///   salir mal: por eso existe `asciiOnly`, que translitera a ASCII puro.
/// * El ancho **no** se toma del nombre del papel: sale del perfil calibrado
///   ([PrinterProfile.effectivePrintableDots]). Un perfil sin calibrar usa un
///   valor conservador para no recortar dígitos del monto.
/// * **No se envía corte** (`GS V`) salvo que el perfil diga que el equipo tiene
///   cortador. La 2C-P80-C es de rasgado manual.
///
/// Esta clase es pura: no toca disco, ni red, ni dispositivos. Se puede probar
/// comparando los bytes generados.
class EscPosReceipt {
  const EscPosReceipt._();

  static const int _esc = 0x1B;
  static const int _gs = 0x1D;

  /// Columnas de la fuente A para un ancho de papel, sin calibración.
  static int columnsFor(int widthMm) =>
      PrinterProfile(paperWidthMm: widthMm).columns;

  /// Construye el flujo completo del recibo: inicialización, contenido y
  /// avance de papel para rasgar a mano.
  ///
  /// [profile] aporta ancho calibrado, márgenes, codificación y modo de corte.
  static Uint8List build(
    ReceiptRecord record, {
    PrinterProfile profile = const PrinterProfile(),
    // Compatibilidad con llamadas antiguas.
    int? widthMm,
    bool? asciiOnly,
  }) {
    final p = widthMm == null && asciiOnly == null
        ? profile
        : profile.copyWith(
            paperWidthMm: widthMm ?? profile.paperWidthMm,
            asciiOnly: asciiOnly ?? profile.asciiOnly,
          );
    final cols = p.columns;
    final b = _Writer(asciiOnly: p.asciiOnly, columns: cols);

    // Inicializa y fija la página de códigos CP850.
    b.raw([_esc, 0x40]);
    if (!p.asciiOnly) b.raw([_esc, 0x74, 0x02]);

    final data = record.snapshot;
    String text(String key) => (data[key]?.toString() ?? '').trim();
    int cents(String key) => int.tryParse(data[key]?.toString() ?? '') ?? 0;

    final issuerName = text('issuerName').isEmpty
        ? 'Control de Alquileres'
        : text('issuerName');
    final paymentDate = parseIsoDate(text('paymentDate'));
    final issuedAt = DateTime.tryParse(text('issuedAt')) ?? DateTime.now();

    b.center(issuerName, doubleHeight: true);
    if (text('issuerId').isNotEmpty) b.center('RNC/Céd.: ${text('issuerId')}');
    if (text('issuerAddress').isNotEmpty) b.center(text('issuerAddress'));
    if (text('issuerPhone').isNotEmpty) {
      b.center('Tel.: ${text('issuerPhone')}');
    }
    b.rule(cols);

    b.center(record.kind.title, bold: true);
    b.center('No. ${record.label}', bold: true);
    b.center(
      'Emitido: ${formatDate(issuedAt)} '
      '${issuedAt.hour.toString().padLeft(2, '0')}:'
      '${issuedAt.minute.toString().padLeft(2, '0')}',
    );
    b.rule(cols);

    b.field('Residencial', text('groupName'), cols);
    b.field('Apartamento', text('apartmentIdentifier'), cols);
    if (text('apartmentLocation').isNotEmpty) {
      b.field('Ubicación', text('apartmentLocation'), cols);
    }
    b.field('Inquilino', text('tenantName'), cols);
    if (text('tenantCedula').isNotEmpty) {
      // En papel se enmascara con `X`: el `•` viaja como 0x07 y muchas
      // impresoras lo tratan como BEL (no lo dibujan).
      b.field('Cédula', maskCedula(text('tenantCedula'), hide: 'X'), cols);
    }
    b.rule(cols);

    switch (record.kind) {
      case ReceiptKind.alquiler:
        b.field('Concepto', text('concept'), cols);
        b.field('Período', text('periodLabel'), cols);
        b.field('Vence', formatDateOrDash(parseIsoDate(text('dueDate'))), cols);
        b.field('Método', text('method'), cols);
        if (text('reference').isNotEmpty) {
          b.field('Referencia', text('reference'), cols);
        }
        b.field('Fecha pago', formatDateOrDash(paymentDate), cols);
      case ReceiptKind.deposito:
        b.field('Concepto', text('depositKindLabel'), cols);
        b.field('Fecha', formatDateOrDash(paymentDate), cols);
        b.field(
          'Depósito retenido',
          formatMoney(cents('heldAfterCents')),
          cols,
        );
        if (text('note').isNotEmpty) b.field('Motivo', text('note'), cols);
      case ReceiptKind.anulacion:
        b.field('Anula recibo', text('originalReceipt'), cols);
        b.field('Fecha pago', formatDateOrDash(paymentDate), cols);
        b.field('Motivo', text('voidReason'), cols);
        b.field('Período', text('periodLabel'), cols);
    }

    b.rule(cols);
    b.total('MONTO', formatMoney(cents('amountCents')), cols);
    if (record.kind == ReceiptKind.alquiler) {
      b.field(
        'Saldo del período',
        formatMoney(cents('balanceAfterCents')),
        cols,
      );
    }
    if (record.kind != ReceiptKind.deposito && text('note').isNotEmpty) {
      b.wrapped('Obs.: ${text('note')}', cols);
    }
    b.rule(cols);
    b.center('Conserve este recibo', bold: true);
    b.wrapped(
      'Documento de control interno. No es comprobante fiscal (NCF).',
      cols,
    );

    // Avance de papel justo para rasgar a mano; nunca se corta antes de
    // terminar de imprimir. El corte solo existe si el perfil dice que el
    // equipo tiene cortador (no es el caso de la 2C-P80-C).
    b.raw([_esc, 0x64, 0x04]);
    if (p.cutMode == CutMode.autoCutter) b.raw([_gs, 0x56, 0x42, 0x00]);

    return b.takeBytes();
  }

  /// Ticket de **calibración**: sirve para medir con una regla el ancho real
  /// imprimible y comprobar acentos, alineaciones, tamaños y montos.
  ///
  /// No toca la base ni necesita un cobro: es puro texto ESC/POS.
  static Uint8List buildCalibration({
    PrinterProfile profile = const PrinterProfile(),
    String model = '2C-P80-C',
    String note = '',
    DateTime? now,
  }) {
    final cols = profile.columns;
    final b = _Writer(asciiOnly: profile.asciiOnly, columns: cols);
    final stamp = now ?? DateTime.now();

    b.raw([_esc, 0x40]);
    if (!profile.asciiOnly) b.raw([_esc, 0x74, 0x02]);

    b.center('PRUEBA DE IMPRESORA', bold: true, doubleHeight: true);
    b.center('*** NO ES UN PAGO ***', bold: true);
    b.center('No afecta saldos ni recibos');
    b.rule(cols);
    b.center('CALIBRACION', bold: true);
    b.center(model);
    b.center(
      '${formatDate(stamp)} '
      '${stamp.hour.toString().padLeft(2, '0')}:'
      '${stamp.minute.toString().padLeft(2, '0')}',
    );
    b.rule(cols);

    // Regla de puntos: el último carácter visible indica el ancho real.
    b.raw([0x1B, 0x61, 0x00]);
    for (var i = 0; i < cols; i += 10) {
      if (i == 0) continue;
      final position = i.toString().padLeft(2, '0');
      final width = cols - i - position.length;
      if (width <= 0) break;
      b.raw(
        encodeLine(
          '$position${' ' * width}$position',
          asciiOnly: profile.asciiOnly,
        ),
      );
      b.raw([0x0A]);
    }
    b.rule(cols);

    b.center('IZQUIERDA / CENTRO / DERECHA', bold: true);
    b.raw(encodeLine('|IZQUIERDA', asciiOnly: profile.asciiOnly));
    b.raw([0x0A]);
    b.center('|CENTRO|');
    b.raw([0x1B, 0x61, 0x02]);
    b.raw(encodeLine('DERECHA|', asciiOnly: profile.asciiOnly));
    b.raw([0x0A]);
    b.raw([0x1B, 0x61, 0x00]);

    // Bordes: si alguna línea se sale del papel, se verá cortada aquí.
    b.raw(encodeLine('|${'-' * (cols - 2)}|', asciiOnly: profile.asciiOnly));
    b.raw([0x0A]);

    b.center('TAMANOS DE LETRA', bold: true);
    b.raw(
      encodeLine(
        'Normal: Acentos áéíóú ÁÉÍÓÚ ñÑ üÜ ¿¡',
        asciiOnly: profile.asciiOnly,
      ),
    );
    b.raw([0x0A]);
    b.raw([0x1D, 0x21, 0x11]);
    b.wrappedFlex('Doble: RD\$ 8,500', profile.columnsAt(2));
    b.raw([0x1D, 0x21, 0x00]);

    b.rule(cols);
    b.field('Papel', '${profile.paperWidthMm} mm', cols);
    b.field(
      'Ancho util',
      '${profile.printableWidthMm.toStringAsFixed(1)} mm '
          '(${profile.effectivePrintableDots} puntos)',
      cols,
    );
    b.field('Columnas', '$cols', cols);
    b.field(
      'Calibrado',
      profile.isCalibrated ? 'Si' : 'No (valor conservador)',
      cols,
    );
    b.field(
      'Acentos',
      profile.asciiOnly ? 'Sin acentos (ASCII)' : 'CP850',
      cols,
    );
    b.field(
      'Corte',
      profile.cutMode == CutMode.manual ? 'Manual' : 'Auto',
      cols,
    );
    if (note.trim().isNotEmpty) b.wrapped('Nota: ${note.trim()}', cols);
    b.rule(cols);
    b.wrapped(
      'Mida con una regla la linea de borde. Si el texto se corta a la '
      'derecha, reduzca el ancho util en Ajustes.',
      cols,
    );
    b.center('FIN DE LA PRUEBA', bold: true);
    b.center('*** NO ES UN PAGO ***', bold: true);
    b.raw([_esc, 0x64, 0x05]);
    return b.takeBytes();
  }

  /// Codifica una línea completa (sin saltos) con la codificación del perfil.
  static Uint8List encodeLine(String value, {bool asciiOnly = false}) =>
      _Writer.encodeText(value, asciiOnly: asciiOnly);
}

/// Codificador de texto ESC/POS (CP850 o ASCII transliterado).
///
/// Se expone aparte para poder reutilizarlo en la hoja de prueba de la
/// impresora sin duplicar la tabla de caracteres.
class EscPosText {
  const EscPosText._();

  static Uint8List encode(String value, {bool asciiOnly = false}) =>
      _Writer.encodeText(value, asciiOnly: asciiOnly);
}

class _Writer {
  _Writer({required this.asciiOnly, required this.columns});

  final bool asciiOnly;

  /// Columnas disponibles en el papel (fuente A).
  final int columns;
  final BytesBuilder _out = BytesBuilder(copy: false);

  void raw(List<int> bytes) => _out.add(bytes);

  Uint8List takeBytes() => _out.takeBytes();

  /// Escribe el texto y **termina la línea** (ESC/POS no corta solo).
  void _text(String value, {bool bold = false, bool doubleHeight = false}) {
    if (bold) raw([0x1B, 0x45, 0x01]);
    if (doubleHeight) raw([0x1D, 0x21, 0x01]);
    raw(encodeText(value, asciiOnly: asciiOnly));
    if (doubleHeight) raw([0x1D, 0x21, 0x00]);
    if (bold) raw([0x1B, 0x45, 0x00]);
    raw([0x0A]);
  }

  void _align(int mode) => raw([0x1B, 0x61, mode]);

  void center(String value, {bool bold = false, bool doubleHeight = false}) {
    _align(1);
    for (final line in wrap(value, columns)) {
      _text(line, bold: bold, doubleHeight: doubleHeight);
    }
    _align(0);
  }

  void rule(int cols) {
    _text('-' * cols);
  }

  /// Etiqueta a la izquierda y valor a la derecha, ocupando el ancho del papel.
  void field(String label, String value, int cols) {
    final cleanLabel = value.trim().isEmpty ? '' : label;
    final cleanValue = value.trim();
    if (cleanValue.isEmpty) return;
    final padding = cols - cleanLabel.length - cleanValue.length;
    if (padding >= 1) {
      _text('$cleanLabel${' ' * padding}$cleanValue');
      return;
    }
    // No cabe en una línea: etiqueta arriba y valor debajo, sin cortar palabras.
    _text(cleanLabel);
    wrapped(cleanValue, cols, indent: '  ');
  }

  void total(String label, String value, int cols) {
    // El monto va en doble ancho: ocupa el doble de columnas por carácter.
    final doubleWidthCols = cols ~/ 2;
    final padding = doubleWidthCols - label.length - value.length;
    raw([0x1B, 0x45, 0x01]);
    raw([0x1D, 0x21, 0x11]); // doble ancho y doble alto
    _text(padding > 0 ? '$label${' ' * padding}$value' : '$label $value');
    raw([0x1D, 0x21, 0x00]);
    raw([0x1B, 0x45, 0x00]);
  }

  /// Texto con ajuste de línea por palabras.
  void wrapped(String value, int cols, {String indent = ''}) {
    for (final line in wrap(value, cols - indent.length)) {
      _text('$indent$line');
    }
  }

  /// Igual que [wrapped] pero respetando el tamaño de letra ya fijado por
  /// quien llama (se usa en el ticket de calibración).
  void wrappedFlex(String value, int cols) {
    for (final line in wrap(value, cols)) {
      raw(encodeText(line, asciiOnly: asciiOnly));
      raw([0x0A]);
    }
  }

  static List<String> wrap(String value, int cols) {
    final width = cols <= 0 ? 1 : cols;
    final lines = <String>[];
    for (final paragraph in value.split('\n')) {
      final words = paragraph.split(RegExp(r'\s+'));
      var current = '';
      for (final word in words) {
        if (word.isEmpty) continue;
        if (current.isEmpty) {
          current = word;
        } else if (current.length + 1 + word.length <= width) {
          current = '$current $word';
        } else {
          lines.add(current);
          current = word;
        }
      }
      if (current.isNotEmpty) lines.add(current);
    }
    return lines.isEmpty ? [''] : lines;
  }

  /// Codifica el texto en CP850 (o ASCII transliterado).
  static Uint8List encodeText(String value, {bool asciiOnly = false}) {
    final buffer = <int>[];
    for (final rune in value.runes) {
      if (rune == 0x0A) {
        buffer.add(0x0A);
        continue;
      }
      if (rune < 0x80) {
        buffer.add(rune);
        continue;
      }
      // CP850 reserva 0x07 para el punto volcado (•), que es lo que usa la
      // cédula enmascarada. Se mapea explícitamente para que no salga '?'.
      if (rune == 0x2022) {
        buffer.add(0x07);
        continue;
      }
      final direct = _cp850Reverse[rune];
      if (direct != null && !asciiOnly) {
        buffer.add(direct);
        continue;
      }
      // Fuera de CP850 o en modo ASCII: se translitera.
      final folded = _foldRune(rune);
      for (final unit in folded.runes) {
        if (unit < 0x80) {
          buffer.add(unit);
        } else if (_cp850Reverse[unit] != null) {
          buffer.add(_cp850Reverse[unit]!);
        } else {
          buffer.add(0x3F); // '?'
        }
      }
    }
    return Uint8List.fromList(buffer);
  }

  static String _foldRune(int rune) {
    const map = <int, String>{
      0xC1: 'A',
      0xC0: 'A',
      0xC4: 'A',
      0xC2: 'A',
      0xE1: 'a',
      0xE0: 'a',
      0xE4: 'a',
      0xE2: 'a',
      0xC9: 'E',
      0xC8: 'E',
      0xCB: 'E',
      0xEA: 'e',
      0xE9: 'e',
      0xE8: 'e',
      0xEB: 'e',
      0xCD: 'I',
      0xCC: 'I',
      0xCF: 'I',
      0xCE: 'I',
      0xED: 'i',
      0xEC: 'i',
      0xEF: 'i',
      0xEE: 'i',
      0xD3: 'O',
      0xD2: 'O',
      0xD6: 'O',
      0xD4: 'O',
      0xF3: 'o',
      0xF2: 'o',
      0xF6: 'o',
      0xF4: 'o',
      0xDA: 'U',
      0xD9: 'U',
      0xDC: 'U',
      0xDB: 'U',
      0xFA: 'u',
      0xF9: 'u',
      0xFC: 'u',
      0xFB: 'u',
      0xD1: 'N',
      0xF1: 'n',
      0xBF: '?',
      0xA1: '!',
      0xB0: 'o',
      0xBA: 'o',
      0xAA: 'a',
      0xAB: '"',
      0xBB: '"',
      0x2013: '-',
      0x2014: '-',
      0x2019: "'",
      0x201C: '"',
      0x201D: '"',
      0x20AC: 'EUR',
    };
    final direct = map[rune];
    if (direct != null) return direct;
    // Caracteres combinables y demás: se sustituye por '?'.
    final decoded = String.fromCharCode(rune);
    try {
      final ascii = decoded.replaceAll(RegExp(r'[^\x20-\x7E]'), '?');
      return ascii;
    } catch (_) {
      return '?';
    }
  }

  /// Tabla CP850 (byte → punto de código) para los caracteres que aparecen en
  /// los recibos en español. Se construye una vez, invertida.
  static final Map<int, int> _cp850Reverse = () {
    // CP850 en el rango 0x80–0xFF, según la tabla de referencia.
    const table = <int>[
      0x00C7, 0x00FC, 0x00E9, 0x00E2, 0x00E4, 0x00E0, 0x00E5, 0x00E7, // 80
      0x00EA, 0x00EB, 0x00E8, 0x00EF, 0x00EE, 0x00EC, 0x00C4, 0x00C5, // 88
      0x00C9, 0x00E6, 0x00C6, 0x00F4, 0x00F6, 0x00F2, 0x00FB, 0x00F9, // 90
      0x00FF, 0x00D6, 0x00DC, 0x00F8, 0x00A3, 0x00D8, 0x00D7, 0x0192, // 98
      0x00E1, 0x00ED, 0x00F3, 0x00FA, 0x00F1, 0x00D1, 0x00AA, 0x00BA, // A0
      0x00BF, 0x00AE, 0x00AC, 0x00BD, 0x00BC, 0x00A1, 0x00AB, 0x00BB, // A8
      0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x00C1, 0x00C2, 0x00C0, // B0
      0x00A9, 0x2563, 0x2551, 0x2557, 0x255D, 0x00A2, 0x00A5, 0x2510, // B8
      0x2514, 0x2534, 0x252C, 0x251C, 0x2500, 0x253C, 0x00E3, 0x00C3, // C0
      0x255A, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256C, 0x00A4, // C8
      0x00F0, 0x00D0, 0x00CA, 0x00CB, 0x00C8, 0x0131, 0x00CD, 0x00CE, // D0
      0x00CF, 0x2518, 0x250C, 0x2588, 0x2584, 0x00A6, 0x00CC, 0x2580, // D8
      0x00D3, 0x00DF, 0x00D4, 0x00D2, 0x00F5, 0x00D5, 0x00B5, 0x00FE, // E0
      0x00DE, 0x00DA, 0x00DB, 0x00D9, 0x00FD, 0x00DD, 0x00AF, 0x00B4, // E8
      0x00AD, 0x00B1, 0x2017, 0x00BE, 0x00B6, 0x00A7, 0x00F7, 0x00B8, // F0
      0x00B0, 0x00A8, 0x00B7, 0x00B9, 0x00B3, 0x00B2, 0x25A0, 0x00A0, // F8
    ];
    final reverse = <int, int>{};
    for (var i = 0; i < table.length; i++) {
      reverse[table[i]] = 0x80 + i;
    }
    return reverse;
  }();
}
