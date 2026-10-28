import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../core/notice_center.dart';
import '../../../data/models.dart';
import '../home/apartment_detail_card.dart';
import '../home/apartment_list_card.dart';

/// **Inicio**: el trabajo del día.
///
/// Se elige el residencial y el apartamento, se ve el estado del inquilino y se
/// pulsa **Cobrar**, que lleva al espacio de cobros con ese apartamento ya
/// seleccionado. Aquí **no** hay formulario de pago ni historial: existe una
/// sola versión de cada uno (en `Cobros`).
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static const double _wideBreakpoint = 1040;
  static const double _gap = 14;
  static const EdgeInsets _padding = EdgeInsets.all(16);

  /// Lleva al apartamento al espacio de cobros (pantalla única y canónica).
  void _cobrar(BuildContext context, ApartmentRow apartment) {
    final controller = AppScope.read(context);
    controller.startPaymentFor(apartment.id);
    NoticesScope.maybeOf(context)?.show(
      'Apartamento ${apartment.identifier} listo para cobrar.',
      tone: NoticeTone.info,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // En pantallas anchas: lista + ficha del apartamento.
        // En pantallas angostas (portátil 11.6"): una sola columna con la lista
        // primero y la ficha debajo; nunca dos pantallas completas al lado.
        final wide = constraints.maxWidth >= _wideBreakpoint;

        if (wide) {
          return Padding(
            padding: _padding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 62,
                  child: ApartmentListCard(
                    onCobrar: (apartment) => _cobrar(context, apartment),
                  ),
                ),
                const SizedBox(width: _gap),
                Expanded(
                  flex: 38,
                  child: SingleChildScrollView(
                    child: ApartmentDetailCard(bounded: false),
                  ),
                ),
              ],
            ),
          );
        }

        // Altura de la lista acotada para que la ficha siempre sea alcanzable
        // sin quedar atrapada en dos scrolls anidados.
        final listHeight = (constraints.maxHeight * 0.56).clamp(240.0, 420.0);
        return SingleChildScrollView(
          padding: _padding,
          child: Column(
            children: [
              SizedBox(
                height: listHeight,
                child: ApartmentListCard(
                  onCobrar: (apartment) => _cobrar(context, apartment),
                ),
              ),
              const SizedBox(height: _gap),
              ApartmentDetailCard(bounded: false),
            ],
          ),
        );
      },
    );
  }
}
