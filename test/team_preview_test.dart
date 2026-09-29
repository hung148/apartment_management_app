import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/team_preview.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';

void main() {
  test(
    'preview acceptance persists locally and retries do not duplicate linkage',
    () async {
      final store = TeamPreviewStore();
      final operation = store.service.prepare(
        'preview',
        TeamAction.acceptInvitation,
        {'invitationId': 'demo-invite'},
      );
      expect(
        (await store.service.invitation('demo-invite'))['canAccept'],
        true,
      );
      await store.service.execute(operation);
      await store.service.execute(operation);
      expect(
        (await store.service.invitation('demo-invite'))['canAccept'],
        false,
      );
      expect(store.staff.last['accountId'], 'preview-linh');
      expect(TeamPreviewStore().staff.last['accountId'], isNull);
    },
  );

  testWidgets(
    'preview shell fits populated screens and controls remain reachable',
    (tester) async {
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.devicePixelRatio = 1;
      for (final size in [
        const Size(320, 740),
        const Size(812, 375),
        const Size(1440, 1000),
      ]) {
        for (final scale in [1.0, 1.3, 2.0]) {
          tester.view.physicalSize = size;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          await tester.pumpWidget(TeamPreviewApp(key: UniqueKey()));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Nguyễn Thị Minh Anh'),
            180,
            scrollable: find.byType(Scrollable).last,
          );
          expect(find.text('Nguyễn Thị Minh Anh'), findsOneWidget);
          await tester.tap(find.byType(ExpansionTile));
          await tester.pumpAndSettle();
          for (final language in ['en', 'vi']) {
            final toggle = find.text(
              language == 'en' ? 'Tiếng Việt' : 'English',
            );
            await tester.ensureVisible(toggle);
            await tester.pumpAndSettle();
            expect(toggle.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            if (const bool.fromEnvironment('PREVIEW_GOLDENS')) {
              await expectLater(
                find.byType(Scaffold),
                matchesGoldenFile(
                  '../.dart_tool/preview-$language-${size.width.toInt()}-$scale.png',
                ),
              );
            }
            await tester.tap(toggle);
            await tester.pumpAndSettle();
          }
          final recipient = find.text('Open recipient');
          await tester.ensureVisible(recipient);
          await tester.tap(recipient);
          await tester.pumpAndSettle();
          expect(find.byType(TextField), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}
