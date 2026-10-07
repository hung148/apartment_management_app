import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'team_screen_test.dart' show mount, access, staff;

/// The page's own vertical scroll view: skips the organization workspace
/// menu (sidebar) and horizontal rows such as the page chips (U1).
Finder mainScrollable() {
  final menus = find.byKey(const ValueKey('workspace-nav')).evaluate().toSet();
  bool inMenu(Element element) {
    var found = false;
    element.visitAncestorElements((ancestor) {
      found = menus.contains(ancestor);
      return !found;
    });
    return found;
  }

  final candidates = find
      .byWidgetPredicate(
        (w) =>
            w is Scrollable &&
            (w.axisDirection == AxisDirection.down ||
                w.axisDirection == AxisDirection.up),
      )
      .evaluate()
      .where((e) => !inMenu(e))
      .toList();
  if (candidates.isEmpty) return find.byType(Scrollable).first;
  final first = candidates.first;
  return find.byElementPredicate((e) => identical(e, first));
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 160, scrollable: mainScrollable());
  await tester.pumpAndSettle();
}

/// Opens a workspace section (sidebar, bottom bar or "More") and optionally
/// one of its pages (U1).
Future<void> openSection(
  WidgetTester tester,
  String section, {
  String? page,
}) async {
  final direct = find.byKey(ValueKey('workspace-section-$section'));
  if (direct.evaluate().isNotEmpty) {
    await tester.tap(direct.first);
  } else {
    await tester.tap(find.byKey(const ValueKey('workspace-section-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('workspace-more-$section')));
  }
  await tester.pumpAndSettle();
  // A section with one page has no page chips.
  final chip = find.byKey(ValueKey('workspace-page-$page'));
  if (page != null && chip.evaluate().isNotEmpty) {
    // The page tabs scroll sideways on narrow screens.
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }
}

Future<void> press(WidgetTester tester, String label) async {
  final finder = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
  );
  await reveal(tester, finder);
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(ValueKey('staff-$key'));
  await reveal(tester, finder);
  await tester.enterText(finder, value);
  await tester.pumpAndSettle();
}

TeamService fake(
  Future<Map<String, dynamic>> Function(Map<String, dynamic>) save, {
  String role = 'owner',
  bool editable = true,
}) => TeamService(
  transport: (name, data) async {
    if (name == 'mutateTeam') return save(data);
    if (data['view'] == 'myAccess') return access(role);
    return {
      'records': [
        {...staff(), 'canEditProfile': editable, 'color': '#123456'},
      ],
      'nextCursor': null,
    };
  },
);

void main() {
  testWidgets(
    'switching organization discards old editor and ignores its late save response',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final calls = <Map<String, dynamic>>[];
      final service = fake((data) {
        calls.add(data);
        return pending.future;
      });
      await mount(tester, service);
      await tester.pumpAndSettle();
      await press(tester, 'Add staff profile');
      await fill(tester, 'displayName', 'Old organization draft');
      await fill(tester, 'code', 'OLD-1');
      await reveal(tester, find.widgetWithText(FilledButton, 'Save profile'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save profile'));
      await tester.pump();
      await mount(tester, service, organization: 'b');
      await tester.pumpAndSettle();
      pending.complete({'staffId': 'old'});
      await tester.pumpAndSettle();
      expect(calls.single['organizationId'], 'a');
      expect(find.text('Staff profile saved.'), findsNothing);
      expect(find.text('Old organization draft'), findsNothing);
      expect(find.text('Team directory'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'long error and uncertain-save messages remain readable with enlarged text',
    (tester) async {
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
      for (final language in ['en', 'vi']) {
        for (final size in [const Size(320, 740), const Size(812, 375)]) {
          await tester.pumpWidget(const SizedBox());
          await mount(
            tester,
            fake(
              (_) async => throw FirebaseFunctionsException(
                code: 'unavailable',
                message: 'timeout',
              ),
            ),
            language: language,
            size: size,
            scale: 2,
          );
          await tester.pumpAndSettle();
          final t = AppTranslations(Locale(language));
          await press(tester, t['team_add_staff']);
          await press(tester, t['team_save_profile']);
          expect(find.text(t['team_required']), findsNWidgets(2));
          expect(tester.takeException(), isNull);
          await fill(tester, 'displayName', 'Nguyễn Thị Lan');
          await fill(tester, 'code', 'NV-2');
          await press(tester, t['team_save_profile']);
          expect(
            find.text(t['team_save_uncertain']).hitTestable(),
            findsOneWidget,
          );
          if (const bool.fromEnvironment('STAFF_GOLDENS')) {
            await expectLater(
              find.byKey(const ValueKey('capture')),
              matchesGoldenFile(
                '../.dart_tool/staff-error-$language-${size.width.toInt()}.png',
              ),
            );
          }
          await reveal(
            tester,
            find.widgetWithText(FilledButton, t['team_retry_save']),
          );
          expect(
            find
                .widgetWithText(FilledButton, t['team_retry_save'])
                .hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets(
    'create validates fields and saves only staff information then refreshes',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      final service = fake((data) async {
        calls.add(data);
        return {'staffId': 'created'};
      });
      await mount(tester, service);
      await tester.pumpAndSettle();
      await press(tester, 'Add staff profile');
      await press(tester, 'Save profile');
      expect(find.text('This field is required.'), findsNWidgets(2));
      expect(calls, isEmpty);
      await fill(tester, 'displayName', '  Nguyễn Thị Lan  ');
      await fill(tester, 'code', '  NV-0002 ');
      await fill(tester, 'email', 'invalid');
      await press(tester, 'Save profile');
      expect(
        find.text('Enter a valid email address, or leave this blank.'),
        findsOneWidget,
      );
      expect(calls, isEmpty);
      await fill(tester, 'email', 'lan@example.com');
      await press(tester, 'Save profile');
      expect(calls.single['action'], 'saveStaff');
      expect(calls.single.containsKey('staffId'), isFalse);
      expect(calls.single['profile'], {
        'displayName': 'Nguyễn Thị Lan',
        'code': 'NV-0002',
        'email': 'lan@example.com',
        'phone': '',
        'color': '',
        'employmentStatus': 'active',
      });
      expect(find.text('Team directory'), findsOneWidget);
      expect(find.text('Staff profile saved.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'edit preserves color and linkage by omitting account changes; cancel writes nothing',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      await mount(
        tester,
        fake((data) async {
          calls.add(data);
          return {'staffId': 'first'};
        }),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('View details'));
      await tester.tap(find.text('View details'));
      await tester.pumpAndSettle();
      await press(tester, 'Edit staff profile');
      await fill(tester, 'displayName', 'Updated name');
      await press(tester, 'Cancel');
      expect(calls, isEmpty);
      expect(find.text('Staff details'), findsOneWidget);
      await press(tester, 'Edit staff profile');
      await fill(tester, 'displayName', 'Updated name');
      await press(tester, 'Save profile');
      expect(calls.single['staffId'], 'first');
      final profile = calls.single['profile'] as Map;
      expect(profile['employmentStatus'], 'inactive');
      expect(profile['color'], '#123456');
      expect(profile.containsKey('accountId'), isFalse);
      expect(profile.containsKey('role'), isFalse);
    },
  );

  testWidgets(
    'uncertain save locks fields and retry reuses operation; double submits blocked',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      final pending = Completer<Map<String, dynamic>>();
      final service = fake((data) async {
        calls.add(data);
        if (calls.length == 1) return pending.future;
        return {'staffId': 'created'};
      });
      await mount(tester, service);
      await tester.pumpAndSettle();
      await press(tester, 'Add staff profile');
      await fill(tester, 'displayName', 'Employee');
      await fill(tester, 'code', 'EMP-1');
      await reveal(tester, find.widgetWithText(FilledButton, 'Save profile'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save profile'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Saving…'))
            .onPressed,
        isNull,
      );
      expect(calls, hasLength(1));
      pending.completeError(
        FirebaseFunctionsException(code: 'unavailable', message: 'timeout'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Your draft is locked'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('staff-displayName')),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isTrue,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Cancel'),
            )
            .onPressed,
        isNull,
      );
      await press(tester, 'Retry same save');
      expect(calls, hasLength(2));
      expect(calls[0], calls[1]);
      expect(find.text('Team directory'), findsOneWidget);
    },
  );

  testWidgets(
    'duplicate code can be corrected; access denial removes draft and private records',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      final service = fake((data) async {
        calls.add(data);
        throw FirebaseFunctionsException(
          code: calls.length == 1 ? 'already-exists' : 'permission-denied',
          message: calls.length == 1
              ? 'team_staff_code_exists'
              : 'team_access_denied',
        );
      });
      await mount(tester, service);
      await tester.pumpAndSettle();
      await press(tester, 'Add staff profile');
      await fill(tester, 'displayName', 'Private draft');
      await fill(tester, 'code', 'TAKEN');
      await press(tester, 'Save profile');
      expect(
        find.text('This staff code is already in use. Choose another code.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('staff-code')),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isFalse,
      );
      await fill(tester, 'code', 'NEW');
      await press(tester, 'Save profile');
      expect(calls[0]['operationId'], isNot(calls[1]['operationId']));
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Add staff profile'), findsNothing);
      expect(find.textContaining('You do not have access'), findsOneWidget);
    },
  );

  testWidgets('staff cannot create or edit and protected profiles hide edit', (
    tester,
  ) async {
    for (final role in ['receptionist', 'owner']) {
      await tester.pumpWidget(const SizedBox());
      await mount(
        tester,
        fake(
          (_) async => throw StateError('Must not write'),
          role: role,
          editable: false,
        ),
      );
      await tester.pumpAndSettle();
      if (role == 'receptionist') {
        expect(find.text('Add staff profile'), findsNothing);
      }
      await reveal(tester, find.text('View details'));
      await tester.tap(find.text('View details'));
      await tester.pumpAndSettle();
      expect(find.text('Edit staff profile'), findsNothing);
    }
  });

  testWidgets(
    'populated edit form fits locales sizes scales themes and keyboard',
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
              await tester.pumpWidget(const SizedBox());
              await mount(
                tester,
                fake((_) async => {'staffId': 'first'}),
                size: size,
                language: language,
                scale: scale,
                brightness: brightness,
              );
              await tester.pumpAndSettle();
              final t = AppTranslations(Locale(language));
              await reveal(tester, find.text(t['team_view_details']));
              await tester.tap(find.text(t['team_view_details']));
              await tester.pumpAndSettle();
              await press(tester, t['team_edit_staff']);
              final field = find.byKey(const ValueKey('staff-email'));
              await reveal(tester, field);
              final bounds = tester.getRect(field);
              await tester.enterText(
                field,
                'long.staff.contact.riverside@example.com',
              );
              await tester.pumpAndSettle();
              expect(tester.getRect(field).size, bounds.size);
              expect(tester.getRect(field).left, bounds.left);
              tester.view.viewInsets = FakeViewPadding(
                bottom: size.height < 500 ? 140 : 250,
              );
              await tester.pumpAndSettle();
              await reveal(
                tester,
                find.widgetWithText(FilledButton, t['team_save_profile']),
              );
              expect(
                find
                    .widgetWithText(FilledButton, t['team_save_profile'])
                    .hitTestable(),
                findsOneWidget,
              );
              expect(
                tester.takeException(),
                isNull,
                reason: '$size $language $scale $brightness keyboard',
              );
              tester.view.resetViewInsets();
              await tester.pumpAndSettle();
              if (const bool.fromEnvironment('STAFF_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/staff-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
                  ),
                );
              }
              await press(tester, t['team_cancel']);
              expect(find.text(t['team_details']), findsOneWidget);
              expect(tester.takeException(), isNull);
            }
          }
        }
      }
    },
  );
}
