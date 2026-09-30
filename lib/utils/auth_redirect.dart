import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_router.dart';

/// Keeps every screen in step with the signed-in account.
///
/// On the web all tabs of the app share one sign-in. Signing out (or into a
/// different account) in one tab changes it for the others too, and a
/// confirmed email change or a deleted account also ends the session. When
/// that happens this sends the app back to a clean start instead of leaving
/// a screen that shows the old account's data:
/// - signed out            -> login screen, nothing to go back to;
/// - switched to another account -> splash, which opens that account's dashboard.
/// A first sign-in is left to the login screen, which moves on by itself.
void watchAuthChanges(GlobalKey<NavigatorState> navigatorKey) {
  String? lastUid = FirebaseAuth.instance.currentUser?.uid;
  FirebaseAuth.instance.authStateChanges().listen((user) {
    final uid = user?.uid;
    if (uid == lastUid) return;
    final previous = lastUid;
    lastUid = uid;
    if (previous == null) return;
    // Wait a frame: logout and account deletion navigate themselves right
    // after signing out, and must not be navigated twice.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = navigatorKey.currentState;
      if (nav == null || FirebaseAuth.instance.currentUser?.uid != uid) return;
      String? top;
      nav.popUntil((route) {
        top = route.settings.name;
        return true; // only reads the top route
      });
      if (uid == null) {
        if (top == AppRouter.loginScreen || top == AppRouter.splashScreen) return;
        nav.pushNamedAndRemoveUntil(AppRouter.loginScreen, (_) => false);
      } else {
        nav.pushNamedAndRemoveUntil(AppRouter.splashScreen, (_) => false);
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  });
}
