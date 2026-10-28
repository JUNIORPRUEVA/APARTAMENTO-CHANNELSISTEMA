import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'src/app/app_controller.dart';
import 'src/app/app_scope.dart';
import 'src/core/notice_center.dart';
import 'src/theme/app_theme.dart';
import 'src/ui/shell/app_shell.dart';

/// Raíz de la aplicación: alcance de estado, notificaciones y tema.
class ControlAlquileresApp extends StatefulWidget {
  const ControlAlquileresApp({
    super.key,
    required this.controller,
    this.startupNotices = const <String>[],
  });

  final AppController controller;

  /// Mensajes silenciosos del arranque (integridad, copias, documentos).
  final List<String> startupNotices;

  @override
  State<ControlAlquileresApp> createState() => _ControlAlquileresAppState();
}

class _ControlAlquileresAppState extends State<ControlAlquileresApp> {
  final NoticeCenter _notices = NoticeCenter();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (final message in widget.startupNotices) {
        _notices.show(message, tone: NoticeTone.warning);
      }
      // Recuperación silenciosa de recibos: regenera PDF pendientes o
      // perdidos desde el snapshot. Nunca vuelve a cobrar.
      final recovery = await widget.controller.recoverDocuments();
      if (!mounted) return;
      if (recovery.repaired > 0) {
        _notices.show(
          'Se regeneraron ${recovery.repaired} recibo(s) pendiente(s).',
          tone: NoticeTone.success,
        );
      } else if (recovery.failures > 0) {
        _notices.show(
          'Hay ${recovery.failures} recibo(s) que no se pudieron generar. '
          'Revise la carpeta de recibos.',
          tone: NoticeTone.warning,
        );
      }
    });
  }

  @override
  void dispose() {
    _notices.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: widget.controller,
      child: NoticesScope(
        center: _notices,
        child: MaterialApp(
          title: 'Control de Alquileres',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          locale: const Locale('es', 'DO'),
          supportedLocales: const [Locale('es', 'DO'), Locale('es')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(
              children: [
                ?child,
                NoticeOverlay(center: _notices),
              ],
            ),
          ),
          home: const AppShell(),
        ),
      ),
    );
  }
}
