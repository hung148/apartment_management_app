import 'package:flutter/material.dart';
import '../../models/team_access.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'access_editor.dart';

/// Includes accounts without staff profiles so legacy access cannot be hidden.
class AccountAccessList extends StatefulWidget {
  final String organizationId;
  final TeamService service;
  final VoidCallback onBack;
  const AccountAccessList({
    super.key,
    required this.organizationId,
    required this.service,
    required this.onBack,
  });
  @override
  State<AccountAccessList> createState() => _AccountAccessListState();
}

class _AccountAccessListState extends State<AccountAccessList> {
  List<Map<String, dynamic>> _records = [];
  Map<String, dynamic>? _selected;
  TeamAccess? _actor;
  String? _cursor;
  bool _busy = true, _failed = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AccountAccessList old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.service != widget.service) {
      _load();
    }
  }

  void _deny() => setState(() {
    _generation++;
    _records = [];
    _selected = null;
    _actor = null;
    _cursor = null;
    _busy = false;
    _failed = true;
  });
  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    final cursor = more ? _cursor : null;
    setState(() {
      _busy = true;
      _failed = false;
      _selected = null;
      if (!more) {
        _records = [];
        _actor = null;
        _cursor = null;
      }
    });
    try {
      final actor = TeamAccess.fromMap(
        await widget.service.myAccess(widget.organizationId) ?? {},
      );
      if (!actor.allBuildings || !actor.allows(TeamPermission.manageTeam)) {
        throw StateError('Access denied');
      }
      final page = await widget.service.page(
        widget.organizationId,
        TeamView.access,
        cursor: cursor,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _actor = actor;
        _records = [if (more) ..._records, ...page.records];
        _cursor = page.nextCursor;
        _busy = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) _deny();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context), selected = _selected;
    if (selected != null && _actor != null) {
      return AccessEditor(
        key: ValueKey('${widget.organizationId}-${selected['id']}'),
        organizationId: widget.organizationId,
        service: widget.service,
        actor: _actor!,
        profile: {
          ...selected,
          'accountId': selected['ownerId'],
          'accountAccess': selected,
        },
        onCancel: () => _load(),
        onSaved: (_) => _load(),
        onAccessDenied: _deny,
      );
    }
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextButton(onPressed: widget.onBack, child: Text(t['team_back'])),
              Text(
                t['team_accounts'],
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(t['team_accounts_note']),
              if (_busy) const LinearProgressIndicator(),
              if (_failed) Text(t['team_denied']),
              OutlinedButton(
                onPressed: _busy ? null : () => _load(),
                child: Text(t['team_refresh']),
              ),
              if (!_busy && !_failed && _records.isEmpty)
                Text(t['team_accounts_empty']),
              for (final record in _records)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record['displayName'] as String? ??
                              record['ownerId'] as String? ??
                              '',
                        ),
                        Text(record['email'] as String? ?? ''),
                        Text(
                          '${t['team_account_reference']}: ${record['ownerId'] ?? ''}',
                        ),
                        if (TeamAccess.fromMap(record).role == null ||
                            record['accessVersion'] != 2)
                          Text(t['team_assignment_required'])
                        else
                          Text(t['team_role_${record['role']}']),
                        Text(
                          '${t['activity_field_status']}: ${t.translationKeys.contains('team_status_${record['status']}') ? t['team_status_${record['status']}'] : t['team_assignment_required']}',
                        ),
                        if (record['staffId'] == null)
                          Text(t['team_account_unlinked']),
                        if (record['canManageAccess'] == true)
                          OutlinedButton(
                            key: ValueKey('review-${record['id']}'),
                            onPressed: _busy
                                ? null
                                : () => setState(() => _selected = record),
                            child: Text(t['team_manage_access']),
                          ),
                      ],
                    ),
                  ),
                ),
              if (_cursor != null && !_failed)
                OutlinedButton(
                  onPressed: _busy ? null : () => _load(more: true),
                  child: Text(t['team_more']),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
