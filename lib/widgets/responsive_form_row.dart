import 'package:flutter/material.dart';

/// Keep paired fields readable when a dialog is narrow or text is enlarged.
class ResponsiveFormRow extends StatelessWidget {
  final List<Widget> children;
  const ResponsiveFormRow({super.key, required this.children});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= 520 &&
          MediaQuery.textScalerOf(context).scale(1) <= 1.3) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children.map((child) {
          if (child is Expanded) return child.child;
          if (child is Flexible) return child.child;
          if (child is SizedBox && child.width != null)
            return SizedBox(height: child.width);
          return child;
        }).toList(),
      );
    },
  );
}

