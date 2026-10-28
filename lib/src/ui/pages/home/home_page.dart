import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/notice_center.dart';
import '../../../data/models.dart';
import '../../dialogs/dialogs.dart';
import 'apartment_detail_card.dart';
import 'apartment_list_card.dart';
import 'payment_card.dart';
import 'payment_history_card.dart';

/// Pantalla de Inicio: reproduce el panel aprobado.
///
/// Dos modos de composición, sin recortes ni texto diminuto:
/// * amplio (>= 1180 px): tabla + ficha arriba, cobro + historial abajo;
/// * compacto: una sola columna desplazable y el cobro se abre en un diálogo.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static const double _wideBreakpoint = 1180;

  /// Alto mínimo (de contenido, sin barra de título ni márgenes) para usar el
  /// diseño de dos filas. En pantallas de 768 px de alto se pasa a la columna
  /// única: así no quedan paneles con scroll diminuto ni botones recortados.
  static const double _minWideHeight = 780;
  static const double _gap = 14;
  static const EdgeInsets _padding = EdgeInsets.all(16);

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
        final wide =
            constraints.maxWidth >= _wideBreakpoint &&
            constraints.maxHeight >= _minWideHeight;

        if (wide) {
          // La fila inferior se dimensiona según el alto real: nunca recorta
          // el botón de guardar y deja que la tabla se desplace internamente.
          final available = constraints.maxHeight - _padding.vertical - _gap;
          final bottomHeight = (available * 0.46).clamp(300.0, 400.0);
          final topHeight = (available - bottomHeight).clamp(190.0, 1000.0);

          return Padding(
            padding: _padding,
            child: Column(
              children: [
                SizedBox(
                  height: topHeight,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 64,
                        child: ApartmentListCard(
                          onCobrar: (apartment) =>
                              _cobrar(context, apartment, true),
                        ),
                      ),
                      const SizedBox(width: _gap),
                      const Expanded(flex: 36, child: ApartmentDetailCard()),
                    ],
                  ),
                ),
                const SizedBox(height: _gap),
                SizedBox(
                  height: bottomHeight,
                  child: const Row(
                    children: [
                      Expanded(flex: 48, child: PaymentCard()),
                      SizedBox(width: _gap),
                      Expanded(flex: 52, child: PaymentHistoryCard()),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final listHeight = (constraints.maxHeight * 0.52).clamp(300.0, 460.0);

        return SingleChildScrollView(
          padding: _padding,
          child: Column(
            children: [
              SizedBox(
                height: listHeight,
                child: ApartmentListCard(
                  onCobrar: (apartment) => _cobrar(context, apartment, false),
                ),
              ),
              const SizedBox(height: _gap),
              const ApartmentDetailCard(bounded: false),
              const SizedBox(height: _gap),
              const PaymentCard(bounded: false),
              const SizedBox(height: _gap),
              const PaymentHistoryCard(bounded: false),
            ],
          ),
        );
      },
    );
  }
}
