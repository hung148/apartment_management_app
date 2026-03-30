import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Currency input formatter that adds thousand separators as user types
/// Converts: 5000000 → 5,000,000
class CurrencyInputFormatter extends TextInputFormatter {
  final int decimalDigits;
  final String locale;
  
  CurrencyInputFormatter({
    this.decimalDigits = 0,
    this.locale = 'vi_VN',
  });

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // If empty, return as is
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Remove all non-digit characters except decimal point
    String digitsOnly = newValue.text.replaceAll(RegExp(r'[^\d.]'), '');
    
    // If no digits, return empty
    if (digitsOnly.isEmpty || digitsOnly == '.') {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Handle decimal point
    if (decimalDigits > 0 && digitsOnly.contains('.')) {
      final parts = digitsOnly.split('.');
      if (parts.length > 2) {
        // Multiple decimal points, keep only first one
        digitsOnly = '${parts[0]}.${parts.sublist(1).join('')}';
      }
      
      // Limit decimal places
      if (parts.length == 2 && parts[1].length > decimalDigits) {
        parts[1] = parts[1].substring(0, decimalDigits);
        digitsOnly = '${parts[0]}.${parts[1]}';
      }
    } else {
      // No decimals allowed, remove any decimal points
      digitsOnly = digitsOnly.replaceAll('.', '');
    }

    // Format with thousand separators
    String formatted;
    try {
      if (digitsOnly.contains('.')) {
        // Has decimal - format both parts separately
        final parts = digitsOnly.split('.');
        final intPart = int.tryParse(parts[0]) ?? 0;
        final formattedInt = NumberFormat('#,###', locale).format(intPart);
        formatted = '$formattedInt.${parts[1]}';
      } else {
        // Integer only - simple format
        final number = int.tryParse(digitsOnly) ?? 0;
        formatted = NumberFormat('#,###', locale).format(number);
      }
    } catch (e) {
      // If formatting fails, return old value
      return oldValue;
    }

    // Calculate new cursor position
    int cursorPosition = formatted.length;
    
    // Try to maintain cursor position relative to digits
    final oldCursorPos = oldValue.selection.baseOffset;
    final newCursorPos = newValue.selection.baseOffset;
    
    if (newCursorPos > 0) {
      // Count digits before cursor in old and new raw text
      final digitsBeforeCursorOld = oldValue.text.substring(0, oldCursorPos.clamp(0, oldValue.text.length))
          .replaceAll(RegExp(r'[^\d]'), '').length;
      final digitsBeforeCursorNew = newValue.text.substring(0, newCursorPos.clamp(0, newValue.text.length))
          .replaceAll(RegExp(r'[^\d]'), '').length;
      
      // Find position in formatted text with same number of digits before cursor
      int targetDigits = digitsBeforeCursorNew;
      int digitsSeen = 0;
      int pos = 0;
      
      for (int i = 0; i < formatted.length; i++) {
        if (formatted[i].contains(RegExp(r'\d'))) {
          digitsSeen++;
          if (digitsSeen >= targetDigits) {
            pos = i + 1;
            break;
          }
        }
      }
      
      cursorPosition = pos > 0 ? pos : formatted.length;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursorPosition.clamp(0, formatted.length)),
    );
  }
}

/// Helper extension to format currency for display
extension CurrencyFormat on double {
  /// Format as Vietnamese currency (5000000 → 5,000,000 đ)
  String toVND() {
    return '${NumberFormat('#,###', 'vi_VN').format(this)} đ';
  }
  
  /// Format with thousand separators only (5000000 → 5,000,000)
  String toFormatted() {
    return NumberFormat('#,###', 'vi_VN').format(this);
  }
}

/// Helper extension to format currency for display (int version)
extension IntCurrencyFormat on int {
  /// Format as Vietnamese currency (5000000 → 5,000,000 đ)
  String toVND() {
    return '${NumberFormat('#,###', 'vi_VN').format(this)} đ';
  }
  
  /// Format with thousand separators only (5000000 → 5,000,000)
  String toFormatted() {
    return NumberFormat('#,###', 'vi_VN').format(this);
  }
}

/// Helper to parse formatted currency back to number
class CurrencyParser {
  static double parse(String formattedValue) {
    final cleaned = formattedValue.replaceAll(RegExp(r'[^\d]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }
  
  static int parseInt(String formattedValue) {
    final cleaned = formattedValue.replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(cleaned) ?? 0;
  }
}