import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Notificaciones breves en la esquina superior derecha (párrafo corto,
/// lenguaje claro, sin bloqueo ni acumulación excesiva).
enum NoticeTone { info, success, warning, error }

class _Notice {
  _Notice(this.id, this.message, this.tone);

  final int id;
  final String message;
  final NoticeTone tone;
}

class NoticeCenter extends ChangeNotifier {
  final List<_Notice> _items = <_Notice>[];
  final Map<int, Timer> _timers = <int, Timer>{};
  int _sequence = 0;

  static const int _maxVisible = 3;
  static const Duration _visibleFor = Duration(seconds: 5);

  List<({int id, String message, NoticeTone tone})> get items => _items
      .map((n) => (id: n.id, message: n.message, tone: n.tone))
      .toList(growable: false);

  void show(String message, {NoticeTone tone = NoticeTone.info}) {
    final text = message.trim();
    if (text.isEmpty) return;

    // Deduplicación: si el mismo aviso ya está visible solo se reinicia su
    // tiempo en pantalla, sin apilar mensajes repetidos.
    for (final item in _items) {
      if (item.message == text) {
        _timers[item.id]?.cancel();
        _timers[item.id] = Timer(_visibleFor, () => _dismiss(item.id));
        return;
      }
    }

    final id = ++_sequence;
    _items.add(_Notice(id, text, tone));
    while (_items.length > _maxVisible) {
      _dismiss(_items.first.id);
    }
    _timers[id] = Timer(_visibleFor, () => _dismiss(id));
    notifyListeners();
  }

  void _dismiss(int id) {
    _timers.remove(id)?.cancel();
    _items.removeWhere((n) => n.id == id);
    notifyListeners();
  }

  void dismiss(int id) => _dismiss(id);

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}

/// Alcance para que cualquier pantalla publique notificaciones.
class NoticesScope extends InheritedNotifier<NoticeCenter> {
  const NoticesScope({
    super.key,
    required NoticeCenter center,
    required super.child,
  }) : super(notifier: center);

  static NoticeCenter of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<NoticesScope>();
    assert(scope != null, 'NoticesScope no encontrado en el árbol.');
    return scope!.notifier!;
  }

  /// Devuelve null si no hay alcance (útil en pruebas aisladas).
  static NoticeCenter? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NoticesScope>()?.notifier;
}

/// Capa visual de las notificaciones. Se coloca sobre toda la aplicación.
class NoticeOverlay extends StatelessWidget {
  const NoticeOverlay({super.key, required this.center});

  final NoticeCenter center;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 60, right: 16),
          child: ListenableBuilder(
            listenable: center,
            builder: (context, _) {
              final items = center.items;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _NoticeCard(
                        message: item.message,
                        tone: item.tone,
                        onClose: () => center.dismiss(item.id),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.message,
    required this.tone,
    required this.onClose,
  });

  final String message;
  final NoticeTone tone;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (tone) {
      NoticeTone.success => (
        AppColors.greenFg,
        Icons.check_circle_outline_rounded,
      ),
      NoticeTone.warning => (AppColors.amberFg, Icons.info_outline_rounded),
      NoticeTone.error => (AppColors.redFg, Icons.error_outline_rounded),
      NoticeTone.info => (AppColors.primary, Icons.notifications_none_rounded),
    };

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 320,
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A101C33),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: AppColors.textStrong,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(
                  Icons.close_rounded,
                  size: 15,
                  color: AppColors.textFaint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
