/// Validaciones prácticas para el contexto dominicano. No bloquean casos
/// legítimos poco comunes (por ejemplo cédulas antiguas sin separadores),
/// solo detectan errores evidentes.
library;

import 'formatters.dart';

class FieldResult {
  const FieldResult(this.value, this.error);

  final String? value;
  final String? error;

  bool get isValid => error == null;
  static const FieldResult ok = FieldResult('', null);
}

/// Número o identificador de apartamento: obligatorio, 1..20 caracteres.
String? validateApartmentIdentifier(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return 'Escriba el número o identificador.';
  if (value.length > 20) return 'Máximo 20 caracteres.';
  if (!RegExp(r'^[0-9A-Za-zÁÉÍÓÚÜÑáéíóúüñ\-.\s]+$').hasMatch(value)) {
    return 'Use letras, números, guiones o puntos.';
  }
  return null;
}

/// Nombre de grupo/residencial: obligatorio, 2..40 caracteres.
String? validateGroupName(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return 'Escriba el nombre del residencial.';
  if (value.length < 2) return 'El nombre es demasiado corto.';
  if (value.length > 40) return 'Máximo 40 caracteres.';
  return null;
}

/// Nombre completo del inquilino.
String? validatePersonName(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return 'Escriba el nombre completo.';
  if (value.length < 3) return 'El nombre es demasiado corto.';
  if (value.length > 80) return 'Máximo 80 caracteres.';
  return null;
}

/// Monto de alquiler escrito por el usuario.
String? validateAmount(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return 'Escriba el monto.';
  final cents = parseAmountToCents(value);
  if (cents == null) return 'Monto no válido. Ejemplo: 8,500.00';
  if (cents <= 0) return 'El monto debe ser mayor que cero.';
  if (cents > 100000000) return 'El monto es demasiado alto.';
  return null;
}

/// Día de vencimiento (1..31). Se ajusta al último día del mes al calcular.
String? validateDueDay(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return 'Escriba el día de vencimiento.';
  final day = int.tryParse(value);
  if (day == null) return 'Use un número del 1 al 31.';
  if (day < 1 || day > 31) return 'Use un número del 1 al 31.';
  return null;
}

/// Cédula: 11 dígitos (con o sin guiones). Se acepta vacío (opcional).
String? validateCedula(String? raw, {bool required = false}) {
  final digits = (raw ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) {
    return required ? 'Escriba la cédula.' : null;
  }
  if (digits.length != 11) return 'La cédula debe tener 11 dígitos.';
  return null;
}

/// Teléfono: al menos 7 dígitos. Se acepta vacío (opcional).
String? validatePhone(String? raw, {bool required = false}) {
  final digits = (raw ?? '').replaceAll(RegExp(r'[^0-9]/'), '');
  final clean = digits.replaceAll(RegExp(r'[^0-9]'), '');
  if (clean.isEmpty) {
    return required ? 'Escriba el teléfono.' : null;
  }
  if (clean.length < 7) return 'El teléfono debe tener al menos 7 dígitos.';
  if (clean.length > 15) return 'El teléfono es demasiado largo.';
  return null;
}

/// Fecha de inicio/mudanza obligatoria.
String? validateRequiredDate(DateTime? date) =>
    date == null ? 'Seleccione una fecha.' : null;
