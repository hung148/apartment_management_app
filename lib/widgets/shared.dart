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
  bool optional = false,
  int? maxLength,                                       
  MaxLengthEnforcement? maxLengthEnforcement,           
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      RichText(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: Colors.black87,
          ),
          children: [
            TextSpan(
              text: ((optional) ? "" : " *"),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.redAccent,
              ),
            ),
          ],
        ), 
      ),
      ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 400,
        ), 
        child: TextFormField(
          controller: controller,
          obscureText: obscureText,
          validator: validator,
          onChanged: onChanged,
          maxLength: maxLength,                         
          maxLengthEnforcement: maxLengthEnforcement    
              ?? MaxLengthEnforcement.enforced,
          decoration: InputDecoration(
            counterText: "",   // hides the "0/100" counter
            contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 10),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: Colors.grey.shade400,
              ),
            ),
            border: OutlineInputBorder(
              borderSide: BorderSide(
                color: Colors.grey.shade400
              ),
            ),
          ),
        ),
      ),
      SizedBox(height: 10,),
    ],
  );
}