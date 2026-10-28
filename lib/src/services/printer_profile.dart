import '../data/models.dart';

/// Qué hacer al terminar de imprimir.
///
/// La 2C-P80-C (y las portátiles de 80 mm en general) **no** traen cortador:
/// el papel se rasga a mano en el borde dentado. Enviar `GS V` a un equipo sin
/// cortador puede atascarlo o dejar el trabajo a medias, así que el valor por
/// defecto es [manual] y solo se envía corte si alguna vez se verifica con el
/// auto-test del equipo que existe cortador.
enum CutMode { manual, autoCutter }

/// Perfil de impresión calibrado para un equipo concreto.
///
/// El punto crítico: **80 mm es el ancho del rollo, no el ancho imprimible**.
/// Las cifras publicadas (72 mm / 576 puntos, 79 mm / 640 puntos, …) varían
/// entre manuales y firmware. Por eso el ancho imprimible se guarda en **puntos
/// del cabezal** (`printableDots`) y se calibra con el auto-test del equipo o
/// con un ticket de calibración medido.
///
/// Mientras no haya calibración (`printableDots == 0`) se usa un valor
/// **conservador** (más angosto que el máximo teórico): así el contenido queda
/// centrado y nunca se recorta. Es preferible un margen pequeño a perder
/// dígitos del monto.
class PrinterProfile {
  const PrinterProfile({
    this.paperWidthMm = 80,
    this.printableDots = 0,
    this.marginDots = 0,
    this.baudRate = 9600,
    this.asciiOnly = false,
    this.cutMode = CutMode.manual,
  });

  /// Ancho nominal del rollo.
  final int paperWidthMm;

  /// Ancho imprimible **calibrado**, en puntos del cabezal (0 = sin calibrar).
  final int printableDots;

  /// Margen de contenido a cada lado, en puntos (0 = sin margen extra).
  final int marginDots;

  /// Velocidad del puerto serie (SPP). Las 2C/POS usan 9600 por defecto.
  final int baudRate;

  /// Imprime sin acentos (translitera a ASCII) para equipos que ignoran CP850.
  final bool asciiOnly;

  final CutMode cutMode;

  /// Resolución nominal indicada por el fabricante (203 dpi ≈ 8 puntos/mm).
  static const int dotsPerMm = 8;

  /// Ancho de un carácter de la fuente A en puntos (12 puntos ≈ 1,5 mm).
  static const int charWidthDots = 12;

  /// Altura de un carácter de la fuente A (para estimar el largo del ticket).
  static const int charHeightDots = 24;

  /// Ancho imprimible por defecto cuando no hay calibración.
  ///
  /// 80 mm → 576 puntos (72 mm) y 58 mm → 384 puntos (48 mm): son los valores
  /// estándar ESC/POS y, al ser menores que el máximo teórico, garantizan que
  /// el contenido entra centrado sin recortarse.
  static int defaultPrintableDots(int paperWidthMm) =>
      paperWidthMm == 58 ? 384 : 576;

  /// Puntos realmente utilizados (calibrado o conservador).
  int get effectivePrintableDots =>
      printableDots > 0 ? printableDots : defaultPrintableDots(paperWidthMm);

  /// `true` cuando alguien midió el ancho real con el auto-test.
  bool get isCalibrated => printableDots > 0;

  /// Ancho imprimible en milímetros.
  double get printableWidthMm => effectivePrintableDots / dotsPerMm;

  /// Margen de contenido en milímetros, a cada lado del papel.
  double get marginMm => marginDots / dotsPerMm;

  /// Margen mínimo para que el contenido quepa dentro del área imprimible.
  ///
  /// Es la mitad de lo que sobra entre el rollo y el área imprimible. En 80 mm
  /// sin calibrar: (80 − 72) / 2 = 4 mm.
  double get minMarginMm {
    final spare = (paperWidthMm - printableWidthMm) / 2;
    return spare <= 0 ? 0 : spare;
  }

  /// Margen efectivo a usar en el PDF: nunca menos de lo que exige el cabezal.
  double effectiveMarginMm(double configuredMarginMm) {
    final configured = configuredMarginMm < 0 ? 0.0 : configuredMarginMm;
    final withContentMargin = marginMm > configured ? marginMm : configured;
    return withContentMargin < minMarginMm ? minMarginMm : withContentMargin;
  }

  /// Columnas de la fuente A que caben de verdad.
  int get columns {
    final usable = effectivePrintableDots - (marginDots * 2);
    final cols = usable ~/ charWidthDots;
    // Fuera de rango = perfil mal calibrado: se acota a algo imprimible.
    return cols < 20 ? 20 : (cols > 80 ? 80 : cols);
  }

  /// Columnas disponibles con un tamaño de letra dado (1 = normal, 2 = doble).
  int columnsAt(int scale) {
    final cols = columns ~/ (scale < 1 ? 1 : scale);
    return cols < 10 ? 10 : cols;
  }

  /// Largo estimado del ticket en milímetros para un número de líneas.
  double estimatedHeightMm(int lines) =>
      (lines * charHeightDots) / dotsPerMm + 10;

  PrinterProfile copyWith({
    int? paperWidthMm,
    int? printableDots,
    int? marginDots,
    int? baudRate,
    bool? asciiOnly,
    CutMode? cutMode,
  }) {
    return PrinterProfile(
      paperWidthMm: paperWidthMm ?? this.paperWidthMm,
      printableDots: printableDots ?? this.printableDots,
      marginDots: marginDots ?? this.marginDots,
      baudRate: baudRate ?? this.baudRate,
      asciiOnly: asciiOnly ?? this.asciiOnly,
      cutMode: cutMode ?? this.cutMode,
    );
  }

  @override
  String toString() =>
      'PrinterProfile($paperWidthMm mm, dots=$printableDots '
      '($effectivePrintableDots efectivos = '
      '${printableWidthMm.toStringAsFixed(1)} mm), '
      'margen=${marginMm.toStringAsFixed(1)} mm, $columns columnas, '
      'baudios=$baudRate, corte=${cutMode.name})';
}

/// Perfil a partir de la configuración guardada.
extension OwnerSettingsPrinterProfile on OwnerSettings {
  PrinterProfile get printerProfile => PrinterProfile(
    paperWidthMm: receiptWidthMm,
    printableDots: printerPrintableDots,
    marginDots: printerMarginDots,
    baudRate: printerBaudRate,
    asciiOnly: asciiOnly,
  );
}
