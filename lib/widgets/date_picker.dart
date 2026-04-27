import 'package:phan_mem_quan_ly_can_ho/utils/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Localized Date Picker supporting Vietnamese and English
/// Uses your existing AppTranslations class for translations
class LocalizedDatePicker extends StatefulWidget {
  final String labelText;
  final DateTime? initialDate;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final ValueChanged<DateTime?>? onDateChanged;
  final String? Function(DateTime?)? validator;
  final bool required;
  final IconData? prefixIcon;
  final bool enabled;

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
  late TextEditingController _dayController;
  late TextEditingController _monthController;
  late TextEditingController _yearController;
  
  DateTime? _currentDate;
  
  // Smart default date ranges
  DateTime get _defaultFirstDate => DateTime.now().subtract(const Duration(days: 365 * 10));
  DateTime get _defaultLastDate => DateTime.now().add(const Duration(days: 365 * 5));
  
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
    final translations = AppTranslations.of(context);
    
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _currentDate ?? DateTime.now(),
      firstDate: widget.firstDate ?? _defaultFirstDate,
      lastDate: widget.lastDate ?? _defaultLastDate,
      locale: translations.locale,
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
    final translations = AppTranslations.of(context);
    
    if (widget.required && _currentDate == null) {
      return translations['please_enter_date'];
    }
    
    if (_currentDate != null) {
      if (!_isValidDate(_currentDate!)) {
        final firstDate = widget.firstDate ?? _defaultFirstDate;
        final lastDate = widget.lastDate ?? _defaultLastDate;
        final format = translations.dateFormat;
        final firstDateStr = DateFormat(format).format(firstDate);
        final lastDateStr = DateFormat(format).format(lastDate);
        return translations.textWithParams('date_must_be_between', {
          'first': firstDateStr,
          'last': lastDateStr,
        });
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
    final translations = AppTranslations.of(context);
    final isVietnamese = translations.isVietnamese;
    
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
                children: isVietnamese 
                  ? _buildVietnameseFields(translations)
                  : _buildEnglishFields(translations),
              ),
            ),
            
            // Display formatted date
            if (_currentDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 12),
                child: Text(
                  translations.formatLongDate(_currentDate!),
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
  
  // Vietnamese: Day / Month / Year
  List<Widget> _buildVietnameseFields(AppTranslations translations) {
    return [
      // Day field
      Expanded(
        flex: 2,
        child: _buildNumberField(
          controller: _dayController,
          hintText: translations['day_hint'],
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
          hintText: translations['month_hint'],
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
          hintText: translations['year_hint'],
          maxLength: 4,
          enabled: widget.enabled,
        ),
      ),
      
      // Calendar button
      _buildCalendarButton(translations),
    ];
  }
  
  // English: Month / Day / Year
  List<Widget> _buildEnglishFields(AppTranslations translations) {
    return [
      // Month field (first for English)
      Expanded(
        flex: 2,
        child: _buildNumberField(
          controller: _monthController,
          hintText: translations['month_hint'],
          maxLength: 2,
          enabled: widget.enabled,
        ),
      ),
      
      _buildSeparator(),
      
      // Day field (second for English)
      Expanded(
        flex: 2,
        child: _buildNumberField(
          controller: _dayController,
          hintText: translations['day_hint'],
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
          hintText: translations['year_hint'],
          maxLength: 4,
          enabled: widget.enabled,
        ),
      ),
      
      // Calendar button
      _buildCalendarButton(translations),
    ];
  }
  
  Widget _buildCalendarButton(AppTranslations translations) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: IconButton(
        icon: const Icon(Icons.calendar_today, size: 20),
        onPressed: widget.enabled ? _showCalendarPicker : null,
        tooltip: translations['select_from_calendar'],
      ),
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
}

/// Compact version for space-constrained layouts
class CompactLocalizedDatePicker extends StatefulWidget {
  final String? labelText;
  final DateTime? initialDate;
  final DateTime? firstDate;
  final DateTime? lastDate;
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
  State<CompactLocalizedDatePicker> createState() => _CompactLocalizedDatePickerState();
}

class _CompactLocalizedDatePickerState extends State<CompactLocalizedDatePicker> {
  late TextEditingController _controller;
  DateTime? _currentDate;
  
  DateTime get _defaultFirstDate => DateTime.now().subtract(const Duration(days: 365 * 10));
  DateTime get _defaultLastDate => DateTime.now().add(const Duration(days: 365 * 5));
  
  @override
  void initState() {
    super.initState();
    _currentDate = widget.initialDate;
    _controller = TextEditingController(
      text: _currentDate != null 
          ? _formatDate(_currentDate!) 
          : '',
    );
  }
  
  String _formatDate(DateTime date) {
    // This will be called during initState, so we can't use context yet
    // We'll format it properly in the build method if needed
    return DateFormat('dd/MM/yyyy').format(date);
  }
  
  String _getHintText(BuildContext context) {
    final translations = AppTranslations.of(context);
    return translations.dateFormat.toLowerCase();
  }
  
  Future<void> _showCalendarPicker() async {
    final translations = AppTranslations.of(context);
    final format = translations.dateFormat;
    
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _currentDate ?? DateTime.now(),
      firstDate: widget.firstDate ?? _defaultFirstDate,
      lastDate: widget.lastDate ?? _defaultLastDate,
      locale: translations.locale,
    );
    
    if (picked != null) {
      setState(() {
        _currentDate = picked;
        _controller.text = DateFormat(format).format(picked);
      });
      widget.onDateChanged?.call(picked);
    }
  }
  
  void _handleTextInput(String value) {
    final translations = AppTranslations.of(context);
    final isVietnamese = translations.isVietnamese;
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
    
    // Format based on language
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
        int day, month, year;
        
        if (isVietnamese) {
          // User typed DD/MM/YYYY
          day = int.parse(digitsOnly.substring(0, 2));
          month = int.parse(digitsOnly.substring(2, 4));
        } else {
          // User typed MM/DD/YYYY
          month = int.parse(digitsOnly.substring(0, 2));
          day = int.parse(digitsOnly.substring(2, 4));
        }
        
        year = int.parse(digitsOnly.substring(4, 8));
        
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
    final translations = AppTranslations.of(context);
    
    return TextFormField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: widget.labelText != null 
            ? '${widget.labelText}${widget.required ? ' *' : ''}'
            : null,
        hintText: _getHintText(context),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        suffixIcon: IconButton(
          icon: const Icon(Icons.calendar_today),
          onPressed: _showCalendarPicker,
          tooltip: translations['select_from_calendar'],
        ),
      ),
      keyboardType: TextInputType.number,
      onChanged: _handleTextInput,
      validator: (_) {
        if (widget.required && _currentDate == null) {
          return translations['please_enter_date'];
        }
        return widget.validator?.call(_currentDate);
      },
    );
  }
}