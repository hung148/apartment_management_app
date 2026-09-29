import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'team_screen_test.dart' show mount, access, staff;
import 'staff_editor_test.dart' show reveal, press;

Map<String, dynamic> profile(bool invite) => {
  ...staff(),
  'employmentStatus': 'active',
  'accountId': invite ? null : 'worker',
  'canManageAccess': !invite,
  if (!invite)
    'accountAccess': {
      ...access('receptionist')['record'] as Map,
      'buildingScope': 'selected',
      'buildingIds': ['a'],
      'permissionOverrides': {'refundPayments': false},
    },
};
TeamService serviceFor(
  Future<Map<String, dynamic>> Function(Map<String, dynamic>) save, {
  bool invite = true,
  String actor = 'owner',
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? buildings,
  Map<String, bool> overrides = const {},
  Map<String, dynamic> profileFields = const {},
}) => TeamService(
  transport: (name, data) async {
    if (name == 'mutateTeam') return save(data);
    if (data['view'] == 'myAccess') {
      return {
        'record': {
          ...access(actor)['record'] as Map,
          'permissionOverrides': overrides,
        },
      };
    }
    if (data['view'] == 'buildings') {
      if (buildings != null) return buildings(data);
      return {
        'records': [
          {'id': 'a', 'name': 'Riverside — Khu căn hộ và khách sạn phía Đông'},
          {'id': 'b', 'name': 'Garden apartments'},
        ],
        'nextCursor': null,
      };
    }
    return {
      'records': [
        {...profile(invite), ...profileFields},
      ],
      'nextCursor': null,
    };
  },
);
Future<void> openEditor(
  WidgetTester tester, {
  bool invite = true,
  String language = 'en',
}) async {
  final t = AppTranslations(Locale(language));
  await reveal(tester, find.text(t['team_view_details']));
  await tester.tap(find.text(t['team_view_details']));
  await tester.pumpAndSettle();
  await press(tester, t[invite ? 'team_invite' : 'team_manage_access']);
}

Future<void> choose(WidgetTester tester, String key, String label) async {
  final field = find.byKey(ValueKey(key));
  await reveal(tester, field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(label).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'unassigned legacy access requires explicit role and status before assignment',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      await mount(
        tester,
        serviceFor(
          (data) async {
            calls.add(data);
            return {'status': 'active'};
          },
          invite: false,
          profileFields: {
            'accountAccess': {'role': 'member', 'status': 'assignmentRequired'},
          },
        ),
      );
      await tester.pumpAndSettle();
      await openEditor(tester, invite: false);
      final reason = find.byKey(const ValueKey('access-reason'));
      await reveal(tester, reason);
      await tester.enterText(reason, 'Reviewed legacy account');
      await press(tester, 'Save access');
      expect(calls, isEmpty);
      await choose(tester, 'access-role', 'Receptionist');
      await choose(tester, 'access-status', 'Active');
      await press(tester, 'Save access');
      expect((calls.single['access'] as Map)['role'], 'receptionist');
      expect((calls.single['access'] as Map)['buildingIds'], isEmpty);
      expect(calls.single['status'], 'active');
    },
  );

  testWidgets(
    'unavailable assigned properties cannot be silently dropped when saving selected scope',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      await mount(
        tester,
        serviceFor(
          (data) async {
            calls.add(data);
            return {};
          },
          invite: false,
          profileFields: {
            'accountAccess': {
              ...access('receptionist')['record'] as Map,
              'buildingScope': 'selected',
              'buildingIds': ['removed'],
            },
          },
        ),
      );
      await tester.pumpAndSettle();
      await openEditor(tester, invite: false);
      final reason = find.byKey(const ValueKey('access-reason'));
      await reveal(tester, reason);
      await tester.enterText(reason, 'Review scope');
      await press(tester, 'Save access');
      expect(calls, isEmpty);
      expect(
        find.textContaining('Remove unavailable properties'),
        findsOneWidget,
      );
      await reveal(tester, find.text('Unavailable property: removed'));
      await tester.tap(find.text('Unavailable property: removed'));
      await tester.pumpAndSettle();
      await press(tester, 'Save access');
      expect((calls.single['access'] as Map)['buildingIds'], isEmpty);
    },
  );
  testWidgets(
    'selected permission label is fully visible at 200 percent Vietnamese text',
    (tester) async {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
      await mount(
        tester,
        serviceFor((_) async => {}, invite: false),
        size: const Size(320, 740),
        language: 'vi',
        scale: 2,
      );
      await tester.pumpAndSettle();
      await openEditor(tester, invite: false, language: 'vi');
      final field = find.byKey(const ValueKey('access-refundPayments'));
      await reveal(tester, field);
      final label = find.descendant(
        of: field,
        matching: find.text('Không cho phép'),
      );
      final paragraph = tester.renderObject<RenderParagraph>(label);
      final boxes = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 13),
      );
      expect(boxes, isNotEmpty);
      for (final box in boxes) {
        expect(
          box.bottom,
          lessThanOrEqualTo(paragraph.size.height + 0.01),
          reason: 'Selected permission text must not be clipped',
        );
      }
      if (const bool.fromEnvironment('ACCESS_GOLDENS')) {
        await expectLater(
          find.byKey(const ValueKey('capture')),
          matchesGoldenFile('../.dart_tool/access-denial-vi-200.png'),
        );
      }
    },
  );
  testWidgets(
    'invitation requires a role and submits explicit empty selected scope without member or owner choices',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      await mount(
        tester,
        serviceFor((data) async {
          calls.add(data);
          return {'invitationId': 'invite-reference'};
        }),
      );
      await tester.pumpAndSettle();
      await openEditor(tester);
      await press(tester, 'Create invitation');
      expect(calls, isEmpty);
      expect(find.text('This field is required.'), findsOneWidget);
      await choose(tester, 'access-role', 'Receptionist');
      expect(
        find.text('No selection means no property access.'),
        findsOneWidget,
      );
      await press(tester, 'Create invitation');
      final grant = calls.single['access'] as Map;
      expect(grant['role'], 'receptionist');
      expect(grant['buildingScope'], 'selected');
      expect(grant['buildingIds'], isEmpty);
      expect(calls.single['action'], 'invite');
      expect(calls.single['staffId'], 'first');
      expect(find.text('invite-reference'), findsOneWidget);
      expect(find.textContaining('No email was sent').first, findsOneWidget);
    },
  );

  testWidgets(
    'all properties clears selected IDs in payload and overrides are explicit',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      await mount(
        tester,
        serviceFor((data) async {
          calls.add(data);
          return {'invitationId': 'id'};
        }),
      );
      await tester.pumpAndSettle();
      await openEditor(tester);
      await choose(tester, 'access-role', 'Manager');
      final building = find.byKey(const ValueKey('access-building-a'));
      await reveal(tester, building);
      await tester.tap(building);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('All properties'));
      await tester.tap(find.text('All properties'));
      await tester.pumpAndSettle();
      await choose(tester, 'access-refundPayments', 'Allow');
      await press(tester, 'Create invitation');
      final grant = calls.single['access'] as Map;
      expect(grant['buildingScope'], 'all');
      expect(grant['buildingIds'], isEmpty);
      expect(grant['permissionOverrides'], {'refundPayments': true});
    },
  );

  testWidgets(
    'existing access retains scope and overrides and requires an audit reason for suspension',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      await mount(
        tester,
        serviceFor((data) async {
          calls.add(data);
          return {'status': 'suspended'};
        }, invite: false),
      );
      await tester.pumpAndSettle();
      await openEditor(tester, invite: false);
      await choose(tester, 'access-status', 'Suspended');
      await press(tester, 'Save access');
      expect(calls, isEmpty);
      final reason = find.byKey(const ValueKey('access-reason'));
      await reveal(tester, reason);
      await tester.enterText(reason, '  Employment review  ');
      await press(tester, 'Save access');
      expect(calls.single['action'], 'setAccess');
      expect(calls.single['userId'], 'worker');
      expect(calls.single['status'], 'suspended');
      expect(calls.single['reason'], 'Employment review');
      expect((calls.single['access'] as Map)['buildingIds'], ['a']);
      expect((calls.single['access'] as Map)['permissionOverrides'], {
        'refundPayments': false,
      });
    },
  );

  testWidgets(
    'administrator choices exclude administrator and no grant exceeds actor permissions',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      await mount(
        tester,
        serviceFor(
          (data) async {
            calls.add(data);
            return {};
          },
          actor: 'administrator',
          overrides: {'refundPayments': false},
        ),
      );
      await tester.pumpAndSettle();
      await openEditor(tester);
      final field = find.byKey(const ValueKey('access-role'));
      await reveal(tester, field);
      final dropdown = tester.widget<DropdownButtonFormField>(field);
      // Open the menu to verify actual role choices, not just hidden labels.
      expect(dropdown, isNotNull);
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(find.text('Administrator'), findsNothing);
      expect(find.text('Owner'), findsNothing);
      expect(find.text('Member'), findsNothing);
      await tester.tap(find.text('Accountant').last);
      await tester.pumpAndSettle();
      await press(tester, 'Create invitation');
      expect(calls, isEmpty);
      expect(find.textContaining('exceeds the permissions'), findsOneWidget);
    },
  );

  testWidgets(
    'uncertain invitation retries the identical operation and denial clears the editor',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      await mount(
        tester,
        serviceFor((data) async {
          calls.add(data);
          throw FirebaseFunctionsException(
            code: calls.length == 1 ? 'unavailable' : 'permission-denied',
            message: 'test',
          );
        }),
      );
      await tester.pumpAndSettle();
      await openEditor(tester);
      await choose(tester, 'access-role', 'Receptionist');
      await press(tester, 'Create invitation');
      expect(find.textContaining('Your draft is locked'), findsOneWidget);
      await press(tester, 'Retry same save');
      expect(calls[0], calls[1]);
      expect(find.byKey(const ValueKey('access-email')), findsNothing);
      expect(find.textContaining('You do not have access'), findsOneWidget);
    },
  );

  testWidgets(
    'property loading failure blocks writes and refresh loads every page',
    (tester) async {
      var fail = true;
      final cursors = <Object?>[];
      await mount(
        tester,
        serviceFor(
          (_) async => throw StateError('must not save'),
          buildings: (data) async {
            if (fail) throw StateError('offline');
            cursors.add(data['cursor']);
            return {
              'records': [
                {
                  'id': data['cursor'] == null ? 'a' : 'b',
                  'name': data['cursor'] == null ? 'First' : 'Second',
                },
              ],
              'nextCursor': data['cursor'] == null ? 'a' : null,
            };
          },
        ),
      );
      await tester.pumpAndSettle();
      await openEditor(tester);
      expect(
        find.text('Properties could not be loaded. Refresh before saving.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create invitation'),
            )
            .onPressed,
        isNull,
      );
      fail = false;
      await press(tester, 'Refresh');
      expect(cursors, [null, 'a']);
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
    },
  );

  testWidgets(
    'populated invitation and access forms fit locales sizes scales themes',
    (tester) async {
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      for (final size in [
        const Size(320, 740),
        const Size(812, 375),
        const Size(1440, 1000),
      ]) {
        for (final language in ['en', 'vi']) {
          for (final scale in [1.0, 1.3, 2.0]) {
            for (final brightness in Brightness.values) {
              for (final invite in [true, false]) {
                await tester.pumpWidget(const SizedBox());
                await mount(
                  tester,
                  serviceFor((_) async => {}, invite: invite),
                  size: size,
                  language: language,
                  scale: scale,
                  brightness: brightness,
                );
                await tester.pumpAndSettle();
                await openEditor(tester, invite: invite, language: language);
                final t = AppTranslations(Locale(language));
                await choose(
                  tester,
                  'access-role',
                  t['team_role_receptionist'],
                );
                final building = find.byKey(
                  const ValueKey('access-building-a'),
                );
                await reveal(tester, building);
                expect(building.hitTestable(), findsOneWidget);
                expect(
                  tester.takeException(),
                  isNull,
                  reason:
                      '$size $language $scale $brightness $invite properties',
                );
                if (const bool.fromEnvironment('ACCESS_GOLDENS')) {
                  await expectLater(
                    find.byKey(const ValueKey('capture')),
                    matchesGoldenFile(
                      '../.dart_tool/access-$language-${size.width.toInt()}-$scale-${brightness.name}-$invite-properties.png',
                    ),
                  );
                }
                if (!invite) {
                  final reason = find.byKey(const ValueKey('access-reason'));
                  await reveal(tester, reason);
                  await tester.enterText(
                    reason,
                    'Đánh giá quyền truy cập các tòa nhà cho nhân sự mới',
                  );
                  await tester.pumpAndSettle();
                }
                final save = find.widgetWithText(
                  FilledButton,
                  t[invite ? 'team_create_invite' : 'team_save_access'],
                );
                await reveal(tester, save);
                expect(save.hitTestable(), findsOneWidget);
                expect(tester.takeException(), isNull);
                if (const bool.fromEnvironment('ACCESS_GOLDENS')) {
                  await expectLater(
                    find.byKey(const ValueKey('capture')),
                    matchesGoldenFile(
                      '../.dart_tool/access-$language-${size.width.toInt()}-$scale-${brightness.name}-$invite-controls.png',
                    ),
                  );
                }
                await press(tester, t['team_cancel']);
                expect(find.text(t['team_details']), findsOneWidget);
              }
            }
          }
        }
      }
    },
  );
}
