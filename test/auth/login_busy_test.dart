import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/main.dart';
import 'package:phan_mem_quan_ly_can_ho/models/owner_model.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/authentication/login_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/services/auth_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'package:provider/provider.dart';

/// Sign-in calls that only finish when the test says so, so the screen can be
/// inspected while it is busy.
class _SlowAuth implements AuthService {
  final signIn = Completer<User?>();
  final google = Completer<User?>();
  final register = Completer<Owner?>();

  @override
  Future<void> applyRememberChoice(bool remember) async {}
  @override
  Future<User?> signInWithEmailPassword(String email, String password) =>
      signIn.future;
  @override
  Future<User?> signInWithGoogle({String? languageCode}) => google.future;
  @override
  Future<Owner?> registerWithEmailPassword({
    required String email,
    required String password,
    required String name,
    String? inviteCode,
    String? languageCode,
  }) => register.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _SlowAuth auth;

  setUp(() => getIt.reset());
  tearDown(getIt.reset);

  Future<void> pumpLogin(WidgetTester tester) async {
    // Made inside the test, not in setUp: a Completer created outside the
    // test's fake clock delivers its result on the real event loop, which
    // pumpAndSettle never runs, so the screen would wait forever.
    auth = _SlowAuth();
    getIt.registerSingleton<AuthService>(auth);
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('vi')],
        localizationsDelegates: const [
          AppTranslationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SingleChildScrollView(
            child: ChangeNotifierProvider(
              create: (_) => ChoiceState(),
              child: const Content(buttonSize: 16, textSize: 14, titleSize: 24),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  List<TextField> fields(WidgetTester tester) =>
      tester.widgetList<TextField>(find.byType(TextField)).toList();

  Future<void> fill(WidgetTester tester, List<String> values) async {
    for (var i = 0; i < values.length; i++) {
      await tester.enterText(find.byType(TextField).at(i), values[i]);
    }
  }

  ButtonStyleButton googleButton(WidgetTester tester) =>
      tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('login-google')));

  testWidgets('sign in: inputs, Google and the sign-up link are locked while '
      'signing in, and unlocked after it fails', (tester) async {
    await pumpLogin(tester);
    await fill(tester, ['owner@example.com', 'secret123']);
    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await tester.pump();

    expect(fields(tester), hasLength(2));
    expect(fields(tester).every((f) => f.enabled == false), isTrue,
        reason: 'email and password must not be editable while signing in');
    expect(googleButton(tester).onPressed, isNull);

    // Tapping "Sign up" while busy must not switch the form later.
    await tester.tap(find.byType(SwitchAuthLink));
    await tester.pump(const Duration(seconds: 2));
    auth.signIn.complete(null);
    await tester.pumpAndSettle();

    expect(fields(tester), hasLength(2), reason: 'still on the sign-in form');
    expect(fields(tester).every((f) => f.enabled != false), isTrue);
    expect(googleButton(tester).onPressed, isNotNull);
    expect(find.text('owner@example.com'), findsOneWidget);
  });

  testWidgets('Google sign-in locks the inputs and spins only the Google '
      'button', (tester) async {
    await pumpLogin(tester);
    await tester.tap(find.byKey(const ValueKey('login-google')));
    await tester.pump();

    expect(fields(tester).every((f) => f.enabled == false), isTrue);
    expect(googleButton(tester).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('login-google')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    auth.google.complete(null); // window closed
    await tester.pumpAndSettle();
    expect(fields(tester).every((f) => f.enabled != false), isTrue);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('sign up: all four inputs are locked while the account is '
      'created', (tester) async {
    await pumpLogin(tester);
    await tester.tap(find.byType(SwitchAuthLink));
    await tester.pumpAndSettle();
    expect(fields(tester), hasLength(4));

    await fill(tester, ['Tom', 'owner@example.com', 'secret123', 'secret123']);
    await tester.tap(find.byKey(const ValueKey('register-submit')));
    await tester.pump();

    expect(fields(tester).every((f) => f.enabled == false), isTrue,
        reason: 'sign-up fields must not be editable while registering');
    expect(googleButton(tester).onPressed, isNull);

    await tester.pump(const Duration(seconds: 2));
    auth.register.complete(null);
    await tester.pumpAndSettle();
    expect(fields(tester).every((f) => f.enabled != false), isTrue);
  });

  Future<void> submitSignUp(WidgetTester tester) async {
    await pumpLogin(tester);
    await tester.tap(find.byType(SwitchAuthLink));
    await tester.pumpAndSettle();
    await fill(tester, ['Tom', 'owner@example.com', 'secret123', 'secret123']);
    await tester.tap(find.byKey(const ValueKey('register-submit')));
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('sign up offline: a short translated message, not the Firebase '
      'text', (tester) async {
    await submitSignUp(tester);
    auth.register.completeError(FirebaseAuthException(
      code: 'network-request-failed',
      message: 'A network error (such as timeout) has occurred.',
    ));
    await tester.pumpAndSettle();

    expect(
      find.text('No internet connection. Check your connection and try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('network error'), findsNothing);
    expect(find.textContaining('network-request-failed'), findsNothing);
  });

  testWidgets('sign up with an unexpected error never shows the raw error',
      (tester) async {
    await submitSignUp(tester);
    auth.register.completeError(Exception('internal detail 42'));
    await tester.pumpAndSettle();

    expect(
      find.text('Sign-up failed. That email may already be in use.'),
      findsOneWidget,
    );
    expect(find.textContaining('internal detail'), findsNothing);
    expect(find.textContaining('Error:'), findsNothing);
  });
}
