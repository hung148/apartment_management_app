import 'package:apartment_management_project_2/main.dart';
import 'package:flutter/material.dart';

class ChatOverlayManager {
  static OverlayEntry? _entry;

  static void install() {
    final context = navigatorKey.currentState?.overlay?.context;
    if (context == null) return;

    _entry?.remove();
    _entry = OverlayEntry(
      builder: (context) => Positioned(
        right: 16,
        bottom: 80,
        child: FloatingActionButton(
          onPressed: () {

          }
        ),
      ),
    );
    navigatorKey.currentState!.overlay!.insert(_entry!);
  }

  static void uninstall() {
    _entry?.remove();
    _entry = null;
  }

}