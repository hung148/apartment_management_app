import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/organizations/organization_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/role_workspace.dart';
import 'team_review_test.dart' show mountReview;
import 'staff_editor_test.dart' show press, openSection;

void main() {
  testWidgets(
    'v2 organization starts workspace without resolving legacy services',
    (tester) async {
      // No getIt registrations: building/payment legacy services must never start.
      final store = TeamPreviewStore();
      await mountReview(
        tester,
        OrganizationScreen(
          organization: Organization(
            id: 'preview',
            name: 'Riverside',
            createdBy: 'owner',
            createdAt: DateTime.utc(2026),
            inviteCode: '',
            accessVersion: 2,
          ),
          teamService: store.service,
        ),
        size: const Size(1440, 1000),
      );
      expect(find.byType(RoleWorkspace), findsOneWidget);
      await openSection(tester, 'staff');
      await press(tester, 'Account access review');
      expect(find.text('an@example.com'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
