import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/main.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/ai_chat/ai_subscription_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/services/ai_agent_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_theme.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/chat/chat_manager.dart';

class _AI extends AIAgentService {
  @override
  Future<Map<String, dynamic>> usage() async => {
    'remainingMessages': 5, 'remainingImports': 1,
  };
}

// Reproduce the app observer raising chat when a dialog opens or closes.
class _RaiseChatObserver extends NavigatorObserver {
  @override
  void didPush(Route route, Route? previousRoute) {
    if (route is PopupRoute) ChatOverlayManager.install();
  }
  @override
  void didPop(Route route, Route? previousRoute) {
    ChatOverlayManager.install();
  }
}

void main() {
  for (final width in [390.0, 1200.0]) {
    testWidgets('AI Pro is reachable above chat at width $width', (tester) async {
      await getIt.reset();
      getIt.registerSingleton<AIAgentService>(_AI());
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() async {
        ChatOverlayManager.dispose();
        await getIt.reset();
      });
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [_RaiseChatObserver()],
        theme: buildAppTheme(),
        locale: const Locale('en', 'US'),
        supportedLocales: const [Locale('en', 'US'), Locale('vi', 'VN')],
        localizationsDelegates: const [
          AppTranslationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: Text('Organization')),
      ));
      await tester.pumpAndSettle();
      expect(navigatorKey.currentState?.overlay, isNotNull);
      ChatOverlayManager.install();
      await tester.pumpAndSettle();
      final fab = find.byKey(const ValueKey('ai-chat-launcher'));
      await tester.tap(fab);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).hitTestable(), 'Keep this draft');
      await tester.tap(find.widgetWithText(TextButton, 'AI Pro').hitTestable());
      await tester.pumpAndSettle();
      expect(find.byType(AISubscriptionDialog), findsOneWidget);
      expect(fab, findsNothing);
      final close = find.descendant(
        of: find.byType(AISubscriptionDialog), matching: find.byTooltip('Close'),
      );
      expect(close.hitTestable(), findsOneWidget);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(AISubscriptionDialog), findsNothing);
      expect(fab.hitTestable(), findsOneWidget);
      await tester.tap(fab);
      await tester.pumpAndSettle();
      expect(find.text('Keep this draft').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      ChatOverlayManager.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
