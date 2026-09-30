import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/email_format.dart';

void main() {
  test('accepts plus addresses and long domain endings like the server', () {
    for (final ok in [
      'trinhhungqt2004+test1@gmail.com',
      'owner@company.travel',
      'a.b-c@sub.example.vn',
      ' spaced@example.com ',
      'source@example.invalid',
    ]) {
      expect(isValidEmail(ok), isTrue, reason: ok);
    }
  });

  test('rejects clearly malformed addresses', () {
    for (final bad in ['', 'plain', 'a@b', '@example.com', 'a b@example.com', 'a@@b.com']) {
      expect(isValidEmail(bad), isFalse, reason: bad);
    }
  });
}
