import 'package:web/web.dart' as web;

/// Milliseconds since the page started loading.
int sinceStart() => web.window.performance.now().round();
