import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Tipografía y medidas base. La referencia usa una tipografía humanista
/// legible (Segoe UI está disponible en Windows; Inter/Arial como respaldo).
const String kAppFontFamily = 'Segoe UI';
const List<String> kAppFontFallback = ['Inter', 'Arial', 'Roboto'];

abstract final class AppMetrics {
  static const double appBarHeight = 50;
  static const double sidebarWidth = 72;
  static const double pagePadding = 16;
  static const double gap = 14;
  static const double cardRadius = 12;
  static const double fieldRadius = 8;
  static const double controlHeight = 40;
  static const double rowHeight = 42;
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.light(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    secondary: AppColors.navy,
    onSecondary: Colors.white,
    surface: AppColors.card,
    onSurface: AppColors.textStrong,
    error: AppColors.red,
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: kAppFontFamily,
    fontFamilyFallback: kAppFontFallback,
    scaffoldBackgroundColor: AppColors.pageBg,
    visualDensity: VisualDensity.compact,
    splashFactory: InkSparkle.splashFactory,
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: const TextStyle(fontSize: 13, color: AppColors.textFaint),
      labelStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
      errorStyle: const TextStyle(fontSize: 11.5, color: AppColors.redFg),
      border: _border(AppColors.border),
      enabledBorder: _border(AppColors.border),
      disabledBorder: _border(AppColors.border),
      focusedBorder: _border(AppColors.primary, width: 1.4),
      errorBorder: _border(AppColors.red),
      focusedErrorBorder: _border(AppColors.red, width: 1.4),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 400),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStateProperty.all(const Color(0xFFC3CDDD)),
    ),
  );
}

OutlineInputBorder _border(Color color, {double width = 1}) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppMetrics.fieldRadius),
    borderSide: BorderSide(color: color, width: width),
  );
}

/// Estilos con nombre propio para no depender de los tamaños genéricos de
/// Material. Se accede como `appText.pageTitle`.
@immutable
class AppTextStyles {
  const AppTextStyles();

  TextStyle get pageTitle => const TextStyle(
    fontSize: 23,
    fontWeight: FontWeight.w800,
    color: AppColors.textStrong,
    letterSpacing: -0.3,
    height: 1.15,
  );

  TextStyle get cardTitle => const TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w800,
    color: AppColors.textStrong,
    letterSpacing: -0.1,
  );

  TextStyle get tableHead => const TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w700,
    color: AppColors.textStrong,
  );

  TextStyle get bodyCell => const TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textBody,
  );

  TextStyle get fieldLabel => const TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
    color: AppColors.textMuted,
  );

  TextStyle get infoLabel =>
      const TextStyle(fontSize: 13, color: AppColors.textMuted);

  TextStyle get infoValue => const TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w600,
    color: AppColors.textStrong,
  );

  TextStyle get sectionTitle => const TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w800,
    color: AppColors.textStrong,
  );
}

const AppTextStyles appText = AppTextStyles();
