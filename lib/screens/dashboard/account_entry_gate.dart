import 'package:flutter/material.dart';
import '../../models/organization_model.dart';
import '../../services/account_entry_service.dart';
import '../../utils/app_router.dart';
import '../../utils/localizations/app_localizations.dart';

/// Staff never build the owner dashboard. Returning from a workplace provides
/// settings and workplace selection without automatically trapping Back.
class AccountEntryGate extends StatefulWidget {
  final Future<AccountEntry> Function() load;
  final Widget Function(AccountEntry) ownerBuilder;
  final Future<void> Function(Organization) openWorkplace;
  final VoidCallback onSettings;
  final VoidCallback? onOwnerReady;
  final Future<void> Function()? onMerge;
  final Widget Function(AccountEntry, Organization)? workspaceBuilder;

  /// The account check saved last time (2026-10-09, speed). When it opened
  /// one workplace, that workspace is shown at once and cannot be used until
  /// the fresh check arrives; a check that does not open it replaces it.
  final Future<AccountEntry?> Function()? saved;
  const AccountEntryGate({
    super.key,
    required this.load,
    required this.ownerBuilder,
    required this.openWorkplace,
    required this.onSettings,
    this.onOwnerReady,
    this.onMerge,
    this.workspaceBuilder,
    this.saved,
  });
  @override
  State<AccountEntryGate> createState() => _AccountEntryGateState();
}

class _AccountEntryGateState extends State<AccountEntryGate> {
  AccountEntry? _entry;
  // Shown, locked, while the first check runs.
  AccountEntry? _saved;
  bool _loading = true, _error = false, _opening = false, _autoOpened = false;
  bool _mergePrompted = false;
  @override
  void initState() {
    super.initState();
    _showSaved();
    _load();
  }

  Future<void> _showSaved() async {
    final read = widget.saved;
    if (read == null || widget.workspaceBuilder == null) return;
    try {
      final saved = await read();
      if (saved != null &&
          saved.opensOneWorkplace &&
          mounted &&
          _loading &&
          _entry == null &&
          !_error) {
        setState(() => _saved = saved);
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final entry = await widget.load();
      if (!mounted) return;
      setState(() {
        _entry = entry;
        _saved = null;
        _loading = false;
      });
      if (!_mergePrompted && entry.canMerge && widget.onMerge != null) {
        _mergePrompted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await widget.onMerge!();
          if (mounted) await _load();
        });
      }
      if (!_autoOpened && widget.workspaceBuilder == null) {
        _autoOpened = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!entry.staffOnly) {
            widget.onOwnerReady?.call();
            return;
          }
          if (entry.state == 'ready' &&
              entry.workplaces.length == 1 &&
              !entry.waitingIds.contains(entry.workplaces.single.id)) {
            _open(entry.workplaces.single);
          }
        });
      }
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = true;
          _entry = null;
          _saved = null;
        });
    }
  }

  Future<void> _open(Organization org) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.openWorkplace(org);
    } finally {
      if (mounted) {
        setState(() => _opening = false);
        await _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final entry = _entry;
    if (!_loading && !_error && entry != null) {
      if (entry.opensOneWorkplace && widget.workspaceBuilder != null) {
        // Same wrapper as the saved copy below, so the open workspace stays.
        return AbsorbPointer(
          key: const ValueKey('entry-workspace'),
          absorbing: false,
          child: widget.workspaceBuilder!(entry, entry.workplaces.single),
        );
      }
    }
    // The saved check opened this workspace last time: show it at once,
    // locked until the fresh check arrives (2026-10-09, speed).
    final saved = _saved;
    if (saved != null &&
        _entry == null &&
        _loading &&
        widget.workspaceBuilder != null) {
      return AbsorbPointer(
        key: const ValueKey('entry-workspace'),
        absorbing: true,
        child: widget.workspaceBuilder!(saved, saved.workplaces.single),
      );
    }
    if (!_loading && !_error && entry != null) {
      if (!entry.staffOnly && entry.mode != 'conflict')
        return widget.ownerBuilder(entry);
    }
    // First check after opening or reloading: we don't know yet whether this
    // is an owner or staff, so show a neutral screen, not "Workplaces".
    if (_loading && entry == null)
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const LinearProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      t[AppRouter.pendingAddress != null
                          ? 'entry_reopening'
                          : 'entry_opening'],
                      key: const ValueKey('entry-opening'),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    return Scaffold(
      appBar: AppBar(
        title: Text(t['staff_workplaces']),
        actions: [
          IconButton(
            onPressed: _loading || _opening ? null : _load,
            tooltip: t['staff_refresh'],
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: widget.onSettings,
            tooltip: t['settings'],
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_loading) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(t['team_loading']),
                  ] else if (_error) ...[
                    Text(t['staff_entry_error']),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        onPressed: _load,
                        child: Text(t['staff_refresh']),
                      ),
                    ),
                  ] else ...[
                    Text(
                      t[entry!.mode == 'conflict'
                          ? 'org_single_organization_review'
                          : const {
                              'suspended',
                              'closed',
                              'waiting',
                              'deleting',
                              'review',
                            }.contains(entry.state)
                          ? 'org_entry_${entry.state}'
                          : entry.staffConflict ??
                                (entry.workplaces.isEmpty
                                    ? 'staff_no_workplace'
                                    : 'staff_choose_workplace')],
                    ),
                    const SizedBox(height: 16),
                    if (entry.canMerge && widget.onMerge != null) ...[
                      FilledButton(
                        onPressed: _opening
                            ? null
                            : () async {
                                setState(() => _opening = true);
                                try {
                                  await widget.onMerge!();
                                } finally {
                                  if (mounted) {
                                    setState(() => _opening = false);
                                    await _load();
                                  }
                                }
                              },
                        child: Text(t['org_merge_title']),
                      ),
                      const SizedBox(height: 16),
                    ],
                    for (final org
                        in entry.mode == 'conflict' ||
                                !const {
                                  'ready',
                                  'waiting',
                                }.contains(entry.state) ||
                                entry.workplaces.length > 1
                            ? <Organization>[]
                            : entry.workplaces)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          child: InkWell(
                            key: ValueKey('staff-workplace-${org.id}'),
                            onTap: _opening || entry.waitingIds.contains(org.id)
                                ? null
                                : () => _open(org),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    org.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    t[entry.waitingIds.contains(org.id)
                                        ? 'team_waiting_role'
                                        : 'staff_open_workplace'],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
