import 'portfolio_repository.dart';

/// Datos de DEMOSTRACIÓN para validación visual. Se marcan con `is_demo = 1`
/// y se pueden eliminar desde Configuración.
///
/// Importante: **no se crean pagos, recibos ni depósitos de demostración**,
/// porque un cobro simulado podría confundirse con dinero real. El historial
/// de pagos de la pantalla de Inicio muestra una vista previa claramente
/// etiquetada que no proviene de esta base de datos.
class DemoSeed {
  const DemoSeed(this._portfolio);

  final PortfolioRepository _portfolio;

  /// Siembra solo si la base está vacía de grupos.
  void maybeSeed() {
    if (_portfolio.hasGroups) return;

    final anamelia = _portfolio.createGroup('Anamelia', isDemo: true);
    final villaCerro = _portfolio.createGroup('Villa Cerro', isDemo: true);
    final anamulla = _portfolio.createGroup('Anamulla', isDemo: true);

    final apartamentos = <({int group, String id, String location, int rent})>[
      (group: anamelia, id: '101', location: 'Primer nivel', rent: 850000),
      (group: anamelia, id: '102', location: 'Primer nivel', rent: 850000),
      (group: anamelia, id: '103', location: 'Primer nivel', rent: 850000),
      (group: anamelia, id: '104', location: 'Segundo nivel', rent: 900000),
      (group: anamelia, id: '105', location: 'Segundo nivel', rent: 900000),
      (group: anamelia, id: '106', location: 'Segundo nivel', rent: 850000),
      (group: anamelia, id: '107', location: 'Tercer nivel', rent: 850000),
      (group: anamelia, id: '108', location: 'Tercer nivel', rent: 900000),
      (group: villaCerro, id: '201', location: 'Planta baja', rent: 750000),
      (group: villaCerro, id: '202', location: 'Planta baja', rent: 750000),
      (group: villaCerro, id: '203', location: 'Planta alta', rent: 800000),
      (group: anamulla, id: '301', location: 'Bloque A', rent: 950000),
      (group: anamulla, id: '302', location: 'Bloque B', rent: 950000),
    ];

    final creados = <String, int>{};
    for (final item in apartamentos) {
      final id = _portfolio.createApartment(
        groupId: item.group,
        identifier: item.id,
        location: item.location,
        rentCents: item.rent,
        isDemo: true,
      );
      creados[item.id] = id;
    }

    // Contratos vigentes de ejemplo (sin pagos asociados).
    _contrato(
      creados['101'],
      nombre: 'María Pérez',
      cedula: '00112345678',
      telefono: '809-555-0123',
      ingreso: DateTime(2026, 1, 5),
      renta: 850000,
    );
    _contrato(
      creados['102'],
      nombre: 'José Ramírez',
      cedula: '00198765432',
      telefono: '829-555-0456',
      ingreso: DateTime(2026, 2, 5),
      renta: 850000,
    );
    _contrato(
      creados['104'],
      nombre: 'Carmen Cruz',
      cedula: '00176543210',
      telefono: '849-555-0789',
      ingreso: DateTime(2026, 1, 10),
      renta: 900000,
    );
    _contrato(
      creados['105'],
      nombre: 'Luis Martínez',
      cedula: '00144455566',
      telefono: '809-555-0321',
      ingreso: DateTime(2026, 3, 5),
      renta: 900000,
    );
    _contrato(
      creados['107'],
      nombre: 'Ana Rodríguez',
      cedula: '00133344455',
      telefono: '829-555-0654',
      ingreso: DateTime(2026, 4, 5),
      renta: 850000,
    );
    _contrato(
      creados['201'],
      nombre: 'Pedro Santana',
      cedula: '00122233344',
      telefono: '809-555-0987',
      ingreso: DateTime(2026, 5, 5),
      renta: 750000,
    );
  }

  void _contrato(
    int? apartmentId, {
    required String nombre,
    required String cedula,
    required String telefono,
    required DateTime ingreso,
    required int renta,
  }) {
    if (apartmentId == null) return;
    _portfolio.registerTenantAndLease(
      apartmentId: apartmentId,
      fullName: nombre,
      cedula: cedula,
      phone: telefono,
      moveInDate: ingreso,
      rentCents: renta,
      dueDay: 5,
      isDemo: true,
    );
  }
}

/// Vista previa del historial de pagos de la interfaz (NO son pagos reales).
class DemoPaymentPreview {
  const DemoPaymentPreview({
    required this.date,
    required this.period,
    required this.periodKey,
    required this.concept,
    required this.amountCents,
    required this.method,
  });

  final DateTime date;
  final String period;
  final String periodKey;
  final String concept;
  final int amountCents;
  final String method;

  /// Filas de ejemplo que reproducen el diseño aprobado. Se muestran con la
  /// etiqueta "Demostración" y nunca se guardan en la base de datos.
  static List<DemoPaymentPreview> rowsFor(int apartmentId) {
    final current = DateTime.now();
    // El pago de hoy corresponde al período siguiente (renta adelantada).
    final next = DateTime(current.year, current.month + 1);
    DateTime monthBack(int months) =>
        DateTime(current.year, current.month - months);
    const concept = 'Alquiler';
    return <DemoPaymentPreview>[
      DemoPaymentPreview(
        date: DateTime(current.year, current.month, current.day),
        period: _short(next.year, next.month),
        periodKey: '${next.year}-${next.month}',
        concept: concept,
        amountCents: 850000,
        method: 'Efectivo',
      ),
      for (var i = 0; i <= 3; i++)
        DemoPaymentPreview(
          date: DateTime(monthBack(i).year, monthBack(i).month, 5),
          period: _short(monthBack(i).year, monthBack(i).month),
          periodKey: '${monthBack(i).year}-${monthBack(i).month}',
          concept: concept,
          amountCents: 850000,
          method: i.isOdd ? 'Transferencia' : 'Efectivo',
        ),
    ];
  }

  static String _short(int year, int month) {
    const names = <String>[
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    return '${names[(month - 1).clamp(0, 11)]} $year';
  }
}
