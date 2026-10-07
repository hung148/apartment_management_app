import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/services/app_functions.dart';

// Grouped functions (2026-10-06, speed step 4): the app must send each call to
// the group the server registered it in (functions/index.js).
void main() {
  test('every call goes to the group the server registered it in', () {
    final source = File('functions/index.js').readAsStringSync();
    final calls = RegExp(
      r"secureCallable\('(\w+)',\s*(\{group:'(\w+)'\})?",
    ).allMatches(source).toList();
    expect(calls.length, greaterThan(30));
    for (final m in calls) {
      expect(functionGroup(m[1]!), m[3] ?? 'app', reason: m[1]);
    }
    expect(functionGroup('importSheet'), 'heavy');
    expect(functionGroup('calendarView'), 'app');
  });

  test('the server exports exactly these groups', () {
    final source = File('functions/index.js').readAsStringSync();
    final groups = RegExp(r"exports\.(\w+)=callables\.group\('(\w+)'")
        .allMatches(source)
        .map((m) => m[2])
        .toSet();
    expect(groups, {'app', 'heavy'});
  });
}
