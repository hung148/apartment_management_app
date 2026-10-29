import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

const double minWidth = 360.0;
const double minHeight = 600.0;

class PdfFontService {
  static pw.Font? _cachedFont;

  static Future<pw.Font> getFont() async {
    if (_cachedFont != null) return _cachedFont!;
    final fontData = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    _cachedFont = pw.Font.ttf(fontData);
    return _cachedFont!;
  }
}


Widget inputField({
  required String label,
  required TextEditingController controller,
  String? Function(String?)? validator,
  void Function(String)? onChanged,
  bool obscureText = false,
  int? maxLength,
  MaxLengthEnforcement? maxLengthEnforcement,
  Color? labelColor,
  // false while the form is being sent: the field can't be focused or typed
  // in and is drawn dimmed.
  bool enabled = true,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6.0),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: controller,
            enabled: enabled,
            obscureText: obscureText,
            validator: validator,
            onChanged: onChanged,
            maxLength: maxLength,
            maxLengthEnforcement:
                maxLengthEnforcement ?? MaxLengthEnforcement.enforced,
            style: TextStyle(color: enabled ? Colors.white : Colors.white54),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(
                color: enabled ? (labelColor ?? Colors.white70) : Colors.white38,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
              floatingLabelStyle: TextStyle(
                color: enabled ? Colors.white : Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              counterText: '',
              filled: false,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
              // Underline only — no box
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white54, width: 2),
              ),
              focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white, width: 2.5),
              ),
              disabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24, width: 2),
              ),
              errorBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFFF6B6B), width: 2),
              ),
              focusedErrorBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFFF6B6B), width: 2.5),
              ),
              errorStyle: const TextStyle(
                color: Color(0xFFFF6B6B),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
