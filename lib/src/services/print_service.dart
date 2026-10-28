import 'dart:io';
import 'dart:typed_data';

import 'package:printing/printing.dart';

import '../data/finance_models.dart';
import '../data/models.dart';
import 'escpos.dart';
import 'receipt_document_service.dart';
import 'serial_transport.dart';

/// Cómo se entrega el trabajo a la impresora.
enum PrinterKind {
  /// Impresora instalada en Windows (cola del spooler).
  windowsQueue,

  /// Impresora Bluetooth expuesta como puerto serie (SPP / RFCOMM).
  serialCom,
}

class PrinterRef {
  const PrinterRef({
    required this.name,
    required this.isDefault,
    this.kind = PrinterKind.windowsQueue,
    this.target,
    this.detail = '',
  });

  /// Texto que ve el usuario.
  final String name;
  final bool isDefault;
  final PrinterKind kind;

  /// Nombre real: cola de Windows o `COM5`.
  final String? target;

  /// Aclaración breve (por ejemplo "Bluetooth probable").
  final String detail;

  String get endpoint => target ?? name;
}

class PrintResult {
  const PrintResult({required this.ok, this.message = ''});

  final bool ok;
  final String message;

  static const PrintResult success = PrintResult(ok: true);
}

/// Punto de salida hacia Windows. Se abstrae para poder probar el flujo
/// (éxito y fallo) sin una impresora física.
abstract interface class PrintGateway {
  Future<List<PrinterRef>> listPrinters();

  Future<PrintResult> print({
    required Uint8List pdfBytes,
    required String? printerName,
    required String jobName,
  });
}

/// Implementación real con el complemento `printing` (spooler de Windows).
///
/// El tamaño del papel lo define el propio PDF (80 mm), de modo que el driver
/// no escala a A4. Si hay una impresora configurada se envía directo a ella;
/// si no, se abre el diálogo de impresión de Windows.
class WindowsPrintGateway implements PrintGateway {
  const WindowsPrintGateway();

  @override
  Future<List<PrinterRef>> listPrinters() async {
    try {
      final printers = await Printing.listPrinters();
      return [
        for (final printer in printers)
          PrinterRef(
            name: printer.name,
            isDefault: printer.isDefault,
            kind: PrinterKind.windowsQueue,
            target: printer.name,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<PrintResult> print({
    required Uint8List pdfBytes,
    required String? printerName,
    required String jobName,
  }) async {
    try {
      if (printerName == null || printerName.trim().isEmpty) {
        await Printing.layoutPdf(
          onLayout: (_) async => pdfBytes,
          name: jobName,
        );
        return PrintResult.success;
      }

      final printers = await Printing.listPrinters();
      Printer? target;
      for (final printer in printers) {
        if (printer.name == printerName) target = printer;
      }
      if (target == null) {
        return const PrintResult(
          ok: false,
          message:
              'La impresora configurada no está disponible. '
              'El pago está guardado.',
        );
      }

      final sent = await Printing.directPrintPdf(
        printer: target,
        onLayout: (_) async => pdfBytes,
        name: jobName,
      );
      return sent
          ? PrintResult.success
          : const PrintResult(
              ok: false,
              message:
                  'La impresora no aceptó el trabajo. El pago está guardado.',
            );
    } catch (_) {
      return const PrintResult(
        ok: false,
        message: 'No se pudo imprimir. El pago está guardado.',
      );
    }
  }
}

/// Punto de salida hacia una impresora conectada por puerto serie
/// (Bluetooth SPP emparejado como `COM`).
abstract interface class SerialPrintGateway {
  Future<List<ComPort>> listPorts();

  Future<PrintResult> printReceipt(
    ReceiptRecord record, {
    required String port,
    int baudRate = 9600,
    int widthMm = 80,
    bool asciiOnly = false,
  });

  /// Hoja de prueba: verifica que el puerto responde y cómo salen los acentos.
  Future<PrintResult> printTestPage({
    required String port,
    int baudRate = 9600,
    int widthMm = 80,
    bool asciiOnly = false,
    String note = '',
  });
}

/// Implementación real: arma los bytes ESC/POS y los escribe en el puerto.
///
/// Nunca lanza: cualquier fallo se devuelve como [PrintResult] con un mensaje
/// en español, porque imprimir jamás debe tumbar un cobro ya guardado.
class Win32SerialPrintGateway implements SerialPrintGateway {
  Win32SerialPrintGateway({SerialTransport? transport})
    : _transport = transport ?? const Win32SerialTransport();

  final SerialTransport _transport;

  @override
  Future<List<ComPort>> listPorts() => _transport.listPorts();

  @override
  Future<PrintResult> printReceipt(
    ReceiptRecord record, {
    required String port,
    int baudRate = 9600,
    int widthMm = 80,
    bool asciiOnly = false,
  }) {
    final bytes = EscPosReceipt.build(
      record,
      widthMm: widthMm,
      asciiOnly: asciiOnly,
    );
    return _send(port, baudRate, bytes);
  }

  @override
  Future<PrintResult> printTestPage({
    required String port,
    int baudRate = 9600,
    int widthMm = 80,
    bool asciiOnly = false,
    String note = '',
  }) {
    final cols = EscPosReceipt.columnsFor(widthMm);
    final lines = <String>[
      'CONTROL DE ALQUILERES',
      'Prueba de impresora',
      '-' * cols,
      'Puerto: $port - $baudRate baudios',
      'Papel: $widthMm mm - $cols columnas',
      'Acentos: áéíóú ñÑ ¿¡ RD\$ 1,500.00',
      '-' * cols,
      'Si lee esta línea, la impresora responde.',
      'Si el texto sale con símbolos raros, marque',
      '"Imprimir sin acentos" en Ajustes.',
      if (note.trim().isNotEmpty) note.trim(),
    ];
    final buffer = <int>[0x1B, 0x40];
    if (!asciiOnly) buffer.addAll([0x1B, 0x74, 0x02]);
    for (final line in lines) {
      buffer.addAll(EscPosText.encode(line, asciiOnly: asciiOnly));
      buffer.add(0x0A);
    }
    buffer.addAll([0x1B, 0x64, 0x04]);
    buffer.addAll([0x1D, 0x56, 0x42, 0x00]);
    return _send(port, baudRate, Uint8List.fromList(buffer));
  }

  Future<PrintResult> _send(String port, int baudRate, Uint8List bytes) async {
    if (port.trim().isEmpty) {
      return const PrintResult(
        ok: false,
        message:
            'No hay un puerto serie configurado. El cobro está guardado '
            'y puede imprimirse luego desde el historial.',
      );
    }
    try {
      await _transport.send(port, bytes, baudRate: baudRate);
      return PrintResult(ok: true, message: 'Enviado a la impresora ($port).');
    } catch (error) {
      return PrintResult(
        ok: false,
        message:
            '${_cleanMessage(error)} El cobro está guardado '
            'y puede reimprimirse desde el historial.',
      );
    }
  }

  static String _cleanMessage(Object error) {
    final text = error.toString();
    if (text.startsWith('Exception: ')) return text.substring(11);
    return text;
  }
}

/// Commit → PDF → impresión. La impresión nunca forma parte de la transacción
/// y jamás revierte un cobro ya confirmado.
class ReceiptPrintService {
  ReceiptPrintService({
    required this.documents,
    required this.gateway,
    SerialPrintGateway? serialGateway,
  }) : serialGateway = serialGateway ?? Win32SerialPrintGateway();

  final ReceiptDocumentService documents;

  /// Salida a la cola de Windows (PDF).
  final PrintGateway gateway;

  /// Salida a puerto serie con ESC/POS.
  final SerialPrintGateway serialGateway;

  Future<List<PrinterRef>> printers() async {
    final windows = await gateway.listPrinters();
    final ports = await serialGateway.listPorts();
    return [
      ...windows,
      for (final port in ports)
        PrinterRef(
          name: port.name,
          isDefault: false,
          kind: PrinterKind.serialCom,
          target: port.name,
          detail: port.likelyBluetooth ? 'Bluetooth probable' : 'Puerto serie',
        ),
    ];
  }

  /// Imprime el recibo según la configuración guardada.
  ///
  /// * Transporte `serial`: envía ESC/POS al puerto y, además, deja el PDF
  ///   generado para que el recibo exista aunque la impresora falle.
  /// * Transporte `windows`: envía el PDF a la cola configurada.
  /// * Sin destino configurado: abre el diálogo de impresión de Windows (el
  ///   único caso donde aparece una ventana; nunca ocurre en el cobro).
  Future<PrintResult> printReceipt(
    ReceiptRecord record, {
    required OwnerSettings settings,
  }) async {
    final document = await documents.ensure(record);
    final path = document.path;
    if (!document.ok || path == null) {
      return const PrintResult(
        ok: false,
        message: 'El cobro está guardado, pero no se pudo preparar el recibo.',
      );
    }

    if (settings.printerTransport == PrinterTransport.serial) {
      final port = (settings.printerTarget ?? '').trim();
      if (port.isEmpty) {
        return const PrintResult(
          ok: false,
          message:
              'No hay puerto serie configurado. El cobro está guardado y el '
              'PDF quedó disponible en el historial.',
        );
      }
      return serialGateway.printReceipt(
        record,
        port: port,
        widthMm: settings.receiptWidthMm,
        asciiOnly: settings.asciiOnly,
      );
    }

    try {
      final bytes = await File(path).readAsBytes();
      final result = await gateway.print(
        pdfBytes: bytes,
        printerName: (settings.printerTarget ?? settings.printerName),
        jobName: 'Recibo ${record.label}',
      );
      if (!result.ok) return result;
      return const PrintResult(ok: true, message: 'Enviado a la impresora.');
    } catch (_) {
      return const PrintResult(
        ok: false,
        message: 'El cobro está guardado, pero el recibo no se pudo leer.',
      );
    }
  }

  /// Hoja de prueba con la configuración actual. No guarda nada.
  Future<PrintResult> printTestPage(OwnerSettings settings) async {
    if (settings.printerTransport == PrinterTransport.serial) {
      return serialGateway.printTestPage(
        port: (settings.printerTarget ?? '').trim(),
        widthMm: settings.receiptWidthMm,
        asciiOnly: settings.asciiOnly,
      );
    }
    final name = (settings.printerTarget ?? settings.printerName) ?? '';
    if (name.trim().isEmpty) {
      return const PrintResult(
        ok: false,
        message: 'Elija una impresora para la prueba.',
      );
    }
    return gateway.print(
      pdfBytes: await documents.buildTestDocument(),
      printerName: name,
      jobName: 'Prueba de impresora',
    );
  }
}
