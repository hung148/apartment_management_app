import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/models/rooms_model.dart';

void main() {
  test(
    'reading and copying a room preserves weekly windows and closed date exceptions',
    () {
      final schedule = {
        'week': {
          for (var i = 0; i < 7; i++)
            '$i': [
              {'start': 480, 'end': 720},
              {'start': 840, 'end': 1320},
            ],
        },
        'exceptions': {
          '2030-01-08': [
            {'start': 600, 'end': 1020},
          ],
          '2030-01-09': [],
        },
      };
      final room = Room.fromMap('room', {
        'roomNumber': '101',
        'currency': 'USD',
        'operatingSchedule': schedule,
      });
      expect(room.toMap()['operatingSchedule'], schedule);
      final edited = room.copyWith(roomNumber: '102');
      expect(edited.toMap()['operatingSchedule'], schedule);
      expect(edited.currency, 'USD');
      expect(
        Room.fromMap('room', edited.toMap()).toMap()['operatingSchedule'],
        schedule,
      );
    },
  );
  test('schedule snapshots resist caller and serialized-map mutation', () {
    final source = <String, dynamic>{
      'week': {
        '0': [
          {'start': 480, 'end': 720},
        ],
      },
      'exceptions': {'2030-01-09': []},
    };
    final room = Room.fromMap('room', {'operatingSchedule': source});
    source['week']['0'][0]['start'] = 600;
    expect(room.operatingSchedule!['week']['0'][0]['start'], 480);
    final encoded = room.toMap();
    encoded['operatingSchedule']['exceptions']['2030-01-09'].add({
      'start': 0,
      'end': 1440,
    });
    expect(room.operatingSchedule!['exceptions']['2030-01-09'], isEmpty);
    expect(
      () => room.operatingSchedule!['week']['0'].clear(),
      throwsUnsupportedError,
    );
    expect(
      () => room.operatingSchedule!['week']['0'][0]['start'] = 0,
      throwsUnsupportedError,
    );
  });
  test('legacy daily settings remain unchanged without a weekly schedule', () {
    final room = Room.fromMap('old', {
      'operatingHoursStartMin': 1320,
      'operatingHoursEndMin': 360,
    });
    expect(room.operatingSchedule, isNull);
    expect(
      room.copyWith(area: 30).toMap().containsKey('operatingSchedule'),
      isFalse,
    );
    expect(room.copyWith(area: 30).operatingHoursEndMin, 360);
  });
}
