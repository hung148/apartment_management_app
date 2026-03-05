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
            obscureText: obscureText,
            validator: validator,
            onChanged: onChanged,
            maxLength: maxLength,
            maxLengthEnforcement:
                maxLengthEnforcement ?? MaxLengthEnforcement.enforced,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: TextStyle(
                color: labelColor ?? Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
              floatingLabelStyle: const TextStyle(
                color: Colors.white,
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