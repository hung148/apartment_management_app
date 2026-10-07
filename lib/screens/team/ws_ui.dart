import 'workspace_page_scope.dart';
import 'package:flutter/material.dart';

/// Shared look for the version-2 organization workspace (U1 redesign).
///
/// Every page inside the workspace is built from these pieces so the whole
/// area reads as one product: a compact header (title, short help, actions),
/// bordered cards on the neutral background, record rows with a status pill
/// and small action buttons, and the same empty / error states everywhere.
/// Colors always come from the app theme (the user's chosen accent).

/// Compact density for everything inside the workspace, including dialogs
/// opened from it (dialogs capture the theme of the page that opens them).
ThemeData workspaceTheme(ThemeData base) {
  final s = base.colorScheme;
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
  const label = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
  const padding = EdgeInsets.symmetric(horizontal: 14, vertical: 8);
  final text = base.textTheme;
  return base.copyWith(
    visualDensity: VisualDensity.compact,
    textTheme: text.copyWith(
      headlineSmall: text.headlineSmall?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      color: s.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: s.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(40, 40),
        padding: padding,
        shape: shape,
        textStyle: label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(40, 40),
        padding: padding,
        shape: shape,
        textStyle: label,
        foregroundColor: s.primary,
        side: BorderSide(color: s.outlineVariant),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(40, 40),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: shape,
        textStyle: label,
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: StadiumBorder(side: BorderSide(color: s.outlineVariant)),
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      showCheckmark: false,
      selectedColor: s.primary,
      secondaryLabelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: s.onPrimary,
      ),
    ),
    listTileTheme: base.listTileTheme.copyWith(
      dense: true,
      shape: shape,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
    ),
    progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
      linearMinHeight: 3,
      linearTrackColor: s.primary.withValues(alpha: 0.12),
    ),
    dividerTheme: DividerThemeData(color: s.outlineVariant, space: 1),
    // One field style for every form in the workspace (labels inside the box).
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      isDense: true,
      filled: true,
      fillColor: s.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: WsSpace.md,
        vertical: WsSpace.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: s.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: s.outlineVariant),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: s.outlineVariant.withValues(alpha: 0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: s.primary, width: 1.5),
      ),
      errorMaxLines: 4,
      helperMaxLines: 3,
      // Examples in empty fields must not look like typed values.
      hintStyle: TextStyle(color: s.onSurfaceVariant.withValues(alpha: 0.5)),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      behavior: SnackBarBehavior.floating,
      shape: shape,
    ),
  );
}

/// Spacing scale for workspace pages (multiples of a 4 px base).
abstract class WsSpace {
  static const double unit = 4;
  static const double xs = unit; // 4
  static const double sm = 2 * unit; // 8
  static const double md = 3 * unit; // 12
  static const double lg = 4 * unit; // 16
  static const double xl = 6 * unit; // 24
}

/// A titled card that groups related fields (form sections, detail blocks).
class WsSection extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget? trailing;
  final List<Widget> children;
  const WsSection({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(WsSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The action stays on one line at the right; when the title and
            // the action do not fit side by side, the action moves under the
            // title (never squeezed into a two-line button).
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: WsSpace.sm,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: WsSpace.sm),
                    ],
                    Flexible(
                      child: Text(title, style: theme.textTheme.titleSmall),
                    ),
                  ],
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: WsSpace.md),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Fields side by side on wide screens, stacked on phones / large text.
class WsFieldRow extends StatelessWidget {
  final List<Widget> children;
  final double breakpoint;
  const WsFieldRow({super.key, required this.children, this.breakpoint = 520});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final wide =
          c.maxWidth >= breakpoint &&
          MediaQuery.textScalerOf(context).scale(14) <= 14 * 1.3;
      if (!wide) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: WsSpace.md),
              children[i],
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: WsSpace.md),
            Expanded(child: children[i]),
          ],
        ],
      );
    },
  );
}

/// "Label   value" line in a detail view.
class WsInfo extends StatelessWidget {
  final String label;
  final String value;
  const WsInfo(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WsSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: WsSpace.sm),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Buttons at the end of a form or card: right-aligned, only as wide as
/// their labels, wrapping onto a new line when space runs out.
class WsActions extends StatelessWidget {
  final List<Widget> children;
  const WsActions({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: WsSpace.md),
    child: Wrap(
      alignment: WrapAlignment.end,
      spacing: WsSpace.sm,
      runSpacing: WsSpace.sm,
      children: children,
    ),
  );
}

/// Scrollable page body: 16 px gutters, filling an organization workspace.
/// Standalone forms retain their requested readable width.
class WsPage extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;
  final ScrollController? controller;
  const WsPage({
    super.key,
    required this.children,
    this.maxWidth = 960,
    this.controller,
  });

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: WorkspacePageScope.constraints(context, maxWidth),
      // Not a lazy ListView: pages are short, and every field, message and
      // button must stay built (focus, validation messages, tests).
      child: SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

/// Page title with a short help line and the page's actions on the right
/// (they move under the title on narrow screens).
class WsHeader extends StatelessWidget {
  final String title;
  final String? help;
  final List<Widget> actions;

  /// Shown as a small "back" link above the title (one step back).
  final Widget? back;
  const WsHeader({
    super.key,
    required this.title,
    this.help,
    this.actions = const [],
    this.back,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // An empty title: the page sits in a dialog that already names it.
        if (title.isNotEmpty) Text(title, style: theme.textTheme.headlineSmall),
        if (help != null && help!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            help!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (back != null)
            Align(alignment: AlignmentDirectional.centerStart, child: back!),
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 560;
              if (actions.isEmpty) return heading;
              final buttons = Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: wide ? WrapAlignment.end : WrapAlignment.start,
                children: actions,
              );
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: heading),
                        const SizedBox(width: 12),
                        // Actions sit at the right edge, not in the middle.
                        Flexible(
                          child: Align(
                            alignment: AlignmentDirectional.topEnd,
                            child: buttons,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [heading, const SizedBox(height: 10), buttons],
                    );
            },
          ),
        ],
      ),
    );
  }
}

/// Small "‹ label" link that goes one step back.
class WsBack extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const WsBack({super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      minimumSize: const Size(40, 36),
    ),
    icon: const Icon(Icons.chevron_left, size: 20),
    label: Text(label),
  );
}

enum WsTone { neutral, good, warning, bad, info }

Color wsToneColor(BuildContext context, WsTone tone) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (tone) {
    WsTone.good => dark ? const Color(0xFF6FCF97) : const Color(0xFF1E7B45),
    WsTone.warning => dark ? const Color(0xFFF2C94C) : const Color(0xFF9A5B00),
    WsTone.bad => dark ? const Color(0xFFFF8A80) : const Color(0xFFB3261E),
    WsTone.info => Theme.of(context).colorScheme.primary,
    WsTone.neutral => Theme.of(context).colorScheme.onSurfaceVariant,
  };
}

/// Status pill (paid / pending / active …).
class WsPill extends StatelessWidget {
  final String label;
  final WsTone tone;
  const WsPill(this.label, {super.key, this.tone = WsTone.neutral});

  @override
  Widget build(BuildContext context) {
    final color = wsToneColor(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// One record: title + pill on the first line, detail lines underneath, the
/// record's actions as small buttons at the bottom. A tone colors the left
/// edge (like the v1 payment cards).
class WsRecord extends StatelessWidget {
  final String title;
  final Widget? leading;
  final Widget? pill;
  final List<String> details;
  final List<Widget> actions;
  final WsTone? tone;
  final VoidCallback? onTap;

  /// Key on the tappable area (tests and links open a record by key).
  final Key? tapKey;
  const WsRecord({
    super.key,
    required this.title,
    this.leading,
    this.pill,
    this.details = const [],
    this.actions = const [],
    this.tone,
    this.onTap,
    this.tapKey,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.4,
    );
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // The pill gives way to the title on narrow screens / big text.
                    if (pill != null) ...[
                      const SizedBox(width: 8),
                      // Right-aligned; shrinks (ellipsis) instead of pushing.
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width < 400
                              ? 120
                              : 200,
                        ),
                        child: pill!,
                      ),
                    ],
                  ],
                ),
                for (final line in details)
                  if (line.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(line, style: muted),
                    ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, children: actions),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: tapKey,
        onTap: onTap,
        child: tone == null
            ? body
            : DecoratedBox(
                decoration: BoxDecoration(
                  border: BorderDirectional(
                    start: BorderSide(
                      color: wsToneColor(context, tone!),
                      width: 3,
                    ),
                  ),
                ),
                child: body,
              ),
      ),
    );
  }
}

/// Letters in a tinted square (room numbers, people).
class WsBadge extends StatelessWidget {
  final String text;
  final IconData? icon;
  const WsBadge({super.key, this.text = '', this.icon});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: s.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: icon != null
          ? Icon(icon, size: 20, color: s.primary)
          : Text(
              text.length > 4 ? text.substring(0, 4) : text,
              maxLines: 1,
              style: TextStyle(
                color: s.primary,
                fontWeight: FontWeight.w700,
                fontSize: text.length > 3 ? 11 : 13,
              ),
            ),
    );
  }
}

/// Nothing here yet: icon, one sentence, optional next step.
class WsEmpty extends StatelessWidget {
  final IconData icon;
  final String message;
  final Widget? action;
  const WsEmpty({
    super.key,
    required this.icon,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 36, color: theme.colorScheme.outline),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

/// Something went wrong: what happened + try again.
class WsNotice extends StatelessWidget {
  final String message;
  final WsTone tone;
  final Widget? action;
  const WsNotice(
    this.message, {
    super.key,
    this.tone = WsTone.bad,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final color = wsToneColor(context, tone);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            tone == WsTone.good
                ? Icons.check_circle_outline
                : tone == WsTone.bad
                ? Icons.error_outline
                : Icons.info_outline,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontWeight: FontWeight.w500),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
