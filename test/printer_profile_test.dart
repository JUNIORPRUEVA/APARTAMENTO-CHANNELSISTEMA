import 'dart:io';

import 'package:control_alquileres/src/data/app_database.dart';
import 'package:control_alquileres/src/data/models.dart';
import 'package:control_alquileres/src/data/settings_repository.dart';
import 'package:control_alquileres/src/services/printer_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Perfil de impresión', () {
    test('80 mm sin calibrar usa un ancho conservador y 48 columnas', () {
      const profile = PrinterProfile();
      expect(profile.isCalibrated, isFalse);
      expect(profile.effectivePrintableDots, 576); // 72 mm, no 640
      expect(profile.printableWidthMm, 72);
      expect(profile.columns, 48);
      // 4 mm a cada lado son necesarios para no salirse del cabezal.
      expect(profile.minMarginMm, 4);
    });

    test('58 mm usa 384 puntos y 32 columnas', () {
      const profile = PrinterProfile(paperWidthMm: 58);
      expect(profile.effectivePrintableDots, 384);
      expect(profile.columns, 32);
      expect(profile.minMarginMm, closeTo(5, 0.001));
    });

    test('un perfil calibrado manda sobre el valor por defecto', () {
      const profile = PrinterProfile(printableDots: 640);
      expect(profile.isCalibrated, isTrue);
      expect(profile.printableWidthMm, 80);
      expect(profile.minMarginMm, 0);
      expect(profile.columns, 53); // 640 / 12
    });

    test('el margen de contenido reduce las columnas disponibles', () {
      const profile = PrinterProfile(marginDots: 24);
      expect(profile.marginMm, 3);
      expect(profile.columns, 44); // (576 − 48) / 12
    });

    test('el margen configurado nunca queda por debajo del necesario', () {
      const profile = PrinterProfile(); // 72 mm imprimibles
      expect(profile.effectiveMarginMm(0), 4);
      expect(profile.effectiveMarginMm(3.5), 4);
      expect(profile.effectiveMarginMm(8), 8);
      // Un perfil de 56 mm imprimibles exige 12 mm por lado.
      const narrow = PrinterProfile(printableDots: 448);
      expect(narrow.effectiveMarginMm(3.5), 12);
    });

    test('un perfil absurdo se acota a algo imprimible', () {
      const tiny = PrinterProfile(printableDots: 96);
      expect(tiny.columns, greaterThanOrEqualTo(20));
      const huge = PrinterProfile(printableDots: 1200);
      expect(huge.columns, lessThanOrEqualTo(80));
    });

    test('el corte por defecto es manual (la 2C-P80-C no tiene cortador)', () {
      expect(const PrinterProfile().cutMode, CutMode.manual);
    });

    test('OwnerSettings produce el perfil con sus datos', () {
      const settings = OwnerSettings(
        issuerName: 'X',
        issuerId: '',
        issuerAddress: '',
        issuerPhone: '',
        printerName: null,
        receiptPrefix: 'REC',
        printerPrintableDots: 576,
        printerMarginDots: 12,
        printerBaudRate: 19200,
        asciiOnly: true,
      );
      final profile = settings.printerProfile;
      expect(profile.printableDots, 576);
      expect(profile.marginDots, 12);
      expect(profile.baudRate, 19200);
      expect(profile.asciiOnly, isTrue);
      expect(profile.paperWidthMm, 80);
    });
  });

  group('Persistencia del perfil', () {
    late Directory temp;
    late AppDatabase db;
    late SettingsRepository repo;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('perfil_');
      db = AppDatabase.openAt(p.join(temp.path, 'base.sqlite'));
      repo = SettingsRepository(db);
    });

    tearDown(() {
      db.close();
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    test('guarda y recupera ancho útil, margen y baudios', () {
      repo.save(
        const OwnerSettings(
          issuerName: 'Anamelia',
          issuerId: '',
          issuerAddress: '',
          issuerPhone: '',
          printerName: '2C-P80-C',
          receiptPrefix: 'REC',
          printerTransport: PrinterTransport.serial,
          printerTarget: 'COM5',
          printerPrintableDots: 576,
          printerMarginDots: 12,
          printerBaudRate: 19200,
          asciiOnly: true,
        ),
      );
      final loaded = repo.load();
      expect(loaded.printerPrintableDots, 576);
      expect(loaded.printerMarginDots, 12);
      expect(loaded.printerBaudRate, 19200);
      expect(loaded.printerTransport, PrinterTransport.serial);
      expect(loaded.printerTarget, 'COM5');
      expect(loaded.asciiOnly, isTrue);
    });

    test('un ancho imposible se descarta y vuelve a "sin calibrar"', () {
      repo.save(
        const OwnerSettings(
          issuerName: 'Anamelia',
          issuerId: '',
          issuerAddress: '',
          issuerPhone: '',
          printerName: null,
          receiptPrefix: 'REC',
          printerPrintableDots: 99999,
          printerMarginDots: -5,
          printerBaudRate: 1234,
        ),
      );
      final loaded = repo.load();
      expect(loaded.printerPrintableDots, 0);
      expect(loaded.printerMarginDots, 0);
      expect(loaded.printerBaudRate, 9600);
    });

    test('el modo de conexión por defecto es automático', () {
      expect(repo.load().printerTransport, PrinterTransport.auto);
    });

    test('un valor de transporte desconocido no rompe la carga', () {
      repo.save(
        const OwnerSettings(
          issuerName: 'Anamelia',
          issuerId: '',
          issuerAddress: '',
          issuerPhone: '',
          printerName: null,
          receiptPrefix: 'REC',
        ),
      );
      db.run(
        "UPDATE owner_settings SET printer_transport = 'usb-raro' WHERE id = 1",
      );
      expect(repo.load().printerTransport, PrinterTransport.windows);
    });
  });
}
