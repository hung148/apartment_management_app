import 'package:flutter/material.dart';

// ─── Combobox: dropdown + type-to-filter, built on Flutter's DropdownMenu ────
class ComboBoxField<T> extends StatelessWidget {
  final List<T> options;
  final String Function(T) labelOf;
  final T? selected;
  final String label;
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

  const ComboBoxField({
    super.key,
    required this.options,
    required this.labelOf,
    required this.selected,
    required this.label,
    this.icon,
    this.enabled = true,
    required this.onSelected,
    this.colorOf,
    this.isSelectable,
    this.menuHeight = 280,
  });

  @override
  Widget build(BuildContext context) {
    // Guard: DropdownMenu can crash internally if given an empty entry
    // list, or an initialSelection that doesn't match any entry.
    final bool hasValidSelection =
        selected != null && options.any((o) => o == selected);

    if (options.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: Colors.grey.shade400),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownMenu<T>(
        key: ValueKey(selected),
        enabled: enabled,
        enableFilter: true,
        requestFocusOnTap: true,
        initialSelection: hasValidSelection ? selected : null,
        expandedInsets: EdgeInsets.zero,
        menuHeight: menuHeight,
        // Gap between the field and the opened popup.
        alignmentOffset: const Offset(0, 4),
        label: Text(label),
        leadingIcon: icon != null
            ? Icon(icon, size: 18, color: Colors.grey.shade400)
            : null,
        textStyle: const TextStyle(fontSize: 14),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: enabled ? Colors.grey.shade50 : Colors.grey.shade100,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
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
                    textStyle: const WidgetStatePropertyAll(
                      TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
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
                    textStyle: const WidgetStatePropertyAll(
                      TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                  ),
          );
        }).toList(),
      ),
    );
  }
}