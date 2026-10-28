import 'package:flutter/material.dart';

/// Iconos aprobados por el dueño (`assets/icons/*.png`).
///
/// El arte original es negro sobre fondo transparente. Para que se vea sobre
/// fondos claros y oscuros se aplica un **tinte** con [BlendMode.srcIn], que
/// solo cambia el color y respeta la transparencia: los PNG originales no se
/// editan ni se recortan.
enum AppIcon {
  home('home.png', 'Inicio'),
  apartments('apartments.png', 'Apartamentos'),
  payments('payments.png', 'Cobros'),
  settings('settings.png', 'Configuración'),
  search('search.png', 'Buscar'),
  back('back.png', 'Volver'),
  add('add.png', 'Agregar'),
  receipt('receipt.png', 'Recibo'),
  edit('edit.png', 'Editar'),
  delete('delete.png', 'Eliminar'),
  print('print.png', 'Imprimir');

  const AppIcon(this.file, this.label);

  final String file;

  /// Texto en español usado en tooltips y etiquetas de accesibilidad.
  final String label;

  String get assetPath => 'assets/icons/$file';
}

/// Pinta un icono del paquete aprobado.
///
/// * [size] es el lado del icono en píxeles lógicos (20–24 en la barra lateral).
/// * Sin [color] se dibuja tal cual (negro del original).
/// * Siempre lleva etiqueta semántica: si el control es solo icono, se pasa
///   [semanticLabel] o se usa el nombre del icono.
class AppIconView extends StatelessWidget {
  const AppIconView(
    this.icon, {
    super.key,
    this.size = 22,
    this.color,
    this.semanticLabel,
  });

  final AppIcon icon;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      icon.assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      // Tinte que conserva las transparencias del PNG original.
      color: color,
      colorBlendMode: color == null ? null : BlendMode.srcIn,
      filterQuality: FilterQuality.medium,
      semanticLabel: semanticLabel ?? icon.label,
      excludeFromSemantics: false,
      errorBuilder: (context, error, stack) => Icon(
        // Nunca se queda un hueco vacío si faltara el archivo.
        Icons.circle_outlined,
        size: size,
        color: color ?? const Color(0xFF8A93AB),
        semanticLabel: semanticLabel ?? icon.label,
      ),
    );
  }
}
