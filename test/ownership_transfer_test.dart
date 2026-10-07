import 'dart:async';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/ownership_transfer_screen.dart';
import 'account_entry_test.dart' as fixtures;

void main() {
  testWidgets('prepared read is consumed once and Refresh reads fresh data', (
    t,
  ) async {
    var reads = 0;
    await fixtures.mount(
      t,
      Scaffold(
        body: OwnershipTransferScreen(
          organizationId: 'org',
          onChanged: () {},
          initialRead: Future.value({
            'owner': true,
            'candidates': [],
            'proposal': null,
          }),
          service: TeamService(
            transport: (_, d) async {
              reads++;
              return {'owner': true, 'candidates': [], 'proposal': null};
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(reads, 0);
    await t.tap(find.widgetWithText(OutlinedButton, 'Refresh'));
    await t.pumpAndSettle();
    expect(reads, 1);
  });
  testWidgets('failed prepared read falls back to retryable fresh read', (
    t,
  ) async {
    var reads = 0;
    await fixtures.mount(
      t,
      Scaffold(
        body: OwnershipTransferScreen(
          organizationId: 'org',
          onChanged: () {},
          initialRead: Future.value(null),
          service: TeamService(
            transport: (_, d) async {
              reads++;
              throw StateError('offline');
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(reads, 1);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await t.tap(find.widgetWithText(OutlinedButton, 'Refresh'));
    await t.pumpAndSettle();
    expect(reads, 2);
  });
  testWidgets('loading does not claim there is no ownership offer', (t) async {
    final pending = Completer<Map<String, dynamic>>();
    await fixtures.mount(
      t,
      Scaffold(
        body: OwnershipTransferScreen(
          organizationId: 'org',
          onChanged: () {},
          service: TeamService(transport: (_, d) => pending.future),
        ),
      ),
    );
    await t.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      find.text(
        AppTranslations.of(
          t.element(find.byType(OwnershipTransferScreen)),
        )['org_transfer_no_offer'],
      ),
      findsNothing,
    );
    pending.complete({'owner': true, 'candidates': [], 'proposal': null});
    await t.pumpAndSettle();
  });
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
  });
  testWidgets('handover and refresh buttons have a visible gap', (t) async {
    await fixtures.mount(
      t,
      Scaffold(
        body: OwnershipTransferScreen(
          organizationId: 'org',
          onChanged: () {},
          service: TeamService(
            transport: (_, d) async => {
              'owner': true,
              'candidates': [],
              'proposal': null,
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final send = t.getRect(find.byType(FilledButton));
    final refresh = t.getRect(find.widgetWithText(OutlinedButton, 'Refresh'));
    expect(refresh.top - send.bottom, greaterThanOrEqualTo(8));
  });
  testWidgets(
    'owner sends a consent offer; lost reply retries identical intent',
    (t) async {
      final calls = <Map<String, dynamic>>[];
      var tries = 0, changed = 0;
      final service = TeamService(
        transport: (name, d) async {
          expect(name, 'transferOrganization');
          if (d['action'] == 'read')
            return {
              'owner': true,
              'candidates': [
                {'id': 'staff', 'name': 'Staff'},
              ],
              'proposal': null,
            };
          calls.add(d);
          if (tries++ == 0) throw StateError('offline');
          return {'status': 'pending'};
        },
      );
      await fixtures.mount(
        t,
        Scaffold(
          body: OwnershipTransferScreen(
            organizationId: 'org',
            service: service,
            onChanged: () => changed++,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(DropdownButtonFormField<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Staff').last);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Send handover offer'));
      await t.pumpAndSettle();
      expect(calls.single['action'], 'propose');
      expect(changed, 0);
      await t.tap(find.widgetWithText(FilledButton, 'Send handover offer'));
      await t.pumpAndSettle();
      expect(calls[1], calls[0]);
      expect(changed, 1);
    },
  );
  testWidgets(
    'nominee sees explicit accept and other staff see no acceptance control',
    (t) async {
      final calls = <Map<String, dynamic>>[];
      await fixtures.mount(
        t,
        Scaffold(
          body: OwnershipTransferScreen(
            organizationId: 'org',
            onChanged: () {},
            service: TeamService(
              transport: (_, d) async {
                if (d['action'] == 'read')
                  return {
                    'owner': false,
                    'candidates': [],
                    'proposal': {
                      'id': 'offer',
                      'recipientName': 'Staff',
                      'canAccept': true,
                    },
                  };
                calls.add(d);
                return {};
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(calls, isEmpty);
      await t.tap(find.widgetWithText(FilledButton, 'Accept ownership'));
      await t.pumpAndSettle();
      expect(calls.single['action'], 'accept');
    },
  );
  for (final locale in ['en', 'vi'])
    for (final size in [
      const Size(360, 800),
      const Size(800, 360),
      const Size(1440, 900),
    ])
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('handover $locale $size $scale', (t) async {
          final service = TeamService(
            transport: (_, d) async => {
              'owner': true,
              'candidates': [
                {
                  'id': 'staff',
                  'name':
                      'Nguyễn Thị Minh Anh — Quản lý tòa nhà Riverside phía Đông',
                },
              ],
              'proposal': null,
            },
          );
          await fixtures.mount(
            t,
            Scaffold(
              body: OwnershipTransferScreen(
                organizationId: 'org',
                service: service,
                onChanged: () {},
              ),
            ),
            locale: locale,
            size: size,
            scale: scale,
          );
          await t.pumpAndSettle();
          await t.ensureVisible(find.byType(DropdownButtonFormField<String>));
          await t.tap(find.byType(DropdownButtonFormField<String>));
          await t.pumpAndSettle();
          await t.tap(find.textContaining('Nguyễn Thị Minh Anh').last);
          await t.pumpAndSettle();
          await t.ensureVisible(find.byType(FilledButton));
          await t.pumpAndSettle();
          expect(find.byType(FilledButton).hitTestable(), findsOneWidget);
          expect(t.takeException(), isNull);
        });
      }
}
