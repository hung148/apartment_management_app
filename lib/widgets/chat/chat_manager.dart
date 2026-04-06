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
            right: 15,
            bottom: 30,
            child: _ChatButton(onTap: () {}),
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

class _ChatButton extends StatefulWidget {
  final VoidCallback onTap;
  const _ChatButton({required this.onTap});

  @override
  State<_ChatButton> createState() => _ChatButtonState();
}

class _ChatButtonState extends State<_ChatButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _pressed ? 0.88 : (_hovered ? 1.08 : 1.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp:   (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: Image.asset(
            'assets/image/chat_button.png',
            width: 96,
            height: 96,
          ),
        ),
      ),
    );
  }
}