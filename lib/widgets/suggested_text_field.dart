import 'package:flutter/material.dart';

/// Free text with optional preset values. Typing never requires a menu selection.
class SuggestedTextField extends StatefulWidget {
  final String value;
  final String label;
  final List<String> options;
  final String Function(String)? labelOf;
  final ValueChanged<String> onChanged;
  final int maxLength;

  const SuggestedTextField({
    super.key,
    required this.value,
    required this.label,
    required this.options,
    required this.onChanged,
    this.labelOf,
    this.maxLength = 200,
  });

  @override
  State<SuggestedTextField> createState() => _SuggestedTextFieldState();
}

class _SuggestedTextFieldState extends State<SuggestedTextField> {
  late final _controller = TextEditingController(text: _label(widget.value));
  String? _lastTyped;
  String _label(String value) => widget.labelOf?.call(value) ?? value;

  @override
  void didUpdateWidget(covariant SuggestedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _lastTyped &&
        _controller.text != _label(widget.value)) {
      _controller.text = _label(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: _controller,
    maxLength: widget.maxLength,
    textCapitalization: TextCapitalization.sentences,
    onChanged: (value) {
      _lastTyped = value;
      widget.onChanged(value);
    },
    decoration: InputDecoration(
      labelText: widget.label,
      border: const OutlineInputBorder(),
      counterText: '',
      suffixIcon: PopupMenuButton<String>(
        tooltip: widget.label,
        icon: const Icon(Icons.keyboard_arrow_down),
        onSelected: (value) {
          _lastTyped = null;
          _controller.text = _label(value);
          widget.onChanged(value);
        },
        itemBuilder: (_) => widget.options
            .map(
              (value) =>
                  PopupMenuItem(value: value, child: Text(_label(value))),
            )
            .toList(),
      ),
    ),
  );
}
