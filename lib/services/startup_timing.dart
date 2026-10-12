import 'package:flutter/foundation.dart';

import 'startup_clock_io.dart'
    if (dart.library.js_interop) 'startup_clock_web.dart'
    as clock;

/// Startup timing (2026-10-11, Tom: measure what happens between opening the
/// app and the calendar). Each step is noted once with the time since the
/// page started loading (web) or since main() (phones); one line is printed
/// to the console when the calendar first shows the server's answer:
/// `[startup] firebase 812ms · appCheck 1030ms · ...`.
class StartupTiming {
  static final _marks = <(String, int)>[];
  static bool _done = false;

  static void mark(String step) {
    if (_done || _marks.any((m) => m.$1 == step)) return;
    _marks.add((step, clock.sinceStart()));
  }

  /// The last step: prints the line once.
  static void finish(String step) {
    if (_done) return;
    mark(step);
    _done = true;
    debugPrint(
      '[startup] ${_marks.map((m) => '${m.$1} ${m.$2}ms').join(' · ')}',
    );
  }
}
