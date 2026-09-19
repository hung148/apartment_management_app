import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shared dialog surface. Existing forms keep their own scrollable body/actions.
class AppDialog extends StatelessWidget {
  final Widget? child;
  final bool scrollable;
  final Color? backgroundColor;
  final double? elevation;
  final ShapeBorder? shape;
  final EdgeInsets? insetPadding;
  final BoxConstraints? constraints;
  const AppDialog({
    super.key,
    this.scrollable = false,
    this.child,
    this.backgroundColor,
    this.elevation,
    this.shape,
    this.insetPadding,
    this.constraints,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final compact = media.size.width < 600;
    final padding = compact
        ? const EdgeInsets.all(12)
        : insetPadding ??
              const EdgeInsets.symmetric(horizontal: 32, vertical: 28);
    final height = math.max(
      0.0,
      media.size.height -
          media.viewInsets.bottom -
          media.padding.vertical -
          padding.vertical,
    );
    return Dialog(
      backgroundColor: backgroundColor ?? Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: elevation == 0 ? 8 : elevation ?? 8,
      shadowColor: const Color(0x221E1B4B),
      shape:
          shape ??
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
      clipBehavior: Clip.antiAlias,
      insetPadding: padding,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: constraints?.maxWidth ?? 800,
          maxHeight: height,
        ),
        child: scrollable ? SingleChildScrollView(child: child) : child,
      ),
    );
  }
}

/// Standard confirmations scroll their content and wrap their action buttons.
class AppAlertDialog extends AlertDialog {
  const AppAlertDialog({
    super.key,
    super.title,
    super.content,
    super.actions,
    super.shape = const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
      side: BorderSide(color: Color(0xFFE2E8F0)),
    ),
    super.titlePadding = const EdgeInsets.fromLTRB(16, 16, 16, 8),
    super.contentPadding = const EdgeInsets.fromLTRB(16, 8, 16, 16),
    super.actionsPadding = const EdgeInsets.fromLTRB(16, 8, 16, 16),
    super.insetPadding = const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 24,
    ),
    super.scrollable = true,
  });
}

