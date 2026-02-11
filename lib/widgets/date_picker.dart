import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// A date picker that supports Vietnamese locale and allows direct text input
/// Usage:
/// ```dart
/// VietnameseDatePicker(
///   labelText: 'Ngày sinh',
///   initialDate: DateTime.now(),
///   onDateChanged: (date) => print(date),
/// )
/// ```
class VietnameseDatePicker extends StatefulWidget {
  final String labelText;
  final DateTime? initialDate;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final ValueChanged<DateTime?>? onDateChanged;
  final String? Function(DateTime?)? validator;
  final bool required;
  final IconData? prefixIcon;
  final bool enabled;

  const VietnameseDatePicker({
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
  State<VietnameseDatePicker> createState() => _VietnameseDatePickerState();
}

class _VietnameseDatePickerState extends State<VietnameseDatePicker> {
  late TextEditingController _dayController;
  late TextEditingController _monthController;
  late TextEditingController _yearController;
  
  DateTime? _currentDate;
  
  // Smart default date ranges
  DateTime get _defaultFirstDate => DateTime.now().subtract(const Duration(days: 365 * 10)); // 10 years ago
  DateTime get _defaultLastDate => DateTime.now().add(const Duration(days: 365 * 5)); // 5 years ahead
  
  @override
  void initState() {
    super.initState();
    _currentDate = widget.initialDate;
    
    _dayController = TextEditingController(
      text: _currentDate != null ? _currentDate!.day.toString() : '',
    );
    _monthController = TextEditingController(
      text: _currentDate != null ? _currentDate!.month.toString() : '',
    );
    _yearController = TextEditingController(
      text: _currentDate != null ? _currentDate!.year.toString() : '',
    );
    
    // Add listeners to auto-construct date
    _dayController.addListener(_updateDateFromFields);
    _monthController.addListener(_updateDateFromFields);
    _yearController.addListener(_updateDateFromFields);
  }
  
  void _updateDateFromFields() {
    final day = int.tryParse(_dayController.text);
    final month = int.tryParse(_monthController.text);
    final year = int.tryParse(_yearController.text);
    
    if (day != null && month != null && year != null) {
      try {
        final newDate = DateTime(year, month, day);
        if (_isValidDate(newDate)) {
          setState(() {
            _currentDate = newDate;
          });
          widget.onDateChanged?.call(newDate);
        }
      } catch (e) {
        // Invalid date
      }
    } else {
      setState(() {
        _currentDate = null;
      });
      widget.onDateChanged?.call(null);
    }
  }
  
  bool _isValidDate(DateTime date) {
    final firstDate = widget.firstDate ?? _defaultFirstDate;
    final lastDate = widget.lastDate ?? _defaultLastDate;
    return date.isAfter(firstDate.subtract(const Duration(days: 1))) &&
           date.isBefore(lastDate.add(const Duration(days: 1)));
  }
  
  Future<void> _showCalendarPicker() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _currentDate ?? DateTime.now(),
      firstDate: widget.firstDate ?? _defaultFirstDate,
      lastDate: widget.lastDate ?? _defaultLastDate,
      locale: const Locale('vi', 'VN'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).primaryColor,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        _currentDate = picked;
        _dayController.text = picked.day.toString();
        _monthController.text = picked.month.toString();
        _yearController.text = picked.year.toString();
      });
      widget.onDateChanged?.call(picked);
    }
  }
  
  String? _validate() {
    if (widget.required && _currentDate == null) {
      return 'Vui lòng nhập ngày';
    }
    
    if (_currentDate != null) {
      if (!_isValidDate(_currentDate!)) {
        final firstDate = widget.firstDate ?? _defaultFirstDate;
        final lastDate = widget.lastDate ?? _defaultLastDate;
        return 'Ngày phải từ ${DateFormat('dd/MM/yyyy').format(firstDate)} đến ${DateFormat('dd/MM/yyyy').format(lastDate)}';
      }
    }
    
    return widget.validator?.call(_currentDate);
  }
  
  @override
  void dispose() {
    _dayController.dispose();
    _monthController.dispose();
    _yearController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return FormField<DateTime>(
      initialValue: _currentDate,
      validator: (_) => _validate(),
      builder: (formFieldState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Label
            if (widget.labelText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    if (widget.prefixIcon != null) ...[
                      Icon(widget.prefixIcon, size: 20),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      widget.labelText + (widget.required ? ' *' : ''),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            
            // Date input fields
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: formFieldState.hasError 
                      ? Colors.red 
                      : Colors.grey.shade400,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  // Day field
                  Expanded(
                    flex: 2,
                    child: _buildNumberField(
                      controller: _dayController,
                      hintText: 'Ngày',
                      maxLength: 2,
                      enabled: widget.enabled,
                    ),
                  ),
                  
                  _buildSeparator(),
                  
                  // Month field
                  Expanded(
                    flex: 2,
                    child: _buildNumberField(
                      controller: _monthController,
                      hintText: 'Tháng',
                      maxLength: 2,
                      enabled: widget.enabled,
                    ),
                  ),
                  
                  _buildSeparator(),
                  
                  // Year field
                  Expanded(
                    flex: 3,
                    child: _buildNumberField(
                      controller: _yearController,
                      hintText: 'Năm',
                      maxLength: 4,
                      enabled: widget.enabled,
                    ),
                  ),
                  
                  // Calendar button
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.calendar_today, size: 20),
                      onPressed: widget.enabled ? _showCalendarPicker : null,
                      tooltip: 'Chọn từ lịch',
                    ),
                  ),
                ],
              ),
            ),
            
            // Display formatted date
            if (_currentDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 12),
                child: Text(
                  _formatVietnameseDate(_currentDate!),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            
            // Error message
            if (formFieldState.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 12),
                child: Text(
                  formFieldState.errorText!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.red,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
  
  Widget _buildNumberField({
    required TextEditingController controller,
    required String hintText,
    required int maxLength,
    required bool enabled,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(maxLength),
      ],
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      ),
      style: const TextStyle(fontSize: 14),
    );
  }
  
  Widget _buildSeparator() {
    return Text(
      '/',
      style: TextStyle(
        fontSize: 16,
        color: Colors.grey.shade400,
        fontWeight: FontWeight.bold,
      ),
    );
  }
  
  String _formatVietnameseDate(DateTime date) {
    final weekdays = [
      'Chủ nhật',
      'Thứ hai',
      'Thứ ba',
      'Thứ tư',
      'Thứ năm',
      'Thứ sáu',
      'Thứ bảy',
    ];
    
    final weekday = weekdays[date.weekday % 7];
    final day = date.day;
    final month = date.month;
    final year = date.year;
    
    return '$weekday, ngày $day tháng $month năm $year';
  }
}

/// Compact version for space-constrained layouts
class CompactVietnameseDatePicker extends StatefulWidget {
  final String? labelText;
  final DateTime? initialDate;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final ValueChanged<DateTime?>? onDateChanged;
  final String? Function(DateTime?)? validator;
  final bool required;

  const CompactVietnameseDatePicker({
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
  State<CompactVietnameseDatePicker> createState() => _CompactVietnameseDatePickerState();
}

class _CompactVietnameseDatePickerState extends State<CompactVietnameseDatePicker> {
  late TextEditingController _controller;
  DateTime? _currentDate;
  
  // Smart default date ranges
  DateTime get _defaultFirstDate => DateTime.now().subtract(const Duration(days: 365 * 10)); // 10 years ago
  DateTime get _defaultLastDate => DateTime.now().add(const Duration(days: 365 * 5)); // 5 years ahead
  
  @override
  void initState() {
    super.initState();
    _currentDate = widget.initialDate;
    _controller = TextEditingController(
      text: _currentDate != null 
          ? DateFormat('dd/MM/yyyy').format(_currentDate!) 
          : '',
    );
  }
  
  Future<void> _showCalendarPicker() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _currentDate ?? DateTime.now(),
      firstDate: widget.firstDate ?? _defaultFirstDate,
      lastDate: widget.lastDate ?? _defaultLastDate,
      locale: const Locale('vi', 'VN'),
    );
    
    if (picked != null) {
      setState(() {
        _currentDate = picked;
        _controller.text = DateFormat('dd/MM/yyyy').format(picked);
      });
      widget.onDateChanged?.call(picked);
    }
  }
  
  void _handleTextInput(String value) {
    // Auto-format as user types: dd/MM/yyyy
    final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
    
    if (digitsOnly.isEmpty) {
      setState(() {
        _currentDate = null;
        _controller.text = '';
      });
      widget.onDateChanged?.call(null);
      return;
    }
    
    String formatted = '';
    
    if (digitsOnly.length <= 2) {
      formatted = digitsOnly;
    } else if (digitsOnly.length <= 4) {
      formatted = '${digitsOnly.substring(0, 2)}/${digitsOnly.substring(2)}';
    } else {
      formatted = '${digitsOnly.substring(0, 2)}/${digitsOnly.substring(2, 4)}/${digitsOnly.substring(4, digitsOnly.length > 8 ? 8 : digitsOnly.length)}';
    }
    
    // Try to parse complete date
    if (digitsOnly.length == 8) {
      try {
        final day = int.parse(digitsOnly.substring(0, 2));
        final month = int.parse(digitsOnly.substring(2, 4));
        final year = int.parse(digitsOnly.substring(4, 8));
        
        final date = DateTime(year, month, day);
        setState(() {
          _currentDate = date;
        });
        widget.onDateChanged?.call(date);
      } catch (e) {
        setState(() {
          _currentDate = null;
        });
        widget.onDateChanged?.call(null);
      }
    }
    
    _controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: widget.labelText != null 
            ? '${widget.labelText}${widget.required ? ' *' : ''}'
            : null,
        hintText: 'dd/MM/yyyy',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        suffixIcon: IconButton(
          icon: const Icon(Icons.calendar_today),
          onPressed: _showCalendarPicker,
          tooltip: 'Chọn từ lịch',
        ),
      ),
      keyboardType: TextInputType.number,
      onChanged: _handleTextInput,
      validator: (_) {
        if (widget.required && _currentDate == null) {
          return 'Vui lòng nhập ngày';
        }
        return widget.validator?.call(_currentDate);
      },
    );
  }
}