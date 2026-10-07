import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../staff_editor_test.dart' show openSection, reveal;

/// Building and room pages open from the calendar (2026-10-03): these helpers
/// get a test there from a mounted RoleWorkspace.

/// Shows [buildingName] in the calendar (picks it when there are several).
Future<void> showCalendarBuilding(WidgetTester tester, String buildingId, String buildingName) async {
  await closeAllDialogs(tester);
  if (find.byKey(const ValueKey('calendar-month')).evaluate().isEmpty) {
    await openSection(tester, 'calendar');
  }
  if (find.byKey(ValueKey('calendar-building-pages-$buildingId')).evaluate().isNotEmpty) return;
  final picker = find.byWidgetPredicate((w) => w is DropdownButtonFormField<String>);
  await reveal(tester, picker.first);
  await tester.tap(picker.first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(buildingName).last);
  await tester.pumpAndSettle();
}

/// Opens one of a building's pages: property, contract, layout or fees.
Future<void> openBuildingPage(
  WidgetTester tester,
  String page, {
  String buildingId = 'riverside',
  String? buildingName,
}) async {
  await closeAllDialogs(tester);
  if (buildingName != null) {
    await showCalendarBuilding(tester, buildingId, buildingName);
  } else if (find.byKey(const ValueKey('calendar-month')).evaluate().isEmpty) {
    await openSection(tester, 'calendar');
  }
  final band = find.byKey(ValueKey('calendar-building-pages-$buildingId'));
  await reveal(tester, band);
  await tester.tap(band);
  await tester.pumpAndSettle();
  final chip = find.byKey(ValueKey('building-page-$page'));
  if (chip.evaluate().isNotEmpty) {
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }
}

/// Opens a room's dialog (its card with details, settings, utilities, fees, prices).
Future<void> openRoomDialog(WidgetTester tester, String roomId) async {
  await closeAllDialogs(tester);
  if (find.byKey(const ValueKey('calendar-month')).evaluate().isEmpty) {
    await openSection(tester, 'calendar');
  }
  final label = find.byKey(ValueKey('calendar-room-$roomId'));
  await reveal(tester, label);
  await tester.tap(label);
  await tester.pumpAndSettle();
}

/// Opens "New building" from the calendar toolbar (or the empty calendar).
Future<void> openNewBuilding(WidgetTester tester) async {
  await closeAllDialogs(tester);
  if (find.byKey(const ValueKey('calendar-month')).evaluate().isEmpty) {
    await openSection(tester, 'calendar');
  }
  var button = find.byKey(const ValueKey('calendar-new-building'));
  if (button.evaluate().isEmpty) button = find.byKey(const ValueKey('calendar-first-building'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// Closes the dialog opened over the calendar.
Future<void> closeCalendarDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('calendar-dialog-close')));
  await tester.pumpAndSettle();
}

/// Pops every route above the calendar. Tests that remount the workspace in a
/// loop keep the same MaterialApp navigator, so a dialog left open by the last
/// round would otherwise cover the toolbar in the next one.
Future<void> closeAllDialogs(WidgetTester tester) async {
  final navigators = find.byType(Navigator);
  if (navigators.evaluate().isEmpty) return;
  final navigator = tester.state<NavigatorState>(navigators.first);
  if (!navigator.canPop()) return;
  navigator.popUntil((route) => route.isFirst);
  await tester.pumpAndSettle();
}
