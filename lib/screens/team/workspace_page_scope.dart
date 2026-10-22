import 'package:flutter/material.dart';
import '../../utils/localizations/app_localizations.dart';

/// Organization pages share the shell's navigation and available width.
/// Standalone screens retain their own readable width and toolbar.
class WorkspacePageScope extends InheritedWidget {
  const WorkspacePageScope({super.key, required super.child});

  static bool contains(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspacePageScope>() != null;

  static BoxConstraints constraints(
    BuildContext context,
    double standaloneWidth,
  ) => BoxConstraints(
    maxWidth: contains(context) ? double.infinity : standaloneWidth,
  );

  @override
  bool updateShouldNotify(WorkspacePageScope oldWidget) => false;
}

/// Pages opened in a dialog over the calendar (2026-10-04). The dialog's title
/// bar names the page and its X closes it, so a page leaves out its own big
/// heading, a "back to …" link that would only close the dialog, and its
/// reload button (shown again when loading failed).
class DialogPageScope extends InheritedWidget {
  const DialogPageScope({super.key, required super.child});

  static bool contains(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DialogPageScope>() != null;

  /// "Back" for a page one step inside a dialog (to the room card, say).
  static String back(BuildContext context) =>
      AppTranslations.of(context).locale.languageCode == 'vi'
      ? 'Quay lại'
      : 'Back';

  @override
  bool updateShouldNotify(DialogPageScope oldWidget) => false;
}

/// A dialog whose title names a room (the calendar's "Phòng QA102 · Đặt
/// phòng ngắn ngày", 2026-10-22): a form that lets the user pick another
/// room reports the new room number, and the dialog renames itself.
class RoomTitleScope extends InheritedWidget {
  final ValueChanged<String> onRoom;
  const RoomTitleScope({super.key, required this.onRoom, required super.child});

  /// Tells the dialog (if any) that the form now shows room [number].
  static void report(BuildContext context, String number) => context
      .getInheritedWidgetOfExactType<RoomTitleScope>()
      ?.onRoom(number);

  @override
  bool updateShouldNotify(RoomTitleScope oldWidget) => false;
}

/// A page shown under a chip in a dialog (the calendar's room dialog,
/// 2026-10-05): the chips switch pages, so the page has no "back" link.
class PageTabScope extends InheritedWidget {
  const PageTabScope({super.key, required super.child});

  static bool contains(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageTabScope>() != null;

  @override
  bool updateShouldNotify(PageTabScope oldWidget) => false;
}

/// A page placed inside another page's scroll (the room dialog's "Thông tin":
/// room details, then booking settings, 2026-10-05): its list does not
/// scroll on its own.
class StackedPageScope extends InheritedWidget {
  const StackedPageScope({super.key, required super.child});

  static bool contains(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StackedPageScope>() != null;

  @override
  bool updateShouldNotify(StackedPageScope oldWidget) => false;
}
