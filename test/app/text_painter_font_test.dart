import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// 2026-10-10 (speed): on the web, Flutter checks each text against the fonts
// its own style names. A style measured or painted with a TextPainter does
// not get the theme's font, so with no fontFamily every accented Vietnamese
// letter counted as missing and the app downloaded two Noto fonts (~270 KB),
// and the widths were measured with a different font than the one drawn.
void main() {
  test('every style given to a TextPainter names a font', () {
    final problems = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      final source = file.readAsStringSync();
      // Named styles: `static const _x = TextStyle(...)` used anywhere in a
      // file that measures text.
      if (!source.contains('TextPainter(')) continue;
      for (final m in RegExp(
        r'const (\w+) = TextStyle\(([^;]*?)\);',
        dotAll: true,
      ).allMatches(source)) {
        final used = RegExp(
          'TextSpan\\([^)]*style: ${m[1]}\\b',
        ).hasMatch(source);
        if (used && !m[2]!.contains('fontFamily')) {
          problems.add('${file.path}: ${m[1]}');
        }
      }
      // Styles written right inside the TextPainter.
      for (final m in RegExp(r'TextPainter\(').allMatches(source)) {
        final end = (m.start + 400).clamp(0, source.length);
        final call = source.substring(m.start, end);
        final inline = call.indexOf('const TextStyle(');
        if (inline < 0) continue;
        final close = call.indexOf(')', inline);
        final style = call.substring(inline, close < 0 ? call.length : close);
        if (!style.contains('fontFamily')) {
          final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
          problems.add('${file.path}:$line');
        }
      }
    }
    expect(problems, isEmpty);
  });
}
