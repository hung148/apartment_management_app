// chat_manager.dart
import 'package:apartment_management_project_2/main.dart';
import 'package:flutter/material.dart';

class ChatOverlayManager {
  static OverlayEntry? _entry;
  static final ValueNotifier<bool> _visible = ValueNotifier(false);

  static void install() {
    _visible.value = true;
    _reinsertOnTop();
  }

  static void uninstall() {
    _visible.value = false;
  }

  static void _reinsertOnTop() {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    // Remove and re-insert so it sits above any dialog entries
    _entry?.remove();
    _entry = OverlayEntry(
      builder: (_) => ValueListenableBuilder<bool>(
        valueListenable: _visible,
        builder: (_, visible, __) {
          if (!visible) return const SizedBox.shrink();
          return Positioned(
            right: 16,
            bottom: 80,
            child: Material(
              color: Colors.transparent,
              child: FloatingActionButton(
                heroTag: 'global_chat_fab',
                onPressed: () {},
                child: const Icon(Icons.chat_bubble_outline_rounded),
              ),
            ),
          );
        },
      ),
    );
    overlay.insert(_entry!);
  }

  static void dispose() {
    _entry?.remove();
    _entry = null;
    _visible.value = false;
  }
}