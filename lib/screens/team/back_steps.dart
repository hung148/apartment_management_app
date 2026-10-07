import 'package:flutter/material.dart';

/// One-step-back handling inside the organization workspace (U1).
///
/// Sub-screens that are shown by a flag instead of a route (room rates, a
/// booking's details, a tenant's lease…) register their own "go back" with
/// [BackStep]. While any step is registered, the workspace blocks the route
/// pop, and system/browser/app Back runs the newest step instead of leaving
/// the organization.
class BackSteps extends ChangeNotifier {
  final List<_StepEntry> _steps = [];
  // Steps register and unregister one frame late; the workspace may be gone
  // by then (leaving the organization).
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _steps.clear();
    super.dispose();
  }

  bool get isEmpty => _steps.isEmpty;

  /// Runs the newest registered step. Returns false when there is none.
  bool back() {
    if (_steps.isEmpty) return false;
    _steps.last.onBack();
    return true;
  }

  void _add(_StepEntry entry) {
    if (_disposed) return;
    _steps.add(entry);
    notifyListeners();
  }

  void _remove(_StepEntry entry) {
    if (_disposed) return;
    if (_steps.remove(entry)) notifyListeners();
  }

  static BackSteps? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BackStepsScope>()?.steps;
}

class _StepEntry {
  VoidCallback onBack;
  _StepEntry(this.onBack);
}

/// Provides [steps] to the subtree and turns route pops into steps.
class BackStepsScope extends StatelessWidget {
  final BackSteps steps;
  final Widget child;
  const BackStepsScope({super.key, required this.steps, required this.child});

  @override
  Widget build(BuildContext context) => _BackStepsScope(
    steps: steps,
    child: ListenableBuilder(
      listenable: steps,
      builder: (context, child) => PopScope(
        canPop: steps.isEmpty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) steps.back();
        },
        child: child!,
      ),
      child: child,
    ),
  );
}

class _BackStepsScope extends InheritedWidget {
  final BackSteps steps;
  const _BackStepsScope({required this.steps, required super.child});
  @override
  bool updateShouldNotify(_BackStepsScope old) => old.steps != steps;
}

/// Registers [onBack] as the current back step while [enabled]. Without a
/// [BackStepsScope] above it, it does nothing.
class BackStep extends StatefulWidget {
  final VoidCallback onBack;
  final bool enabled;
  final Widget child;
  const BackStep({
    super.key,
    required this.onBack,
    this.enabled = true,
    required this.child,
  });
  @override
  State<BackStep> createState() => _BackStepState();
}

class _BackStepState extends State<BackStep> {
  BackSteps? _steps;
  _StepEntry? _entry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final steps = BackSteps.of(context);
    if (steps != _steps) {
      _unregister();
      _steps = steps;
    }
    _sync();
  }

  @override
  void didUpdateWidget(covariant BackStep old) {
    super.didUpdateWidget(old);
    _entry?.onBack = widget.onBack;
    _sync();
  }

  void _sync() {
    if (widget.enabled && _entry == null && _steps != null) {
      final entry = _StepEntry(widget.onBack);
      _entry = entry;
      // Registering notifies listeners; never during this build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_entry == entry && mounted) _steps?._add(entry);
      });
    } else if (!widget.enabled) {
      _unregister();
    }
  }

  void _unregister() {
    final entry = _entry;
    _entry = null;
    if (entry != null) {
      final steps = _steps;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => steps?._remove(entry),
      );
    }
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
