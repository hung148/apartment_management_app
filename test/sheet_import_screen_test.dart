import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/sheet_import_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'team_review_test.dart' show mountReview;
import 'staff_editor_test.dart' show reveal;

// Sheet import (2026-10-05): made-up file only (tool/import_sample.xlsx).
void main() {
  testWidgets('overlapping preview disables import confirmation', (tester) async {
    final calls=<Map<String,dynamic>>[];
    await mountReview(tester, SheetImportScreen(organizationId:'org',
      pickFile: () async => (name:'sample.xlsx', bytes:Uint8List.fromList(File('tool/import_sample.xlsx').readAsBytesSync())),
      service: TeamService(transport:(name,data)async {
        calls.add(data);return {'counts':{'bookings':2},'existing':{},'problems':[],
          'overlapCount':1,'overlaps':[]};
      })));
    await tester.tap(find.byKey(const ValueKey('import-choose')));await tester.pumpAndSettle();
    final start=find.byKey(const ValueKey('import-start'));
    expect(tester.widget<FilledButton>(start).onPressed,isNull);
    expect(calls.length,1);expect(find.byKey(const ValueKey('import-apply')),findsNothing);
  });
  testWidgets('choose, preview, import, then save the new Google Sheet', (
    tester,
  ) async {
    final bytes = Uint8List.fromList(
      File('tool/import_sample.xlsx').readAsBytesSync(),
    );
    final calls = <Map<String, dynamic>>[];
    Map<String, dynamic> preview({Map<String, dynamic>? created}) => {
      'counts': {
        'buildings': 2,
        'rooms': 8,
        'bookings': 8,
        'leases': 2,
        'payments': 11,
        'staff': 3,
        'expenses': 2,
        'buildingRents': 1,
      },
      'existing': {
        'buildings': {'total': 2, 'there': created == null ? 0 : 0},
      },
      'problems': [
        {
          'code': 'room_added',
          'tab': 'Đặt phòng',
          'id': 'MK10',
          'guest': 'Khách Mẫu 10',
          'building': 'Nhà Mẫu B',
          'room': 'P299',
        },
      ],
      'problemCount': 1,
      'overlaps': [
        {
          'building': 'Nhà Mẫu A',
          'room': 'P101',
          'a': {'guest': 'Khách Mẫu 02', 'start': 'a', 'end': 'b'},
          'b': {'guest': 'Khách Mẫu 03', 'start': 'c', 'end': 'd'},
        },
      ],
      'overlapCount': 0,
      if (created != null) 'created': created,
      if (created != null)
        'sheet': [
          {
            'name': 'Tòa nhà',
            'headers': ['Tòa nhà'],
            'rows': [
              ['Nhà Mẫu A'],
            ],
          },
        ],
    };
    final service = TeamService(
      transport: (name, data) async {
        expect(name, 'importSheet');
        calls.add(Map<String, dynamic>.from(data));
        return switch (data['action']) {
          'preview' => preview(),
          'apply' => preview(created: {'buildings': 2, 'rooms': 8}),
          'saveSheet' => {'fileId': 'f1', 'url': 'https://docs.google.com/x'},
          _ => throw StateError('unexpected'),
        };
      },
    );
    Uri? opened;
    var changes = 0;
    await mountReview(
      tester,
      SheetImportScreen(
        organizationId: 'org',
        service: service,
        onChanged: () => changes++,
        pickFile: () async => (name: 'mau.xlsx', bytes: bytes),
        openUrl: (u) async {
          opened = u;
          return true;
        },
      ),
    );
    expect(find.byKey(const ValueKey('import-start')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('import-choose')));
    await tester.pumpAndSettle();
    // Only the known columns left the device; no password column.
    final sent = jsonEncode(calls.single['sheets']);
    expect(sent, isNot(contains('Mật khẩu')));
    expect(sent, isNot(contains('mat-khau-gia')));
    expect(find.text('mau.xlsx'), findsOneWidget);
    expect(find.text('In this file'), findsOneWidget);
    expect(
      find.text('Room not in the Phòng tab: added (1)'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('import-overlaps')), findsNothing);
    // Nothing is created before the second, confirming tap.
    await reveal(tester, find.byKey(const ValueKey('import-start')));
    await tester.tap(find.byKey(const ValueKey('import-start')));
    await tester.pumpAndSettle();
    expect(calls.length, 1);
    expect(changes, 0);
    expect(find.byKey(const ValueKey('import-confirm')), findsOneWidget);
    await reveal(tester, find.byKey(const ValueKey('import-apply')));
    await tester.tap(find.byKey(const ValueKey('import-apply')));
    await tester.pumpAndSettle();
    expect(calls[1]['action'], 'apply');
    expect(changes, 1);
    expect(calls[1]['operationId'], isA<String>());
    expect(find.byKey(const ValueKey('import-created')), findsOneWidget);
    await reveal(tester, find.byKey(const ValueKey('import-save-sheet')));
    await tester.tap(find.byKey(const ValueKey('import-save-sheet')));
    await tester.pumpAndSettle();
    final save = calls[2];
    expect(save['action'], 'saveSheet');
    expect(base64Decode(save['fileBase64'] as String).sublist(0, 2), [
      0x50,
      0x4b,
    ]);
    expect(find.byKey(const ValueKey('import-sheet-saved')), findsOneWidget);
    await reveal(tester, find.byKey(const ValueKey('import-open-sheet')));
    await tester.tap(find.byKey(const ValueKey('import-open-sheet')));
    await tester.pumpAndSettle();
    expect(opened.toString(), 'https://docs.google.com/x');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a file that is not an export is refused on the device', (
    tester,
  ) async {
    var called = false;
    await mountReview(
      tester,
      SheetImportScreen(
        organizationId: 'org',
        service: TeamService(
          transport: (name, data) async {
            called = true;
            return {};
          },
        ),
        pickFile: () async =>
            (name: 'x.xlsx', bytes: Uint8List.fromList([1, 2, 3])),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('import-choose')));
    await tester.pumpAndSettle();
    expect(called, isFalse);
    expect(find.text('This is not an Excel (.xlsx) file.'), findsOneWidget);
  });
}
