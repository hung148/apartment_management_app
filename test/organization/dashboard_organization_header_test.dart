import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/dashboard/dashboard_organization_header.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/invitation_acceptance.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_theme.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';

void main() {
  testWidgets('localized icon actions remain reachable across sizes, text scales and themes', (tester) async {
    await (FontLoader('Roboto')..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final service = TeamService(transport: (name, data) async => {});
    for (final language in ['en', 'vi']) {
      final t = AppTranslations(Locale(language));
      for (final size in [const Size(360, 800), const Size(800, 360), const Size(1200, 800)]) {
        for (final scale in [1.0, 1.3, 2.0]) {
          for (final brightness in Brightness.values) {
            for (final canCreate in [true, false]) {
              await tester.binding.setSurfaceSize(size);
              var joins = 0, creates = 0, agreements = 0;
              final boundary = GlobalKey();
              await tester.pumpWidget(MaterialApp(
                locale: Locale(language), supportedLocales: const [Locale('en'), Locale('vi')],
                localizationsDelegates: const [AppTranslationsDelegate(), GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
                theme: brightness == Brightness.light ? buildAppTheme() : ThemeData(fontFamily: 'Roboto', brightness: brightness, colorSchemeSeed: AppThemeColors.teal),
                home: MediaQuery(data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
                  child: Scaffold(body: RepaintBoundary(key: boundary, child: ColoredBox(color: brightness == Brightness.light ? const Color(0xFFF6F7F4) : const Color(0xFF121212), child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16), child: Column(children: [
                      DashboardOrganizationHeader(
                        invitation: InvitationEntryButton(iconOnly: true, service: service, onReturn: () {}),
                        canCreate: canCreate, onJoin: () { joins++; }, onCreate: () { creates++; }, onAgreements: () { agreements++; }),
                      for (final name in ['Staging Test Source — Riverside East', 'Staging Test Target — Nguyễn Văn Thoại'])
                        Card(child: ListTile(title: Text(name), subtitle: Text(t['team_role_owner']), trailing: const Icon(Icons.more_horiz))),
                    ])))))),
              ));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull, reason: '$language $size $scale $brightness $canCreate');
              expect(find.text(t['your_organizations']), findsOneWidget);
              for (final key in ['join', 'team_accept_invitation', 'agreements_title']) {
                expect(find.byTooltip(t[key]).hitTestable(), findsOneWidget);
                expect(find.text(t[key]), findsNothing);
                expect(tester.getSize(find.byTooltip(t[key])).width, greaterThanOrEqualTo(40));
              }
              expect(find.byTooltip(t['create']), canCreate ? findsOneWidget : findsNothing);
              final ordered = ['agreements_title', 'team_accept_invitation', 'join', if (canCreate) 'create']
                  .map((key) => tester.getRect(find.byTooltip(t[key]))).toList();
              for (var i = 0; i < ordered.length; i++) {
                expect(ordered[i].width, 40);
                expect(ordered[i].center.dy, ordered.first.center.dy);
                if (i > 0) expect(ordered[i].left, greaterThan(ordered[i - 1].left));
              }
              final titleRect = tester.getRect(find.text(t['your_organizations']));
              expect(ordered.first.left, greaterThanOrEqualTo(titleRect.right));
              expect(ordered.first.center.dy, titleRect.center.dy);
              final before = tester.getRect(find.byTooltip(t['join']));
              await tester.tap(find.byTooltip(t['join']));
              await tester.tap(find.byTooltip(t['agreements_title']));
              if (canCreate) await tester.tap(find.byTooltip(t['create']));
              await tester.pumpAndSettle();
              expect([joins, creates, agreements], [1, canCreate ? 1 : 0, 1]);
              expect(tester.getRect(find.byTooltip(t['join'])), before);
              await tester.longPress(find.byTooltip(t['join']));
              await tester.pumpAndSettle();
              expect(find.text(t['join']), findsOneWidget);
              await tester.pump(const Duration(seconds: 3));
              if (canCreate && brightness == Brightness.light && ((language == 'vi' && size.width == 360 && scale == 2) || (language == 'en' && size.width == 1200 && scale == 1))) {
                await tester.runAsync(() async {
                  final image = await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
                  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
                  final file = File('.dart_tool/dashboard-ui/$language.png');
                  await file.parent.create(recursive: true);
                  await file.writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }
              await tester.pumpWidget(const SizedBox());
            }
          }
        }
      }
    }
    await tester.binding.setSurfaceSize(null);
  });
}
