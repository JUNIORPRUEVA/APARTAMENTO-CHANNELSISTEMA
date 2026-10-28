/// Formateadores de dinero, fechas y períodos con convención dominicana:
/// RD$ con coma de miles y punto decimal, fechas DD/MM/AAAA.
library;

const List<String> _mesesCortos = <String>[
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

const List<String> _mesesLargos = <String>[
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// Inserta comas cada tres dígitos.
String groupThousands(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${value < 0 ? '-' : ''}$buffer';
}

/// Ej.: 850000 -> "RD$ 8,500" (sin decimales cuando son cero).
String formatMoney(int cents) {
  final negative = cents < 0;
  final value = cents.abs();
  final whole = value ~/ 100;
  final rest = value % 100;
  final body = rest == 0
      ? groupThousands(whole)
      : '${groupThousands(whole)}.${rest.toString().padLeft(2, '0')}';
  return 'RD\$ ${negative ? '-' : ''}$body';
}

/// Ej.: 850000 -> "8,500.00" (para campos de entrada).
String formatAmountInput(int cents) {
  final value = cents.abs();
  final whole = value ~/ 100;
  final rest = value % 100;
  return '${cents < 0 ? '-' : ''}${groupThousands(whole)}.'
      '${rest.toString().padLeft(2, '0')}';
}

/// Ej.: 850000 -> "8,500"
String formatAmountPlain(int cents) {
  final value = cents.abs();
  return '${cents < 0 ? '-' : ''}'
      '${groupThousands(value ~/ 100)}'
      '${value % 100 == 0 ? '' : '.${(value % 100).toString().padLeft(2, '0')}'}';
}

/// Acepta "8,500.00", "RD$ 8,500", "8500.5". Rechaza montos negativos.
int? parseAmountToCents(String raw) {
  // Un guion indica un monto negativo: no es válido para un cobro.
  if (raw.contains('-')) return null;
  final cleaned = raw.replaceAll(RegExp(r'[^0-9.,]'), '').replaceAll(',', '');
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  if (value == null || value.isNaN || value.isInfinite) return null;
  if (value < 0) return null;
  return (value * 100).round();
}

String _two(int value) => value.toString().padLeft(2, '0');

/// DD/MM/AAAA
String formatDate(DateTime date) =>
    '${_two(date.day)}/${_two(date.month)}/${date.year}';

/// AAAA-MM-DD (formato de almacenamiento)
String toIsoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${_two(date.month)}-${_two(date.day)}';

DateTime? parseIsoDate(String? value) {
  if (value == null || value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// "Nov 2026"
String formatPeriodShort(int year, int month) {
  final name = _mesesCortos[(month - 1).clamp(0, 11)];
  return '${name[0].toUpperCase()}${name.substring(1)} $year';
}

/// "noviembre 2026"
String formatPeriodLong(int year, int month) =>
    '${_mesesLargos[(month - 1).clamp(0, 11)]} $year';

/// "Noviembre 2026" (con mayúscula inicial, como en la referencia)
String formatPeriodTitle(int year, int month) {
  final name = formatPeriodLong(year, month);
  return name.isEmpty ? name : '${name[0].toUpperCase()}${name.substring(1)}';
}

/// "05/11/2026" o "—" si no hay fecha.
String formatDateOrDash(DateTime? date) =>
    date == null ? '—' : formatDate(date);

/// Cédula dominicana con separadores: 001-1234567-8
String formatCedula(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length != 11) return raw;
  return '${digits.substring(0, 3)}-${digits.substring(3, 10)}-'
      '${digits.substring(10)}';
}

/// Cédula parcialmente oculta para el recibo impreso.
///
/// El papel viaja fuera del sistema (el inquilino lo guarda, lo muestra, lo
/// bota) así que no se imprime el documento completo: solo los 3 primeros
/// dígitos y los 2 últimos, que bastan para identificar el comprobante.
/// `001-1234567-8` → `001-•••••••-78`. Si el valor no tiene 11 dígitos se
/// ocultan todos los dígitos salvo los dos últimos.
///
/// [hide] permite elegir el carácter de ocultación. En papel térmico se usa
/// `X` porque el punto volcado (`•`) viaja como el byte 0x07, que muchas
/// impresoras interpretan como BEL y no dibujan.
String maskCedula(String raw, {String hide = '•'}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  final dots = hide * 7;
  if (digits.length == 11) {
    return '${digits.substring(0, 3)}-$dots-${digits.substring(9)}';
  }
  final hidden = hide * 4;
  if (digits.length > 2) {
    return '$hidden${digits.substring(digits.length - 2)}';
  }
  if (digits.isEmpty) return hidden;
  return '$hidden$digits';
}

/// Fecha segura dentro del mes (evita 31 de febrero, etc.).
DateTime dayInMonth(int year, int month, int day) {
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day.clamp(1, lastDay));
}

/// Próxima ocurrencia del día de vencimiento (ajustada al último día del mes).
DateTime nextDueDateFor(DateTime today, int dueDay) {
  final current = dayInMonth(today.year, today.month, dueDay);
  if (!current.isBefore(DateTime(today.year, today.month, today.day))) {
    return current;
  }
  final next = DateTime(today.year, today.month + 1);
  return dayInMonth(next.year, next.month, dueDay);
}
