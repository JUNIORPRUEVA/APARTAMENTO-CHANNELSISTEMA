import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../app/app_scope.dart';
import '../../../data/models.dart';
import '../../../services/backup_service.dart';
import '../../../services/print_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/common.dart';
import '../../dialogs/dialogs.dart';

const String kAppVersion = '1.2.0 — Fase 3';

Future<void> showSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x660B1733),
    builder: (context) => const _SettingsDialog(),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final TextEditingController _name;
  late final TextEditingController _id;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _prefix;

  List<PrinterRef> _printers = const <PrinterRef>[];

  /// Destino elegido, con el formato `cola:<nombre>` o `serie:<COMn>`.
  String? _selectedTarget;
  PrinterTransport _transport = PrinterTransport.auto;
  bool _loadingPrinters = true;
  bool _printing = false;
  int _receiptWidth = 80;
  double _receiptMargin = 3.5;
  bool _asciiOnly = false;
  int _printableDots = 0;
  int _marginDots = 0;
  int _baudRate = 9600;
  String _statusMessage = '';
  bool _statusOk = false;
  late final TextEditingController _exportDir;
  late final TextEditingController _dotsController;
  late final TextEditingController _marginDotsController;

  @override
  void initState() {
    super.initState();
    final owner = AppScope.read(context).owner;
    _name = TextEditingController(text: owner.issuerName);
    _id = TextEditingController(text: owner.issuerId);
    _address = TextEditingController(text: owner.issuerAddress);
    _phone = TextEditingController(text: owner.issuerPhone);
    _prefix = TextEditingController(text: owner.receiptPrefix);
    _exportDir = TextEditingController(
      text: owner.backupExportDir.isEmpty
          ? _defaultExportDir()
          : owner.backupExportDir,
    );
    _receiptWidth = owner.receiptWidthMm;
    _receiptMargin = owner.receiptMarginMm;
    _asciiOnly = owner.asciiOnly;
    _transport = owner.printerTransport;
    _printableDots = owner.printerPrintableDots;
    _marginDots = owner.printerMarginDots;
    _baudRate = owner.printerBaudRate;
    _dotsController = TextEditingController(
      text: _printableDots == 0 ? '' : '$_printableDots',
    );
    _marginDotsController = TextEditingController(
      text: _marginDots == 0 ? '' : '$_marginDots',
    );
    if (owner.printerTarget != null && owner.printerTarget!.isNotEmpty) {
      _selectedTarget =
          '${owner.printerTransport == PrinterTransport.serial ? 'serie' : 'cola'}:'
          '${owner.printerTarget}';
    }
    _loadPrinters();
  }

  String _defaultExportDir() {
    final profile =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (profile == null) return 'copias-alquileres';
    return p.join(profile, 'Desktop', 'copias-alquileres');
  }

  Future<void> _loadPrinters() async {
    try {
      final printers = await AppScope.read(context).listPrinters();
      if (!mounted) return;
      setState(() {
        _printers = printers;
        _loadingPrinters = false;
        if (_selectedTarget == null && printers.isNotEmpty) {
          final preferred = printers.firstWhere(
            (printer) => printer.isDefault,
            orElse: () => printers.first,
          );
          _selectedTarget =
              '${preferred.kind == PrinterKind.serialCom ? 'serie' : 'cola'}:'
              '${preferred.endpoint}';
        }
      });
      // Con el destino ya elegido se muestra si responde o no.
      await _refreshStatus();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPrinters = false);
    }
  }

  Future<void> _refreshStatus() async {
    final controller = AppScope.read(context);
    final draft = _draftSettings();
    final detection = await controller.detectPrinter(draft);
    if (!mounted) return;
    setState(() {
      _statusOk = detection.found;
      _statusMessage = detection.found
          ? 'Impresora lista: ${detection.label}'
          : detection.message;
    });
  }

  /// Claves válidas del desplegable (`cola:…` / `serie:…`).
  List<String> get _targetKeys => [
    for (final printer in _printers)
      '${printer.kind == PrinterKind.serialCom ? 'serie' : 'cola'}:'
          '${printer.endpoint}',
  ];

  /// `true` cuando la impresora guardada ya no está en la lista detectada.
  String? get _missingTarget {
    final raw = _selectedTarget;
    if (raw == null || raw.isEmpty) return null;
    return _targetKeys.contains(raw) ? null : _draftTarget.target;
  }

  String? get _dropdownValue {
    final raw = _selectedTarget;
    if (raw == null || raw.isEmpty) return null;
    return _targetKeys.contains(raw) || _missingTarget != null ? raw : null;
  }

  /// Destino seleccionado en formato (transporte, destino).
  ({PrinterTransport transport, String? target}) get _draftTarget {
    final raw = _selectedTarget;
    if (raw == null || raw.isEmpty) {
      return (transport: _transport, target: null);
    }
    final parts = raw.split(':');
    if (parts.length < 2) return (transport: _transport, target: raw);
    final isSerial = parts.first == 'serie';
    return (
      transport: isSerial ? PrinterTransport.serial : PrinterTransport.windows,
      target: parts.sublist(1).join(':'),
    );
  }

  OwnerSettings _draftSettings() {
    final target = _draftTarget;
    final label = _printers
        .where((printer) => printer.endpoint == target.target)
        .map((printer) => printer.name)
        .firstOrNull;
    return OwnerSettings(
      issuerName: _name.text.trim(),
      issuerId: _id.text.trim(),
      issuerAddress: _address.text.trim(),
      issuerPhone: _phone.text.trim(),
      printerName: label ?? target.target,
      printerTransport: _transport,
      printerTarget: target.target,
      receiptPrefix: _prefix.text.trim().isEmpty ? 'REC' : _prefix.text.trim(),
      receiptWidthMm: _receiptWidth,
      receiptMarginMm: _receiptMargin,
      asciiOnly: _asciiOnly,
      printerPrintableDots: _printableDots,
      printerMarginDots: _marginDots,
      printerBaudRate: _baudRate,
      backupExportDir: _exportDir.text.trim(),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _id.dispose();
    _address.dispose();
    _phone.dispose();
    _prefix.dispose();
    _exportDir.dispose();
    _dotsController.dispose();
    _marginDotsController.dispose();
    super.dispose();
  }

  void _save() {
    final controller = AppScope.read(context);
    final message = controller.saveOwner(_draftSettings());
    reportOutcome(context, message, successMessage: 'Datos guardados.');
  }

  Future<void> _testPrint() async {
    final controller = AppScope.read(context);
    setState(() => _printing = true);
    try {
      // Automático: prueba las impresoras disponibles y guarda la que responda.
      final attempt = await controller.printCalibrationAuto(_draftSettings());
      if (!mounted) return;
      reportOutcome(
        context,
        attempt.ok ? null : attempt.result.message,
        successMessage: attempt.ok
            ? 'Ticket de prueba enviado a la impresora.'
            : '',
      );
      await _refreshStatus();
    } catch (error) {
      if (!mounted) return;
      reportOutcome(
        context,
        'No se pudo imprimir la prueba: $error',
        successMessage: '',
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _backupNow() async {
    final controller = AppScope.read(context);
    try {
      final service = BackupService(
        database: controller.database,
        paths: controller.paths,
      );
      final report = await Future<BackupReport>.value(service.runNow());
      if (!mounted) return;
      reportOutcome(
        context,
        null,
        successMessage: 'Copia creada (${(report.bytes / 1024).round()} KB).',
      );
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      reportOutcome(
        context,
        'No se pudo crear la copia de seguridad.',
        successMessage: '',
      );
    }
  }

  Future<void> _exportBackup() async {
    final controller = AppScope.read(context);
    final target = _exportDir.text.trim();
    if (target.isEmpty) {
      reportOutcome(
        context,
        'Escriba la carpeta de destino.',
        successMessage: '',
      );
      return;
    }
    try {
      final service = BackupService(
        database: controller.database,
        paths: controller.paths,
      );
      if (service.list().isEmpty) service.runNow();
      final path = service.exportLatestTo(target);
      if (!mounted) return;
      reportOutcome(context, null, successMessage: 'Copia exportada a $path');
    } catch (error) {
      if (!mounted) return;
      reportOutcome(
        context,
        'No se pudo exportar. Verifique la carpeta o la memoria USB.',
        successMessage: '',
      );
    }
  }

  Future<void> _restoreBackup() async {
    final controller = AppScope.read(context);
    final service = BackupService(
      database: controller.database,
      paths: controller.paths,
    );
    final entries = service.list();
    if (entries.isEmpty) {
      reportOutcome(
        context,
        'Todavía no hay copias para restaurar.',
        successMessage: '',
      );
      return;
    }

    final selected = await showDialog<BackupEntry>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                child: Text(
                  'Restaurar una copia',
                  style: appText.cardTitle.copyWith(fontSize: 17),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: InlineNotice(
                  text:
                      'Antes de restaurar se guarda una copia del estado '
                      'actual. La aplicación se cerrará para aplicar la copia.',
                  tone: PillTone.warning,
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.history_rounded,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                      title: Text(
                        entry.createdAt.toString().substring(0, 16),
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        '${(entry.bytes / 1024).round()} KB',
                        style: const TextStyle(fontSize: 11),
                      ),
                      onTap: () => Navigator.of(context).pop(entry),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlineButton(
                      label: 'Cancelar',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Confirmar restauración'),
        content: Text(
          'Se reemplazarán los datos actuales por la copia del '
          '${selected.createdAt.toString().substring(0, 16)}. '
          'Los datos actuales se guardan en una copia previa.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          OutlineButton(
            label: 'Cancelar',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          const SizedBox(width: 10),
          PrimaryButton(
            label: 'Restaurar',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final error = service.restore(selected);
    if (!mounted) return;
    if (error != null) {
      reportOutcome(context, error, successMessage: '');
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Restauración aplicada'),
        content: const Text(
          'Los datos fueron restaurados. Cierre la aplicación y ábrala de '
          'nuevo para continuar.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          PrimaryButton(
            label: 'Entendido',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _purgeDemo() async {
    final controller = AppScope.read(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Eliminar datos de demostración'),
        content: const Text(
          'Se eliminarán los residenciales, apartamentos, inquilinos y '
          'contratos marcados como demostración. Esta acción no se puede '
          'deshacer.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          OutlineButton(
            label: 'Cancelar',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          const SizedBox(width: 10),
          PrimaryButton(
            label: 'Eliminar',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final message = controller.purgeDemoData();
    if (!mounted) return;
    reportOutcome(
      context,
      message,
      successMessage: 'Datos de demostración eliminados.',
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final backup = BackupService(
      database: controller.database,
      paths: controller.paths,
    );
    final lastBackup = backup.lastRun;

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.settings_outlined,
                    size: 20,
                    color: AppColors.navy,
                  ),
                  const SizedBox(width: 9),
                  Text(
                    'Ajustes',
                    style: appText.cardTitle.copyWith(fontSize: 17),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: AppColors.textMuted,
                    tooltip: 'Cerrar',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Datos del negocio (para los recibos)',
                      style: appText.sectionTitle,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Estos datos aparecen impresos en cada recibo.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    LabeledField(
                      label: 'Nombre del propietario o negocio',
                      child: TextField(
                        controller: _name,
                        decoration: const InputDecoration(
                          hintText: 'Ej. Inversiones Anamelia SRL',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: LabeledField(
                            label: 'Cédula o RNC',
                            child: TextField(controller: _id),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: LabeledField(
                            label: 'Teléfono',
                            child: TextField(controller: _phone),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LabeledField(
                      label: 'Dirección',
                      child: TextField(controller: _address),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        SizedBox(
                          width: 180,
                          child: LabeledField(
                            label: 'Prefijo del recibo',
                            child: TextField(
                              controller: _prefix,
                              decoration: const InputDecoration(
                                hintText: 'REC',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 190,
                          child: LabeledField(
                            label: 'Ancho del papel',
                            child: DropdownButtonFormField<int>(
                              initialValue: _receiptWidth,
                              items: const [
                                DropdownMenuItem(
                                  value: 80,
                                  child: Text('80 mm'),
                                ),
                                DropdownMenuItem(
                                  value: 58,
                                  child: Text('58 mm'),
                                ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _receiptWidth = value ?? 80),
                              decoration: const InputDecoration(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    Text('Impresora', style: appText.sectionTitle),
                    const SizedBox(height: 4),
                    const Text(
                      'La impresora se configura sola. Pulse «Probar impresora» '
                      'una vez: si sale el ticket, queda lista y no habrá que '
                      'elegir puertos ni dispositivos nunca más.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    PrimaryButton(
                      label: _printing ? 'Probando…' : 'Probar impresora',
                      appIcon: AppIcon.print,
                      height: 36,
                      onPressed: _printing ? null : _testPrint,
                    ),
                    const SizedBox(height: 8),
                    // Estado real de la conexión (sin tecnicismos ni trazas).
                    Row(
                      children: [
                        Icon(
                          _statusOk
                              ? Icons.check_circle_outline
                              : Icons.info_outline,
                          size: 15,
                          color: _statusOk
                              ? AppColors.greenFg
                              : AppColors.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _statusMessage.isEmpty
                                ? 'Sin comprobar todavía.'
                                : _statusMessage,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: _statusOk
                                  ? AppColors.greenFg
                                  : AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Solo para casos raros: elegir la impresora a mano.
                    Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 6),
                        title: const Text(
                          'Elegir impresora a mano (solo si hace falta)',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                        children: [
                          SizedBox(
                            width: 250,
                            child: LabeledField(
                              label: 'Conexión',
                              child: DropdownButtonFormField<PrinterTransport>(
                                initialValue: _transport,
                                isExpanded: true,
                                items: const [
                                  DropdownMenuItem(
                                    value: PrinterTransport.auto,
                                    child: Text('Automático'),
                                  ),
                                  DropdownMenuItem(
                                    value: PrinterTransport.windows,
                                    child: Text('Windows'),
                                  ),
                                  DropdownMenuItem(
                                    value: PrinterTransport.serial,
                                    child: Text('Bluetooth (COM)'),
                                  ),
                                ],
                                onChanged: (value) => setState(() {
                                  _transport = value ?? PrinterTransport.auto;
                                }),
                                decoration: const InputDecoration(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _loadingPrinters
                                    ? const Text(
                                        'Buscando impresora...',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          color: AppColors.textMuted,
                                        ),
                                      )
                                    : DropdownButtonFormField<String>(
                                        // Si la impresora guardada ya no
                                        // aparece (apagada, desemparejada), se
                                        // muestra igual para no perder la
                                        // configuración.
                                        initialValue: _dropdownValue,
                                        isExpanded: true,
                                        items: [
                                          if (_missingTarget != null)
                                            DropdownMenuItem(
                                              value: _selectedTarget,
                                              child: Text(
                                                '${_missingTarget!} · no disponible',
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          for (final printer in _printers)
                                            DropdownMenuItem(
                                              value:
                                                  '${printer.kind == PrinterKind.serialCom ? 'serie' : 'cola'}:'
                                                  '${printer.endpoint}',
                                              child: Text(
                                                printer.detail.isEmpty
                                                    ? printer.name
                                                    : '${printer.name} · ${printer.detail}',
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                        ],
                                        onChanged: (value) => setState(() {
                                          _selectedTarget = value;
                                          final draft = _draftTarget;
                                          _transport = draft.transport;
                                        }),
                                        decoration: const InputDecoration(
                                          hintText: 'Sin impresora configurada',
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 10),
                              OutlineButton(
                                label: 'Actualizar',
                                icon: Icons.refresh_rounded,
                                dense: true,
                                onPressed: () {
                                  setState(() => _loadingPrinters = true);
                                  _loadPrinters();
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 6),
                        title: const Text(
                          'Avanzado (solo si el ticket sale cortado)',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                        children: [
                          LabeledField(
                            label: 'Ancho útil calibrado (puntos)',
                            child: TextField(
                              controller: _dotsController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                hintText: 'Vacío = automático (576 en 80 mm)',
                              ),
                              onChanged: (value) {
                                final parsed = int.tryParse(
                                  value.replaceAll(RegExp(r'[^0-9]'), ''),
                                );
                                _printableDots = parsed == null || parsed < 96
                                    ? 0
                                    : (parsed > 1200 ? 1200 : parsed);
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: LabeledField(
                                  label: 'Margen de contenido (puntos)',
                                  child: TextField(
                                    controller: _marginDotsController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      hintText: '0',
                                    ),
                                    onChanged: (value) {
                                      final parsed = int.tryParse(
                                        value.replaceAll(RegExp(r'[^0-9]'), ''),
                                      );
                                      _marginDots = parsed == null || parsed < 0
                                          ? 0
                                          : (parsed > 240 ? 240 : parsed);
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: LabeledField(
                                  label: 'Velocidad (baudios)',
                                  child: DropdownButtonFormField<int>(
                                    initialValue: _baudRate,
                                    isExpanded: true,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 9600,
                                        child: Text('9600'),
                                      ),
                                      DropdownMenuItem(
                                        value: 19200,
                                        child: Text('19200'),
                                      ),
                                      DropdownMenuItem(
                                        value: 38400,
                                        child: Text('38400'),
                                      ),
                                      DropdownMenuItem(
                                        value: 115200,
                                        child: Text('115200'),
                                      ),
                                    ],
                                    onChanged: (value) => setState(
                                      () => _baudRate = value ?? 9600,
                                    ),
                                    decoration: const InputDecoration(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          CheckboxListTile(
                            value: _asciiOnly,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text(
                              'Imprimir sin acentos (si salen símbolos raros)',
                              style: TextStyle(fontSize: 12),
                            ),
                            onChanged: (value) =>
                                setState(() => _asciiOnly = value ?? false),
                          ),
                          const Text(
                            'El ticket de calibración trae un marco y una '
                            'regla: si el marco no sale completo, baje el '
                            'ancho útil hasta que entre entero.',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Datos y respaldo', style: appText.sectionTitle),
                    const SizedBox(height: 8),
                    _Line(
                      label: 'Carpeta de datos',
                      value: controller.paths.dataDir,
                    ),
                    _Line(
                      label: 'Última copia',
                      value: lastBackup == null
                          ? 'Todavía no se ha creado'
                          : lastBackup.toString().substring(0, 16),
                    ),
                    _Line(
                      label: 'Copias guardadas',
                      value: '${backup.list().length}',
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlineButton(
                          label: 'Crear copia ahora',
                          icon: Icons.backup_outlined,
                          dense: true,
                          onPressed: _backupNow,
                        ),
                        OutlineButton(
                          label: 'Restaurar copia',
                          icon: Icons.restore_rounded,
                          dense: true,
                          onPressed: _restoreBackup,
                        ),
                        if (controller.hasDemoData)
                          OutlineButton(
                            label: 'Eliminar datos de demostración',
                            tone: OutlineTone.danger,
                            dense: true,
                            onPressed: _purgeDemo,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LabeledField(
                      label: 'Carpeta para exportar (USB o respaldo externo)',
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _exportDir,
                              decoration: const InputDecoration(
                                hintText: 'Ej. E:\\copias',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlineButton(
                            label: 'Exportar',
                            icon: Icons.usb_rounded,
                            dense: true,
                            onPressed: _exportBackup,
                          ),
                        ],
                      ),
                    ),
                    if (backup.list().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Copias disponibles: '
                          '${backup.list().map((b) => b.createdAt.toString().substring(0, 16)).take(3).join(' · ')}'
                          '${backup.list().length > 3 ? ' …' : ''}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textFaint,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      'Versión $kAppVersion · Funciona sin internet. '
                      'Los datos se guardan en este equipo.',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlineButton(
                    label: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  PrimaryButton(label: 'Guardar', onPressed: _save),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: appText.infoLabel)),
          Expanded(
            child: SelectableText(
              value,
              style: appText.infoValue.copyWith(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
