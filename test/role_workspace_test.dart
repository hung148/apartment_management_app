import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/models/team_access.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/role_workspace.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'team_review_test.dart' show mountReview;
import 'staff_editor_test.dart' show press, reveal;

void main() {
  testWidgets(
    'receptionist records standalone payment through workspace then sees refreshed balance',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = TeamPreviewStore()..workspaceRole = 'receptionist';
      await mountReview(
        tester,
        RoleWorkspace(organizationId: 'preview', service: store.service),
        size: const Size(1440, 1000),
      );
      await press(tester, 'Collect / refund payments');
      await press(tester, 'Record a payment or refund');
      expect(find.text('Refund payment'), findsNothing);
      await reveal(tester, find.byKey(const ValueKey('payment-amount')));
      await tester.enterText(
        find.byKey(const ValueKey('payment-amount')),
        '250000',
      );
      await press(tester, 'Confirm recording');
      expect(store.payment['paidAmount'], 750000);
      await press(tester, 'Back to payments');
      expect(find.textContaining('750,000'), findsOneWidget);
      expect(store.activity.last['action'], 'paymentCollect');
    },
  );
  testWidgets(
    'staff can open their own activity and profile without team administration',
    (tester) async {
      final store = TeamPreviewStore()..workspaceRole = 'receptionist';
      store.addOperationalSamples();
      await mountReview(
        tester,
        RoleWorkspace(organizationId: 'preview', service: store.service),
        size: const Size(1440, 1000),
      );
      await press(tester, 'Staff activity history');
      expect(find.textContaining('preview-receptionist'), findsWidgets);
      expect(find.textContaining('preview-manager'), findsNothing);
      await press(tester, AppTranslations(const Locale('en'))['team_back']);
      await press(tester, AppTranslations(const Locale('en'))['team_profile']);
      expect(find.text('Account access review'), findsNothing);
      expect(find.text('an@example.com'), findsNothing);
    },
  );
  testWidgets('all roles see only their permitted workspace sections', (
    tester,
  ) async {
    for (final role in TeamRole.values) {
      final store = TeamPreviewStore()..workspaceRole = role.name;
      final access = TeamAccess.fromMap(TeamPreviewStore.grant(role.name));
      await mountReview(
        tester,
        RoleWorkspace(
          key: UniqueKey(),
          organizationId: 'preview',
          service: store.service,
        ),
        size: const Size(1440, 1000),
      );
      expect(
        find.text('Bookings'),
        access.allows(TeamPermission.readBookings)
            ? findsOneWidget
            : findsNothing,
      );
      expect(
        find.text('Financial records'),
        access.allows(TeamPermission.readFinancialReports)
            ? findsOneWidget
            : findsNothing,
      );
      expect(
        find.text('Team & access'),
        access.allows(TeamPermission.manageTeam)
            ? findsOneWidget
            : findsNothing,
      );
    }
  });
  testWidgets(
    'property change clears records; read denial clears entire workspace',
    (tester) async {
      var denied = false;
      final store = TeamPreviewStore();
      final service = TeamService(
        transport: (name, data) async {
          if (denied) throw StateError('revoked');
          return store.call(name, data);
        },
      );
      await mountReview(
        tester,
        RoleWorkspace(organizationId: 'preview', service: service),
        size: const Size(1440, 1000),
      );
      await press(tester, 'Bookings');
      expect(find.textContaining('Khách lưu trú'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Garden Homestay').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Khách lưu trú'), findsNothing);
      denied = true;
      await press(tester, 'Bookings');
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.textContaining('Khách lưu trú'), findsNothing);
    },
  );
  testWidgets('populated workspace fits locales screens text scales and themes', (
    tester,
  ) async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final language in ['en', 'vi']) {
      final t = AppTranslations(Locale(language));
      for (final size in [
        const Size(320, 740),
        const Size(812, 375),
        const Size(1440, 1000),
      ]) {
        for (final scale in [1.0, 1.3, 2.0]) {
          for (final brightness in Brightness.values) {
            final store = TeamPreviewStore()
              ..workspaceRole = 'manager'
              ..assignedOnly = true;
            await mountReview(
              tester,
              RoleWorkspace(
                key: UniqueKey(),
                organizationId: 'preview',
                service: store.service,
              ),
              language: language,
              size: size,
              scale: scale,
              brightness: brightness,
            );
            for (final view in ['bookings', 'financial']) {
              await press(tester, t['workspace_$view']);
              await reveal(tester, find.textContaining(t['workspace_status']));
              expect(tester.takeException(), isNull);
              if (const bool.fromEnvironment('WORKSPACE_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/workspace-$language-${size.width.toInt()}-$scale-${brightness.name}-$view.png',
                  ),
                );
              }
            }
          }
        }
      }
    }
  });
}
