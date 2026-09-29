import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/property_contract_history.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'property_contract_test.dart' show sample, page;
import 'team_review_test.dart' show mountReview;

import 'room_booking_settings_test.dart' show enter;

Future<void> reveal(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> press(WidgetTester tester, String label) async {
  final finder = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Map<String, dynamic> row(int i) => {
  'id': 'version-$i',
  'actorId': 'manager-account-12345678901234567890123456789',
  'currency': 'USD',
  'createdAt': '2030-01-01T12:00:00.000Z',
  'before': {
    ...sample(),
    'direction': 'rentOut',
    'notes': 'Earlier agreed terms',
  },
  'after': sample(),
};
Widget history(TeamService s, {String building = 'riverside'}) =>
    PropertyContractHistory(
      organizationId: 'preview',
      buildingId: building,
      service: s,
      onBack: () {},
    );
void main() {
  testWidgets(
    'saved history opens from contract and returning preserves unsaved draft',
    (tester) async {
      final store = TeamPreviewStore();
      store.buildings.first['rentalContract'] = sample();
      await mountReview(tester, page(store.service));
      await press(tester, 'Save contract');
      await enter(tester, 'contract-partyName', 'Unsaved draft');
      await press(tester, 'Contract history');
      expect(find.textContaining('preview-owner'), findsOneWidget);
      expect(find.textContaining('Unsaved draft'), findsNothing);
      await press(tester, 'Back to contract');
      expect(find.text('Unsaved draft'), findsOneWidget);
    },
  );
  testWidgets(
    'pagination retries preserve rows, revocation clears sensitive history, refresh recovers',
    (tester) async {
      final store = TeamPreviewStore();
      store.contractHistory['riverside'] = List.generate(23, row);
      String? failure;
      final service = TeamService(
        transport: (name, data) async {
          if (failure != null) {
            throw FirebaseFunctionsException(code: failure, message: 'test');
          }
          return store.call(name, data);
        },
      );
      await mountReview(tester, history(service));
      expect(
        find.byKey(const ValueKey('contract-history-version-0')),
        findsOneWidget,
      );
      failure = 'unavailable';
      await press(tester, 'Load older versions');
      expect(
        find.byKey(const ValueKey('contract-history-version-0')),
        findsOneWidget,
      );
      failure = null;
      await press(tester, 'Retry older versions');
      expect(
        find.byKey(const ValueKey('contract-history-version-22')),
        findsOneWidget,
      );
      expect(find.text('Load older versions'), findsNothing);
      failure = 'permission-denied';
      await press(tester, 'Refresh history');
      expect(find.byType(Card), findsNothing);
      expect(
        find.text('Contract unavailable. Reload to check your access.'),
        findsOneWidget,
      );
      failure = null;
      store.contractHistory.clear();
      await press(tester, 'Refresh history');
      expect(find.text('No saved contract versions yet.'), findsOneWidget);
    },
  );
  testWidgets('switching properties ignores late history responses', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    final service = TeamService(
      transport: (name, data) async => data['buildingId'] == 'riverside'
          ? pending.future
          : {'records': [], 'nextCursor': null},
    );
    await mountReview(tester, history(service), settle: false);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await mountReview(tester, history(service, building: 'other'));
    pending.complete({
      'records': [row(0)],
      'nextCursor': null,
    });
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNothing);
    expect(find.text('No saved contract versions yet.'), findsOneWidget);
  });
  testWidgets(
    'long before and after versions fit languages sizes text scales and themes',
    (tester) async {
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      for (final language in ['en', 'vi']) {
        for (final size in [
          const Size(320, 740),
          const Size(812, 375),
          const Size(1440, 1000),
        ]) {
          for (final scale in [1.0, 1.3, 2.0]) {
            for (final brightness in Brightness.values) {
              final store = TeamPreviewStore();
              store.contractHistory['riverside'] = [row(0)];
              final t = AppTranslations(Locale(language));
              await mountReview(
                tester,
                history(store.service),
                language: language,
                size: size,
                scale: scale,
                brightness: brightness,
              );
              final toggle = find.text(t['contract_history_before']);
              await reveal(tester, toggle);
              await tester.tap(toggle);
              await tester.pumpAndSettle();
              final previous = find.textContaining('Earlier agreed terms');
              await reveal(tester, previous);
              expect(previous.hitTestable(), findsOneWidget);
              expect(tester.takeException(), isNull);
              if (const bool.fromEnvironment('HISTORY_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/contract-history-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
                  ),
                );
              }
            }
          }
        }
      }
    },
  );
}
