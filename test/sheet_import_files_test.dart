import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/services/sheet_import_files.dart';

// Sheet import (2026-10-05): tool/import_sample.xlsx is made-up data in the
// old app's format (tool/make_import_sample.py).
void main() {
  final sample = File('tool/import_sample.xlsx').readAsBytesSync();

  test('reads the known tabs and columns only; never the password', () {
    final sheets = readOldAppSheet(sample);
    expect(sheets.keys.toSet(), {'Đặt phòng', 'Phòng', 'Nhân viên', 'Chi phí'});
    final staff = sheets['Nhân viên'] as Map;
    expect(staff['headers'], [
      'ID',
      'Tên nhân viên',
      'Tên đăng nhập',
      'Quyền',
      'Quản lý cơ sở',
      'Màu',
      'Tỷ lệ hoa hồng',
    ]);
    expect('$sheets', isNot(contains('mat-khau-gia')));
    expect('$sheets', isNot(contains('Mật khẩu')));
    final stays = sheets['Đặt phòng'] as Map;
    // The unnamed change-log column stays behind; empty rows are dropped.
    expect((stays['headers'] as List).length, 17);
    expect((stays['rows'] as List).length, 10);
    final headers = (stays['headers'] as List).cast<String>();
    final first = (stays['rows'] as List).first as List;
    expect(
      first[headers.indexOf('Ngày giờ checkin')],
      matches(RegExp(r'^\d{4}-\d{2}-\d{2} 14:00:00$')),
    );
    expect(first[headers.indexOf('Tên khách hàng')], 'Khách Mẫu 01');
    final second = (stays['rows'] as List)[1] as List;
    expect(second[headers.indexOf('Số điện thoại')], 912000001);
  });

  test('dates by cell style; money formats stay numbers', () {
    final sheets = readOldAppSheet(sample);
    final costs = sheets['Chi phí'] as Map;
    final h = (costs['headers'] as List).cast<String>();
    final row = (costs['rows'] as List).first as List;
    expect(row[h.indexOf('Ngày chi')], matches(RegExp(r'^\d{4}-\d{2}-\d{2} 00:00:00$')));
    expect(row[h.indexOf('Số tiền')], 25000000);
  });

  test('refuses files that are not the old app\'s export', () {
    expect(
      () => readOldAppSheet([1, 2, 3]),
      throwsA(isA<SheetFileError>().having((e) => e.reason, 'reason', 'not_xlsx')),
    );
    final bytes = buildImportSheet([
      {
        'name': 'Khác',
        'headers': ['A'],
        'rows': [
          ['x'],
        ],
      },
    ]);
    expect(
      () => readOldAppSheet(bytes),
      throwsA(
        isA<SheetFileError>().having((e) => e.reason, 'reason', 'not_old_app'),
      ),
    );
  });

  test('the new sheet: one tab per list, headers first, numbers kept', () {
    final bytes = buildImportSheet([
      {
        'name': 'Tòa nhà',
        'headers': ['Tòa nhà', 'Số phòng'],
        'rows': [
          ['Nhà Mẫu A', 3],
        ],
      },
      {
        'name': 'Chi phí',
        'headers': ['Ngày', 'Số tiền'],
        'rows': [
          ['2026-09-15', 25000000],
        ],
      },
    ]);
    expect(bytes.sublist(0, 2), [0x50, 0x4b]);
    final book = readXlsx(bytes);
    expect(book.keys.toList(), ['Tòa nhà', 'Chi phí']);
    final rows = book['Chi phí']!;
    expect(rows[0], ['Ngày', 'Số tiền']);
    expect(rows[1], ['2026-09-15', 25000000]);
  });
}
