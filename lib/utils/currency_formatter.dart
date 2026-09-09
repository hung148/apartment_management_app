import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Currency input formatter that adds thousand separators as user types
/// Converts: 5000000 → 5,000,000
class CurrencyInputFormatter extends TextInputFormatter {
  final int decimalDigits;
  final String locale;

  CurrencyInputFormatter({this.decimalDigits = 0, this.locale = 'en_US'});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    // If empty, return as is
    if (newValue.text.isEmpty) {
      return newValue;
    }

    final raw = newValue.text.replaceAll(',', '');
    if (!RegExp(decimalDigits > 0 ? r'^\d*(\.\d*)?$' : r'^\d*$').hasMatch(raw))
      return oldValue;
    final parts = raw.split('.');
    if (parts.length > 1 && parts[1].length > decimalDigits) return oldValue;
    final whole = parts.first;
    final grouped = whole.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
    final formatted = grouped + (parts.length > 1 ? '.${parts[1]}' : '');

    int caret(int offset) {
      if (offset < 0) return formatted.length;
      final count = newValue.text
          .substring(0, offset.clamp(0, newValue.text.length))
          .replaceAll(',', '')
          .length;
      if (count == 0) return 0;
      var seen = 0;
      for (var i = 0; i < formatted.length; i++) {
        if (formatted[i] != ',') seen++;
        if (seen == count) return i + 1;
      }
      return formatted.length;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection(
        baseOffset: caret(newValue.selection.baseOffset),
        extentOffset: caret(newValue.selection.extentOffset),
      ),
    );
  }
}

/// Helper extension to format currency for display
extension CurrencyFormat on double {
  /// Format as Vietnamese currency (5000000 → 5,000,000 đ)
  String toVND() {
    return '${NumberFormat('#,###', 'en_US').format(this)} đ';
  }

  /// Format with thousand separators only (5000000 → 5,000,000)
  String toFormatted() {
    return NumberFormat('#,###', 'en_US').format(this);
  }
}

/// Helper extension to format currency for display (int version)
extension IntCurrencyFormat on int {
  /// Format as Vietnamese currency (5000000 → 5,000,000 đ)
  String toVND() {
    return '${NumberFormat('#,###', 'en_US').format(this)} đ';
  }

  /// Format with thousand separators only (5000000 → 5,000,000)
  String toFormatted() {
    return NumberFormat('#,###', 'en_US').format(this);
  }
}

/// Helper to parse formatted currency back to number
class CurrencyParser {
  static double? tryParse(String value) =>
      double.tryParse(value.replaceAll(',', '').trim());

  static String format(num value) =>
      NumberFormat('#,##0.##', 'en_US').format(value);

  static double parse(String formattedValue) {
    final cleaned = formattedValue.replaceAll(',', '').trim();
    return double.tryParse(cleaned) ?? 0.0;
  }

  static int parseInt(String formattedValue) {
    final cleaned = formattedValue.replaceAll(',', '').trim();
    return int.tryParse(cleaned) ?? 0;
  }
}
