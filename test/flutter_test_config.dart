import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs before every test file. The organization workspace now opens on the
/// Bookings section (U1), whose screen reads saved booking drafts from
/// SharedPreferences; without a mock that call never answers in tests and the
/// page keeps loading. Tests that need saved values still set their own.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SharedPreferences.setMockInitialValues({});
  await testMain();
}
