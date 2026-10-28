import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/notice_center.dart';
import '../../../data/models.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../../dialogs/dialogs.dart';
import '../../widgets/common.dart';
import '../home/apartment_list_card.dart';
import '../home/payment_card.dart';

/// Cobros: selección del apartamento y formulario de pago.
///
/// En la Fase 1 el cobro está deshabilitado de forma explícita: no se guarda
/// ningún pago ni se emite ningún recibo.
class CobrosPage extends StatelessWidget {
  const CobrosPage({super.key});

  void _cobrar(BuildContext context, ApartmentRow apartment, bool wide) {
    AppScope.read(context).selectApartment(apartment.id);
    if (wide) {
      NoticesScope.maybeOf(context)?.show(
        'El registro de pagos se habilitará en la siguiente etapa.',
        tone: NoticeTone.info,
      );
    } else {
      showPaymentDialog(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1080;
        if (wide) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _CobrosHeader(),
                const SizedBox(height: 12),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        flex: 56,
                        child: ApartmentListCard(
                          title: 'Apartamentos con contrato',
                          showCreate: false,
                          onCobrar: (apartment) =>
                              _cobrar(context, apartment, true),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(flex: 44, child: PaymentCard()),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const _CobrosHeader(),
              const SizedBox(height: 12),
              ApartmentListCard(
                title: 'Apartamentos con contrato',
                showCreate: false,
                bounded: false,
                onCobrar: (apartment) => _cobrar(context, apartment, false),
              ),
              const SizedBox(height: 14),
              const PaymentCard(bounded: false),
            ],
          ),
        );
      },
    );
  }
}

class _CobrosHeader extends StatelessWidget {
  const _CobrosHeader();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const Icon(
            Icons.account_balance_wallet_rounded,
            size: 22,
            color: AppColors.navy,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cobros', style: appText.cardTitle.copyWith(fontSize: 17)),
                const SizedBox(height: 2),
                const Text(
                  'Seleccione un apartamento para ver su estado de cuenta. '
                  'El registro de pagos, los recibos de 80 mm y la impresora '
                  'se habilitarán en la siguiente etapa.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
