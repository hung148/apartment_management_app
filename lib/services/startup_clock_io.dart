final _watch = Stopwatch()..start();

/// Milliseconds since the app started (first use of this clock, in main).
int sinceStart() => _watch.elapsedMilliseconds;
