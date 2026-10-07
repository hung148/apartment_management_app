import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/dashboard/account_menu_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/account_workspace_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/organization_settings_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'account_entry_test.dart' as fixtures;

void main() {
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final locale in ['en', 'vi']) {
    for (final size in [
      const Size(320, 740),
      const Size(812, 375),
      const Size(1440, 1000),
    ]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets(
          'Account children return and header close stays reachable $locale $size $scale',
          (t) async {
            final service = TeamService(
              transport: (name, d) async {
                if (name == 'readTeam')
                  return {
                    'record': {
                      'accessVersion': 2,
                      'role': 'owner',
                      'status': 'active',
                      'buildingScope': 'all',
                    },
                  };
                if (name == 'transferOrganization')
                  return {
                    'owner': true,
                    'candidates': [
                      {
                        'id': 'staff',
                        'name': 'Nguyễn Thị Minh Anh — Riverside East',
                      },
                    ],
                    'proposal': null,
                  };
                return {'state': 'disconnected', 'canConnect': true};
              },
            );
            final settings = OrganizationSettingsService(
              transport: (_, d) async => {
                'organization': {
                  'id': 'org',
                  'name': 'Riverside',
                  'createdBy': 'owner',
                  'accessVersion': 2,
                },
                'canManage': true,
                'paymentAccounts': [
                  {'id': 'bank', 'label': 'Synthetic bank account'},
                ],
              },
            );
            await fixtures.mount(
              t,
              Scaffold(
                body: Builder(
                  builder: (c) {
                    void openMenu() {
                      showDialog<void>(
                        context: c,
                        builder: (menu) => AccountMenuDialog(
                          maxWidth: 480,
                          children: [
                            for (final label in ['personal_info', 'org_info'])
                              AccountMenuTile(
                                icon: Icons.person_outline,
                                label: AppTranslations.of(menu)[label],
                                onTap: () {},
                              ),
                            AccountWorkspaceButtons(
                              organizationId: 'org',
                              service: service,
                              tile: (o, tap) => AccountMenuTile(
                                key: ValueKey('open-${o.id}'),
                                icon: o.icon,
                                label: o.label(menu),
                                onTap: tap,
                              ),
                              onOpen: (o) => openAccountChild(
                                menu,
                                reopen: openMenu,
                                canReopen: () => c.mounted,
                                open: () => showAccountWorkspaceDialog(
                                  c,
                                  option: o,
                                  organizationId: 'org',
                                  service: service,
                                  settings: settings,
                                  onChanged: () {},
                                ),
                              ),
                            ),
                            for (final label in [
                              'lang',
                              'theme_color',
                              'record_recovery_title',
                              'logout',
                              'delete_account',
                            ])
                              AccountMenuTile(
                                icon: Icons.person_outline,
                                label: AppTranslations.of(menu)[label],
                                onTap: () {},
                              ),
                          ],
                        ),
                      );
                    }

                    return TextButton(
                      onPressed: openMenu,
                      child: const Text('Open Account'),
                    );
                  },
                ),
              ),
              locale: locale,
              size: size,
              scale: scale,
            );
            await t.tap(find.text('Open Account'));
            await t.pumpAndSettle();
            final close = find.byKey(const ValueKey('account-menu-close'));
            expect(close.hitTestable(), findsOneWidget);
            expect(t.getSize(close).shortestSide, greaterThanOrEqualTo(48));
            final headerRect = t.getRect(close);
            for (final option in accountWorkspaceOptions) {
              final action = find.byKey(ValueKey('open-${option.id}'));
              await t.ensureVisible(action);
              await t.pumpAndSettle();
              expect(t.getRect(close), headerRect);
              await t.tap(action);
              await t.pumpAndSettle();
              expect(find.byType(AccountWorkspaceDialog), findsOneWidget);
              expect(
                find.byType(AccountMenuDialog, skipOffstage: false),
                findsNothing,
              );
              await t.tap(
                find.byKey(const ValueKey('account-workspace-close')),
              );
              await t.pumpAndSettle();
              expect(find.byType(AccountMenuDialog), findsOneWidget);
              expect(close.hitTestable(), findsOneWidget);
              expect(t.takeException(), isNull);
            }
            // Escape/back closes only the active child, then header closes Account.
            final action = find.byKey(const ValueKey('open-ownership'));
            await t.ensureVisible(action);
            await t.tap(action);
            await t.pumpAndSettle();
            await t.binding.handlePopRoute();
            await t.pumpAndSettle();
            expect(find.byType(AccountMenuDialog), findsOneWidget);
            if ((locale == 'vi' && size.width == 320 && scale == 2) ||
                (locale == 'en' && size.width == 1440 && scale == 1)) {
              await t.runAsync(() async {
                final boundary = t
                    .element(find.byType(Dialog))
                    .findAncestorRenderObjectOfType<RenderRepaintBoundary>()!;
                final im = await boundary.toImage();
                final bytes = await im.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await Directory(
                  '.dart_tool/account-return-layout',
                ).create(recursive: true);
                await File(
                  '.dart_tool/account-return-layout/menu-$locale.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                im.dispose();
              });
            }
            await t.tap(close);
            await t.pumpAndSettle();
            expect(find.byType(AccountMenuDialog), findsNothing);
          },
        );
      }
    }
  }
}
