import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/team_review_queue.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/invitation_acceptance.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/team_display.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_theme.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'team_screen_test.dart' show access, staffName;
import 'staff_editor_test.dart' show reveal, press;
import 'access_editor_test.dart' show choose;

const email = 'nguyen.thi.minh.anh.riverside@example.com';
Map<String, dynamic> preview({bool closed = false}) => {
  'invitationId': 'invitation-reference',
  'organizationId': 'org',
  'organizationName': 'Riverside — Khu căn hộ và khách sạn phía Đông',
  'status': closed ? 'expired' : 'pending',
  'canAccept': !closed,
  'expiresAt': '2030-01-01T00:00:00.000Z',
  'access': {
    ...access('receptionist')['record'] as Map,
    'buildingScope': 'selected',
    'buildingIds': ['a'],
  },
  'properties': [
    {'id': 'a', 'name': 'Tòa nhà Riverside — Khu căn hộ phía Đông'},
  ],
};
TeamService queueService(
  Future<Map<String, dynamic>> Function(Map<String, dynamic>) save, {
  String role = 'owner',
}) => TeamService(
  transport: (name, data) async {
    if (name == 'mutateTeam') return save(data);
    if (name == 'lookupTeamInvitation') return preview();
    if (data['view'] == 'myAccess') return access(role);
    if (data['view'] == 'buildings') {
      return {
        'records': [
          {'id': 'a', 'name': 'Riverside'},
        ],
        'nextCursor': null,
      };
    }
    if (data['view'] == 'staff') {
      return {
        'records': [
          {
            'id': 'eligible',
            'displayName': staffName,
            'code': 'NV-001',
            'accountId': null,
            'employmentStatus': 'active',
            'canEditProfile': true,
          },
          {
            'id': 'linked',
            'displayName': 'Already linked',
            'code': 'NV-002',
            'accountId': 'someone',
            'employmentStatus': 'active',
            'canEditProfile': true,
          },
          {
            'id': 'inactive',
            'displayName': 'Inactive employee',
            'code': 'NV-003',
            'accountId': null,
            'employmentStatus': 'inactive',
            'canEditProfile': true,
          },
        ],
        'nextCursor': null,
      };
    }
    if (data['view'] == 'requests') {
      return {
        'records': [
          {
            'id': 'request',
            'displayName': staffName,
            'email': email,
            'status': 'pending',
            'canReview': true,
          },
        ],
        'nextCursor': null,
      };
    }
    return {
      'records': [
        {
          'id': 'invitation-reference',
          'email': email,
          'status': 'pending',
          'canRevoke': true,
          'access': {'role': 'receptionist'},
          'expiresAt': '2030-01-01T00:00:00.000Z',
        },
      ],
      'nextCursor': null,
    };
  },
);
Future<void> mountReview(
  WidgetTester tester,
  Widget child, {
  String language = 'en',
  double scale = 1,
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.light,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: const [
        AppTranslationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: brightness == Brightness.light
          ? buildAppTheme()
          : ThemeData(
              brightness: brightness,
              fontFamily: 'Roboto',
              colorSchemeSeed: AppThemeColors.teal,
            ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: RepaintBoundary(key: const ValueKey('capture'), child: child!),
      ),
      home: Scaffold(body: child),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Future<void> lookup(WidgetTester tester, {String language = 'en'}) async {
  final field = find.byKey(const ValueKey('invitation-reference'));
  await reveal(tester, field);
  await tester.enterText(field, 'invitation-reference');
  await press(
    tester,
    AppTranslations(Locale(language))['team_preview_invitation'],
  );
}

void main() {
  test(
    'invitation date follows language and malformed dates do not render raw data',
    () {
      final date = DateTime(2030, 1, 2, 15, 4).toIso8601String();
      expect(
        teamDate(date, AppTranslations(const Locale('vi'))),
        '02/01/2030 15:04',
      );
      expect(
        teamDate(date, AppTranslations(const Locale('en'))),
        '01/02/2030 15:04',
      );
      expect(
        teamDate('broken', AppTranslations(const Locale('en'))),
        'Not specified',
      );
    },
  );
  testWidgets(
    'queue loading empty error and pagination retain correct organization',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      var mode = 'loading';
      final cursors = <Object?>[];
      final service = TeamService(
        transport: (_, data) async {
          expect(data['organizationId'], 'org');
          if (data['view'] == 'myAccess') return access();
          if (mode == 'loading') return pending.future;
          if (mode == 'error') throw StateError('offline');
          if (mode == 'empty') return {'records': [], 'nextCursor': null};
          cursors.add(data['cursor']);
          return {
            'records': [
              {
                'id': data['cursor'] == null ? 'one' : 'two',
                'email': data['cursor'] == null
                    ? 'first@example.com'
                    : 'second@example.com',
                'status': 'revoked',
                'canRevoke': false,
                'access': {'role': 'viewer'},
              },
            ],
            'nextCursor': data['cursor'] == null ? 'one' : null,
          };
        },
      );
      // Pump without settling a deliberately pending request.
      await mountReview(
        tester,
        TeamReviewQueue(organizationId: 'org', service: service, onBack: () {}),
        settle: false,
      );
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      pending.complete({'records': [], 'nextCursor': null});
      await tester.pumpAndSettle();
      expect(find.text('No records to review.'), findsOneWidget);
      mode = 'error';
      await press(tester, 'Refresh');
      expect(
        find.text('Could not load the review queue. Refresh to try again.'),
        findsOneWidget,
      );
      mode = 'pages';
      await press(tester, 'Refresh');
      await press(tester, 'Load more records');
      expect(cursors, [null, 'one']);
      expect(find.text('first@example.com'), findsOneWidget);
      expect(find.text('second@example.com'), findsOneWidget);
      expect(find.text('Revoke invitation'), findsNothing);
      mode = 'empty';
      await press(tester, 'Refresh');
      expect(find.text('first@example.com'), findsNothing);
    },
  );
  testWidgets(
    'request with no eligible staff grants nothing and returns to queue',
    (tester) async {
      final service = TeamService(
        transport: (name, data) async {
          expect(name, 'readTeam');
          if (data['view'] == 'myAccess') return access();
          if (data['view'] == 'requests') {
            return {
              'records': [
                {
                  'id': 'request',
                  'email': email,
                  'status': 'pending',
                  'canReview': true,
                },
              ],
              'nextCursor': null,
            };
          }
          return {'records': [], 'nextCursor': null};
        },
      );
      await mountReview(
        tester,
        TeamReviewQueue(organizationId: 'org', service: service, onBack: () {}),
      );
      await press(tester, 'Access requests');
      await press(tester, 'Review request');
      expect(
        find.textContaining('No eligible staff profiles.'),
        findsOneWidget,
      );
      expect(find.text('Approve request'), findsNothing);
      await press(tester, 'Refresh');
      expect(find.text('Review request'), findsOneWidget);
    },
  );
  testWidgets(
    'request approval requires explicit eligible profile and role, and never sends invite',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      final service = queueService((data) async {
        calls.add(data);
        return {'status': 'approved'};
      });
      await mountReview(
        tester,
        TeamReviewQueue(organizationId: 'org', service: service, onBack: () {}),
      );
      await press(tester, 'Access requests');
      await press(tester, 'Review request');
      expect(calls, isEmpty);
      expect(find.textContaining('Already linked'), findsNothing);
      expect(find.textContaining('Inactive employee'), findsNothing);
      await press(tester, '$staffName • NV-001');
      expect(find.text(email), findsOneWidget);
      await press(tester, 'Approve request');
      expect(calls, isEmpty);
      await choose(tester, 'access-role', 'Receptionist');
      await press(tester, 'Approve request');
      expect(calls.single['action'], 'reviewRequest');
      expect(calls.single['decision'], 'approve');
      expect(calls.single['staffId'], 'eligible');
      expect(calls.single['requestId'], 'request');
      expect((calls.single['access'] as Map)['role'], 'receptionist');
      expect((calls.single['access'] as Map)['buildingIds'], isEmpty);
      expect(calls.single.containsKey('email'), isFalse);
    },
  );
  testWidgets(
    'request rejection retry preserves its action and operation and revoke targets invitation',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      final service = queueService((data) async {
        calls.add(data);
        if (calls.length == 1) {
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'timeout',
          );
        }
        return {'status': 'rejected'};
      });
      await mountReview(
        tester,
        TeamReviewQueue(organizationId: 'org', service: service, onBack: () {}),
      );
      await press(tester, 'Access requests');
      await press(tester, 'Reject request');
      expect(find.textContaining('Your draft is locked'), findsOneWidget);
      await press(tester, 'Retry same save');
      expect(calls[0], calls[1]);
      expect(calls.last['decision'], 'reject');
      expect(calls.last.containsKey('access'), isFalse);
      await press(tester, 'Invitations');
      await press(tester, 'Revoke invitation');
      expect(calls.last['action'], 'revokeInvitation');
      expect(calls.last['invitationId'], 'invitation-reference');
    },
  );
  testWidgets(
    'non-admin cannot load queue and denied mutation clears private records',
    (tester) async {
      await mountReview(
        tester,
        TeamReviewQueue(
          organizationId: 'org',
          service: queueService((_) async => {}, role: 'receptionist'),
          onBack: () {},
        ),
      );
      expect(find.text(email), findsNothing);
      expect(find.textContaining('You do not have access'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await mountReview(
        tester,
        TeamReviewQueue(
          organizationId: 'org',
          service: queueService(
            (_) async => throw FirebaseFunctionsException(
              code: 'permission-denied',
              message: 'denied',
            ),
          ),
          onBack: () {},
        ),
      );
      await press(tester, 'Revoke invitation');
      expect(find.text(email), findsNothing);
      expect(find.textContaining('You do not have access'), findsOneWidget);
    },
  );
  testWidgets(
    'recipient preview grants nothing, reference edits clear it, acceptance retries safely',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      var backs = 0;
      final service = TeamService(
        transport: (name, data) async {
          if (name == 'lookupTeamInvitation') return preview();
          calls.add(data);
          if (calls.length == 1) {
            throw FirebaseFunctionsException(
              code: 'unavailable',
              message: 'timeout',
            );
          }
          return {'status': 'active'};
        },
      );
      await mountReview(
        tester,
        InvitationAcceptance(service: service, onBack: () => backs++),
      );
      await lookup(tester);
      expect(calls, isEmpty);
      expect(
        find.text('Tòa nhà Riverside — Khu căn hộ phía Đông'),
        findsOneWidget,
      );
      await reveal(tester, find.byKey(const ValueKey('invitation-reference')));
      await tester.enterText(
        find.byKey(const ValueKey('invitation-reference')),
        'changed',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Tòa nhà Riverside — Khu căn hộ phía Đông'),
        findsNothing,
      );
      await lookup(tester);
      await press(tester, 'Accept invitation');
      await press(tester, 'Retry same save');
      expect(calls[0], calls[1]);
      expect(calls.last['action'], 'acceptInvitation');
      expect(calls.last['organizationId'], 'org');
      expect(
        find.text(
          'Invitation accepted. Your account is linked to the staff profile.',
        ),
        findsOneWidget,
      );
      await press(tester, 'Done');
      expect(backs, 1);
    },
  );
  testWidgets('unavailable or expired invitation offers no acceptance action', (
    tester,
  ) async {
    for (final fail in [true, false]) {
      await tester.pumpWidget(const SizedBox());
      final service = TeamService(
        transport: (name, data) async {
          expect(name, 'lookupTeamInvitation');
          if (fail) {
            throw FirebaseFunctionsException(
              code: 'not-found',
              message: 'private',
            );
          }
          return preview(closed: true);
        },
      );
      await mountReview(
        tester,
        InvitationAcceptance(service: service, onBack: () {}),
      );
      await lookup(tester);
      expect(
        find.widgetWithText(FilledButton, 'Accept invitation'),
        findsNothing,
      );
      expect(
        find.text(
          fail
              ? 'Invitation unavailable. Check the reference and sign in with the invited, verified email, then try again.'
              : 'Expired',
        ),
        findsOneWidget,
      );
    }
  });
  testWidgets(
    'populated queues approvals and recipient preview fit languages screens text sizes and themes',
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
              final service = queueService((_) async => {});
              final t = AppTranslations(Locale(language));
              Future<void> capture(String state) async {
                expect(
                  tester.takeException(),
                  isNull,
                  reason: '$size $language $scale $brightness $state',
                );
                if (const bool.fromEnvironment('REVIEW_GOLDENS')) {
                  await expectLater(
                    find.byKey(const ValueKey('capture')),
                    matchesGoldenFile(
                      '../.dart_tool/review-$language-${size.width.toInt()}-$scale-${brightness.name}-$state.png',
                    ),
                  );
                }
              }

              await tester.pumpWidget(const SizedBox());
              await mountReview(
                tester,
                TeamReviewQueue(
                  organizationId: 'org',
                  service: service,
                  onBack: () {},
                ),
                size: size,
                language: language,
                scale: scale,
                brightness: brightness,
              );
              await reveal(
                tester,
                find.widgetWithText(
                  OutlinedButton,
                  t['team_revoke_invitation'],
                ),
              );
              expect(
                find
                    .widgetWithText(OutlinedButton, t['team_revoke_invitation'])
                    .hitTestable(),
                findsOneWidget,
              );
              await capture('invitations');
              await tester.scrollUntilVisible(
                find.widgetWithText(OutlinedButton, t['team_requests']),
                -180,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              await press(tester, t['team_requests']);
              await reveal(
                tester,
                find.widgetWithText(FilledButton, t['team_review_request']),
              );
              await capture('requests');
              await press(tester, t['team_review_request']);
              await press(tester, '$staffName • NV-001');
              await choose(tester, 'access-role', t['team_role_receptionist']);
              await reveal(
                tester,
                find.widgetWithText(FilledButton, t['team_approve_request']),
              );
              expect(
                find
                    .widgetWithText(FilledButton, t['team_approve_request'])
                    .hitTestable(),
                findsOneWidget,
              );
              await capture('approval');
              await press(tester, t['team_cancel']);
              await tester.pumpWidget(const SizedBox());
              await mountReview(
                tester,
                InvitationEntryButton(service: service, onReturn: () {}),
                size: size,
                language: language,
                scale: scale,
                brightness: brightness,
              );
              await tester.tap(
                find.widgetWithText(
                  OutlinedButton,
                  t['team_accept_invitation'],
                ),
              );
              await tester.pumpAndSettle();
              await lookup(tester, language: language);
              await reveal(
                tester,
                find.widgetWithText(FilledButton, t['team_accept_invitation']),
              );
              expect(
                find
                    .widgetWithText(FilledButton, t['team_accept_invitation'])
                    .hitTestable(),
                findsOneWidget,
              );
              await capture('recipient');
            }
          }
        }
      }
    },
  );
}
