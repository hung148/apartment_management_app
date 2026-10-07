import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/property_contract_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/role_workspace.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'support/calendar_nav.dart';
import 'team_review_test.dart' show mountReview;
import 'room_rates_test.dart' show press, reveal;
import 'room_booking_settings_test.dart' show enter;
import 'access_editor_test.dart' show choose;

Map<String, dynamic> sample() => {
  'direction': 'rentIn',
  'status': 'active',
  'partyName': 'Nguyễn Thị Minh Anh — chủ nhà Riverside phía Đông',
  'partyPhone': '0901234567',
  'amountMinor': 12345,
  'dueDay': 31,
  'startDate': '2030-01-01',
  'endDate': null,
  'notes':
      'Thanh toán theo hợp đồng đã ký. Liên hệ trước khi thay đổi lịch thanh toán.',
};
Widget page(TeamService s, {String building = 'riverside'}) =>
    PropertyContractScreen(
      organizationId: 'preview',
      buildingId: building,
      service: s,
      onBack: () {},
    );
void main() {
  test('contract date parsing rejects overflow and respects leap years', () {
    expect(contractDate('2032-02-29'), isTrue);
    for (final d in [
      '2030-02-29',
      '2030-01-32',
      '1999-01-01',
      '2200-01-01',
      '2030-1-1',
    ]) {
      expect(contractDate(d), isFalse);
    }
  });
  testWidgets(
    'manager opens contract from workspace, selects direction, saves USD then changes to ended rent out',
    (tester) async {
      final store = TeamPreviewStore()..workspaceRole = 'manager';
      store.buildings.first['currency'] = 'USD';
      store.buildings.first['renterName'] = 'Preserved legacy party';
      await mountReview(
        tester,
        RoleWorkspace(organizationId: 'preview', service: store.service),
      );
      await openBuildingPage(tester, 'contract');
      await press(tester, 'Save contract');
      await reveal(tester, find.text('Choose rent in or rent out.'));
      expect(find.text('Choose rent in or rent out.'), findsOneWidget);
      await choose(tester, 'contract-direction-null', 'Rent in');
      await enter(tester, 'contract-partyName', 'Landlord');
      await enter(tester, 'contract-amount', '123.45');
      await enter(tester, 'contract-dueDay', '31');
      await enter(tester, 'contract-startDate', '2030-01-01');
      await press(tester, 'Save contract');
      expect(store.buildings.first['rentalContract']['amountMinor'], 12345);
      expect(store.buildings.first['renterName'], 'Preserved legacy party');
      await press(tester, 'Reload contract');
      expect(find.text('Landlord'), findsOneWidget);
      await choose(tester, 'contract-direction-rentIn', 'Rent out');
      await choose(tester, 'contract-status-active', 'Ended');
      await press(tester, 'Save contract');
      await reveal(
        tester,
        find.text('Enter the end date before marking the contract ended.'),
      );
      expect(
        find.text('Enter the end date before marking the contract ended.'),
        findsOneWidget,
      );
      await enter(tester, 'contract-endDate', '2030-12-31');
      await press(tester, 'Save contract');
      expect(store.buildings.first['rentalContract']['direction'], 'rentOut');
      expect(store.buildings.first['rentalContract']['status'], 'ended');
      expect(
        find.byKey(const ValueKey('building-page-contract')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      store.workspaceRole = 'receptionist';
      await mountReview(
        tester,
        RoleWorkspace(organizationId: 'preview', service: store.service),
      );
      expect(find.text('Whole-building contract'), findsNothing);
    },
  );
  testWidgets(
    'invalid values send nothing; uncertain save freezes exact retry; stale and revoked access clear authority',
    (tester) async {
      final store = TeamPreviewStore();
      store.buildings.first['rentalContract'] = sample();
      final calls = <Map<String, dynamic>>[];
      String? error;
      final service = TeamService(
        transport: (name, data) async {
          if (error != null) {
            throw FirebaseFunctionsException(code: error, message: 'test');
          }
          if (data['action'] == 'update') {
            calls.add(data);
            final result = await store.call(name, data);
            if (calls.length == 1) throw StateError('lost reply');
            return result;
          }
          return store.call(name, data);
        },
      );
      await mountReview(tester, page(service));
      for (final row in [
        ['amount', '1.25'],
        ['dueDay', '32'],
        ['startDate', '2030-02-30'],
      ]) {
        await enter(tester, 'contract-${row[0]}', row[1]);
      }
      await press(tester, 'Save contract');
      expect(calls, isEmpty);
      await enter(tester, 'contract-amount', '500');
      await enter(tester, 'contract-dueDay', '1');
      await enter(tester, 'contract-startDate', '2030-01-01');
      await press(tester, 'Save contract');
      expect(calls, hasLength(1));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('contract-notes')))
            .enabled,
        isFalse,
      );
      await press(tester, 'Retry the same contract change');
      expect(calls, hasLength(2));
      expect(calls.first, calls.last);
      error = 'aborted';
      await press(tester, 'Save contract');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save contract'),
            )
            .onPressed,
        isNull,
      );
      error = null;
      await press(tester, 'Reload contract');
      error = 'permission-denied';
      await press(tester, 'Save contract');
      expect(find.byKey(const ValueKey('contract-notes')), findsNothing);
    },
  );
  testWidgets(
    'loading, failed reads and property switch ignore late responses',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final store = TeamPreviewStore();
      final service = TeamService(
        transport: (name, data) async {
          if (data['buildingId'] == 'riverside') return pending.future;
          throw StateError('offline');
        },
      );
      await mountReview(tester, page(service), settle: false);
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await mountReview(tester, page(service, building: 'other'));
      pending.complete(
        await store.call('propertyContract', {
          'action': 'read',
          'organizationId': 'preview',
          'buildingId': 'riverside',
        }),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Contract unavailable. Reload to check your access.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('contract-partyName')), findsNothing);
    },
  );
  testWidgets(
    'populated and validation states fit en vi phone landscape desktop text scales and themes',
    (tester) async {
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      for (final lang in ['en', 'vi']) {
        for (final size in [
          const Size(320, 740),
          const Size(812, 375),
          const Size(1440, 1000),
        ]) {
          for (final scale in [1.0, 1.3, 2.0]) {
            for (final brightness in Brightness.values) {
              final store = TeamPreviewStore();
              store.buildings.first.addAll({
                'currency': 'USD',
                'rentalContract': sample(),
                'renterName':
                    'Thông tin người thuê cũ cần đối chiếu — Riverside',
              });
              final t = AppTranslations(Locale(lang));
              await mountReview(
                tester,
                page(store.service),
                language: lang,
                size: size,
                scale: scale,
                brightness: brightness,
              );
              await reveal(
                tester,
                find.byKey(const ValueKey('contract-partyName')),
              );
              final labels = find.descendant(
                of: find.byKey(const ValueKey('contract-field-amount')),
                matching: find.byType(RichText),
              );
              for (final rich in labels.evaluate()) {
                final paragraph = rich.renderObject;
                if (paragraph is RenderParagraph) {
                  expect(
                    paragraph.didExceedMaxLines,
                    isFalse,
                    reason:
                        'Currency and field labels must remain readable at $lang $size $scale',
                  );
                }
              }
              expect(tester.takeException(), isNull);
              if (const bool.fromEnvironment('CONTRACT_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/contract-party-$lang-${size.width.toInt()}-$scale-${brightness.name}.png',
                  ),
                );
              }
              await enter(tester, 'contract-endDate', '2029-01-01');
              await press(tester, t['contract_save']);
              await reveal(tester, find.text(t['contract_date_invalid']));
              expect(
                find.text(t['contract_date_invalid']).hitTestable(),
                findsOneWidget,
              );
              if (const bool.fromEnvironment('CONTRACT_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/contract-error-$lang-${size.width.toInt()}-$scale-${brightness.name}.png',
                  ),
                );
              }
              await enter(tester, 'contract-endDate', '2030-12-31');
              await press(tester, t['contract_save']);
              expect(
                store.buildings.first['rentalContract']['endDate'],
                '2030-12-31',
              );
              expect(tester.takeException(), isNull);
            }
          }
        }
      }
    },
  );
}
