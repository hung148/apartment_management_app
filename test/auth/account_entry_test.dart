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
  testWidgets(
    'the saved workspace opens at once, locked; the fresh check keeps it',
    (t) async {
      _probeStarts = 0;
      final fresh = Completer<AccountEntry>();
      await mount(t, _savedGate(() => fresh.future, _one('w')));
      await t.pump();
      expect(find.text('Workspace'), findsOneWidget);
      expect(_locked(t), isTrue);
      fresh.complete(_one('w'));
      await t.pump();
      await t.pump();
      expect(find.text('Workspace'), findsOneWidget);
      expect(_locked(t), isFalse);
      expect(_probeStarts, 1, reason: 'the same workspace stays open');
    },
  );
  testWidgets(
    'a fresh check that does not open it replaces the saved workspace',
    (t) async {
      for (final outcome in ['other', 'suspended', 'error']) {
        final fresh = Completer<AccountEntry>();
        await mount(t, _savedGate(() => fresh.future, _one('w')));
        await t.pump();
        expect(find.text('Workspace'), findsOneWidget);
        if (outcome == 'error') {
          fresh.completeError(StateError('offline'));
        } else {
          fresh.complete(
            outcome == 'other' ? _one('x') : _one('w', state: 'suspended'),
          );
        }
        await t.pump();
        await t.pump();
        if (outcome == 'other') {
          expect(find.byKey(const ValueKey('ws-x')), findsOneWidget);
          expect(find.byKey(const ValueKey('ws-w')), findsNothing);
        } else {
          expect(find.text('Workspace'), findsNothing, reason: outcome);
        }
        await t.pumpWidget(const SizedBox());
      }
    },
  );
  test('only a check that opens one workplace is kept, and it reads back', () {
    expect(_one('w').toSaved(), isNotNull);
    expect(
      AccountEntry.fromSaved(_one('w').toSaved())!.workplaces.single.id,
      'w',
    );
    expect(_one('w', state: 'suspended').toSaved(), isNull);
    expect(
      AccountEntry(
        mode: 'owner',
        canCreate: true,
        workplaces: [org('a'), org('b')],
      ).toSaved(),
      isNull,
    );
    expect(
      AccountEntry(
        mode: 'staff',
        canCreate: false,
        workplaces: [org('a')],
        needsVerifiedEmail: true,
      ).toSaved(),
      isNull,
    );
    expect(AccountEntry.fromSaved({'id': 'w', 'mode': 'conflict'}), isNull);
    expect(AccountEntry.fromSaved({'mode': 'staff'}), isNull);
    expect(AccountEntry.fromSaved(null), isNull);
  });
  test(
    'invitation email verification does not block an existing owner after merging',
    () async {
      final service = AccountEntryService(
        transport: (name, data) async {
          if (name == 'claimMyInvitations')
            return {'results': [], 'needsVerifiedEmail': true};
          return {
            'accountPolicy': {
              'mode': 'owner',
              'entryState': 'ready',
              'canCreate': false,
            },
            'records': [
              {'id': 'merged', 'name': 'Unified', 'accessVersion': 2},
            ],
          };
        },
      );
      final entry = await service.load();
      expect(entry.needsVerifiedEmail, false);
      expect(entry.workplaces.single.id, 'merged');
    },
  );
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test(
    'entry paginates, claims (server that does not say) and fails closed on missing policy',
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
      expect(calls, [
        'listMyOrganizations',
        'listMyOrganizations',
        'claimMyInvitations',
      ]);
      await expectLater(
        AccountEntryService(transport: (n, d) async => {'records': []}).load(),
        throwsStateError,
      );
    },
  );
  // Speed (2026-10-09): the list says whether invitations wait to be claimed;
  // the claim is asked for only then, and a joined one lists again.
  test(
    'the claim runs only when the list reports waiting invitations',
    () async {
      for (final (pending, joined) in [
        (false, false),
        (true, false),
        (true, true),
      ]) {
        final calls = <String>[];
        var lists = 0;
        final service = AccountEntryService(
          transport: (name, data) async {
            calls.add(name);
            if (name == 'claimMyInvitations') {
              return {
                'results': [
                  if (joined) {'organizationId': 'org2', 'status': 'joined'},
                ],
              };
            }
            lists++;
            return {
              'accountPolicy': {'mode': 'staff', 'canCreate': false},
              'records': [
                {'id': 'org$lists', 'name': 'Work', 'accessVersion': 2},
              ],
              'invitations': {'pending': pending, 'needsVerifiedEmail': false},
            };
          },
        );
        final e = await service.load();
        expect(
          calls.where((c) => c == 'claimMyInvitations').length,
          pending ? 1 : 0,
        );
        expect(lists, joined ? 2 : 1);
        expect(e.workplaces.single.id, joined ? 'org2' : 'org1');
      }
    },
  );
  test(
    'an unverified email is reported from the list without a claim',
    () async {
      final calls = <String>[];
      final service = AccountEntryService(
        transport: (name, data) async {
          calls.add(name);
          return {
            'accountPolicy': {'mode': 'staff', 'canCreate': false},
            'records': [],
            'invitations': {'pending': false, 'needsVerifiedEmail': true},
          };
        },
      );
      expect((await service.load()).needsVerifiedEmail, true);
      expect(calls, ['listMyOrganizations']);
    },
  );
  test('a failed claim fails the entry even when the list worked', () async {
    for (final says in [false, true]) {
      final service = AccountEntryService(
        transport: (name, data) async {
          if (name == 'claimMyInvitations') throw StateError('offline');
          return {
            'accountPolicy': {'mode': 'staff', 'canCreate': false},
            'records': [],
            if (says) 'invitations': {'pending': true},
          };
        },
      );
      await expectLater(service.load(), throwsStateError);
    }
  });
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
  testWidgets('the first check shows a neutral screen, not Workplaces', (
    t,
  ) async {
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
        testWidgets(
          'ambiguous workplaces are blocked $locale ${size.width} x${scale}',
          (t) async {
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
            expect(
              find.byKey(const ValueKey('staff-workplace-a')),
              findsNothing,
            );
            expect(
              find.byKey(const ValueKey('staff-workplace-b')),
              findsNothing,
            );
            expect(
              find.byKey(const ValueKey('staff-workplace-c')),
              findsNothing,
            );
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
          },
        );
      }
}

// Speed (2026-10-09, Tom): the workspace the last check opened is shown at once
// from the saved check, locked until the fresh check arrives.
int _probeStarts = 0;

class _Probe extends StatefulWidget {
  const _Probe({super.key});
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _probeStarts++;
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('Workspace'));
}

AccountEntry _one(String id, {String state = 'ready'}) => AccountEntry(
  mode: 'staff',
  state: state,
  canCreate: false,
  workplaces: [org(id)],
);

Widget _savedGate(Future<AccountEntry> Function() load, AccountEntry? saved) =>
    AccountEntryGate(
      load: load,
      saved: () async => saved,
      ownerBuilder: (_) => const Text('Owner dashboard'),
      openWorkplace: (_) async {},
      onSettings: () {},
      workspaceBuilder: (_, o) => _Probe(key: ValueKey('ws-${o.id}')),
    );

bool _locked(WidgetTester t) => t
    .widget<AbsorbPointer>(find.byKey(const ValueKey('entry-workspace')))
    .absorbing;
