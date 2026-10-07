import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_theme.dart';
import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/services/account_entry_service.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/dashboard/account_entry_gate.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';

Organization org(String id) => Organization(
  id: id,
  name: 'Riverside — Khu căn hộ và khách sạn phía Đông $id',
  createdBy: 'owner',
  createdAt: DateTime(2026),
  inviteCode: '',
  accessVersion: 2,
);
const captureKey = ValueKey('entry-capture');
Future<void> mount(
  WidgetTester t,
  Widget child, {
  Size size = const Size(390, 844),
  String locale = 'en',
  double scale = 1,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: const [
        AppTranslationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: RepaintBoundary(key: captureKey, child: child),
    ),
  );
  await t.pump();
}

Widget gate(
  Future<AccountEntry> Function() load, {
  Future<void> Function(Organization)? open,
  VoidCallback? settings,
}) => AccountEntryGate(
  load: load,
  ownerBuilder: (_) => const Text('Owner dashboard'),
  openWorkplace: open ?? (_) async {},
  onSettings: settings ?? () {},
);
void main() {
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test(
    'entry claims first, paginates and fails closed on missing policy',
    () async {
      final calls = <String>[];
      final service = AccountEntryService(
        transport: (name, data) async {
          calls.add(name);
          if (name == 'claimMyInvitations') return {'results': []};
          return {
            'accountPolicy': {'mode': 'staff', 'canCreate': false},
            'records': [
              {
                'id': data['cursor'] == null ? 'a' : 'b',
                'name': 'Work',
                'accessVersion': 2,
                'createdAt': '2026-01-01T00:00:00Z',
              },
            ],
            'nextCursor': data['cursor'] == null ? 'page2' : null,
          };
        },
      );
      final e = await service.load();
      expect(e.workplaces.length, 2);
      expect(e.canCreate, false);
      expect(calls.first, 'claimMyInvitations');
      await expectLater(
        AccountEntryService(transport: (n, d) async => {'records': []}).load(),
        throwsStateError,
      );
    },
  );
  test(
    'preview follows staff policy and supplies the same entry projection',
    () async {
      final store = TeamPreviewStore()..accountMode = 'staff';
      final entry = await AccountEntryService(transport: store.call).load();
      expect(entry.staffOnly, true);
      expect(entry.canCreate, false);
      await expectLater(
        store.call('organizationSettings', {'action': 'create'}),
        throwsA(isA<Exception>()),
      );
      store.ownerEmails.add('owner@example.com');
      await expectLater(
        store.call('mutateTeam', {
          'action': 'addStaff',
          'operationId': 'conflict',
          'profile': {'email': 'owner@example.com'},
          'access': {},
        }),
        throwsA(predicate((e) => e.toString().contains('team_owner_account'))),
      );
    },
  );
  testWidgets(
    'existing employer conflict is actionable and does not open any workplace',
    (t) async {
      await mount(
        t,
        gate(
          () async => const AccountEntry(
            mode: 'staff',
            canCreate: false,
            workplaces: [],
            staffConflict: 'team_other_employer',
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.textContaining('already assigned to another company'),
        findsOneWidget,
      );
      expect(find.text('Owner dashboard'), findsNothing);
      expect(find.byIcon(Icons.settings).hitTestable(), findsOneWidget);
    },
  );
  testWidgets('one workplace opens once; returning does not trap Back', (
    t,
  ) async {
    var opened = 0;
    final open = Completer<void>();
    await mount(
      t,
      gate(
        () async => AccountEntry(
          mode: 'staff',
          canCreate: false,
          workplaces: [org('a')],
        ),
        open: (_) async {
          opened++;
          await open.future;
        },
      ),
    );
    await t.pumpAndSettle();
    expect(opened, 1);
    expect(find.text('Owner dashboard'), findsNothing);
    open.complete();
    await t.pumpAndSettle();
    expect(opened, 1);
    expect(find.byKey(const ValueKey('staff-workplace-a')), findsOneWidget);
  });
  testWidgets('the first check shows a neutral screen, not Workplaces', (t) async {
    final pending = Completer<AccountEntry>();
    AppRouter.pendingAddress = '/org/o1/rooms';
    addTearDown(() => AppRouter.pendingAddress = null);
    await mount(t, gate(() => pending.future));
    expect(find.text('Reopening the page you were on…'), findsOneWidget);
    expect(find.text('Your workplace'), findsNothing);
    expect(find.text('Owner dashboard'), findsNothing);
    pending.complete(
      const AccountEntry(mode: 'normal', canCreate: true, workplaces: []),
    );
    await t.pumpAndSettle();
    expect(find.text('Owner dashboard'), findsOneWidget);
  });
  testWidgets('loading and errors hide owner dashboard and retry recovers', (
    t,
  ) async {
    var attempts = 0;
    final pending = Completer<AccountEntry>();
    await mount(
      t,
      gate(() {
        attempts++;
        return attempts == 1
            ? pending.future
            : Future.value(
                const AccountEntry(
                  mode: 'normal',
                  canCreate: true,
                  workplaces: [],
                ),
              );
      }),
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Owner dashboard'), findsNothing);
    pending.completeError(StateError('offline'));
    await t.pumpAndSettle();
    expect(find.textContaining('Could not check'), findsOneWidget);
    await t.tap(find.byType(OutlinedButton));
    await t.pumpAndSettle();
    expect(find.text('Owner dashboard'), findsOneWidget);
  });
  testWidgets(
    'waiting and suspended entry keep settings reachable without automatic navigation',
    (t) async {
      var opened = 0, settings = 0;
      await mount(
        t,
        gate(
          () async => AccountEntry(
            mode: 'staff',
            canCreate: false,
            workplaces: [org('a')],
            waitingIds: {'a'},
          ),
          open: (_) async {
            opened++;
          },
          settings: () {
            settings++;
          },
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('staff-workplace-a')));
      await t.pumpAndSettle();
      expect(opened, 0);
      await t.tap(find.byIcon(Icons.settings));
      expect(settings, 1);
    },
  );
  for (final locale in ['en', 'vi'])
    for (final size in [
      const Size(360, 800),
      const Size(800, 360),
      const Size(1440, 900),
    ])
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('ambiguous workplaces are blocked $locale ${size.width} x${scale}', (t) async {
          var opened = 0;
          final pending = Completer<void>();
          await mount(
            t,
            gate(
              () async => AccountEntry(
                mode: 'conflict',
                canCreate: false,
                workplaces: [org('a'), org('b'), org('c')],
              ),
              open: (_) async {
                opened++;
                await pending.future;
              },
            ),
            size: size,
            locale: locale,
            scale: scale,
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.text('Owner dashboard'), findsNothing);
          expect(find.byKey(const ValueKey('staff-workplace-a')), findsNothing);
          expect(find.byKey(const ValueKey('staff-workplace-b')), findsNothing);
          expect(find.byKey(const ValueKey('staff-workplace-c')), findsNothing);
          expect(opened, 0);
          pending.complete();
          await t.pumpAndSettle();
          expect(find.byIcon(Icons.settings).hitTestable(), findsOneWidget);
          expect(t.takeException(), isNull);
          if ((locale == 'vi' && size.width == 360 && scale == 2) ||
              (locale == 'en' && size.width == 1440 && scale == 1)) {
            await t.runAsync(() async {
              final boundary =
                  t.element(find.byKey(captureKey)).renderObject!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final dir = Directory('.dart_tool/staff-policy-screenshots');
              await dir.create(recursive: true);
              await File(
                '${dir.path}/$locale-${size.width.toInt()}-$scale.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        });
      }
}
