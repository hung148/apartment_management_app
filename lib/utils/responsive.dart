import 'dart:async';
import 'package:flutter/material.dart';

class DebouncedMediaQuery extends StatefulWidget {
  final Widget Function(BuildContext context, Size size) builder;
  final Duration delay;

  const DebouncedMediaQuery({
    super.key,
    required this.builder,
    this.delay = const Duration(milliseconds: 150),
  });

  @override
  State<DebouncedMediaQuery> createState() => _DebouncedMediaQueryState();
}

class _DebouncedMediaQueryState extends State<DebouncedMediaQuery> {
  Timer? _timer;
  Size? _stableSize;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newSize = MediaQuery.of(context).size;

    if (_stableSize == null) {
      // First time, set immediately
      _stableSize = newSize;
      return;
    }

    _timer?.cancel();
    _timer = Timer(widget.delay, () {
      if (mounted) {
        setState(() => _stableSize = newSize);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _stableSize ?? MediaQuery.of(context).size);
  }
}