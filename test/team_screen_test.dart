import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/team_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_theme.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';

const staffName = 'Nguyễn Thị Minh Anh — Quản lý khu căn hộ Riverside';
Map<String, dynamic> access([String role = 'owner']) => {
  'record': {
    'role': role,
    'accessVersion': 2,
    'status': 'active',
    'buildingScope': 'all',
  },
};
Map<String, dynamic> staff([String id = 'first']) => {
  'id': id,
  'displayName': staffName,
  'code': 'NV-RIVERSIDE-000012345',
  'employmentStatus': 'inactive',
  'accountId': 'linked-account',
  'canEditProfile': true,
  'email': 'minhanh.riverside.management@example.com',
  'phone': '+84 912 345 678',
};

Future<void> mount(
  WidgetTester tester,
  TeamService service, {
  String organization = 'a',
  String language = 'en',
  double scale = 1,
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.light
          ? buildAppTheme()
          : ThemeData(
              brightness: brightness,
              fontFamily: 'Roboto',
              colorSchemeSeed: AppThemeColors.teal,
            ),
      locale: Locale(language),
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: const [
        AppTranslationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: RepaintBoundary(key: const ValueKey('capture'), child: child!),
      ),
      home: Scaffold(
        body: TeamScreen(organizationId: organization, service: service),
      ),
    ),
  );
}

void main() {
  test(
    'organization migration version survives copies but cannot enter client writes',
    () {
      final org = Organization.fromMap('a', {
        'accessVersion': 2,
        'createdAt': Timestamp.now(),
      });
      expect(org.accessVersion, 2);
      expect(org.copyWith(name: 'Renamed').accessVersion, 2);
      expect(org.toMap().containsKey('accessVersion'), isFalse);
      expect(
        Organization.fromMap('b', {'createdAt': Timestamp.now()}).accessVersion,
        1,
      );
    },
  );

  testWidgets(
    'pagination and details separate employment from linked login; denial clears data',
    (tester) async {
      var denied = false;
      final cursors = <String?>[];
      final service = TeamService(
        transport: (_, data) async {
          if (denied) {
            throw FirebaseFunctionsException(
              code: 'permission-denied',
              message: 'private',
            );
          }
          if (data['view'] == 'myAccess') return access();
          cursors.add(data['cursor'] as String?);
          return {
            'records': [staff(data['cursor'] == null ? 'first' : 'second')],
            'nextCursor': data['cursor'] == null ? 'first' : null,
          };
        },
      );
      await mount(tester, service);
      await tester.pumpAndSettle();
      expect(find.text('Employment: Inactive employment'), findsOneWidget);
      expect(find.text('Login account: Linked'), findsOneWidget);
      await tester.tap(find.text('Load more staff'));
      await tester.pumpAndSettle();
      expect(cursors, [null, 'first']);
      await tester.tap(find.text('View details').first);
      await tester.pumpAndSettle();
      expect(find.text('Staff details'), findsOneWidget);
      await tester.ensureVisible(
        find.text('minhanh.riverside.management@example.com'),
      );
      expect(
        find.text('minhanh.riverside.management@example.com'),
        findsOneWidget,
      );
      denied = true;
      await tester.ensureVisible(find.text('Refresh'));
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text(staffName), findsNothing);
      expect(find.textContaining('You do not have access'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late organization response cannot overwrite current organization',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final service = TeamService(
        transport: (_, data) async {
          if (data['organizationId'] == 'a') return pending.future;
          if (data['view'] == 'myAccess') return access('receptionist');
          return {'records': [], 'nextCursor': null};
        },
      );
      await mount(tester, service);
      await tester.pump();
      expect(find.text('Loading staff…'), findsOneWidget);
      await mount(tester, service, organization: 'b');
      await tester.pumpAndSettle();
      expect(find.text('My staff profile'), findsOneWidget);
      expect(
        find.text('No staff profile is linked to your account.'),
        findsOneWidget,
      );
      pending.complete(access());
      await tester.pumpAndSettle();
      expect(find.text('My staff profile'), findsOneWidget);
      expect(find.text(staffName), findsNothing);
    },
  );

  testWidgets('empty, failed, and suspended states have usable refresh', (
    tester,
  ) async {
    for (final mode in ['empty', 'failed', 'suspended']) {
      await tester.pumpWidget(const SizedBox());
      var staffCalls = 0;
      final service = TeamService(
        transport: (_, data) async {
          if (mode == 'failed') throw StateError('offline');
          if (data['view'] == 'myAccess') {
            final result = access();
            if (mode == 'suspended') {
              (result['record'] as Map)['status'] = 'suspended';
            }
            return result;
          }
          staffCalls++;
          return {'records': [], 'nextCursor': null};
        },
      );
      await mount(tester, service);
      await tester.pumpAndSettle();
      expect(
        find.text(switch (mode) {
          'empty' => 'No staff profiles yet.',
          'failed' => 'Staff could not be loaded. Refresh to try again.',
          _ =>
            'You do not have access to these staff records. Contact your owner or administrator.',
        }),
        findsOneWidget,
      );
      expect(find.text('Refresh').hitTestable(), findsOneWidget);
      if (mode == 'suspended') expect(staffCalls, 0);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'populated directory and details fit locales sizes scales and themes',
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
              final service = TeamService(
                transport: (_, data) async => data['view'] == 'myAccess'
                    ? access()
                    : {
                        'records': [
                          staff(),
                          {
                            ...staff('other'),
                            'displayName': 'Trần Văn Bình',
                            'accountId': null,
                            'employmentStatus': 'active',
                          },
                        ],
                        'nextCursor': null,
                      },
              );
              await mount(
                tester,
                service,
                size: size,
                language: language,
                scale: scale,
                brightness: brightness,
              );
              await tester.pumpAndSettle();
              final t = AppTranslations(Locale(language));
              final details = find.byKey(const ValueKey('team-details-first'));
              await tester.scrollUntilVisible(
                details,
                180,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              expect(details.hitTestable(), findsOneWidget);
              expect(
                tester.takeException(),
                isNull,
                reason: '$size $language $scale $brightness directory',
              );
              if (const bool.fromEnvironment('TEAM_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/team-$language-${size.width.toInt()}-$scale-${brightness.name}-directory.png',
                  ),
                );
              }
              await tester.tap(details);
              await tester.pumpAndSettle();
              await tester.scrollUntilVisible(
                find.text(t['team_access_note']),
                180,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              expect(
                find.text(t['team_access_note']).hitTestable(),
                findsOneWidget,
              );
              expect(
                tester.takeException(),
                isNull,
                reason: '$size $language $scale $brightness details',
              );
              if (const bool.fromEnvironment('TEAM_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/team-$language-${size.width.toInt()}-$scale-${brightness.name}-details.png',
                  ),
                );
              }
              await tester.scrollUntilVisible(
                find.text(t['team_back']),
                -180,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              expect(find.text(t['team_back']).hitTestable(), findsOneWidget);
              await tester.tap(find.text(t['team_back']));
              await tester.pumpAndSettle();
              expect(find.text(t['team_directory']), findsOneWidget);
              expect(tester.takeException(), isNull);
            }
          }
        }
      }
    },
  );
}
