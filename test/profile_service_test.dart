import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/services/profile_service.dart';

void main() {
  test('name and phone rules match the server', () {
    expect(ProfileService.cleanName('  Tom   Trinh '), 'Tom Trinh');
    expect(ProfileService.isValidName('   '), isFalse);
    expect(ProfileService.isValidName('x' * 101), isFalse);
    expect(ProfileService.isValidName('Trịnh Hùng'), isTrue);
    for (final ok in ['', '0901234567', '+84 90 123 4567', '(028) 3822-1234']) {
      expect(ProfileService.isValidPhone(ok), isTrue, reason: ok);
    }
    for (final bad in ['12', '09x1234567', '+1234567890123456', '++84901234567']) {
      expect(ProfileService.isValidPhone(bad), isFalse, reason: bad);
    }
  });

  test('update sends the cleaned fields and reads the saved values', () async {
    final calls = <Map<String, dynamic>>[];
    final service = ProfileService(transport: (name, data) async {
      expect(name, 'myProfile');
      calls.add(data);
      return data['action'] == 'update' ? {'name': 'Tom Trinh', 'phone': null, 'updated': 2} : {'email': 'a@b.co'};
    });
    final saved = await service.update(name: ' Tom  Trinh ', phone: '  ');
    expect(saved.name, 'Tom Trinh');
    expect(saved.phone, isNull);
    await service.syncEmail();
    expect(calls, [
      {'action': 'update', 'name': 'Tom Trinh', 'phone': ''},
      {'action': 'syncEmail'},
    ]);
  });
}
