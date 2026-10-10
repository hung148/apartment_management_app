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
    final groups = RegExp(
      r"exports\.(\w+)=callables\.group\('(\w+)'",
    ).allMatches(source).map((m) => m[2]).toSet();
    expect(groups, {'app', 'heavy'});
  });

  // Sign out everywhere (2026-10-06): only the server's session_revoked
  // refusal signs this device out; other sign-in errors do not.
  test('a refused sign-in is recognised; other errors are not', () {
    expect(
      isSessionRevoked(
        FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'session_revoked',
        ),
      ),
      isTrue,
    );
    expect(
      isSessionRevoked(
        FirebaseFunctionsException(
          code: 'unauthenticated',
          message: 'app_check_required',
        ),
      ),
      isFalse,
    );
    expect(
      isSessionRevoked(
        FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'session_revoked',
        ),
      ),
      isFalse,
    );
    expect(isSessionRevoked(StateError('session_revoked')), isFalse);
  });
  // 2026-10-09 (Tom): only calls that may change data move the count.
  test('reads do not count as changes; anything else does', () {
    final start = ServerWrites.count;
    for (final (name, data) in [
      ('calendarView', <String, dynamic>{}),
      ('readTeam', {'view': 'myAccess'}),
      ('bookingWorkspace', {'action': 'rooms'}),
      ('bookingWorkspace', {'action': 'quote'}),
      ('tenantContacts', {'action': 'read'}),
      ('organizationSettings', {'action': 'readCurrency'}),
    ]) {
      ServerWrites.note(name, data);
    }
    expect(ServerWrites.count, start);
    ServerWrites.note('bookingWorkspace', {'action': 'save'});
    ServerWrites.note('mutateTeam', {'action': 'setAccess'});
    ServerWrites.note('somethingNew', null);
    expect(ServerWrites.count, start + 3);
  });

  // W3 (2026-10-10): in the WebAssembly build whole numbers from the server
  // can arrive as doubles; the app reads them as ints.
  test('whole numbers from the server become ints, others stay', () {
    final out =
        wholeNumbersAsInt({
              'totalMinor': 300000.0,
              'rate': 1.5,
              'big': 1e20,
              'nights': [1.0, 2.0],
              'nested': {7: 3.0},
              'name': 'Lan',
              'none': null,
            })
            as Map<String, dynamic>;
    expect(out['totalMinor'], isA<int>());
    expect(out['totalMinor'], 300000);
    expect(out['rate'], 1.5);
    expect(out['big'], 1e20);
    expect(out['nights'], [1, 2]);
    expect((out['nested'] as Map<String, dynamic>)['7'], 3);
    expect(out['name'], 'Lan');
    expect(out['none'], isNull);
  });
}
