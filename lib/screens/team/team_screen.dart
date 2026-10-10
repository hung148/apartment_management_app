import 'workspace_page_scope.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../../models/team_access.dart';
import '../../services/read_cache.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'staff_editor.dart';
import 'access_editor.dart';
import 'team_review_queue.dart';
import 'activity_history.dart';
import 'account_access_list.dart';
import 'roles_screen.dart';
import 'back_steps.dart';
import 'ws_ui.dart';

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
  bool _roles = false;
  // R2: "Add staff by Gmail" (profile + pre-approval in one form).
  bool _addingByGmail = false;
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
      _roles = false;
      _addingByGmail = false;
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
      // The server authorizes the staff page and returns the caller's current
      // access in the same transaction. Older deployments use the fallback.
      // Speed (2026-10-09): the first page shows the copy saved on this device
      // at once, still "loading" (rows and manager buttons locked) until the
      // server's fresh page has checked access and replaced it.
      final pages = more
          ? Stream.fromFuture(
              service
                  .page(organization, TeamView.staff, cursor: cursor)
                  .then((p) => Saved(p, saved: false, at: DateTime.now())),
            )
          : service.staffPageLive(organization);
      final before = more ? _records : const <Map<String, dynamic>>[];
      await for (final answer in pages) {
        if (!mounted || generation != _generation) return;
        final page = answer.data;
        // A saved copy without the access record is not shown.
        if (answer.saved && page.actor == null) continue;
        final record = page.actor ?? await service.myAccess(organization);
        if (!mounted || generation != _generation) return;
        final access = TeamAccess.fromMap(record ?? {});
        final admin =
            access.allows(TeamPermission.manageTeam) && access.allBuildings;
        if (!admin && !access.allows(TeamPermission.readOwnActivity)) {
          if (answer.saved) continue; // the fresh answer decides
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
        setState(() {
          _admin = admin;
          _actor = access;
          _records = [...before, ...page.records];
          _cursor = page.nextCursor;
          _loading = answer.saved;
        });
      }
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

  /// Team managers pick roles; role managers also create and edit them.
  bool get _canOpenRoles =>
      _admin ||
      (_actor != null &&
          _actor!.allBuildings &&
          _actor!.allows(TeamPermission.manageRoles));

  bool _linked(Map<String, dynamic> record) =>
      record['accountId'] is String &&
      (record['accountId'] as String).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final selected = _selected;
    if (_roles && _actor != null) {
      return BackStep(
        onBack: () {
          setState(() => _roles = false);
          _load();
        },
        child: RolesScreen(
          key: ValueKey('roles-${widget.organizationId}'),
          organizationId: widget.organizationId,
          service: widget.service,
          actor: _actor!,
          onBack: () {
            setState(() => _roles = false);
            _load();
          },
          onAccessDenied: () => setState(() {
            _roles = false;
            _records = [];
            _cursor = null;
            _admin = false;
            _error = 'team_denied';
          }),
        ),
      );
    }
    if (_accounts) {
      return BackStep(
        onBack: () {
          setState(() => _accounts = false);
          _load();
        },
        child: AccountAccessList(
          organizationId: widget.organizationId,
          service: widget.service,
          onBack: () {
            setState(() => _accounts = false);
            _load();
          },
        ),
      );
    }
    if (_reviewing) {
      return BackStep(
        onBack: () => _load(),
        child: TeamReviewQueue(
          key: ValueKey('queue-${widget.organizationId}'),
          organizationId: widget.organizationId,
          service: widget.service,
          onBack: () => _load(),
        ),
      );
    }
    if (_addingByGmail && _actor != null) {
      return AccessEditor(
        key: ValueKey('add-by-gmail-${widget.organizationId}'),
        organizationId: widget.organizationId,
        service: widget.service,
        actor: _actor!,
        profile: const {},
        onCancel: () => setState(() => _addingByGmail = false),
        onAccessDenied: () => setState(() {
          _addingByGmail = false;
          _records = [];
          _cursor = null;
          _admin = false;
          _error = 'team_denied';
        }),
        onSaved: (result) {
          setState(() => _addingByGmail = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(t['team_added_by_gmail'])));
          _load();
        },
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
      return BackStep(
        onBack: () => setState(() => _activity = false),
        child: ActivityHistory(
          organizationId: widget.organizationId,
          service: widget.service,
          onBack: () => setState(() => _activity = false),
        ),
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
          constraints: WorkspacePageScope.constraints(context, 960),
          child: ListView(
            key: ValueKey(
              '${widget.organizationId}-${selected?['id'] ?? 'directory'}',
            ),
            padding: const EdgeInsets.all(16),
            children: [
              Builder(
                builder: (context) {
                  final ready = _admin && !_loading && _error == null;
                  return WsHeader(
                    back: selected == null
                        ? null
                        : WsBack(
                            label: t['team_back'],
                            onPressed: () => setState(() => _selected = null),
                          ),
                    title:
                        t[selected == null
                            ? (_admin ? 'team_directory' : 'team_profile')
                            : 'team_details'],
                    help: t['team_distinction'],
                    actions: [
                      if (ready && selected == null)
                        FilledButton.icon(
                          key: const ValueKey('team-add-by-gmail'),
                          onPressed: () =>
                              setState(() => _addingByGmail = true),
                          icon: const Icon(
                            Icons.person_add_alt_1_outlined,
                            size: 18,
                          ),
                          label: Text(t['team_add_by_gmail']),
                        ),
                      if (ready &&
                          (selected == null ||
                              selected['canEditProfile'] == true))
                        OutlinedButton.icon(
                          onPressed: () => setState(() {
                            _draft = selected;
                            _editing = true;
                          }),
                          icon: Icon(
                            selected == null
                                ? Icons.person_add_outlined
                                : Icons.edit_outlined,
                            size: 18,
                          ),
                          label: Text(
                            t[selected == null
                                ? 'team_add_staff'
                                : 'team_edit_staff'],
                          ),
                        ),
                      if (ready &&
                          selected != null &&
                          (selected['canManageAccess'] == true ||
                              (!_linked(selected) &&
                                  selected['employmentStatus'] == 'active' &&
                                  selected['canEditProfile'] == true)))
                        OutlinedButton.icon(
                          onPressed: () =>
                              setState(() => _accessEditing = true),
                          icon: const Icon(
                            Icons.admin_panel_settings_outlined,
                            size: 18,
                          ),
                          label: Text(
                            t[_linked(selected)
                                ? 'team_manage_access'
                                : 'team_invite'],
                          ),
                        ),
                    ],
                  );
                },
              ),
              // Team tools: one compact row instead of a stack of buttons.
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (selected == null &&
                        _admin &&
                        !_loading &&
                        _error == null)
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _accounts = true),
                        icon: const Icon(
                          Icons.manage_accounts_outlined,
                          size: 18,
                        ),
                        label: Text(t['team_accounts']),
                      ),
                    if (selected == null &&
                        _canOpenRoles &&
                        !_loading &&
                        _error == null)
                      OutlinedButton.icon(
                        key: const ValueKey('team-roles'),
                        onPressed: () => setState(() => _roles = true),
                        icon: const Icon(Icons.badge_outlined, size: 18),
                        label: Text(t['roles_title']),
                      ),
                    if (selected == null &&
                        _admin &&
                        !_loading &&
                        _error == null)
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _reviewing = true),
                        icon: const Icon(Icons.inbox_outlined, size: 18),
                        label: Text(t['team_review_queue']),
                      ),
                    if (selected == null &&
                        _admin &&
                        !_loading &&
                        _error == null)
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _activity = true),
                        icon: const Icon(Icons.history, size: 18),
                        label: Text(t['activity_title']),
                      ),
                    if (!WorkspacePageScope.contains(context))
                      OutlinedButton.icon(
                        onPressed: _loading ? null : () => _load(),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(t['team_refresh']),
                      ),
                  ],
                ),
              ),
              if (_admin && _error == null && _invitationId != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t['team_invite_reference'],
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        SelectableText(_invitationId!),
                        const SizedBox(height: 4),
                        Text(t['team_invite_created']),
                      ],
                    ),
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
                  WsRecord(
                    onTap: _loading
                        ? null
                        : () => setState(() => _selected = record),
                    leading: WsBadge(text: _value(record, 'code', t)),
                    title: _value(record, 'displayName', t),
                    pill: WsPill(
                      t[_linked(record) ? 'team_linked' : 'team_unlinked'],
                      tone: _linked(record) ? WsTone.good : WsTone.neutral,
                    ),
                    details: [
                      '${t['team_code']}: ${_value(record, 'code', t)}',
                      '${t['team_employment']}: ${_employment(record, t)}',
                      '${t['team_account']}: ${t[_linked(record) ? 'team_linked' : 'team_unlinked']}',
                    ],
                    actions: [
                      Text(
                        t['team_view_details'],
                        key: ValueKey('team-details-${record['id']}'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
