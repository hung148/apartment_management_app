import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/google_drive_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/problem_photos.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/technical_problems_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/services/drive_connect.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'account_entry_test.dart' as fixtures;

// A real 1×1 PNG, so Image.memory can draw it.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Map<String, dynamic> _problem({
  String status = 'open',
  List<Map<String, dynamic>> photos = const [],
}) => {
  'id': 'p1',
  'revision': '1:0',
  'roomId': 'r1',
  'roomNumber': '101',
  'title': 'Đèn hỏng',
  'description': '',
  'status': status,
  'blocksRoom': false,
  'reportedByName': 'Chị Lan',
  'reportedLocalDate': '2026-11-18',
  'occupant': null,
  'fixedByName': status == 'fixed' ? 'Thợ Hùng' : null,
  'fixedLocalDate': status == 'fixed' ? '2026-11-19' : null,
  'costMinor': null,
  'currency': 'VND',
  'expenseId': null,
  'note': '',
  'photos': photos,
};

Map<String, dynamic> _photo(String id, String by) => {
  'id': id,
  'mimeType': 'image/png',
  'addedBy': by,
  'addedByName': by,
  'addedLocalDate': '2026-11-18',
};

Map<String, dynamic> _list({
  bool manager = true,
  String drive = 'connected',
  Map<String, dynamic>? problem,
  String uid = 'owner',
}) => {
  'records': [problem ?? _problem()],
  'rooms': [
    {'id': 'r1', 'roomNumber': '101', 'blocked': false},
  ],
  'accounts': [],
  'currency': 'VND',
  'today': '2026-11-20',
  'canReport': true,
  'canManage': manager,
  'canExpense': false,
  'uid': uid,
  'drive': {
    'state': drive,
    'email': drive == 'none' ? null : 'owner@gmail.com',
  },
};

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'add photos: wrong files are skipped, a lost reply is retried with the same operation',
    (t) async {
      final sent = <Map<String, dynamic>>[];
      var photos = <Map<String, dynamic>>[_photo('ph1', 'maid')];
      var lose = true;
      final service = TeamService(
        transport: (name, d) async {
          if (d['action'] == 'list')
            return _list(problem: _problem(photos: photos));
          if (d['action'] == 'photo')
            return {
              'photoId': d['photoId'],
              'mimeType': 'image/png',
              'dataBase64': base64Encode(_png),
            };
          sent.add(Map<String, dynamic>.from(d));
          if (d['action'] == 'removePhoto') {
            photos = photos.where((p) => p['id'] != d['photoId']).toList();
            return {
              'problemId': 'p1',
              'photoId': d['photoId'],
              'trashed': true,
            };
          }
          if (lose) {
            lose = false;
            throw FirebaseFunctionsException(
              code: 'unavailable',
              message: 'offline',
            );
          }
          photos = [...photos, _photo('ph2', 'owner')];
          return {'problemId': 'p1', 'photo': _photo('ph2', 'owner')};
        },
      );
      var asked = 0;
      await fixtures.mount(
        t,
        Scaffold(
          body: TechnicalProblemsScreen(
            organizationId: 'o',
            buildingId: 'b',
            service: service,
            pickPhotos: (max) async {
              asked = max;
              return [
                PickedPhoto(_png, 'den.png'),
                PickedPhoto(utf8.encode('GIF89a......'), 'clip.gif'),
              ];
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await _tap(t, find.byKey(const ValueKey('problem-p1')));
      expect(find.text('Photos (1/6)'), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-ph1')), findsOneWidget);
      await _tap(t, find.byKey(const ValueKey('photos-add')));
      expect(asked, 5, reason: 'only the free places are offered');
      expect(find.textContaining('clip.gif'), findsOneWidget);
      expect(sent.single['action'], 'addPhoto');
      expect(sent.single['mimeType'], 'image/png');
      expect(sent.single['dataBase64'], base64Encode(_png));
      // The reply was lost: the same request is sent again.
      expect(find.byKey(const ValueKey('photos-retry')), findsOneWidget);
      await _tap(t, find.byKey(const ValueKey('photos-retry')));
      expect(sent[1], sent[0]);
      expect(find.text('Photos (2/6)'), findsOneWidget);
      // Open a photo, remove it (two steps).
      await _tap(t, find.byKey(const ValueKey('photo-ph2')));
      await _tap(t, find.byKey(const ValueKey('photo-remove')));
      expect(find.textContaining('Google Drive trash'), findsOneWidget);
      await _tap(t, find.byKey(const ValueKey('photo-remove-confirm')));
      expect(sent.last['action'], 'removePhoto');
      expect(sent.last['photoId'], 'ph2');
      expect(find.text('Photos (1/6)'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  // 2026-10-05 (Tom): photos can be chosen on the report form; they go up
  // right after the problem is saved.
  testWidgets('photos chosen while reporting are uploaded after sending', (
    t,
  ) async {
    final sent = <Map<String, dynamic>>[];
    final service = TeamService(
      transport: (name, d) async {
        if (d['action'] == 'list') return _list();
        if (d['action'] == 'photo')
          return {
            'photoId': d['photoId'],
            'mimeType': 'image/png',
            'dataBase64': base64Encode(_png),
          };
        sent.add(Map<String, dynamic>.from(d));
        if (d['action'] == 'report') return {'problemId': 'p9', 'warnings': []};
        return {'problemId': 'p9', 'photo': _photo('ph9', 'owner')};
      },
    );
    await fixtures.mount(
      t,
      Scaffold(
        body: TechnicalProblemsScreen(
          organizationId: 'o',
          buildingId: 'b',
          service: service,
          pickPhotos: (max) async => [
            PickedPhoto(_png, 'a.png'),
            PickedPhoto(_png, 'b.png'),
          ],
        ),
      ),
    );
    await t.pumpAndSettle();
    await _tap(t, find.byKey(const ValueKey('problems-report')));
    await _tap(t, find.byKey(const ValueKey('problem-room-r1')));
    await t.enterText(
      find.byKey(const ValueKey('problem-title')),
      'Vòi nước rỉ',
    );
    await _tap(t, find.byKey(const ValueKey('problem-draft-add-photos')));
    expect(find.text('Photos (2/6)'), findsOneWidget);
    expect(find.byKey(const ValueKey('problem-draft-photo-1')), findsOneWidget);
    // Remove one before sending.
    await _tap(
      t,
      find.descendant(
        of: find.byKey(const ValueKey('problem-draft-photo-1')),
        matching: find.byIcon(Icons.close),
      ),
    );
    expect(find.text('Photos (1/6)'), findsOneWidget);
    expect(sent, isEmpty, reason: 'nothing is sent before the report');
    await _tap(t, find.byKey(const ValueKey('problem-save')));
    expect(sent.first['action'], 'report');
    expect(sent.where((s) => s['action'] == 'addPhoto').length, 1);
    final photo = sent.firstWhere((s) => s['action'] == 'addPhoto');
    expect(photo['problemId'], 'p9');
    expect(photo['dataBase64'], base64Encode(_png));
    expect(find.byKey(const ValueKey('problem-done')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'without Google Drive the problem explains where to connect; no add button',
    (t) async {
      final service = TeamService(
        transport: (name, d) async => _list(drive: 'none'),
      );
      await fixtures.mount(
        t,
        Scaffold(
          body: TechnicalProblemsScreen(
            organizationId: 'o',
            buildingId: 'b',
            service: service,
          ),
        ),
        locale: 'vi',
      );
      await t.pumpAndSettle();
      await _tap(t, find.byKey(const ValueKey('problem-p1')));
      expect(find.byKey(const ValueKey('photos-drive-note')), findsOneWidget);
      expect(find.textContaining('Màn hình chính › Google Drive'), findsOneWidget);
      expect(find.byKey(const ValueKey('photos-add')), findsNothing);
    },
  );

  testWidgets(
    'staff: add while open, remove only their own; nothing after the fix',
    (t) async {
      var status = 'open';
      final service = TeamService(
        transport: (name, d) async {
          if (d['action'] == 'photo')
            return {
              'photoId': d['photoId'],
              'mimeType': 'image/png',
              'dataBase64': base64Encode(_png),
            };
          return _list(
            manager: false,
            uid: 'maid',
            problem: _problem(
              status: status,
              photos: [_photo('mine', 'maid'), _photo('other', 'front')],
            ),
          );
        },
      );
      await fixtures.mount(
        t,
        Scaffold(
          body: TechnicalProblemsScreen(
            organizationId: 'o',
            buildingId: 'b',
            service: service,
          ),
        ),
      );
      await t.pumpAndSettle();
      await _tap(t, find.byKey(const ValueKey('problem-p1')));
      expect(find.byKey(const ValueKey('photos-add')), findsOneWidget);
      await _tap(t, find.byKey(const ValueKey('photo-other')));
      expect(find.byKey(const ValueKey('photo-remove')), findsNothing);
      await _tap(t, find.text('Close'));
      await _tap(t, find.byKey(const ValueKey('photo-mine')));
      expect(find.byKey(const ValueKey('photo-remove')), findsOneWidget);
      await _tap(t, find.text('Close'));
      status = 'fixed';
      await fixtures.mount(
        t,
        Scaffold(
          body: TechnicalProblemsScreen(
            key: const ValueKey('fixed'),
            organizationId: 'o',
            buildingId: 'b',
            service: service,
          ),
        ),
      );
      await t.pumpAndSettle();
      await _tap(t, find.byKey(const ValueKey('problem-filter-all')));
      await _tap(t, find.byKey(const ValueKey('problem-p1')));
      expect(find.byKey(const ValueKey('photos-add')), findsNothing);
    },
  );

  testWidgets(
    'Google Drive settings: connect, refusal messages, disconnect in two steps',
    (t) async {
      final sent = <Map<String, dynamic>>[];
      var state = {
        'state': 'none',
        'email': null,
        'connectedByName': null,
        'canConnect': true,
        'clientId': 'cid',
      };
      var refuse = 'drive_scope_missing';
      final service = TeamService(
        transport: (name, d) async {
          expect(name, 'googleDrive');
          sent.add(Map<String, dynamic>.from(d));
          if (d['action'] == 'connect' && refuse.isNotEmpty) {
            final key = refuse;
            refuse = '';
            throw FirebaseFunctionsException(
              code: 'failed-precondition',
              message: key,
            );
          }
          if (d['action'] == 'connect')
            state = {
              ...state,
              'state': 'connected',
              'email': 'owner@gmail.com',
              'connectedByName': 'Tom',
            };
          if (d['action'] == 'disconnect')
            state = {
              ...state,
              'state': 'none',
              'email': null,
              'connectedByName': null,
            };
          return state;
        },
      );
      var popups = 0;
      Future<String> popup(String clientId) async {
        expect(clientId, 'cid');
        popups++;
        if (popups == 2) throw const DriveConnectError('popup_closed');
        return 'code$popups';
      }

      await fixtures.mount(
        t,
        Scaffold(
          body: GoogleDriveScreen(
            organizationId: 'o',
            service: service,
            requestCode: popup,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Not connected'), findsOneWidget);
      await _tap(t, find.byKey(const ValueKey('drive-connect')));
      expect(sent.last, {
        'action': 'connect',
        'organizationId': 'o',
        'code': 'code1',
      });
      expect(
        find.textContaining('Tick the Google Drive permission'),
        findsOneWidget,
      );
      // Closing Google's window is not an error.
      await _tap(t, find.byKey(const ValueKey('drive-connect')));
      expect(find.byKey(const ValueKey('drive-error')), findsNothing);
      await _tap(t, find.byKey(const ValueKey('drive-connect')));
      expect(sent.last['code'], 'code3');
      expect(find.text('owner@gmail.com'), findsOneWidget);
      await _tap(t, find.byKey(const ValueKey('drive-disconnect')));
      expect(
        find.byKey(const ValueKey('drive-disconnect-warning')),
        findsOneWidget,
      );
      expect(
        sent.last['action'],
        'connect',
        reason: 'nothing sent before confirming',
      );
      await _tap(t, find.byKey(const ValueKey('drive-disconnect-confirm')));
      expect(sent.last['action'], 'disconnect');
      expect(find.text('Not connected'), findsOneWidget);
    },
  );

  // 2026-10-06 (Tom): connected once on the home screen, for every
  // organization the owner owns: no organization is sent.
  testWidgets('home screen: the owner connects their own Google Drive', (
    t,
  ) async {
    final sent = <Map<String, dynamic>>[];
    final service = TeamService(
      transport: (name, d) async {
        expect(name, 'googleDrive');
        sent.add(Map<String, dynamic>.from(d));
        return {
          'state': d['action'] == 'connect' ? 'connected' : 'none',
          'email': d['action'] == 'connect' ? 'owner@gmail.com' : null,
          'canConnect': true,
          'clientId': 'cid',
          'account': true,
        };
      },
    );
    await fixtures.mount(
      t,
      Scaffold(
        body: GoogleDriveScreen(
          service: service,
          requestCode: (_) async => 'code1',
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(sent.single, {'action': 'status'});
    expect(find.textContaining('every organization you own'), findsOneWidget);
    await _tap(t, find.byKey(const ValueKey('drive-connect')));
    expect(sent.last, {'action': 'connect', 'code': 'code1'});
    expect(find.text('owner@gmail.com'), findsOneWidget);
  });

  testWidgets(
    'staff see the Drive state without buttons; reconnect is offered when Google stopped access',
    (t) async {
      var canConnect = false;
      final service = TeamService(
        transport: (name, d) async => {
          'state': 'needsReconnect',
          'email': 'owner@gmail.com',
          'connectedByName': 'Tom',
          'canConnect': canConnect,
          'clientId': canConnect ? 'cid' : null,
        },
      );
      await fixtures.mount(
        t,
        Scaffold(
          body: GoogleDriveScreen(
            organizationId: 'o',
            service: service,
            requestCode: (_) async => 'c',
          ),
        ),
        locale: 'vi',
      );
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('drive-reconnect-notice')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('drive-connect')), findsNothing);
      canConnect = true;
      await fixtures.mount(
        t,
        Scaffold(
          body: GoogleDriveScreen(
            key: const ValueKey('again'),
            organizationId: 'o',
            service: service,
            requestCode: (_) async => 'c',
          ),
        ),
        locale: 'vi',
      );
      await t.pumpAndSettle();
      expect(find.text('Kết nối lại'), findsOneWidget);
    },
  );

  for (final locale in ['en', 'vi']) {
    for (final size in [const Size(360, 800), const Size(1440, 900)]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('photo and drive layouts $locale ${size.width} $scale', (
          t,
        ) async {
          final service = TeamService(
            transport: (name, d) async {
              if (name == 'googleDrive') {
                return {
                  'state': 'connected',
                  'email': 'chu.nha.toa.a.huong.bien@gmail.com',
                  'connectedByName': 'Nguyễn Văn Hưng',
                  'canConnect': true,
                  'clientId': 'cid',
                };
              }
              if (d['action'] == 'photo')
                return {
                  'photoId': d['photoId'],
                  'mimeType': 'image/png',
                  'dataBase64': base64Encode(_png),
                };
              return _list(
                problem: _problem(
                  photos: [for (var i = 0; i < 6; i++) _photo('ph$i', 'maid')],
                ),
              );
            },
          );
          await fixtures.mount(
            t,
            Scaffold(
              body: TechnicalProblemsScreen(
                organizationId: 'o',
                buildingId: 'b',
                service: service,
              ),
            ),
            locale: locale,
            size: size,
            scale: scale,
          );
          await t.pumpAndSettle();
          await _tap(t, find.byKey(const ValueKey('problem-p1')));
          expect(find.byKey(const ValueKey('photo-ph5')), findsOneWidget);
          expect(
            find.byKey(const ValueKey('photos-add')),
            findsNothing,
            reason: 'six photos is the limit',
          );
          expect(t.takeException(), isNull, reason: 'photos');
          await fixtures.mount(
            t,
            Scaffold(
              body: GoogleDriveScreen(organizationId: 'o', service: service),
            ),
            locale: locale,
            size: size,
            scale: scale,
          );
          await t.pumpAndSettle();
          final button = find.byKey(const ValueKey('drive-disconnect'));
          await t.ensureVisible(button);
          await t.pumpAndSettle();
          expect(button.hitTestable(), findsOneWidget);
          expect(t.takeException(), isNull, reason: 'drive');
        });
      }
    }
  }
}
