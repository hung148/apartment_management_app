import 'package:flutter/material.dart';

// text fields
Widget inputField({
  required String label,
  required TextEditingController controller,
  String? Function(String?)? validator,
  void Function(String)? onChanged, 
  bool obscureText = false, 
  bool optional = false
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
          decoration: InputDecoration(
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