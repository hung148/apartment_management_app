import 'dart:ui';

import 'package:flutter/material.dart';

/// A quiet glass surface keeps the settings action legible over the hero photo.
class DashboardSettingsButton extends StatelessWidget {
  const DashboardSettingsButton({
    super.key,
    required this.onPressed,
    required this.tooltip,
    this.showBadge = false,
  });

  final VoidCallback onPressed;
  final String tooltip;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.46),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Same 40x40 rounded square as the glass behind it, so the hover
          // and press highlight line up with the visible button. The tap
          // target stays 48x48.
          IconButton(
            onPressed: onPressed,
            tooltip: tooltip,
            style: IconButton.styleFrom(
              foregroundColor: Colors.white,
              fixedSize: const Size.square(40),
              minimumSize: const Size.square(40),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ).copyWith(
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return Colors.white.withValues(alpha: 0.24);
                }
                if (states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)) {
                  return Colors.white.withValues(alpha: 0.14);
                }
                return null;
              }),
            ),
            icon: Badge(
              isLabelVisible: showBadge,
              child: const Icon(Icons.settings_outlined),
            ),
          ),
        ],
      ),
    );
  }
}
