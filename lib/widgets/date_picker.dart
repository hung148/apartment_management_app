import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_localizations.dart';

class LocalizedDatePicker extends StatefulWidget {
  final String labelText;
  final DateTime? initialDate, firstDate, lastDate;
  final ValueChanged<DateTime?>? onDateChanged;
  final String? Function(DateTime?)? validator;
  final bool required, enabled;
  final IconData? prefixIcon;
  const LocalizedDatePicker({
    super.key,
    required this.labelText,
    this.initialDate,
    this.firstDate,
    this.lastDate,
    this.onDateChanged,
    this.validator,
    this.required = false,
    this.prefixIcon,
    this.enabled = true,
  });
  @override
  State<LocalizedDatePicker> createState() => _LocalizedDatePickerState();
}

class _LocalizedDatePickerState extends State<LocalizedDatePicker> {
  final _controller = TextEditingController();
  final _fieldKey = GlobalKey<FormFieldState<String>>();
  DateTime? _date;
  DateTime get _first => DateUtils.dateOnly(widget.firstDate ?? DateTime(1900));
  DateTime get _last => DateUtils.dateOnly(widget.lastDate ?? DateTime(2100));
  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
  }

  void _syncText() {
    _controller.text = _date == null
        ? ''
        : DateFormat(AppTranslations.of(context).dateFormat).format(_date!);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncText();
  }

  @override
  void didUpdateWidget(covariant LocalizedDatePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialDate != widget.initialDate) {
      _date = widget.initialDate;
      _syncText();
    }
  }

  Future<void> _pick() async {
    final t = AppTranslations.of(context);
    var initial = DateUtils.dateOnly(_date ?? DateTime.now());
    if (initial.isBefore(_first)) initial = _first;
    if (initial.isAfter(_last)) initial = _last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _first,
      lastDate: _last,
      locale: t.locale,
      helpText: widget.labelText,
    );
    if (!mounted || picked == null) return;
    setState(() {
      _date = picked;
      _syncText();
    });
    _fieldKey.currentState?.didChange(_controller.text);
    widget.onDateChanged?.call(picked);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    return TextFormField(
      key: _fieldKey,
      controller: _controller,
      readOnly: true,
      enabled: widget.enabled,
      onTap: _pick,
      decoration: InputDecoration(
        labelText: widget.labelText + (widget.required ? ' *' : ''),
        hintText: t.dateFormat.toUpperCase(),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.required && _date != null)
              IconButton(
                tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                icon: const Icon(Icons.clear),
                onPressed: !widget.enabled
                    ? null
                    : () {
                        setState(() {
                          _date = null;
                          _syncText();
                        });
                        _fieldKey.currentState?.didChange('');
                        widget.onDateChanged?.call(null);
                      },
              ),
            IconButton(
              onPressed: widget.enabled ? _pick : null,
              tooltip: t['select_from_calendar'],
              icon: const Icon(Icons.calendar_today),
            ),
          ],
        ),
        errorMaxLines: 3,
      ),
      validator: (_) {
        if (widget.required && _date == null) return t['please_enter_date'];
        if (_date != null &&
            (_date!.isBefore(_first) || _date!.isAfter(_last))) {
          final format = DateFormat(t.dateFormat);
          return t.textWithParams('date_must_be_between', {
            'first': format.format(_first),
            'last': format.format(_last),
          });
        }
        return widget.validator?.call(_date);
      },
    );
  }
}

class CompactLocalizedDatePicker extends StatelessWidget {
  final String? labelText;
  final DateTime? initialDate, firstDate, lastDate;
  final ValueChanged<DateTime?>? onDateChanged;
  final String? Function(DateTime?)? validator;
  final bool required;
  const CompactLocalizedDatePicker({
    super.key,
    this.labelText,
    this.initialDate,
    this.firstDate,
    this.lastDate,
    this.onDateChanged,
    this.validator,
    this.required = false,
  });
  @override
  Widget build(BuildContext context) => LocalizedDatePicker(
    labelText: labelText ?? '',
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    onDateChanged: onDateChanged,
    validator: validator,
    required: required,
  );
}
