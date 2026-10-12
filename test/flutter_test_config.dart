import 'dart:async';
import 'package:phan_mem_quan_ly_can_ho/screens/calendar/room_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs before every test file. The organization workspace now opens on the
/// Bookings section (U1), whose screen reads saved booking drafts from
/// SharedPreferences; without a mock that call never answers in tests and the
/// page keeps loading. Tests that need saved values still set their own.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SharedPreferences.setMockInitialValues({});
  // The calendar's old tools row (hidden in the app since the client's
  // design, 2026-10-11) stays on in tests: they open every form from it.
  RoomCalendar.debugShowTools = true;
  await testMain();
}
