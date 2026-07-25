import 'package:flutter/material.dart';

// ─── Combobox: dropdown + type-to-filter, built on Flutter's DropdownMenu ────
class ComboBoxField<T> extends StatefulWidget {
  final List<T> options;
  final String Function(T) labelOf;
  final T? selected;
  final String? label;
  final IconData? icon;
  final bool enabled;
  final void Function(T?) onSelected;

  final Color? Function(T)? colorOf;
  final Color? Function(T)? dotColorOf;

  final EdgeInsets leadingPadding;
  final FontWeight fontWeight;

  final bool Function(T)? isSelectable;
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
    this.dotColorOf,
    this.leadingPadding = const EdgeInsets.only(left: 4, right: 4),
    this.fontWeight = FontWeight.normal,
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
    this.fontSize = 14,
    this.iconSize = 18,
    this.entryFontSize = 13.5,
    this.showTrailingIcon = true,
  });

  @override
  State<ComboBoxField<T>> createState() => _ComboBoxFieldState<T>();
}

class _ComboBoxFieldState<T> extends State<ComboBoxField<T>> {
  late TextEditingController _controller;
  bool _suppressListener = false;

  bool get _hasValidSelection =>
      widget.selected != null && widget.options.any((o) => o == widget.selected);

  String get _selectedLabel =>
      _hasValidSelection ? widget.labelOf(widget.selected as T) : '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _selectedLabel);
    _controller.addListener(_handleTextChange);
  }

  @override
  void didUpdateWidget(covariant ComboBoxField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the field text in sync when `selected` changes externally
    // (e.g. auto-fill from a cascading building/room/tenant pick).
    final newLabel = _selectedLabel;
    if (_controller.text != newLabel) {
      _suppressListener = true;
      _controller.text = newLabel;
      _suppressListener = false;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChange);
    _controller.dispose();
    super.dispose();
  }

  void _handleTextChange() {
    if (_suppressListener) return;
    // The user cleared the field by deleting text (not via selection or
    // Enter) — treat that as an explicit "unselect" so cascading fields
    // reset immediately instead of waiting for a confirmed pick.
    if (_controller.text.isEmpty && widget.selected != null) {
      widget.onSelected(null);
    }
  }

  Widget _dot(Color color, {double size = 10}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  @override
  Widget build(BuildContext context) {
    final Color resolvedFill = widget.enabled
        ? (widget.fillColor ?? Colors.grey.shade50)
        : (widget.disabledFillColor ?? Colors.grey.shade100);
    final Color resolvedBorder = widget.borderColor ?? Colors.grey.shade300;
    final Color resolvedFocusedBorder =
        widget.focusedBorderColor ?? const Color(0xFF2563EB);
    final Color resolvedIconColor = widget.iconColor ?? Colors.grey.shade400;
    final Color resolvedTextColor = widget.textColor ?? Colors.black87;

    Widget? buildFieldLeading() {
      if (widget.icon == null && widget.dotColorOf == null) return null;
      final Color? currentDot =
          (widget.dotColorOf != null && _hasValidSelection)
              ? widget.dotColorOf!(widget.selected as T)
              : null;
      return Padding(
        padding: widget.leadingPadding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.icon != null)
              Icon(widget.icon, size: widget.iconSize, color: resolvedIconColor),
            if (widget.icon != null && currentDot != null) const SizedBox(width: 8),
            if (currentDot != null) _dot(currentDot, size: widget.iconSize * 0.55),
          ],
        ),
      );
    }

    final Widget field = widget.options.isEmpty
        ? Container(
            padding: widget.contentPadding,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: widget.iconSize, color: Colors.grey.shade400),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    widget.label ?? '',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: widget.fontSize),
                  ),
                ),
              ],
            ),
          )
        : DropdownMenu<T>(
            controller: _controller,
            enabled: widget.enabled,
            enableFilter: true,
            filterCallback: (entries, filter) {
              if (filter.isEmpty) return entries;
              final lowerFilter = filter.toLowerCase();
              return entries
                  .where((e) => e.label.toLowerCase().contains(lowerFilter))
                  .toList();
            },
            requestFocusOnTap: true,
            trailingIcon: widget.showTrailingIcon
                ? (widget.trailingIcon ??
                    Icon(Icons.keyboard_arrow_down_rounded,
                        size: widget.iconSize, color: resolvedIconColor))
                : const SizedBox.shrink(),
            selectedTrailingIcon: widget.showTrailingIcon
                ? (widget.trailingIcon ??
                    Icon(Icons.keyboard_arrow_up_rounded,
                        size: widget.iconSize, color: resolvedIconColor))
                : const SizedBox.shrink(),
            expandedInsets: EdgeInsets.zero,
            menuHeight: widget.menuHeight,
            alignmentOffset: const Offset(0, 4),
            label: widget.label != null
                ? Text(widget.label!, style: TextStyle(fontSize: widget.fontSize))
                : null,
            leadingIcon: buildFieldLeading(),
            textStyle: TextStyle(
              fontSize: widget.fontSize,
              color: resolvedTextColor,
              fontWeight: widget.fontWeight,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: resolvedFill,
              isDense: true,
              contentPadding: widget.contentPadding,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                borderSide: BorderSide(color: resolvedBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                borderSide: BorderSide(color: resolvedBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                borderSide: BorderSide(color: resolvedFocusedBorder, width: 1.8),
              ),
            ),
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
              padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(vertical: 6)),
            ),
            onSelected: widget.onSelected,
            dropdownMenuEntries: widget.options.map((o) {
              final bool selectable = widget.isSelectable?.call(o) ?? true;
              final Color? textColorForOption = widget.colorOf?.call(o);
              final Color? dotColorForOption = widget.dotColorOf?.call(o);

              return DropdownMenuEntry<T>(
                value: o,
                label: widget.labelOf(o),
                enabled: selectable,
                leadingIcon:
                    dotColorForOption != null ? _dot(dotColorForOption) : null,
                style: textColorForOption == null
                    ? ButtonStyle(
                        shape: const WidgetStatePropertyAll(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                        ),
                        padding: const WidgetStatePropertyAll(
                            EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
                        textStyle: WidgetStatePropertyAll(
                          TextStyle(
                              fontWeight: FontWeight.w600, fontSize: widget.entryFontSize),
                        ),
                      )
                    : ButtonStyle(
                        foregroundColor: WidgetStatePropertyAll(textColorForOption),
                        backgroundColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.hovered) ||
                              states.contains(WidgetState.focused)) {
                            return textColorForOption.withValues(alpha: 0.08);
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
                          TextStyle(
                              fontWeight: FontWeight.w600, fontSize: widget.entryFontSize),
                        ),
                      ),
              );
            }).toList(),
          );

    return widget.wrapInBottomPadding
        ? Padding(padding: const EdgeInsets.only(bottom: 12), child: field)
        : field;
  }
}