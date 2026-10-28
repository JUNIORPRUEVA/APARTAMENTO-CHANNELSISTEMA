import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../core/app_failure.dart';

/// Un puerto serie disponible en el equipo.
class ComPort {
  const ComPort({
    required this.name,
    required this.devicePath,
    required this.baudRate,
  });

  /// Nombre que espera la API de Windows, por ejemplo `COM5`.
  final String name;

  /// Ruta del dispositivo en el registro (`\Device\BthModem0`, `\Device\VCP0`…).
  /// Sirve para etiquetar el puerto, no para abrirlo.
  final String devicePath;

  /// Velocidad propuesta. Las impresoras Bluetooth SPP suelen usar 9600.
  final int baudRate;

  /// `true` cuando la ruta del dispositivo sugiere Bluetooth (BthModem) o un
  /// adaptador USB-serie. Es una **pista**, no una garantía.
  bool get likelyBluetooth => devicePath.toLowerCase().contains('bth');

  String get label => name;
}

/// Entrega de bytes a un puerto serie.
///
/// Existe como interfaz para que la lógica de impresión se pueda probar sin
/// hardware. La implementación real es [Win32SerialTransport].
abstract interface class SerialTransport {
  /// Puertos serie presentes en el equipo. Nunca lanza: si no puede leer el
  /// registro devuelve una lista vacía.
  Future<List<ComPort>> listPorts();

  /// Escribe [bytes] en [port]. Lanza [AppFailure] si el puerto no se puede
  /// abrir o la escritura falla. Completa cuando el sistema aceptó todos los
  /// bytes (no cuando la impresora los imprimió).
  Future<void> send(
    String port,
    Uint8List bytes, {
    int baudRate = 9600,
    Duration timeout = const Duration(seconds: 20),
  });
}

/// Implementación Windows: CreateFile + SetCommState + WriteFile por FFI.
///
/// Se usa un binding propio y mínimo (kernel32) en lugar de un paquete externo
/// para no depender de la evolución de una API de terceros en una función tan
/// sensible como imprimir dinero.
///
/// La escritura se ejecuta en un isolate aparte: `WriteFile` sobre un puerto
/// serie es bloqueante y a 9600 baudios un recibo tarda ~2 s, tiempo suficiente
/// para congelar la interfaz si se hace en el hilo de la UI.
class Win32SerialTransport implements SerialTransport {
  const Win32SerialTransport();

  @override
  Future<List<ComPort>> listPorts() async {
    if (!Platform.isWindows) return const [];
    try {
      // `reg query` no requiere permisos especiales y es más barato que
      // enumerar dispositivos con SetupAPI.
      final result = await Process.run(
        'reg',
        ['query', r'HKLM\HARDWARE\DEVICEMAP\SERIALCOMM'],
        stdoutEncoding: latin1,
        stderrEncoding: latin1,
      );
      if (result.exitCode != 0) return const [];
      return parseSerialMap(result.stdout as String);
    } catch (_) {
      return const [];
    }
  }

  /// Extrae los pares dispositivo → puerto del texto de `reg query`.
  ///
  /// Cada línea útil tiene la forma:
  /// `    \Device\BthModem0    REG_SZ    COM5`
  static List<ComPort> parseSerialMap(String output) {
    final ports = <ComPort>[];
    final pattern = RegExp(
      r'^\s*(\S+)\s+REG_SZ\s+(COM\d+)\s*$',
      caseSensitive: false,
      multiLine: true,
    );
    for (final match in pattern.allMatches(output)) {
      final device = match.group(1)!;
      final name = match.group(2)!.toUpperCase();
      if (ports.any((port) => port.name == name)) continue;
      ports.add(ComPort(name: name, devicePath: device, baudRate: 9600));
    }
    ports.sort((a, b) {
      final na = int.tryParse(a.name.replaceAll(RegExp(r'\D'), '')) ?? 0;
      final nb = int.tryParse(b.name.replaceAll(RegExp(r'\D'), '')) ?? 0;
      return na.compareTo(nb);
    });
    return ports;
  }

  @override
  Future<void> send(
    String port,
    Uint8List bytes, {
    int baudRate = 9600,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (!Platform.isWindows) {
      throw const AppFailure(
        'La impresión por puerto serie solo está disponible en Windows.',
      );
    }
    if (bytes.isEmpty) {
      throw const AppFailure('No hay nada que enviar a la impresora.');
    }
    final name = port.trim().toUpperCase();
    if (!RegExp(r'^COM\d+$').hasMatch(name)) {
      throw AppFailure('El puerto serie "$port" no es válido.');
    }
    try {
      await Isolate.run(
        () => _writeSync(name, baudRate, bytes, timeout.inMilliseconds),
        debugName: 'escpos-serial-write',
      );
    } on _SerialError catch (error) {
      throw AppFailure(error.message);
    }
  }
}

/// Error interno del isolate (se traduce a [AppFailure] en el hilo principal).
class _SerialError implements Exception {
  _SerialError(this.message);
  final String message;
}

// --------------------------------------------------------------- FFI mínimo

const int _genericRead = 0x80000000;
const int _genericWrite = 0x40000000;
const int _openExisting = 3;
const int _invalidHandleValue = -1;

const int _errorFileNotFound = 2;
const int _errorAccessDenied = 5;
const int _errorGenFailure = 31;
const int _errorHandleEof = 38;
const int _errorSemTimeout = 121;
const int _errorNotEnoughMemory = 8;

typedef _CreateFileWNative =
    IntPtr Function(
      Pointer<Utf16>,
      Uint32,
      Uint32,
      IntPtr,
      Uint32,
      Uint32,
      IntPtr,
    );
typedef _CreateFileWDart =
    int Function(Pointer<Utf16>, int, int, int, int, int, int);

typedef _CloseHandleNative = Int32 Function(IntPtr);
typedef _CloseHandleDart = int Function(int);

typedef _GetCommStateNative = Int32 Function(IntPtr, Pointer<_Dcb>);
typedef _GetCommStateDart = int Function(int, Pointer<_Dcb>);

typedef _SetCommStateNative = Int32 Function(IntPtr, Pointer<_Dcb>);
typedef _SetCommStateDart = int Function(int, Pointer<_Dcb>);

typedef _SetCommTimeoutsNative = Int32 Function(IntPtr, Pointer<_CommTimeouts>);
typedef _SetCommTimeoutsDart = int Function(int, Pointer<_CommTimeouts>);

typedef _WriteFileNative =
    Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, IntPtr);
typedef _WriteFileDart =
    int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, int);

typedef _FlushFileBuffersNative = Int32 Function(IntPtr);
typedef _FlushFileBuffersDart = int Function(int);

class _Kernel32 {
  _Kernel32() : _lib = DynamicLibrary.open('kernel32.dll');

  final DynamicLibrary _lib;

  late final _CreateFileWDart createFile = _lib
      .lookupFunction<_CreateFileWNative, _CreateFileWDart>('CreateFileW');
  late final _CloseHandleDart closeHandle = _lib
      .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
  late final _GetCommStateDart getCommState = _lib
      .lookupFunction<_GetCommStateNative, _GetCommStateDart>('GetCommState');
  late final _SetCommStateDart setCommState = _lib
      .lookupFunction<_SetCommStateNative, _SetCommStateDart>('SetCommState');
  late final _SetCommTimeoutsDart setCommTimeouts = _lib
      .lookupFunction<_SetCommTimeoutsNative, _SetCommTimeoutsDart>(
        'SetCommTimeouts',
      );
  late final _WriteFileDart writeFile = _lib
      .lookupFunction<_WriteFileNative, _WriteFileDart>('WriteFile');
  late final _FlushFileBuffersDart flushFileBuffers = _lib
      .lookupFunction<_FlushFileBuffersNative, _FlushFileBuffersDart>(
        'FlushFileBuffers',
      );

  static int lastError() => DynamicLibrary.process()
      .lookupFunction<Int32 Function(), int Function()>('GetLastError')();
}

/// `DCB` de `win32con.h`. Se declara completo (28 bytes) con el formato exacto
/// que espera `SetCommState`; los campos no usados se dejan en cero.
final class _Dcb extends Struct {
  @Uint32()
  external int dcBlength;

  @Uint32()
  external int baudRate;

  /// Bitfield: fBinary(0), fParity(1), fOutxCtsFlow(2), fOutxDsrFlow(3),
  /// fDtrControl(4-5), fDsrSensitivity(6), fTXContinueOnXoff(7), fOutX(8),
  /// fInX(9), fErrorChar(10), fNull(11), fRtsControl(12-13), fAbortOnError(14).
  @Uint32()
  external int flags;

  @Uint16()
  external int wReserved;

  @Uint16()
  external int xonLim;

  @Uint16()
  external int xoffLim;

  @Uint8()
  external int byteSize;

  @Uint8()
  external int parity;

  @Uint8()
  external int stopBits;

  @Uint8()
  external int xonChar;

  @Uint8()
  external int xoffChar;

  @Uint8()
  external int errorChar;

  @Uint8()
  external int eofChar;

  @Uint8()
  external int evtChar;

  @Uint16()
  external int wReserved1;
}

final class _CommTimeouts extends Struct {
  @Uint32()
  external int readIntervalTimeout;

  @Uint32()
  external int readTotalTimeoutMultiplier;

  @Uint32()
  external int readTotalTimeoutConstant;

  @Uint32()
  external int writeTotalTimeoutMultiplier;

  @Uint32()
  external int writeTotalTimeoutConstant;
}

/// Escritura bloqueante. Se ejecuta dentro de un isolate.
void _writeSync(String port, int baudRate, Uint8List bytes, int timeoutMs) {
  final api = _Kernel32();
  final wide = '\\\\.\\$port'.toNativeUtf16();
  var handle = -1;
  try {
    handle = api.createFile(
      wide,
      _genericRead | _genericWrite,
      0, // sin compartir: si otra app tiene el puerto, falla (mejor saberlo)
      0,
      _openExisting,
      0,
      0,
    );
    if (handle == _invalidHandleValue) {
      final code = _Kernel32.lastError();
      throw _SerialError(_describeOpen(port, code));
    }

    final dcb = calloc<_Dcb>();
    final timeouts = calloc<_CommTimeouts>();
    try {
      dcb.ref.dcBlength = sizeOf<_Dcb>();
      if (api.getCommState(handle, dcb) == 0) {
        throw _SerialError(
          'La impresora no respondió en $port. '
          'Verifique que esté encendida y emparejada.',
        );
      }
      dcb.ref
        ..baudRate = baudRate
        ..byteSize = 8
        ..parity =
            0 // NOPARITY
        ..stopBits =
            0 // ONESTOPBIT
        ..flags = 0x1 | 0x10 | 0x1000; // fBinary | DTR enable | RTS enable
      if (api.setCommState(handle, dcb) == 0) {
        throw _SerialError(
          'No se pudo configurar el puerto $port a $baudRate baudios.',
        );
      }

      timeouts.ref
        ..readIntervalTimeout = 0
        ..readTotalTimeoutMultiplier = 0
        ..readTotalTimeoutConstant = 0
        ..writeTotalTimeoutMultiplier = 0
        ..writeTotalTimeoutConstant = timeoutMs;
      api.setCommTimeouts(handle, timeouts);

      // Se envía por bloques: los adaptadores Bluetooth tienen búferes pequeños
      // y una escritura enorme puede fallar o perder bytes.
      var offset = 0;
      while (offset < bytes.length) {
        final chunk = bytes.sublist(
          offset,
          (offset + 512).clamp(0, bytes.length),
        );
        final buffer = calloc<Uint8>(chunk.length);
        final written = calloc<Uint32>();
        try {
          buffer.asTypedList(chunk.length).setAll(0, chunk);
          final ok = api.writeFile(handle, buffer, chunk.length, written, 0);
          if (ok == 0) {
            final code = _Kernel32.lastError();
            throw _SerialError(_describeWrite(port, code));
          }
          if (written.value != chunk.length) {
            throw _SerialError(
              'La impresora recibió solo ${written.value} de '
              '${chunk.length} bytes en $port. '
              'El trabajo quedó incompleto: revise el papel y reimprima.',
            );
          }
        } finally {
          calloc.free(buffer);
          calloc.free(written);
        }
        offset += chunk.length;
      }
      api.flushFileBuffers(handle);
    } finally {
      calloc.free(dcb);
      calloc.free(timeouts);
    }
  } finally {
    if (handle != -1) api.closeHandle(handle);
    calloc.free(wide);
  }
}

String _describeOpen(String port, int code) {
  switch (code) {
    case _errorFileNotFound:
      return 'El puerto $port no existe. '
          'Empareje la impresora Bluetooth y vuelva a intentarlo.';
    case _errorAccessDenied:
      return 'El puerto $port está ocupado por otro programa '
          '(o la impresora está apagada).';
    case _errorNotEnoughMemory:
      return 'Windows no pudo abrir $port por falta de memoria.';
    default:
      return 'No se pudo abrir el puerto $port (error $code de Windows).';
  }
}

String _describeWrite(String port, int code) {
  switch (code) {
    case _errorGenFailure:
      return 'Windows rechazó la escritura en $port. '
          'Revise que la impresora esté encendida y con papel.';
    case _errorSemTimeout:
      return 'La impresora no aceptó los datos en $port '
          '(tiempo de espera agotado). Reintente cuando esté encendida.';
    case _errorHandleEof:
      return 'La conexión con la impresora se interrumpió durante el envío '
          '($port). El trabajo quedó incompleto: reimprima.';
    case _errorAccessDenied:
      return 'Otro programa está usando el puerto $port.';
    default:
      return 'Falló el envío al puerto $port (error $code de Windows).';
  }
}
