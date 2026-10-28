import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/notice_center.dart';
import '../../../data/models.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/common.dart';
import '../home/apartment_detail_card.dart';
import '../home/apartment_list_card.dart';
import '../home/payment_card.dart';
import '../home/payment_history_card.dart';

/// **Cobros**: el único espacio donde se registra dinero y se ven los recibos.
///
/// Contiene, una sola vez:
/// * el selector de apartamento (con el mismo componente de Inicio);
/// * el formulario de cobro real (efectivo/transferencia, abono o total);
/// * el historial de pagos del apartamento con *Ver PDF*, *Reimprimir* y
///   *Anular* (anulación auditada, nunca borrado).
///
/// Los depósitos se manejan desde la ficha del apartamento (misma lógica ya
/// probada), sin duplicar aquí el formulario.
class CobrosPage extends StatelessWidget {
  const CobrosPage({super.key});

  static const double _wideBreakpoint = 1080;
  static const double _gap = 14;
  static const EdgeInsets _padding = EdgeInsets.all(16);

  void _select(BuildContext context, ApartmentRow apartment) {
    final controller = AppScope.read(context);
    if (controller.selectedApartmentId == apartment.id) return;
    controller.selectApartment(apartment.id);
    NoticesScope.maybeOf(context)?.show(
      'Apartamento ${apartment.identifier} seleccionado.',
      tone: NoticeTone.info,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final apartment = controller.selectedApartment;
    final hasApartment = apartment?.lease != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideBreakpoint;

        final header = _Header(apartment: apartment, hasLease: hasApartment);

        // Sin apartamento seleccionado: se pide elegir uno en el mismo lugar,
        // sin pantallas nuevas.
        if (!hasApartment) {
          return SingleChildScrollView(
            padding: _padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: _gap),
                SizedBox(
                  height: 320,
                  child: ApartmentListCard(
                    title: 'Elija el apartamento a cobrar',
                    showCreate: false,
                    onCobrar: (row) => _select(context, row),
                  ),
                ),
              ],
            ),
          );
        }

        if (wide) {
          // Columna izquierda: cobro + historial (lo que se usa al cobrar).
          // Columna derecha: datos del inquilino y depósito (contexto).
          return Padding(
            padding: _padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 12),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 58,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // `bounded: false`: el alto lo pone el scroll,
                              // nunca un Expanded dentro de una columna.
                              const PaymentCard(bounded: false),
                              const SizedBox(height: _gap),
                              const PaymentHistoryCard(bounded: false),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: _gap),
                      Expanded(
                        flex: 42,
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              const ApartmentDetailCard(bounded: false),
                              const SizedBox(height: _gap),
                              SizedBox(
                                height: 240,
                                child: ApartmentListCard(
                                  title: 'Cambiar de apartamento',
                                  showCreate: false,
                                  onCobrar: (row) => _select(context, row),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        // Portátil pequeño: una sola columna en el orden de uso.
        return SingleChildScrollView(
          padding: _padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 12),
              const PaymentCard(bounded: false),
              const SizedBox(height: _gap),
              const PaymentHistoryCard(bounded: false),
              const SizedBox(height: _gap),
              const ApartmentDetailCard(bounded: false),
            ],
          ),
        );
      },
    );
  }
}

/// Encabezado compacto: qué apartamento se está cobrando y su estado.
class _Header extends StatelessWidget {
  const _Header({required this.apartment, required this.hasLease});

  final ApartmentRow? apartment;
  final bool hasLease;

  @override
  Widget build(BuildContext context) {
    final text = apartment == null
        ? 'Elija un apartamento para registrar un cobro'
        : 'Apartamento ${apartment!.identifier} · ${apartment!.groupName}';
    final detail = !hasLease
        ? 'Sin contrato activo'
        : '${apartment!.tenantName ?? 'Sin inquilino'} · '
              '${apartment!.rentStatus.label}';

    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const AppIconView(AppIcon.payments, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cobros', style: appText.cardTitle.copyWith(fontSize: 16)),
                const SizedBox(height: 2),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textBody,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (hasLease)
            OutlineButton(
              label: 'Cambiar',
              appIcon: AppIcon.back,
              dense: true,
              height: 30,
              onPressed: () => AppScope.read(context).selectApartment(null),
            ),
          if (hasLease) const SizedBox(width: 8),
          if (hasLease)
            StatusPill(
              label: apartment!.rentStatus.label,
              tone: toneForStatus(apartment!.rentStatus),
            ),
        ],
      ),
    );
  }
}
