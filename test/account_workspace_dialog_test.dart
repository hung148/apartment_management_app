import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/models/team_access.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/account_workspace_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/role_workspace.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/org_location.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/organization_settings_service.dart';
import 'account_entry_test.dart' as fixtures;

void main() {
  setUpAll(() async {
    for (final family in ['Roboto', 'Ahem']) {
      await (FontLoader(family)
            ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
            ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
          .load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final language in ['en', 'vi'])
    for (final size in [
      const Size(320, 740),
      const Size(812, 375),
      const Size(1440, 1000),
    ])
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets(
          'populated import dialog $language $size $scale reaches confirmation',
          (t) async {
            final calls = <Map<String, dynamic>>[];
            final service = TeamService(
              transport: (name, d) async {
                expect(name, 'importSheet');
                calls.add(d);
                expect(d['action'], 'preview');
                return {
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
                  'existing': {},
                  'overlapCount': 0,
                  'overlaps': [],
                  'problemCount': 1,
                  'problems': [
                    {
                      'code': 'room_added',
                      'tab': 'Đặt phòng',
                      'id': 'MK10',
                      'guest': 'Nguyễn Thị Minh Anh — gia đình Riverside',
                      'building':
                          'Riverside — Khu căn hộ và khách sạn phía Đông',
                      'room': 'P299 — Phòng gia đình hướng biển',
                    },
                  ],
                };
              },
            );
            await fixtures.mount(
              t,
              Scaffold(
                body: Builder(
                  builder: (c) => TextButton(
                    onPressed: () => showDialog<void>(
                      context: c,
                      builder: (_) => AccountWorkspaceDialog(
                        option: accountWorkspaceOptions.last,
                        organizationId: 'org',
                        service: service,
                        onChanged: () {},
                        pickImportFile: () async => (
                          name: 'synthetic-preview.xlsx',
                          bytes: Uint8List.fromList(
                            File('tool/import_sample.xlsx').readAsBytesSync(),
                          ),
                        ),
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
              locale: language,
              size: size,
              scale: scale,
            );
            await t.tap(find.text('Open'));
            await t.pumpAndSettle();
            final pick = find.byKey(const ValueKey('import-choose'));
            await t.ensureVisible(pick);
            await t.pumpAndSettle();
            await t.tap(pick);
            await t.pumpAndSettle();
            expect(find.byKey(const ValueKey('import-confirm')), findsNothing);
            final start = find.byKey(const ValueKey('import-start'));
            await t.ensureVisible(start);
            await t.pumpAndSettle();
            expect(start.hitTestable(), findsOneWidget);
            await t.tap(start);
            await t.pumpAndSettle();
            final apply = find.byKey(const ValueKey('import-apply'));
            await t.ensureVisible(apply);
            await t.pumpAndSettle();
            expect(apply.hitTestable(), findsOneWidget);
            expect(
              find
                  .byKey(const ValueKey('account-workspace-close'))
                  .hitTestable(),
              findsOneWidget,
            );
            expect(calls.length, 1);
            expect(t.takeException(), isNull);
            if ((language == 'en' && size.width == 1440 && scale == 1) ||
                (language == 'vi' && size.width == 320 && scale == 2)) {
              await t.runAsync(() async {
                final boundary = t
                    .element(find.byType(Dialog))
                    .findAncestorRenderObjectOfType<RenderRepaintBoundary>()!;
                final image = await boundary.toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await Directory(
                  '.dart_tool/account-dialog-layout',
                ).create(recursive: true);
                await File(
                  '.dart_tool/account-dialog-layout/import-preview-$language-${size.width.toInt()}-$scale.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
          },
        );
      }
  testWidgets(
    'receiving account label does not truncate on narrow large text',
    (t) async {
      final settings = OrganizationSettingsService(
        transport: (_, d) async => {
          'id': 'org',
          'name': 'Riverside',
          'accessVersion': 2,
          'createdBy': 'owner',
          'createdAt': '2026-10-01T00:00:00Z',
          'role': 'owner',
          'canManage': true,
          'paymentAccounts': [
            {'id': 'bank', 'label': 'Synthetic bank'},
          ],
        },
      );
      await fixtures.mount(
        t,
        Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => showAccountWorkspaceDialog(
                c,
                option: accountWorkspaceOptions[2],
                organizationId: 'org',
                service: TeamService(transport: (_, d) async => {}),
                settings: settings,
                onChanged: () {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
        size: const Size(320, 740),
        locale: 'vi',
        scale: 2,
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      final label = find.text('Tên tài khoản');
      await t.ensureVisible(label);
      await t.pumpAndSettle();
      expect(t.renderObject<RenderParagraph>(label).didExceedMaxLines, isFalse);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('double tapping Account action opens one dialog intent', (
    t,
  ) async {
    var opens = 0;
    await fixtures.mount(
      t,
      Scaffold(
        body: AccountWorkspaceButtons(
          organizationId: 'org',
          service: TeamService(
            transport: (_, d) async => {
              'record': {
                'accessVersion': 2,
                'role': 'owner',
                'status': 'active',
                'buildingScope': 'all',
              },
            },
          ),
          tile: (o, tap) => TextButton(onPressed: tap, child: Text(o.id)),
          onOpen: (_) => opens++,
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('drive'));
    await t.tap(find.text('drive'));
    await t.pumpAndSettle();
    expect(opens, 1);
  });
  for (final role in TeamPolicy.templateIds) {
    testWidgets('Account actions retain $role permission boundaries', (
      t,
    ) async {
      final opened = <String>[];
      await fixtures.mount(
        t,
        Scaffold(
          body: AccountWorkspaceButtons(
            organizationId: 'org',
            service: TeamService(
              transport: (_, d) async => {
                'record': {
                  'accessVersion': 2,
                  'role': role,
                  'status': 'active',
                  'buildingScope': 'all',
                  'grants': {
                    for (final e in TeamPolicy.templates[role]!.entries)
                      e.key.name: e.value.name,
                  },
                },
              },
            ),
            tile: (o, tap) => TextButton(onPressed: tap, child: Text(o.id)),
            onOpen: (o) => opened.add(o.id),
          ),
        ),
      );
      await t.pumpAndSettle();
      final expected = role == 'owner'
          ? ['ownership', 'drive', 'accounts', 'import']
          : role == 'administrator'
          ? ['ownership', 'accounts']
          : ['ownership'];
      for (final o in accountWorkspaceOptions) {
        expect(
          find.text(o.id),
          expected.contains(o.id) ? findsOneWidget : findsNothing,
        );
      }
      expect(opened, isEmpty);
    });
  }
  testWidgets(
    'loading error retry and suspended access expose no privileged buttons',
    (t) async {
      final pending = Completer<Map<String, dynamic>>();
      var tries = 0;
      final service = TeamService(
        transport: (_, d) async {
          if (tries++ == 0) return pending.future;
          return {
            'record': {
              'accessVersion': 2,
              'role': 'owner',
              'status': 'suspended',
              'buildingScope': 'all',
            },
          };
        },
      );
      await fixtures.mount(
        t,
        Scaffold(
          body: AccountWorkspaceButtons(
            organizationId: 'org',
            service: service,
            tile: (o, tap) => TextButton(onPressed: tap, child: Text(o.id)),
            onOpen: (_) {},
          ),
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      pending.completeError(StateError('offline'));
      await t.pumpAndSettle();
      expect(find.text('ownership'), findsNothing);
      await t.tap(find.text('Refresh'));
      await t.pumpAndSettle();
      expect(find.byType(TextButton), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'old Settings ownership link opens dialog over allowed workspace',
    (t) async {
      final store = TeamPreviewStore();
      final addresses = <String>[];
      final service = TeamService(
        transport: (name, d) async {
          if (name == 'transferOrganization')
            return {'owner': true, 'candidates': [], 'proposal': null};
          return store.call(name, d);
        },
      );
      await fixtures.mount(
        t,
        RoleWorkspace(
          organizationId: 'preview',
          service: service,
          initial: const OrgLocation(
            'preview',
            section: 'settings',
            page: 'ownership',
          ),
          onLocationChanged: (l) => addresses.add(l.address),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(AccountWorkspaceDialog), findsOneWidget);
      expect(addresses.last, contains('/calendar/board'));
      expect(
        find.byKey(const ValueKey('workspace-section-settings')),
        findsNothing,
      );
      await t.tap(find.byKey(const ValueKey('account-workspace-close')));
      await t.pumpAndSettle();
      expect(find.byType(AccountWorkspaceDialog), findsNothing);
    },
  );
  for (final page in ['drive', 'import', 'unknown']) {
    testWidgets('staff cannot open old Settings $page link', (t) async {
      final store = TeamPreviewStore()..workspaceRole = 'housekeeper';
      await fixtures.mount(
        t,
        RoleWorkspace(
          organizationId: 'preview',
          service: store.service,
          initial: OrgLocation('preview', section: 'settings', page: page),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(AccountWorkspaceDialog), findsNothing);
      expect(
        find.byKey(const ValueKey('workspace-section-settings')),
        findsNothing,
      );
    });
  }
  testWidgets('pending nominee dialog keeps accept and refresh separated', (
    t,
  ) async {
    final service = TeamService(
      transport: (_, d) async => {
        'owner': false,
        'candidates': [],
        'proposal': {
          'id': 'offer',
          'recipientName': 'Nguyễn Thị Minh Anh — Riverside',
          'canAccept': true,
        },
      },
    );
    await fixtures.mount(
      t,
      Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () => showAccountWorkspaceDialog(
              c,
              option: accountWorkspaceOptions.first,
              organizationId: 'org',
              service: service,
              onChanged: () {},
            ),
            child: const Text('Open'),
          ),
        ),
      ),
      locale: 'vi',
      scale: 2,
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    final accept = find.byType(FilledButton);
    await t.ensureVisible(accept);
    await t.pumpAndSettle();
    final refresh = find.widgetWithText(OutlinedButton, 'Làm mới');
    expect(
      t.getRect(refresh).top - t.getRect(accept).bottom,
      greaterThanOrEqualTo(8),
    );
    expect(
      find.byKey(const ValueKey('account-workspace-close')).hitTestable(),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'long handover candidate remains inside its field at 200 percent',
    (t) async {
      const name = 'Nguyễn Thị Minh Anh — Quản lý tòa nhà Riverside phía Đông';
      final service = TeamService(
        transport: (_, d) async => {
          'owner': true,
          'candidates': [
            {'id': 'staff', 'name': name},
          ],
          'proposal': null,
        },
      );
      await fixtures.mount(
        t,
        Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => showAccountWorkspaceDialog(
                c,
                option: accountWorkspaceOptions.first,
                organizationId: 'org',
                service: service,
                onChanged: () {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
        size: const Size(320, 740),
        locale: 'vi',
        scale: 2,
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      final field = find.byType(DropdownButtonFormField<String>);
      await t.ensureVisible(field);
      await t.pumpAndSettle();
      await t.tap(field);
      await t.pumpAndSettle();
      await t.tap(find.text(name).last);
      await t.pumpAndSettle();
      final text = t.getRect(find.text(name));
      final box = t.getRect(field);
      expect(text.top, greaterThanOrEqualTo(box.top));
      expect(text.bottom, lessThanOrEqualTo(box.bottom));
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'receiving accounts dialog leaves Close reachable above landscape keyboard',
    (t) async {
      t.view.viewInsets = const FakeViewPadding(bottom: 180);
      addTearDown(t.view.resetViewInsets);
      final settings = OrganizationSettingsService(
        transport: (_, d) async => {
          'id': 'org',
          'name': 'Riverside',
          'accessVersion': 2,
          'createdBy': 'owner',
          'createdAt': '2026-10-01T00:00:00Z',
          'role': 'owner',
          'canManage': true,
          'paymentAccounts': [],
        },
      );
      await fixtures.mount(
        t,
        Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => showAccountWorkspaceDialog(
                c,
                option: accountWorkspaceOptions[2],
                organizationId: 'org',
                service: TeamService(transport: (_, d) async => {}),
                settings: settings,
                onChanged: () {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
        size: const Size(812, 375),
        locale: 'vi',
        scale: 2,
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('account-workspace-close')).hitTestable(),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('receiving account save notifies workspace only after success', (
    t,
  ) async {
    var changes = 0;
    final calls = <Map<String, dynamic>>[];
    final settings = OrganizationSettingsService(
      transport: (_, d) async {
        if (d['action'] == 'accounts') {
          calls.add(d);
          return {};
        }
        return {
          'id': 'org',
          'name': 'Riverside',
          'accessVersion': 2,
          'createdBy': 'owner',
          'createdAt': '2026-10-01T00:00:00Z',
          'role': 'owner',
          'canManage': true,
          'paymentAccounts': [
            {'id': 'bank', 'label': 'Synthetic bank'},
          ],
        };
      },
    );
    await fixtures.mount(
      t,
      Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () => showAccountWorkspaceDialog(
              c,
              option: accountWorkspaceOptions[2],
              organizationId: 'org',
              service: TeamService(transport: (_, d) async => {}),
              settings: settings,
              onChanged: () => changes++,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    expect(changes, 0);
    await t.enterText(find.byType(TextField), 'Updated synthetic bank');
    final save = find.byKey(const ValueKey('account-save'));
    await t.ensureVisible(save);
    await t.pumpAndSettle();
    await t.tap(save);
    await t.pumpAndSettle();
    expect(changes, 1);
    expect(
      (calls.single['accounts'] as List).single['label'],
      'Updated synthetic bank',
    );
  });
  for (final locale in ['en', 'vi'])
    for (final size in [
      const Size(320, 740),
      const Size(812, 375),
      const Size(1440, 1000),
    ])
      for (final scale in [1.0, 1.3, 2.0])
        for (final option in accountWorkspaceOptions) {
          testWidgets(
            '${option.id} dialog $locale $size $scale scrolls and closes',
            (t) async {
              final service = TeamService(
                transport: (name, d) async {
                  if (name == 'transferOrganization')
                    return {'owner': true, 'candidates': [], 'proposal': null};
                  if (name == 'googleDrive')
                    return {
                      'state': 'connected',
                      'canConnect': true,
                      'email': 'synthetic.owner@recovery-verification.example',
                      'connectedByName':
                          'Nguyễn Thị Minh Anh — Chủ sở hữu Riverside',
                    };
                  return {};
                },
              );
              final settings = OrganizationSettingsService(
                transport: (_, d) async => {
                  'id': 'org',
                  'name': 'Riverside',
                  'accessVersion': 2,
                  'createdBy': 'owner',
                  'createdAt': '2026-10-01T00:00:00Z',
                  'role': 'owner',
                  'canManage': true,
                  'paymentAccounts': [
                    {
                      'id': 'bank',
                      'label':
                          'Vietcombank — Nguyễn Thị Minh Anh — Tài khoản nhận tiền Riverside',
                    },
                  ],
                },
              );
              await fixtures.mount(
                t,
                Scaffold(
                  body: Builder(
                    builder: (c) => TextButton(
                      onPressed: () => showAccountWorkspaceDialog(
                        c,
                        option: option,
                        organizationId: 'org',
                        service: service,
                        settings: settings,
                        onChanged: () {},
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                ),
                locale: locale,
                size: size,
                scale: scale,
              );
              await t.tap(find.text('Open'));
              await t.pumpAndSettle();
              expect(find.byType(AccountWorkspaceDialog), findsOneWidget);
              final close = find.byKey(
                const ValueKey('account-workspace-close'),
              );
              expect(close.hitTestable(), findsOneWidget);
              expect(t.takeException(), isNull);
              if (option.id == 'ownership') {
                final send = find.byType(FilledButton);
                await t.ensureVisible(send);
                await t.pumpAndSettle();
                final refresh = find.widgetWithText(
                  OutlinedButton,
                  locale == 'en' ? 'Refresh' : 'Làm mới',
                );
                expect(
                  t.getRect(refresh).top - t.getRect(send).bottom,
                  greaterThanOrEqualTo(8),
                );
              }
              if ((locale == 'en' && size.width == 1440 && scale == 1) ||
                  (locale == 'vi' && size.width == 320 && scale == 2)) {
                await t.runAsync(() async {
                  final boundary = t
                      .element(find.byType(Dialog))
                      .findAncestorRenderObjectOfType<RenderRepaintBoundary>()!;
                  final im = await boundary.toImage();
                  final bytes = await im.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  await Directory(
                    '.dart_tool/account-dialog-layout',
                  ).create(recursive: true);
                  await File(
                    '.dart_tool/account-dialog-layout/${option.id}-$locale-${size.width.toInt()}-$scale.png',
                  ).writeAsBytes(bytes!.buffer.asUint8List());
                  im.dispose();
                });
              }
              final actionKey = switch (option.id) {
                'accounts' => 'account-save',
                'drive' => 'drive-disconnect',
                'import' => 'import-choose',
                _ => null,
              };
              if (actionKey != null) {
                final action = find.byKey(ValueKey(actionKey));
                await t.ensureVisible(action);
                await t.pumpAndSettle();
                expect(action.hitTestable(), findsOneWidget);
                expect(close.hitTestable(), findsOneWidget);
                expect(t.takeException(), isNull);
              }
              await t.tap(close);
              await t.pumpAndSettle();
              expect(find.byType(AccountWorkspaceDialog), findsNothing);
            },
          );
        }
}
