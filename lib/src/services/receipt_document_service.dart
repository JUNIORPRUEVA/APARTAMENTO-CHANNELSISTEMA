import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/formatters.dart';
import '../data/app_paths.dart';
import '../data/finance_models.dart';
import '../data/finance_repository.dart';
import 'printer_profile.dart';

class DocumentResult {
  const DocumentResult({required this.ok, this.path, this.error});

  final bool ok;
  final String? path;
  final String? error;

  static DocumentResult success(String path) =>
      DocumentResult(ok: true, path: path);

  static DocumentResult failure(String message) =>
      DocumentResult(ok: false, error: message);
}

/// Genera y mantiene los PDF de recibo (80 mm) fuera de la transacción.
///
/// * La ruta es determinista: `recibos<SERIE>-<número>.pdf`.
/// * Se escribe en un archivo temporal y se renombra (reemplazo atómico), así
///   que nunca queda un PDF a medias.
/// * Si el PDF falta o está corrupto, se regenera desde el **snapshot**
///   guardado en la base: no se crea ningún pago nuevo.
class ReceiptDocumentService {
  ReceiptDocumentService({
    required this.finance,
    required this.paths,
    required this.currentWidthMm,
    double Function()? currentMarginMm,
    PrinterProfile Function()? currentProfile,
  }) : _currentMarginMm = currentMarginMm,
       _currentProfile = currentProfile;

  final FinanceRepository finance;
  final AppPaths paths;

  /// Ancho del papel configurado en Ajustes (58 u 80 mm).
  final int Function() currentWidthMm;

  /// Margen imprimible configurado en Ajustes.
  final double Function()? _currentMarginMm;

  /// Perfil calibrado actual (ancho imprimible en puntos).
  final PrinterProfile Function()? _currentProfile;

  double get currentMarginMm =>
      (_currentMarginMm?.call() ?? 3.5).clamp(0.0, 15.0).toDouble();

  PrinterProfile get currentProfile =>
      _currentProfile?.call() ??
      PrinterProfile(
        paperWidthMm: currentWidthMm(),
        marginDots: (currentMarginMm * PrinterProfile.dotsPerMm).round(),
      );

  static pw.Font? _regular;
  static pw.Font? _bold;

  /// Carga una tipografía real de Windows (acentos correctos). Si no está
  /// disponible se usa la Helvetica integrada del paquete `pdf`.
  static Future<void> _ensureFonts() async {
    if (_regular != null) return;
    pw.Font? regular;
    pw.Font? bold;
    for (final candidate in const [
      r'C:\Windows\Fonts\segoeui.ttf',
      r'C:\Windows\Fonts\arial.ttf',
    ]) {
      final file = File(candidate);
      if (!file.existsSync()) continue;
      try {
        regular = pw.Font.ttf(ByteData.sublistView(file.readAsBytesSync()));
        break;
      } catch (_) {
        regular = null;
      }
    }
    for (final candidate in const [
      r'C:\Windows\Fonts\segoeuib.ttf',
      r'C:\Windows\Fonts\arialbd.ttf',
    ]) {
      final file = File(candidate);
      if (!file.existsSync()) continue;
      try {
        bold = pw.Font.ttf(ByteData.sublistView(file.readAsBytesSync()));
        break;
      } catch (_) {
        bold = null;
      }
    }
    _regular = regular ?? pw.Font.helvetica();
    _bold = bold ?? (regular == null ? pw.Font.helveticaBold() : _regular);
  }

  /// Construye el PDF a partir del snapshot inmutable. Puro y verificable en
  /// pruebas (no toca disco).
  static Future<Uint8List> buildPdf(
    ReceiptRecord record, {
    int widthMm = 80,
    double marginMm = 3.5,
    PrinterProfile? profile,
  }) async {
    await _ensureFonts();
    final font = _regular!;
    final bold = _bold!;

    final data = record.snapshot;
    final kind = record.kind;
    final paperWidth = widthMm == 58 ? 58 : 80;
    final width = paperWidth * PdfPageFormat.mm;
    // El margen nunca puede ser menor que lo que exige el cabezal: si el ancho
    // imprimible calibrado es 72 mm, un margen de 3,5 mm (73 mm útiles) se
    // recortaría a la derecha. Se toma el mayor de los dos.
    final effectiveProfile =
        profile ??
        PrinterProfile(
          paperWidthMm: paperWidth,
          marginDots: (marginMm * PrinterProfile.dotsPerMm).round(),
        );
    var margin = marginMm <= 0 ? 3.5 : (marginMm > 15 ? 15.0 : marginMm);
    if (effectiveProfile.paperWidthMm == paperWidth) {
      final required = effectiveProfile.effectiveMarginMm(margin);
      if (required > margin) margin = required;
    }
    final format = PdfPageFormat(
      width,
      double.infinity,
      marginAll: margin * PdfPageFormat.mm,
    );

    String text(String key) => (data[key]?.toString() ?? '').trim();
    int cents(String key) => int.tryParse(data[key]?.toString() ?? '') ?? 0;

    final issuerName = text('issuerName').isEmpty
        ? 'Control de Alquileres'
        : text('issuerName');
    final money = formatMoney(cents('amountCents'));
    final paymentDate = parseIsoDate(text('paymentDate'));
    final issuedAt = DateTime.tryParse(text('issuedAt')) ?? DateTime.now();

    pw.Widget line(String left, String right, {bool strong = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 18 * PdfPageFormat.mm,
              child: pw.Text(
                left,
                style: pw.TextStyle(font: strong ? bold : font, fontSize: 7),
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                right,
                style: pw.TextStyle(font: strong ? bold : font, fontSize: 7),
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget rule() => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
      child: pw.Divider(height: 0.5, thickness: 0.5, color: PdfColors.black),
    );

    final children = <pw.Widget>[
      pw.Center(
        child: pw.Text(
          issuerName,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: bold, fontSize: 9),
        ),
      ),
      if (text('issuerId').isNotEmpty)
        pw.Center(
          child: pw.Text(
            'RNC/Céd.: ${text('issuerId')}',
            style: pw.TextStyle(font: font, fontSize: 6.5),
          ),
        ),
      if (text('issuerAddress').isNotEmpty)
        pw.Center(
          child: pw.Text(
            text('issuerAddress'),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: font, fontSize: 6.5),
          ),
        ),
      if (text('issuerPhone').isNotEmpty)
        pw.Center(
          child: pw.Text(
            'Tel.: ${text('issuerPhone')}',
            style: pw.TextStyle(font: font, fontSize: 6.5),
          ),
        ),
      rule(),
      pw.Center(
        child: pw.Text(
          kind.title,
          style: pw.TextStyle(font: bold, fontSize: 8),
        ),
      ),
      pw.SizedBox(height: 1),
      pw.Center(
        child: pw.Text(
          'No. ${record.label}',
          style: pw.TextStyle(font: bold, fontSize: 8),
        ),
      ),
      pw.SizedBox(height: 1),
      pw.Center(
        child: pw.Text(
          'Emitido: ${formatDate(issuedAt)} '
          '${issuedAt.hour.toString().padLeft(2, '0')}:'
          '${issuedAt.minute.toString().padLeft(2, '0')}',
          style: pw.TextStyle(font: font, fontSize: 6.5),
        ),
      ),
      rule(),
      line('Residencial', text('groupName')),
      line('Apartamento', text('apartmentIdentifier')),
      if (text('apartmentLocation').isNotEmpty)
        line('Ubicación', text('apartmentLocation')),
      line('Inquilino', text('tenantName')),
      if (text('tenantCedula').isNotEmpty)
        line('Cédula', maskCedula(text('tenantCedula'))),
      rule(),
    ];

    if (kind == ReceiptKind.alquiler) {
      children.addAll([
        line('Concepto', text('concept')),
        line('Período', text('periodLabel')),
        line('Vence', formatDateOrDash(parseIsoDate(text('dueDate')))),
        line('Método', text('method')),
        if (text('reference').isNotEmpty) line('Referencia', text('reference')),
        line('Fecha pago', formatDateOrDash(paymentDate)),
      ]);
    } else if (kind == ReceiptKind.deposito) {
      children.addAll([
        line('Concepto', text('depositKindLabel')),
        line('Fecha', formatDateOrDash(paymentDate)),
        line('Depósito retenido', formatMoney(cents('heldAfterCents'))),
        if (text('note').isNotEmpty) line('Motivo', text('note')),
      ]);
    } else {
      children.addAll([
        line('Anula recibo', text('originalReceipt')),
        line('Fecha pago', formatDateOrDash(paymentDate)),
        line('Motivo', text('voidReason')),
        line('Período', text('periodLabel')),
      ]);
    }

    children.addAll([
      rule(),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text('MONTO', style: pw.TextStyle(font: bold, fontSize: 8)),
          pw.Text(money, style: pw.TextStyle(font: bold, fontSize: 11)),
        ],
      ),
      if (kind == ReceiptKind.alquiler)
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Saldo del período',
              style: pw.TextStyle(font: font, fontSize: 7),
            ),
            pw.Text(
              formatMoney(cents('balanceAfterCents')),
              style: pw.TextStyle(font: font, fontSize: 7),
            ),
          ],
        ),
      if (kind != ReceiptKind.deposito && text('note').isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: pw.Text(
            'Obs.: ${text('note')}',
            style: pw.TextStyle(font: font, fontSize: 6.5),
          ),
        ),
      rule(),
      pw.Center(
        child: pw.Text(
          'Conserve este recibo',
          style: pw.TextStyle(font: bold, fontSize: 7),
        ),
      ),
      pw.Center(
        child: pw.Text(
          'Documento de control interno. No es comprobante fiscal (NCF).',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: font, fontSize: 5.8),
        ),
      ),
    ]);

    final document = pw.Document(
      title: '${kind.title} ${record.label}',
      producer: 'Control de Alquileres',
    );
    document.addPage(
      pw.Page(
        pageFormat: format,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
    return document.save();
  }

  /// Nombre de archivo determinista y seguro.
  static String fileNameFor(ReceiptRecord record) {
    final series = record.series.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return '$series-${record.number.toString().padLeft(8, '0')}.pdf';
  }

  /// `true` si el snapshot tiene lo mínimo para imprimir un documento fiel.
  static bool _snapshotIsUsable(Map<String, Object?> snapshot) {
    if (snapshot.isEmpty) return false;
    final amount = snapshot['amountCents'];
    final number = snapshot['number'];
    final tenant = (snapshot['tenantName']?.toString() ?? '').trim();
    return amount != null && number != null && tenant.isNotEmpty;
  }

  String pathFor(ReceiptRecord record) =>
      p.join(paths.receiptsDir, fileNameFor(record));

  /// Ticket de **calibración** en PDF (para imprimir por la cola de Windows).
  ///
  /// Muestra bordes al límite del área imprimible, un renglón en cada
  /// alineación, la escala de columnas, acentos y montos en RD$, más los datos
  /// del perfil. Con una regla se comprueba si el equipo imprime los 80 mm
  /// completos o solo una parte, y se ajusta el ancho útil en Ajustes.
  Future<Uint8List> buildCalibrationDocument({
    PrinterProfile? profile,
    String model = '',
  }) async {
    await _ensureFonts();
    final font = _regular!;
    final bold = _bold!;
    final p = profile ?? currentProfile;
    final margin = p.effectiveMarginMm(0);
    final format = PdfPageFormat(
      p.paperWidthMm * PdfPageFormat.mm,
      double.infinity,
      marginAll: margin * PdfPageFormat.mm,
    );
    final now = DateTime.now();
    final document = pw.Document(
      title: 'Calibración de impresora',
      producer: 'Control de Alquileres',
    );
    document.addPage(
      pw.Page(
        pageFormat: format,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                'PRUEBA DE IMPRESORA · NO ES UN PAGO',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(font: bold, fontSize: 8.5),
              ),
            ),
            pw.Center(
              child: pw.Text(
                'No afecta saldos ni numeración de recibos',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(font: font, fontSize: 6.5),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(
                'CALIBRACIÓN',
                style: pw.TextStyle(font: bold, fontSize: 9),
              ),
            ),
            pw.Center(
              child: pw.Text(
                model.trim().isEmpty ? 'Impresora térmica' : model.trim(),
                style: pw.TextStyle(font: font, fontSize: 7),
              ),
            ),
            pw.Center(
              child: pw.Text(
                '${formatDate(now)} '
                '${now.hour.toString().padLeft(2, '0')}:'
                '${now.minute.toString().padLeft(2, '0')}',
                style: pw.TextStyle(font: font, fontSize: 6.5),
              ),
            ),
            pw.SizedBox(height: 3),
            // Marco: si falta algún lado, el área imprimible es menor.
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(width: 1, color: PdfColors.black),
              ),
              padding: const pw.EdgeInsets.all(2),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(
                    'IZQUIERDA',
                    style: pw.TextStyle(font: font, fontSize: 7),
                  ),
                  pw.Center(
                    child: pw.Text(
                      'CENTRO',
                      style: pw.TextStyle(font: font, fontSize: 7),
                    ),
                  ),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text(
                      'DERECHA',
                      style: pw.TextStyle(font: font, fontSize: 7),
                    ),
                  ),
                  pw.Text(
                    '-' * p.columns,
                    style: pw.TextStyle(font: font, fontSize: 6),
                  ),
                  pw.Text(
                    'Acentos: áéíóú ÁÉÍÓÚ ñÑ üÜ ¿¡',
                    style: pw.TextStyle(font: font, fontSize: 7),
                  ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Normal',
                        style: pw.TextStyle(font: font, fontSize: 7),
                      ),
                      pw.Text(
                        'RD\$ 8,500.00',
                        style: pw.TextStyle(font: font, fontSize: 7),
                      ),
                    ],
                  ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Doble',
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'RD\$ 9,750',
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              'Papel: ${p.paperWidthMm} mm · '
              'ancho útil: ${p.printableWidthMm.toStringAsFixed(1)} mm '
              '(${p.effectivePrintableDots} puntos)',
              style: pw.TextStyle(font: font, fontSize: 6.5),
            ),
            pw.Text(
              'Columnas: ${p.columns} · Calibrado: '
              '${p.isCalibrated ? 'sí' : 'no (valor conservador)'}',
              style: pw.TextStyle(font: font, fontSize: 6.5),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Si el marco no sale completo, reduzca el ancho útil en '
              'Ajustes (Avanzado) hasta que entre entero.',
              style: pw.TextStyle(font: font, fontSize: 6.2),
            ),
          ],
        ),
      ),
    );
    return document.save();
  }

  /// Asegura que el PDF exista y esté sano. Idempotente.
  Future<DocumentResult> ensure(
    ReceiptRecord record, {
    bool force = false,
  }) async {
    try {
      // Un snapshot vacío o ilegible significa que el documento no se puede
      // reconstruir con fidelidad: es preferible un fallo explícito a imprimir
      // un recibo en blanco (o con datos de otro movimiento).
      if (!_snapshotIsUsable(record.snapshot)) {
        finance.markReceiptPdf(
          receiptId: record.id,
          status: 'fallido',
          error: 'El contenido guardado del recibo está incompleto.',
        );
        return DocumentResult.failure(
          'El recibo ${record.label} no tiene contenido guardado y no se '
          'puede generar.',
        );
      }

      final target = File(pathFor(record));
      if (!force &&
          target.existsSync() &&
          target.lengthSync() > 700 &&
          record.pdfStatus == 'generado') {
        return DocumentResult.success(target.path);
      }

      final bytes = await buildPdf(
        record,
        widthMm: currentWidthMm(),
        marginMm: currentMarginMm,
        profile: currentProfile,
      );
      if (bytes.length < 700) {
        throw StateError('El PDF generado está vacío.');
      }

      Directory(paths.receiptsDir).createSync(recursive: true);
      final temp = File('${target.path}.tmp');
      temp.writeAsBytesSync(bytes, flush: true);
      // Reemplazo atómico: el archivo final nunca queda a medias.
      temp.renameSync(target.path);

      finance.markReceiptPdf(
        receiptId: record.id,
        status: 'generado',
        path: target.path,
      );
      return DocumentResult.success(target.path);
    } catch (error) {
      finance.markReceiptPdf(
        receiptId: record.id,
        status: 'fallido',
        error: error.toString(),
      );
      return DocumentResult.failure(
        'No se pudo generar el recibo ${record.label}.',
      );
    }
  }

  /// Regenera pendientes y detecta PDF borrados o dañados. Devuelve el número
  /// de documentos que siguen sin poder generarse.
  Future<int> recoverPending() async {
    var failures = 0;
    for (final record in finance.receiptsNeedingPdf()) {
      final result = await ensure(record);
      if (!result.ok) failures++;
    }
    return failures;
  }

  /// Comprueba que los PDF marcados como generados sigan en disco.
  Future<int> verifyExisting({int limit = 200}) async {
    var repaired = 0;
    for (final record in finance.receiptsWithGeneratedPdf(limit: limit)) {
      final file = File(pathFor(record));
      if (file.existsSync() && file.lengthSync() > 700) continue;
      final result = await ensure(record, force: true);
      if (result.ok) repaired++;
    }
    return repaired;
  }
}
