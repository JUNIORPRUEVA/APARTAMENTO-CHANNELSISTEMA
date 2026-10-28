// Imprime el ticket de calibración por un puerto COM (ESC/POS nativo).
//
// Sirve para validar la impresora en el sitio, sin abrir la aplicación:
//
//   dart run tool/print_calibration.dart COM5
//   dart run tool/print_calibration.dart COM5 9600
//
// Opcional: ancho útil calibrado en puntos (por defecto 576 = 72 mm).
//
//   dart run tool/print_calibration.dart COM5 9600 640
//
// Requisitos: la impresora encendida, emparejada por Bluetooth (SPP) y con el
// puerto COM **saliente** que crea Windows. El puerto se puede ver con
// `Get-CimInstance Win32_PnPEntity | Where-Object Name -match 'COM\d+'`.
//
// Este comando NO toca la base de datos ni registra pagos.
import 'dart:io';

import 'package:control_alquileres/src/services/escpos.dart';
import 'package:control_alquileres/src/services/printer_profile.dart';
import 'package:control_alquileres/src/services/serial_transport.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Uso: dart run tool/print_calibration.dart <COMn> [baudios] [puntos]',
    );
    exitCode = 64;
    return;
  }
  final port = args[0].toUpperCase();
  final baud = args.length > 1 ? int.tryParse(args[1]) ?? 9600 : 9600;
  final dots = args.length > 2 ? int.tryParse(args[2]) ?? 0 : 0;

  const transport = Win32SerialTransport();

  final ports = await transport.listPorts();
  stdout.writeln('Puertos detectados:');
  if (ports.isEmpty) {
    stdout.writeln('  (ninguno) — revise el emparejamiento Bluetooth.');
  }
  for (final p in ports) {
    stdout.writeln(
      '  ${p.name}  ${p.friendlyName.isEmpty ? p.devicePath : p.friendlyName}'
      '${p.isIncomingLink ? '  [ENTRANTE: no sirve para imprimir]' : ''}',
    );
  }

  final target = ports.where((p) => p.name == port);
  if (target.isNotEmpty && !target.first.canSend) {
    stderr.writeln(
      'El puerto $port es de entrada (incoming); la impresora no lo usa.',
    );
    exitCode = 2;
    return;
  }

  final profile = PrinterProfile(
    paperWidthMm: 80,
    printableDots: dots,
    baudRate: baud,
  );
  stdout.writeln('Perfil: $profile');

  final bytes = EscPosReceipt.buildCalibration(profile: profile);
  try {
    await transport.send(port, bytes, baudRate: baud);
    stdout
      ..writeln('Enviado ${bytes.length} bytes a $port.')
      ..writeln(
        'Mida el marco del ticket con una regla: el ancho impreso en mm x 8 '
        'es el valor de "ancho útil (puntos)" que debe guardar en Ajustes.',
      );
  } catch (error) {
    stderr.writeln('No se pudo enviar: $error');
    exitCode = 1;
  }
}
