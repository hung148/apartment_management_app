import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
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

  // Sign out everywhere (2026-10-06): only the server's session_revoked
  // refusal signs this device out; other sign-in errors do not.
  test('a refused sign-in is recognised; other errors are not', () {
    expect(isSessionRevoked(FirebaseFunctionsException(code: 'unauthenticated', message: 'session_revoked')), isTrue);
    expect(isSessionRevoked(FirebaseFunctionsException(code: 'unauthenticated', message: 'app_check_required')), isFalse);
    expect(isSessionRevoked(FirebaseFunctionsException(code: 'permission-denied', message: 'session_revoked')), isFalse);
    expect(isSessionRevoked(StateError('session_revoked')), isFalse);
  });
}
