import 'dart:convert';
import 'package:phan_mem_quan_ly_can_ho/services/device_sealer.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/services/read_cache.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'room_calendar_test.dart' show bar, calendarFixture, mountCalendar;

// The copy of server answers kept on the device (2026-10-06, speed step 1).
void main() {
  late SharedPreferences prefs;
  var account = 'u1';
  var now = DateTime(2026, 10, 6, 12);
  ReadCache cache() =>
      ReadCache(prefs, account: () => account, now: () => now, sealer: _TestSealer());

  setUp(() async {
    SharedPreferences.setMockInitialValues({'language_code': 'vi'});
    prefs = await SharedPreferences.getInstance();
    account = 'u1';
    now = DateTime(2026, 10, 6, 12);
  });

  test('the same request reads back, whatever the key order', () async {
    final c = cache();
    await c.write('calendarView', {'organizationId': 'o1', 'from': 'a'}, {
      'x': 1,
    }, organizationId: 'o1');
    final r = await c.read('calendarView', {'from': 'a', 'organizationId': 'o1'});
    expect(r?.data, {'x': 1});
    expect(r?.saved, isTrue);
    expect(r?.at, now);
    expect(await c.read('calendarView', {'organizationId': 'o1', 'from': 'b'}), isNull);
    expect(prefs.getString('language_code'), 'vi');
  });

  test('another account never reads it; sign-out wipes everything', () async {
    final c = cache();
    await c.write('readTeam', {'organizationId': 'o1'}, {'x': 1});
    account = 'u2';
    expect(await c.read('readTeam', {'organizationId': 'o1'}), isNull);
    await c.keepOnlyAccount('u2');
    account = 'u1';
    expect(await c.read('readTeam', {'organizationId': 'o1'}), isNull);
    await c.write('readTeam', {'organizationId': 'o1'}, {'x': 1});
    await c.keepOnlyAccount(null);
    expect(prefs.getKeys().where((k) => k.startsWith('rc1|')), isEmpty);
    expect(prefs.getString('language_code'), 'vi');
  });

  test('no signed-in account: nothing is saved', () async {
    account = '';
    final c = cache();
    await c.write('readTeam', {'organizationId': 'o1'}, {'x': 1});
    expect(prefs.getKeys().where((k) => k.startsWith('rc1|')), isEmpty);
  });

  test('forgetting one organization keeps the others', () async {
    final c = cache();
    await c.write('a', {'organizationId': 'o1'}, {'x': 1}, organizationId: 'o1');
    await c.write('a', {'organizationId': 'o2'}, {'x': 2}, organizationId: 'o2');
    await c.forgetOrganization('o1');
    expect(await c.read('a', {'organizationId': 'o1'}), isNull);
    expect((await c.read('a', {'organizationId': 'o2'}))?.data, {'x': 2});
  });

  test('old copies expire; the oldest go first beyond the limit', () async {
    final c = cache();
    await c.write('a', {'n': 0}, {'x': 0});
    now = now.add(ReadCache.maxAge + const Duration(minutes: 1));
    expect(await c.read('a', {'n': 0}), isNull);
    for (var i = 1; i <= ReadCache.maxEntries + 5; i++) {
      now = now.add(const Duration(seconds: 1));
      await c.write('a', {'n': i}, {'x': i});
    }
    expect(
      prefs.getKeys().where((k) => k.startsWith('rc1|')).length,
      ReadCache.maxEntries,
    );
    expect(await c.read('a', {'n': 1}), isNull);
    expect((await c.read('a', {'n': ReadCache.maxEntries + 5}))?.data, {
      'x': ReadCache.maxEntries + 5,
    });
  });

  test('saved copy first, then the server; refusal wipes the organization', () async {
    final c = cache();
    var answer = <String, dynamic>{'v': 'fresh'};
    Object? fail;
    final service = TeamService(
      cache: c,
      transport: (name, data) async {
        if (fail != null) throw fail!;
        return answer;
      },
    );
    final payload = {'organizationId': 'o1', 'from': 'a'};
    final first = await service.calendarViewLive(payload).toList();
    expect(first.map((s) => (s.data['v'], s.saved)), [('fresh', false)]);
    answer = {'v': 'newer'};
    final second = await service.calendarViewLive(payload).toList();
    expect(second.map((s) => (s.data['v'], s.saved)), [
      ('fresh', true),
      ('newer', false),
    ]);
    fail = FirebaseFunctionsException(code: 'permission-denied', message: 'x');
    final seen = <bool>[];
    await expectLater(
      service.calendarViewLive(payload).map((s) => seen.add(s.saved)).drain(),
      throwsA(isA<FirebaseFunctionsException>()),
    );
    expect(seen, [true]);
    expect(await c.read('calendarView', payload), isNull);
  });

  test('a service with a test transport uses no device copy by default', () async {
    ReadCache.shared = cache();
    addTearDown(() => ReadCache.shared = null);
    final service = TeamService(transport: (n, d) async => {'v': 1});
    await service.calendarViewLive({'organizationId': 'o1'}).toList();
    expect(prefs.getKeys().where((k) => k.startsWith('rc1|')), isEmpty);
  });

  testWidgets('the calendar shows the saved copy when the server is unreachable, '
      'and nothing once access is refused', (tester) async {
    final c = cache();
    Object? fail;
    TeamService service() => TeamService(
      cache: c,
      transport: (name, data) async {
        if (fail != null) throw fail!;
        if (name == 'calendarView') {
          return calendarFixture(
            data['from'] as String,
            to: data['to'] as String?,
          );
        }
        return <String, dynamic>{};
      },
    );
    await mountCalendar(tester, service());
    expect(bar('booking:b1'), findsOneWidget);

    fail = FirebaseFunctionsException(code: 'unavailable', message: 'x');
    await mountCalendar(tester, service());
    expect(bar('booking:b1'), findsOneWidget);
    expect(
      find.text(
        'Could not load the calendar. Check the connection and try again.',
      ),
      findsOneWidget,
    );

    fail = FirebaseFunctionsException(code: 'permission-denied', message: 'x');
    await mountCalendar(tester, service());
    expect(bar('booking:b1'), findsNothing);
    fail = FirebaseFunctionsException(code: 'unavailable', message: 'x');
    await mountCalendar(tester, service());
    expect(bar('booking:b1'), findsNothing, reason: 'the copy was wiped');
    expect(tester.takeException(), isNull);
  });
}

class _TestSealer implements DeviceSealer {
  @override Future<String> seal(String plain) async => base64Encode(utf8.encode(plain));
  @override Future<String?> open(String sealed) async { try {return utf8.decode(base64Decode(sealed));} catch(_) {return null;} }
  @override Future<void> forgetKey() async {}
}
