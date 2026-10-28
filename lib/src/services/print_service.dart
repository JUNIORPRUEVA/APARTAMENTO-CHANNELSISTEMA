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
    this.isAvailable = true,
  });

  /// Texto que ve el usuario.
  final String name;
  final bool isDefault;
  final PrinterKind kind;

  /// Nombre real: cola de Windows o `COM5`.
  final String? target;

  /// Aclaración breve (por ejemplo "Bluetooth probable").
  final String detail;

  /// `false` cuando Windows la reporta desconectada (se ignora al imprimir).
  final bool isAvailable;

  String get endpoint => target ?? name;
}

class PrintResult {
  const PrintResult({required this.ok, this.message = ''});

  final bool ok;
  final String message;

  static const PrintResult success = PrintResult(ok: true);
}

/// Resultado de un intento **automático**: incluye qué impresora respondió,
/// para que la aplicación la recuerde y no vuelva a preguntar nunca.
class PrintAttempt {
  const PrintAttempt({
    required this.result,
    this.endpoint,
    this.kind,
    this.label = '',
  });

  final PrintResult result;

  /// Cola de Windows o `COM5` que aceptó el trabajo.
  final String? endpoint;
  final PrinterKind? kind;
  final String label;

  bool get ok => result.ok;
  bool get hasTarget => endpoint != null && kind != null;
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
            isAvailable: printer.isAvailable,
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

  // ------------------------------------------------ automático (recomendado)
  //
  // El cliente no elige puertos ni ve listas de dispositivos: la aplicación
  // ordena las impresoras candidatas, prueba en silencio y recuerda la que
  // funcionó. Si la impresora configurada falla (apagada, desemparejada), se
  // prueba la siguiente sin molestar a nadie.

  /// Colas de Windows que no son impresoras de tickets.
  static final RegExp _virtualQueue = RegExp(
    r'pdf|xps|onenote|fax|microsoft print|documento',
    caseSensitive: false,
  );

  /// Nombres que suenan a impresora térmica de tickets.
  static final RegExp _thermalHint = RegExp(
    r'pos|term|thermal|sewoo|seewo|rongta|xprinter|bixolon|zjiang|2c-|tm-?t|gp-?58|gp-?80|80mm|58mm',
    caseSensitive: false,
  );

  /// Impresoras que se probarán solas, en orden: la que ya funcionó, las
  /// térmicas instaladas en Windows y, al final, los puertos Bluetooth (SPP).
  Future<List<PrinterDetection>> autoCandidates(OwnerSettings settings) async {
    final ordered = <PrinterDetection>[];
    final seen = <String>{};

    void add(PrinterDetection detection) {
      final endpoint = detection.endpoint;
      if (!detection.found || endpoint == null || endpoint.isEmpty) return;
      if (!seen.add('${detection.kind?.name}:$endpoint')) return;
      ordered.add(detection);
    }

    add(await detect(settings));
    for (final queue in await _thermalQueues()) {
      add(queue);
    }
    for (final port in await _serialPorts()) {
      add(port);
    }
    return ordered;
  }

  /// Colas de Windows que parecen impresora de tickets.
  Future<List<PrinterDetection>> _thermalQueues() async {
    final found = <PrinterDetection>[];
    final List<PrinterRef> queues;
    try {
      queues = await gateway.listPrinters();
    } catch (_) {
      return found;
    }
    for (final printer in queues) {
      final name = printer.endpoint;
      if (!printer.isAvailable) continue;
      if (_virtualQueue.hasMatch(name)) continue;
      if (!_thermalHint.hasMatch(name)) continue;
      found.add(
        PrinterDetection(
          found: true,
          kind: PrinterKind.windowsQueue,
          endpoint: name,
          label: printer.name,
          message: 'Impresora lista: ${printer.name}.',
        ),
      );
    }
    return found;
  }

  /// Puertos serie que pueden enviar datos (impresora Bluetooth SPP).
  ///
  /// Con [bluetoothOnly] se descartan los puertos de la placa (`COM1`): nunca
  /// se manda un ticket a un puerto que no sea la impresora.
  Future<List<PrinterDetection>> _serialPorts({
    bool bluetoothOnly = false,
  }) async {
    final found = <PrinterDetection>[];
    final List<ComPort> ports;
    try {
      ports = await serialGateway.listPorts();
    } catch (_) {
      return found;
    }
    // Orden estable: primero los `BthModem0` (el puerto que Windows crea al
    // emparejar una impresora) y luego el resto, por nombre.
    final ordered = [...ports]
      ..sort((a, b) {
        final byPath = a.devicePath.compareTo(b.devicePath);
        return byPath != 0 ? byPath : a.name.compareTo(b.name);
      });
    for (final port in ordered) {
      if (!port.canSend) continue;
      if (bluetoothOnly && !port.likelyBluetooth) continue;
      found.add(
        PrinterDetection(
          found: true,
          kind: PrinterKind.serialCom,
          endpoint: port.name,
          label: port.label,
          message: 'Impresora lista: ${port.label}.',
        ),
      );
    }
    return found;
  }

  /// Imprime el recibo probando sola las impresoras disponibles.
  Future<PrintAttempt> printReceiptAuto(
    ReceiptRecord record, {
    required OwnerSettings settings,
  }) async {
    final document = await documents.ensure(record);
    final path = document.path;
    if (!document.ok || path == null) {
      return const PrintAttempt(
        result: PrintResult(
          ok: false,
          message:
              'El cobro está guardado, pero no se pudo preparar el recibo. '
              'Podrá imprimirlo después desde el historial.',
        ),
      );
    }
    return _tryAll(
      settings: settings,
      job: (route) => _sendReceipt(record, route, settings, path),
    );
  }

  /// Ticket de prueba de Ajustes, también automático.
  Future<PrintAttempt> printCalibrationAuto(
    OwnerSettings settings, {
    String model = '2C-P80-C',
  }) {
    return _tryAll(
      settings: settings,
      job: (route) => _sendCalibration(settings, route, model),
    );
  }

  /// Prueba los destinos **de uno en uno**: primero la impresora ya
  /// configurada (el caso normal, sin enumerar nada), después las térmicas de
  /// Windows y por último los puertos Bluetooth. Se detiene en cuanto una
  /// responde, así el cliente nunca espera ni ve listas de dispositivos.
  Future<PrintAttempt> _tryAll({
    required OwnerSettings settings,
    required Future<PrintResult> Function(PrinterDetection route) job,
  }) async {
    final tried = <String>{};

    Future<PrintAttempt?> attempt(PrinterDetection route) async {
      final endpoint = route.endpoint;
      if (!route.found || endpoint == null || endpoint.isEmpty) return null;
      if (!tried.add('${route.kind?.name}:$endpoint')) return null;
      final result = await job(route);
      if (!result.ok) return null;
      return PrintAttempt(
        result: const PrintResult(
          ok: true,
          message: 'Ticket enviado a la impresora.',
        ),
        endpoint: endpoint,
        kind: route.kind,
        label: route.label,
      );
    }

    final first = await attempt(await detect(settings));
    if (first != null) return first;

    for (final queue in await _thermalQueues()) {
      final done = await attempt(queue);
      if (done != null) return done;
    }

    // Los puertos serie solo se prueban si el cliente usa Bluetooth o si aún no
    // hay impresora configurada: así una cola de Windows que falla nunca manda
    // el ticket a un puerto cualquiera. Se prueba un solo puerto Bluetooth.
    final configured = (settings.printerTarget ?? '').trim().isNotEmpty;
    final allowSerial =
        !configured || settings.printerTransport == PrinterTransport.serial;
    if (allowSerial) {
      final ports = await _serialPorts(bluetoothOnly: true);
      for (final port in ports.take(1)) {
        final done = await attempt(port);
        if (done != null) return done;
      }
    }

    return const PrintAttempt(
      result: PrintResult(
        ok: false,
        message:
            'No se pudo imprimir. El pago está guardado: encienda la impresora '
            'y reimprima el ticket desde el historial.',
      ),
    );
  }

  Future<PrintResult> _sendReceipt(
    ReceiptRecord record,
    PrinterDetection route,
    OwnerSettings settings,
    String pdfPath,
  ) async {
    if (route.kind == PrinterKind.serialCom) {
      return serialGateway.printReceipt(
        record,
        port: route.endpoint!,
        profile: settings.printerProfile,
      );
    }
    try {
      final bytes = await File(pdfPath).readAsBytes();
      return await gateway.print(
        pdfBytes: bytes,
        printerName: route.endpoint,
        jobName: 'Recibo ${record.label}',
      );
    } catch (_) {
      return const PrintResult(
        ok: false,
        message: 'No se pudo enviar el recibo a esa impresora.',
      );
    }
  }

  Future<PrintResult> _sendCalibration(
    OwnerSettings settings,
    PrinterDetection route,
    String model,
  ) async {
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
