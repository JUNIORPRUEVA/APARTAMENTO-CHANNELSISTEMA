// Recorrido funcional completo de la Fase 2 sobre una COPIA de la base real.
//
// Uso:
//   dart run tool/phase2_flow.dart <carpetaDatosOrigen> <carpetaTrabajo>
//
// El script nunca modifica la carpeta de datos original: copia el .sqlite y los
// recibos a la carpeta de trabajo y opera allí. Sirve como evidencia de:
// cobro atómico, número de recibo correlativo, PDF de 80 mm, idempotencia,
// anulación auditada y depósitos con topes.
import 'dart:io';

import 'package:control_alquileres/src/data/app_database.dart';
import 'package:control_alquileres/src/data/app_paths.dart';
import 'package:control_alquileres/src/data/finance_models.dart';
import 'package:control_alquileres/src/data/finance_repository.dart';
import 'package:control_alquileres/src/data/models.dart';
import 'package:control_alquileres/src/data/portfolio_repository.dart';
import 'package:control_alquileres/src/data/settings_repository.dart';
import 'package:control_alquileres/src/services/receipt_document_service.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stdout.writeln('Uso: dart run tool/phase2_flow.dart <origen> <trabajo>');
    exit(64);
  }

  final workDir = Directory(args[1])..createSync(recursive: true);
  final paths = AppPaths.create(workDir.path);
  final source = File(p.join(args[0], 'control_alquileres.sqlite'));
  if (!source.existsSync()) {
    stdout.writeln('No se encontró la base de datos de origen.');
    exit(66);
  }
  source.copySync(paths.databaseFile);

  final db = AppDatabase.openAt(paths.databaseFile);
  final portfolio = PortfolioRepository(db);
  final finance = FinanceRepository(db);
  final settings = SettingsRepository(db);
  final documents = ReceiptDocumentService(
    finance: finance,
    paths: paths,
    currentWidthMm: () => settings.load().receiptWidthMm,
  );

  stdout.writeln('== Base (copia) ==');
  stdout.writeln('versión de esquema: ${db.userVersion}');
  stdout.writeln('integridad: ${db.quickCheck() ?? 'ok'}');
  final own = settings.load().issuerName;
  if (own.trim().isEmpty) {
    settings.save(
      const OwnerSettings(
        issuerName: 'Inversiones Anamelia SRL',
        issuerId: '1-31-12345-6',
        issuerAddress: 'Av. Independencia 45, Santo Domingo',
        issuerPhone: '809-555-0000',
        printerName: null,
        receiptPrefix: 'REC',
      ),
    );
    stdout.writeln('datos del emisor: configurados para la prueba');
  } else {
    stdout.writeln('datos del emisor: $own');
  }

  final apartment = portfolio.listApartments().firstWhere(
    (a) => a.hasActiveLease,
    orElse: () => portfolio.listApartments().first,
  );
  final lease = apartment.lease;
  if (lease == null) {
    stdout.writeln('No hay contratos activos: no se puede continuar.');
    db.close();
    exit(65);
  }

  final period = finance.oldestUnpaid(lease.id);
  if (period == null) {
    stdout.writeln('El contrato no tiene períodos pendientes.');
    db.close();
    exit(0);
  }

  stdout.writeln('\n== 1. Cobro ==');
  stdout.writeln(
    'apartamento ${apartment.identifier} · inquilino ${apartment.tenantName}',
  );
  stdout.writeln(
    'período ${period.label} · debe ${_money(period.remainingCents)}',
  );
  const requestId = 'flujo-fase2-1';
  final payment = finance.registerPayment(
    requestId: requestId,
    leaseId: lease.id,
    periodYear: period.year,
    periodMonth: period.month,
    amountCents: period.remainingCents ~/ 2,
    paymentDate: DateTime.now(),
    method: PaymentMethod.efectivo,
    note: 'Pago parcial de prueba',
  );
  stdout.writeln(
    'pago #${payment.paymentId} · recibo ${payment.receiptLabel} · '
    'saldo ${_money(payment.balanceAfterCents)}',
  );

  stdout.writeln('\n== 2. Idempotencia (mismo requestId) ==');
  final duplicate = finance.registerPayment(
    requestId: requestId,
    leaseId: lease.id,
    periodYear: period.year,
    periodMonth: period.month,
    amountCents: period.remainingCents ~/ 2,
    paymentDate: DateTime.now(),
    method: PaymentMethod.efectivo,
  );
  stdout.writeln(
    'duplicado=${duplicate.duplicate} · mismo pago=${duplicate.paymentId == payment.paymentId}',
  );

  stdout.writeln('\n== 3. PDF del recibo ==');
  final receipt = finance.receipt(payment.receiptId)!;
  final document = await documents.ensure(receipt);
  final file = document.path == null ? null : File(document.path!);
  stdout.writeln('ruta: ${document.path}');
  stdout.writeln(
    'existe=${file?.existsSync()} bytes=${file?.existsSync() == true ? file!.lengthSync() : 0}',
  );

  stdout.writeln('\n== 4. Saldo del período tras el pago ==');
  final afterPayment = finance
      .periodsFor(
        lease.id,
        from: DateTime(period.year, period.month),
        to: DateTime(period.year, period.month),
      )
      .single;
  stdout.writeln(
    'pagado ${_money(afterPayment.paidCents)} · saldo ${_money(afterPayment.remainingCents)}',
  );

  stdout.writeln('\n== 5. Anulación auditada ==');
  final reversal = finance.voidPayment(
    paymentId: payment.paymentId,
    reason: 'Prueba de anulación de la Fase 2',
  );
  final reversalReceipt = finance.receipt(reversal.receiptId)!;
  final reversalDoc = await documents.ensure(reversalReceipt);
  final restored = finance
      .periodsFor(
        lease.id,
        from: DateTime(period.year, period.month),
        to: DateTime(period.year, period.month),
      )
      .single;
  stdout.writeln(
    'nota ${reversalReceipt.label} (${reversalReceipt.kind.dbValue}) · '
    'PDF=${reversalDoc.ok} · saldo restaurado ${_money(restored.remainingCents)}',
  );
  final originalStillThere = finance.receipt(payment.receiptId)!;
  stdout.writeln(
    'recibo original ${originalStillThere.label} conservado=${File(originalStillThere.pdfPath ?? '').existsSync()}',
  );

  stdout.writeln('\n== 6. Depósitos ==');
  final received = finance.registerDeposit(
    requestId: 'dep-1',
    leaseId: lease.id,
    kind: DepositKind.recibido,
    amountCents: 800000,
    movementDate: DateTime.now(),
  );
  final depositDoc = await documents.ensure(
    finance.receipt(received.receiptId)!,
  );
  stdout.writeln(
    'recibido ${_money(800000)} · retenido ${_money(received.heldAfterCents)} · PDF=${depositDoc.ok}',
  );
  try {
    finance.registerDeposit(
      requestId: 'dep-2',
      leaseId: lease.id,
      kind: DepositKind.devuelto,
      amountCents: 999999,
      movementDate: DateTime.now(),
    );
    stdout.writeln('ERROR: se permitió devolver más de lo retenido');
  } catch (error) {
    stdout.writeln('devolución excesiva rechazada: ${error.runtimeType}');
  }
  final refund = finance.registerDeposit(
    requestId: 'dep-3',
    leaseId: lease.id,
    kind: DepositKind.devuelto,
    amountCents: 300000,
    movementDate: DateTime.now(),
  );
  final retained = finance.registerDeposit(
    requestId: 'dep-4',
    leaseId: lease.id,
    kind: DepositKind.retenido,
    amountCents: 500000,
    movementDate: DateTime.now(),
    reason: 'Daños en la pintura',
  );
  await documents.ensure(finance.receipt(refund.receiptId)!);
  await documents.ensure(finance.receipt(retained.receiptId)!);
  final summary = finance.depositSummary(lease.id);
  stdout.writeln(
    'devuelto ${_money(summary.refundedCents)} · retenido por daños '
    '${_money(summary.retainedCents)} · garantía restante ${_money(summary.heldCents)}',
  );
  stdout.writeln(
    'los depósitos NO aparecen como pagos: '
    '${finance.paymentsForLease(lease.id).where((p) => !p.isVoided).length} pago(s) vigente(s)',
  );

  stdout.writeln('\n== Estado final ==');
  stdout.writeln(
    'pagos=${db.rows('SELECT COUNT(*) AS c FROM payments').first['c']} '
    'recibos=${db.rows('SELECT COUNT(*) AS c FROM receipts').first['c']} '
    'anulaciones=${db.rows('SELECT COUNT(*) AS c FROM payment_reversals').first['c']} '
    'depósitos=${db.rows('SELECT COUNT(*) AS c FROM deposit_movements').first['c']}',
  );
  final receipts = Directory(
    paths.receiptsDir,
  ).listSync().whereType<File>().toList();
  stdout.writeln('archivos PDF en la carpeta de recibos: ${receipts.length}');
  for (final file in receipts) {
    stdout.writeln('  ${p.basename(file.path)} (${file.lengthSync()} bytes)');
  }
  stdout.writeln('integridad final: ${db.quickCheck() ?? 'ok'}');
  db.close();
}

String _money(int cents) {
  final value = cents.abs();
  final whole = value ~/ 100;
  final rest = value % 100;
  final grouped = whole.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return 'RD\$ $grouped.${rest.toString().padLeft(2, '0')}';
}
