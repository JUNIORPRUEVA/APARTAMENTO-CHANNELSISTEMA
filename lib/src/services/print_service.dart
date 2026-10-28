import 'dart:io';
import 'dart:typed_data';

import 'package:printing/printing.dart';

import '../data/finance_models.dart';
import '../data/models.dart';
import 'escpos.dart';
import 'printer_profile.dart';
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
    PrinterProfile profile = const PrinterProfile(),
  });

  /// Ticket de calibración: mide el ancho real y comprueba acentos y alineado.
  Future<PrintResult> printCalibration({
    required String port,
    PrinterProfile profile = const PrinterProfile(),
    String model = '',
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
    PrinterProfile profile = const PrinterProfile(),
  }) {
    final bytes = EscPosReceipt.build(record, profile: profile);
    return _send(port, profile.baudRate, bytes);
  }

  @override
  Future<PrintResult> printCalibration({
    required String port,
    PrinterProfile profile = const PrinterProfile(),
    String model = '',
    String note = '',
  }) {
    final bytes = EscPosReceipt.buildCalibration(
      profile: profile,
      model: model.trim().isEmpty ? 'Impresora termica' : model.trim(),
      note: note,
    );
    return _send(port, profile.baudRate, bytes);
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
      return PrintResult(
        ok: true,
        message:
            'Enviado a la impresora ($port). No hay confirmación del '
            'dispositivo: revise el papel.',
      );
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
    var text = error.toString();
    for (final prefix in const ['Exception: ', 'AppFailure: ']) {
      if (text.startsWith(prefix)) text = text.substring(prefix.length);
    }
    return text;
  }
}

/// Resultado de buscar la impresora configurada en el equipo.
class PrinterDetection {
  const PrinterDetection({
    required this.found,
    this.kind,
    this.endpoint,
    this.label = '',
    this.message = '',
  });

  final bool found;
  final PrinterKind? kind;

  /// Cola de Windows o `COM5`.
  final String? endpoint;

  /// Nombre para mostrar (incluye el nombre amistoso del puerto si se conoce).
  final String label;

  /// Mensaje en español listo para el aviso.
  final String message;

  static const PrinterDetection missing = PrinterDetection(
    found: false,
    message: 'No se encontró la impresora. Revise Bluetooth.',
  );
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

  static final RegExp _comPattern = RegExp(r'^COM\d+$', caseSensitive: false);

  Future<List<PrinterRef>> printers() async {
    final windows = await gateway.listPrinters();
    final ports = await serialGateway.listPorts();
    return [
      ...windows,
      for (final port in ports)
        PrinterRef(
          name: port.label,
          isDefault: false,
          kind: PrinterKind.serialCom,
          target: port.name,
          detail: port.detail,
        ),
    ];
  }

  /// Decide por dónde imprimir, sin adivinar.
  ///
  /// En modo `auto` el orden es: destino ya configurado (COM o cola) → único
  /// puerto serie de tipo Bluetooth presente → nada (y se avisa). Nunca se
  /// elige una impresora al azar entre varias.
  Future<PrinterDetection> detect(OwnerSettings settings) async {
    final target = (settings.printerTarget ?? '').trim();
    final wanted = settings.printerTransport;

    // Modo Windows sin destino: se usa el diálogo del sistema (no es una
    // impresora "detectada", pero sí un camino válido para imprimir).
    if (wanted == PrinterTransport.windows && target.isEmpty) {
      return const PrinterDetection(
        found: true,
        kind: PrinterKind.windowsQueue,
        endpoint: null,
        label: 'diálogo de Windows',
        message:
            'Se abrirá el diálogo de impresión de Windows para elegir '
            'impresora.',
      );
    }

    if (wanted != PrinterTransport.serial && target.isNotEmpty) {
      final queues = await gateway.listPrinters();
      if (queues.any((queue) => queue.endpoint == target)) {
        return PrinterDetection(
          found: true,
          kind: PrinterKind.windowsQueue,
          endpoint: target,
          label: target,
          message: 'Impresora lista: $target.',
        );
      }
    }

    final ports = await serialGateway.listPorts();
    if (target.isNotEmpty) {
      final match = ports.where(
        (port) => port.name.toUpperCase() == target.toUpperCase(),
      );
      if (match.isNotEmpty) {
        return PrinterDetection(
          found: true,
          kind: PrinterKind.serialCom,
          endpoint: match.first.name,
          label: match.first.label,
          message: 'Impresora lista: ${match.first.label}.',
        );
      }
      // El destino dice COM pero el puerto no existe (desemparejada, apagada).
      if (_comPattern.hasMatch(target)) {
        return PrinterDetection(
          found: false,
          message:
              'El puerto $target no está disponible. Revise que la impresora '
              'esté encendida y emparejada por Bluetooth.',
        );
      }
      return const PrinterDetection(
        found: false,
        message:
            'No se encontró la impresora seleccionada. Revise Bluetooth o '
            'elija otra en Ajustes.',
      );
    }

    if (wanted == PrinterTransport.windows) {
      return const PrinterDetection(
        found: false,
        message:
            'No hay impresora elegida en Windows. Selecciónela en Ajustes.',
      );
    }

    // Modo automático sin destino: solo si hay UN puerto Bluetooth claro.
    final bluetoothPorts = ports
        .where((port) => port.likelyBluetooth && port.canSend)
        .toList(growable: false);
    if (bluetoothPorts.length == 1) {
      final only = bluetoothPorts.first;
      return PrinterDetection(
        found: true,
        kind: PrinterKind.serialCom,
        endpoint: only.name,
        label: only.label,
        message: 'Impresora lista: ${only.label}.',
      );
    }
    if (bluetoothPorts.length > 1) {
      return const PrinterDetection(
        found: false,
        message: 'Hay varios puertos Bluetooth. Elija la impresora en Ajustes.',
      );
    }
    return PrinterDetection.missing;
  }

  /// Imprime el recibo según la configuración guardada.
  ///
  /// * Puerto serie: envía ESC/POS y deja el PDF generado igualmente.
  /// * Cola de Windows: envía el PDF a la cola configurada.
  /// * Sin destino: abre el diálogo de impresión de Windows (única ventana).
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

    final route = await detect(settings);
    if (!route.found) {
      return PrintResult(
        ok: false,
        message:
            '${route.message} El cobro está guardado y el recibo quedó en el '
            'historial para reimprimir.',
      );
    }

    if (route.kind == PrinterKind.serialCom) {
      return serialGateway.printReceipt(
        record,
        port: route.endpoint!,
        profile: settings.printerProfile,
      );
    }

    try {
      final bytes = await File(path).readAsBytes();
      final result = await gateway.print(
        pdfBytes: bytes,
        printerName: route.endpoint,
        jobName: 'Recibo ${record.label}',
      );
      if (!result.ok) return result;
      return PrintResult(
        ok: true,
        message: route.endpoint == null
            ? 'Recibo enviado al diálogo de impresión de Windows.'
            : 'Enviado a la impresora (${route.endpoint}). No hay '
                  'confirmación del dispositivo: revise el papel.',
      );
    } catch (_) {
      return const PrintResult(
        ok: false,
        message: 'El cobro está guardado, pero el recibo no se pudo leer.',
      );
    }
  }

  /// Ticket de calibración con la configuración indicada (no guarda nada).
  ///
  /// En cola de Windows se imprime un PDF con reglas y montos; en puerto serie
  /// se envía el ticket ESC/POS nativo, que es el que permite **medir** con una
  /// regla el ancho real y ajustar el perfil.
  Future<PrintResult> printCalibration(
    OwnerSettings settings, {
    String model = '2C-P80-C',
  }) async {
    final route = await detect(settings);
    if (!route.found) {
      return PrintResult(ok: false, message: route.message);
    }
    final profile = settings.printerProfile;

    if (route.kind == PrinterKind.serialCom) {
      return serialGateway.printCalibration(
        port: route.endpoint!,
        profile: profile,
        model: model,
      );
    }

    final bytes = await documents.buildCalibrationDocument(
      profile: profile,
      model: model,
    );
    return gateway.print(
      pdfBytes: bytes,
      printerName: route.endpoint,
      jobName: 'Calibración de impresora',
    );
  }
}
