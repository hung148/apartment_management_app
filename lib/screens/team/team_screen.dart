import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../../models/team_access.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'staff_editor.dart';
import 'access_editor.dart';
import 'team_review_queue.dart';
import 'activity_history.dart';
import 'account_access_list.dart';

/// Server-authorized directory. Employment and login linkage are deliberately
/// displayed separately; neither implies that an account has active access.
class TeamScreen extends StatefulWidget {
  final String organizationId;
  final TeamService service;
  const TeamScreen({
    super.key,
    required this.organizationId,
    required this.service,
  });

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  List<Map<String, dynamic>> _records = [];
  Map<String, dynamic>? _selected;
  String? _cursor, _error;
  bool _loading = true, _admin = false;
  bool _editing = false;
  bool _reviewing = false;
  bool _activity = false;
  bool _accounts = false;
  bool _accessEditing = false;
  TeamAccess? _actor;
  String? _invitationId;
  Map<String, dynamic>? _draft;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TeamScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.organizationId != widget.organizationId ||
        oldWidget.service != widget.service) {
      _invitationId = null;
      _activity = false;
      _accounts = false;
      _load();
    }
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    final organization = widget.organizationId;
    final service = widget.service;
    final cursor = more ? _cursor : null;
    setState(() {
      _loading = true;
      _error = null;
      _selected = null;
      _editing = false;
      _reviewing = false;
      _accessEditing = false;
      _draft = null;
      if (!more) {
        _records = [];
        _cursor = null;
        _admin = false;
      }
    });
    try {
      final record = await service.myAccess(organization);
      if (!mounted || generation != _generation) return;
      final access = TeamAccess.fromMap(record ?? {});
      final admin =
          access.allows(TeamPermission.manageTeam) && access.allBuildings;
      if (!admin && !access.allows(TeamPermission.readOwnActivity)) {
        if (mounted && generation == _generation) {
          setState(() {
            _records = [];
            _cursor = null;
            _loading = false;
            _error = 'team_denied';
          });
        }
        return;
      }
      final page = await service.page(
        organization,
        TeamView.staff,
        cursor: cursor,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _admin = admin;
        _actor = access;
        _records = more ? [..._records, ...page.records] : page.records;
        _cursor = page.nextCursor;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _records = [];
        _cursor = null;
        _loading = false;
        _error =
            error is FirebaseFunctionsException &&
                ['permission-denied', 'unauthenticated'].contains(error.code)
            ? 'team_denied'
            : error is FirebaseFunctionsException &&
                  error.code == 'failed-precondition'
            ? 'team_not_ready'
            : 'team_load_error';
      });
    }
  }

  String _value(Map<String, dynamic> record, String key, AppTranslations t) =>
      record[key] is String && (record[key] as String).trim().isNotEmpty
      ? record[key] as String
      : t['team_unspecified'];

  String _employment(Map<String, dynamic> record, AppTranslations t) =>
      t[switch (record['employmentStatus']) {
        'active' => 'team_employed',
        'inactive' => 'team_inactive',
        _ => 'team_unspecified',
      }];

  bool _linked(Map<String, dynamic> record) =>
      record['accountId'] is String &&
      (record['accountId'] as String).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final selected = _selected;
    if (_accounts) {
      return AccountAccessList(
        organizationId: widget.organizationId,
        service: widget.service,
        onBack: () {
          setState(() => _accounts = false);
          _load();
        },
      );
    }
    if (_reviewing) {
      return TeamReviewQueue(
        key: ValueKey('queue-${widget.organizationId}'),
        organizationId: widget.organizationId,
        service: widget.service,
        onBack: () => _load(),
      );
    }
    if (_accessEditing && selected != null && _actor != null) {
      return AccessEditor(
        key: ValueKey('access-${widget.organizationId}-${selected['id']}'),
        organizationId: widget.organizationId,
        service: widget.service,
        actor: _actor!,
        profile: selected,
        onCancel: () => setState(() => _accessEditing = false),
        onAccessDenied: () => setState(() {
          _accessEditing = false;
          _selected = null;
          _records = [];
          _cursor = null;
          _admin = false;
          _invitationId = null;
          _error = 'team_denied';
        }),
        onSaved: (result) {
          _invitationId = result['invitationId'] as String?;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                t[_invitationId == null
                    ? 'team_access_saved'
                    : 'team_invite_created'],
              ),
            ),
          );
          _load();
        },
      );
    }
    if (_activity) {
      return ActivityHistory(
        organizationId: widget.organizationId,
        service: widget.service,
        onBack: () => setState(() => _activity = false),
      );
    }
    if (_editing) {
      return StaffEditor(
        key: ValueKey('${widget.organizationId}-${_draft?['id'] ?? 'new'}'),
        organizationId: widget.organizationId,
        service: widget.service,
        profile: _draft,
        onCancel: () => setState(() => _editing = false),
        onSaved: () {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(t['team_profile_saved'])));
          _load();
        },
        onAccessDenied: () => setState(() {
          _generation++;
          _editing = false;
          _draft = null;
          _selected = null;
          _records = [];
          _cursor = null;
          _admin = false;
          _error = 'team_denied';
        }),
      );
    }
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            key: ValueKey(
              '${widget.organizationId}-${selected?['id'] ?? 'directory'}',
            ),
            padding: const EdgeInsets.all(16),
            children: [
              if (selected != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _selected = null),
                    icon: const Icon(Icons.arrow_back),
                    label: Text(t['team_back']),
                  ),
                ),
              Text(
                t[selected == null
                    ? (_admin ? 'team_directory' : 'team_profile')
                    : 'team_details'],
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(t['team_distinction']),
              if (_admin && !_loading && _error == null && selected == null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _accounts = true),
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: Text(t['team_accounts']),
                  ),
                ),
              if (_admin && !_loading && _error == null && selected == null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _activity = true),
                    icon: const Icon(Icons.history),
                    label: Text(t['activity_title']),
                  ),
                ),
              if (_admin && !_loading && _error == null && selected == null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _reviewing = true),
                    icon: const Icon(Icons.inbox_outlined),
                    label: Text(t['team_review_queue']),
                  ),
                ),
              if (_admin && _error == null && _invitationId != null) ...[
                const SizedBox(height: 16),
                Text(t['team_invite_reference']),
                SelectableText(_invitationId!),
                Text(t['team_invite_created']),
              ],
              if (_admin &&
                  !_loading &&
                  _error == null &&
                  selected != null &&
                  (selected['canManageAccess'] == true ||
                      (!_linked(selected) &&
                          selected['employmentStatus'] == 'active' &&
                          selected['canEditProfile'] == true)))
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _accessEditing = true),
                      icon: const Icon(Icons.admin_panel_settings_outlined),
                      label: Text(
                        t[_linked(selected)
                            ? 'team_manage_access'
                            : 'team_invite'],
                      ),
                    ),
                  ),
                ),
              if (_admin &&
                  !_loading &&
                  _error == null &&
                  (selected == null || selected['canEditProfile'] == true))
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: () => setState(() {
                        _draft = selected;
                        _editing = true;
                      }),
                      icon: Icon(
                        selected == null
                            ? Icons.person_add_outlined
                            : Icons.edit_outlined,
                      ),
                      label: Text(
                        t[selected == null
                            ? 'team_add_staff'
                            : 'team_edit_staff'],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : () => _load(),
                  icon: const Icon(Icons.refresh),
                  label: Text(t['team_refresh']),
                ),
              ),
              if (_loading) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(semanticsLabel: t['team_loading']),
                const SizedBox(height: 8),
                Text(t['team_loading']),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(t[_error!], semanticsLabel: t[_error!]),
              ] else if (!_loading && _records.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(t[_admin ? 'team_empty' : 'team_no_profile']),
                ),
              if (selected != null) ...[
                const SizedBox(height: 16),
                Text(
                  _value(selected, 'displayName', t),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (final field in ['code', 'email', 'phone'])
                  _detail(t['team_$field'], _value(selected, field, t)),
                _detail(t['team_employment'], _employment(selected, t)),
                _detail(
                  t['team_account'],
                  t[_linked(selected) ? 'team_linked' : 'team_unlinked'],
                ),
                const SizedBox(height: 12),
                Text(t['team_access_note']),
              ] else ...[
                for (final record in _records)
                  Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _loading
                          ? null
                          : () => setState(() => _selected = record),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _value(record, 'displayName', t),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${t['team_code']}: ${_value(record, 'code', t)}',
                            ),
                            Text(
                              '${t['team_employment']}: ${_employment(record, t)}',
                            ),
                            Text(
                              '${t['team_account']}: ${t[_linked(record) ? 'team_linked' : 'team_unlinked']}',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              t['team_view_details'],
                              key: ValueKey('team-details-${record['id']}'),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_cursor != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: OutlinedButton(
                      onPressed: _loading ? null : () => _load(more: true),
                      child: Text(t['team_more']),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        SelectableText(value),
      ],
    ),
  );
}
