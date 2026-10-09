import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/org_shell.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/role_workspace.dart';
import 'package:phan_mem_quan_ly_can_ho/services/exchange_rate_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/organization_money.dart';
import 'package:phan_mem_quan_ly_can_ho/services/organization_settings_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_money.dart';
import 'team_review_test.dart' show mountReview;

void main() {
  testWidgets('currency refresh failure is visible and retry recovers', (tester) async {
    final money = OrganizationMoney.shared;
    money.clear();
    addTearDown(money.clear);
    var reads = 0;
    final waiting = Completer<Map<String, dynamic>>();
    final service = TeamService(transport: (_, data) async {
      if (data['action'] == 'readCurrency') {
        reads++;
        if (reads == 1) throw StateError('offline');
        return waiting.future;
      }
      throw StateError('unavailable');
    });
    await mountReview(tester, OrgShell(organizationId: 'o', name: 'Example', service: service));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not refresh currency'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pump();
    expect(reads, 2);
    expect(find.textContaining('Could not refresh currency'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    waiting.completeError(StateError('offline'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('reused shell switches currency and ignores old title response', (tester) async {
    final money = OrganizationMoney.shared;
    money.clear();
    addTearDown(money.clear);
    final rates = ExchangeRateSnapshot(perUsd: {'USD': 1, 'VND': 25000}, dates: {});
    money.configure('first', 'USD', rates);
    money.configure('second', 'VND', rates);
    final reads = <String>[];
    final pending = Completer<Map<String, dynamic>>();
    final service = TeamService(transport: (call, data) async {
      if (data['action'] == 'readCurrency') {
        reads.add(data['organizationId'] as String);
        return pending.future;
      }
      throw StateError('unavailable');
    });
    final oldTitle = Completer<Map<String, dynamic>>();
    final settings = OrganizationSettingsService(transport: (_, __) => oldTitle.future);
    Widget shell(String id, String? name) => OrgShell(
      key: const ValueKey('same-shell'), organizationId: id, name: name,
      service: service, settings: settings,
    );
    await mountReview(tester, shell('first', null));
    expect(AppMoney.displayConversion?.currency, 'USD');
    await mountReview(tester, shell('second', 'Second organization'));
    expect(AppMoney.displayConversion?.currency, 'VND');
    expect(reads, ['first', 'second']);
    oldTitle.complete({'name': 'Old organization', 'role': 'owner'});
    await tester.pumpAndSettle();
    expect(tester.widget<RoleWorkspace>(find.byType(RoleWorkspace)).title, 'Second organization');
    await tester.pumpWidget(const SizedBox());
    pending.completeError(StateError('offline'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
