import 'package:flutter/material.dart';

// ─── Combobox: dropdown + type-to-filter, built on Flutter's DropdownMenu ────
class ComboBoxField<T> extends StatelessWidget {
  final List<T> options;
  final String Function(T) labelOf;
  final T? selected;
  final String? label;
  final IconData? icon;
  final bool enabled;
  final void Function(T?) onSelected;

  /// Optional: return a color to tint an option's label (e.g. green/red).
  final Color? Function(T)? colorOf;

  /// Optional: return false to make an option unselectable (greyed out).
  final bool Function(T)? isSelectable;

  /// Max height of the opened dropdown list. Prevents it from covering
  /// the whole dialog on long lists.
  final double menuHeight;

  final Color? fillColor;
  final Color? disabledFillColor;
  final Color? borderColor;
  final Color? focusedBorderColor;
  final Color? iconColor;
  final Color? textColor;
  final double borderRadius;
  final EdgeInsets contentPadding;

  final bool wrapInBottomPadding;

  final Widget? trailingIcon;

  final double fontSize;
  final double iconSize;
  final double entryFontSize;

  final bool showTrailingIcon;

  const ComboBoxField({
    super.key,
    required this.options,
    required this.labelOf,
    required this.selected,
    this.label,
    this.icon,
    this.enabled = true,
    required this.onSelected,
    this.colorOf,
    this.isSelectable,
    this.menuHeight = 280,
    this.fillColor,
    this.disabledFillColor,
    this.borderColor,
    this.focusedBorderColor,
    this.iconColor,
    this.textColor,
    this.borderRadius = 10,
    this.contentPadding =
        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    this.wrapInBottomPadding = true,
    this.trailingIcon,
    this.fontSize = 14,       // default matches old hardcoded value
    this.iconSize = 18,       // default matches old hardcoded value
    this.entryFontSize = 13.5,
    this.showTrailingIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    // Guard: DropdownMenu can crash internally if given an empty entry
    // list, or an initialSelection that doesn't match any entry.
    final bool hasValidSelection =
        selected != null && options.any((o) => o == selected);
    
    final Color resolvedFill =
        enabled ? (fillColor ?? Colors.grey.shade50) : (disabledFillColor ?? Colors.grey.shade100);
    final Color resolvedBorder = borderColor ?? Colors.grey.shade300;
    final Color resolvedFocusedBorder = focusedBorderColor ?? const Color(0xFF2563EB);
    final Color resolvedIconColor = iconColor ?? Colors.grey.shade400;
    final Color resolvedTextColor = textColor ?? Colors.black87;

    final Widget field = options.isEmpty
      ? Container(
          padding: contentPadding,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: iconSize, color: Colors.grey.shade400),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  label ?? '',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: fontSize),
                ),
              ),
            ],
          ),
        )
      : DropdownMenu<T>(
          key: ValueKey(selected),
          enabled: enabled,
          enableFilter: true,
          requestFocusOnTap: true,
          trailingIcon: showTrailingIcon
            ? (trailingIcon ??
                Icon(Icons.keyboard_arrow_down_rounded,
                    size: iconSize, color: resolvedIconColor))
            : const SizedBox.shrink(),
          selectedTrailingIcon: showTrailingIcon
            ? (trailingIcon ??
                Icon(Icons.keyboard_arrow_up_rounded, 
                    size: iconSize, color: resolvedIconColor))
            : const SizedBox.shrink(),
          initialSelection: hasValidSelection ? selected : null,
          expandedInsets: EdgeInsets.zero,
          menuHeight: menuHeight,
          alignmentOffset: const Offset(0, 4),
          label: label != null
            ? Text(label!, style: TextStyle(fontSize: fontSize))
            : null,
          leadingIcon: icon != null
              ? Icon(icon, size: iconSize, color: resolvedIconColor)
              : null,
          textStyle: TextStyle(fontSize: fontSize, color: resolvedTextColor),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: resolvedFill,
            isDense: true,
            contentPadding: contentPadding,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide: BorderSide(color: resolvedBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide: BorderSide(color: resolvedBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide: BorderSide(color: resolvedFocusedBorder, width: 1.8),
            ),
          ),
        // ── Menu chrome: rounded corners, soft shadow, subtle border ──
        menuStyle: MenuStyle(
          elevation: const WidgetStatePropertyAll(6),
          shadowColor:
              WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.15)),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.white),
          backgroundColor: const WidgetStatePropertyAll(Colors.white),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.grey.shade400, width: 1.2),
            ),
          ),
          padding:
              const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
        ),
        onSelected: onSelected,
        dropdownMenuEntries: options.map((o) {
          final bool selectable = isSelectable?.call(o) ?? true;
          final Color? color = colorOf?.call(o);

          return DropdownMenuEntry<T>(
            value: o,
            label: labelOf(o),
            enabled: selectable,
            // Only attach a custom style when there's an actual color —
            // a null-returning foregroundColor resolver is what caused
            // the internal DropdownMenu crash before.
            style: color == null
                ? ButtonStyle(
                    shape: const WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                    ),
                    padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
                    textStyle: WidgetStatePropertyAll(
                      TextStyle(fontWeight: FontWeight.w600, fontSize: entryFontSize),
                    ),
                  )
                : ButtonStyle(
                    foregroundColor: WidgetStatePropertyAll(color),
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.hovered) ||
                          states.contains(WidgetState.focused)) {
                        return color.withValues(alpha: 0.08);
                      }
                      return null;
                    }),
                    shape: const WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                    ),
                    padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
                    textStyle: WidgetStatePropertyAll(
                      TextStyle(fontWeight: FontWeight.w600, fontSize: entryFontSize),
                    ),
                  ),
          );
        }).toList(),
      );

    return wrapInBottomPadding
      ? Padding(padding: const EdgeInsets.only(bottom: 12), child: field)
      : field;
  }
}