import 'workspace_page_scope.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'ws_ui.dart';
import '../../models/team_access.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'team_display.dart';

/// Explicit invitation grants and existing-account changes share one form.
/// Building names come from the authorized projection, never legacy Firestore.
class AccessEditor extends StatefulWidget {
  final String organizationId;
  final TeamService service;
  final TeamAccess actor;
  final Map<String, dynamic> profile;
  final Map<String, dynamic>? accessRequest;
  final VoidCallback onCancel, onAccessDenied;
  final ValueChanged<Map<String, dynamic>> onSaved;
  const AccessEditor({
    super.key,
    required this.organizationId,
    required this.service,
    required this.actor,
    required this.profile,
    this.accessRequest,
    required this.onCancel,
    required this.onAccessDenied,
    required this.onSaved,
  });

  @override
  State<AccessEditor> createState() => _AccessEditorState();
}

class _AccessEditorState extends State<AccessEditor> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  late final TextEditingController _email;
  // R2 "add staff by Gmail": the profile does not exist yet (no id).
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool get _adding => widget.profile['id'] == null;
  final _reason = TextEditingController();
  String? _role;
  // Organization roles from the server (R1), with canAssign per role.
  List<Map<String, dynamic>> _roleOptions = [];
  String? _status, _error;
  bool _all = false, _loading = true, _saving = false;
  bool _loadFailed = false;
  final Set<String> _selected = {};

  /// True when the person still has per-person switches from before roles
  /// could be edited; saving sends none, which removes them.
  bool _retiredOverrides = false;
  List<Map<String, dynamic>> _buildings = [];
  TeamOperation? _operation;
  bool get _invite =>
      widget.profile['accountId'] == null || widget.profile['accountId'] == '';
  bool get _approval => widget.accessRequest != null;
  bool get _locked => _loading || _saving || _operation != null;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(
      text: widget.profile['email'] as String? ?? '',
    );
    final raw = widget.profile['accountAccess'];
    if (!_invite && raw is Map) {
      final access = TeamAccess.fromMap(Map<String, dynamic>.from(raw));
      _role = access.role;
      _all = access.allBuildings;
      _selected.addAll(access.buildingIds);
      _retiredOverrides = access.overrides.isNotEmpty;
      if (['active', 'suspended', 'revoked'].contains(access.status)) {
        _status = access.status;
      }
    }
    _loadBuildings();
  }

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _phone.dispose();
    _reason.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadBuildings() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
      _error = null;
      _buildings = [];
    });
    try {
      final roleOptions = await _loadRoles();
      if (!mounted) return;
      final buildings = <Map<String, dynamic>>[];
      final seen = <String>{};
      String? cursor;
      do {
        final page = await widget.service.page(
          widget.organizationId,
          TeamView.buildings,
          limit: 100,
          cursor: cursor,
        );
        if (!mounted) return;
        buildings.addAll(page.records);
        cursor = page.nextCursor;
        if (cursor != null && !seen.add(cursor)) {
          throw StateError('Repeated cursor');
        }
      } while (cursor != null);
      setState(() {
        _buildings = buildings;
        _roleOptions = roleOptions;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (_denied(error)) {
        widget.onAccessDenied();
        return;
      }
      setState(() {
        _loading = false;
        _loadFailed = true;
        _error = 'team_properties_error';
      });
    }
  }

  static const _grantReasons = [
    'team_role_protected',
    'team_grant_exceeds_access',
  ];

  bool _denied(Object error) =>
      error is FirebaseFunctionsException &&
      ['permission-denied', 'unauthenticated'].contains(error.code) &&
      serverReason(error, _grantReasons).isEmpty;

  /// Organization roles; the starter templates when the server has no roles
  /// callable yet (app deployed before the backend).
  Future<List<Map<String, dynamic>>> _loadRoles() async {
    try {
      final data = await widget.service.roles(widget.organizationId);
      if (data['roles'] is List) {
        return [
          for (final r in data['roles'] as List)
            Map<String, dynamic>.from(r as Map),
        ];
      }
    } on FirebaseFunctionsException catch (error) {
      if (!const {'not-found', 'unimplemented'}.contains(error.code)) rethrow;
    }
    return [
      for (final id in TeamPolicy.templateIds)
        if (id != 'owner')
          {
            'id': id,
            'template': id,
            'name': '',
            'grants': TeamPolicy.encode(TeamPolicy.templates[id]!),
            'canAssign':
                widget.actor.canManageAccessOf(id) &&
                TeamPolicy.templates[id]!.keys.every(widget.actor.allows),
          },
    ];
  }

  List<Map<String, dynamic>> get _assignable =>
      _roleOptions.where((r) => r['canAssign'] == true).toList();

  void _feedback(String key) {
    setState(() => _error = key);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  Future<void> _save() async {
    if (_saving || _loading || _loadFailed) return;
    if (_operation == null) {
      if (!_form.currentState!.validate()) {
        _feedback('team_check_access');
        return;
      }
      if (_role == null || (!_invite && _status == null)) {
        _feedback('team_check_access');
        return;
      }
      if (!_all &&
          (_selected.length > 100 ||
              !_selected.every((id) => _buildings.any((b) => b['id'] == id)))) {
        _feedback('team_properties_invalid');
        return;
      }
      final grant = TeamAccess(
        role: _role,
        status: 'active',
        allBuildings: _all,
        buildingIds: _all ? {} : _selected,
      );
      // Hints only; the server re-checks the role and every override.
      if (!_assignable.any((r) => r['id'] == _role)) {
        _feedback('team_grant_exceeds');
        return;
      }
      final access = grant.toMap()..remove('status');
      _operation = widget.service.prepare(
        widget.organizationId,
        _approval
            ? TeamAction.reviewRequest
            : _adding
            ? TeamAction.addStaff
            : _invite
            ? TeamAction.invite
            : TeamAction.setAccess,
        {
          'access': access,
          if (_adding) ...{
            'profile': {
              'displayName': _name.text.trim(),
              'email': _email.text.trim().toLowerCase(),
              'phone': _phone.text.trim(),
            },
          } else if (_approval) ...{
            'requestId': widget.accessRequest!['id'],
            'decision': 'approve',
            'staffId': widget.profile['id'],
          } else if (_invite) ...{
            'staffId': widget.profile['id'],
            'email': _email.text.trim().toLowerCase(),
          } else ...{
            'userId': widget.profile['accountId'],
            'status': _status,
            'reason': _reason.text.trim(),
          },
        },
      );
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.service.execute(_operation!);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _operation = null;
      });
      widget.onSaved(result);
    } catch (error) {
      if (!mounted) return;
      if (_denied(error)) {
        widget.onAccessDenied();
        return;
      }
      if (serverReason(error, _grantReasons).isNotEmpty) {
        _operation = null;
        setState(() => _saving = false);
        _feedback('team_grant_exceeds');
        return;
      }
      // R2: the Gmail is already in this organization (member or waiting to sign in).
      final emailReason = serverReason(error, const [
        'team_other_employer',
        'team_same_owner_approval',
        'team_owner_account',
        'team_email_already_member',
        'team_email_already_invited',
        'team_invalid_email',
      ]);
      if (emailReason.isNotEmpty) {
        _operation = null;
        setState(() => _saving = false);
        _feedback(
          emailReason == 'team_invalid_email'
              ? 'team_gmail_invalid'
              : emailReason,
        );
        return;
      }
      if (serverReason(error, const ['team_role_not_found']).isNotEmpty) {
        // The role was deleted meanwhile: reload the list and ask again.
        _operation = null;
        setState(() {
          _saving = false;
          _role = null;
        });
        _feedback('roles_not_found');
        _loadBuildings();
        return;
      }
      var key = 'team_save_uncertain';
      if (error is FirebaseFunctionsException &&
          [
            'invalid-argument',
            'failed-precondition',
            'not-found',
            'already-exists',
          ].contains(error.code)) {
        _operation = null;
        key = 'team_access_rejected';
      }
      setState(() => _saving = false);
      _feedback(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final roles = _assignable;
    final missing = _selected.where(
      (id) => !_buildings.any((b) => b['id'] == id),
    );
    return PopScope(
      canPop: !_saving && _operation == null,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: WorkspacePageScope.constraints(context, 720),
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t[_approval
                          ? 'team_approve_request'
                          : _adding
                          ? 'team_add_by_gmail'
                          : _invite
                          ? 'team_invite'
                          : 'team_manage_access'],
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    if (!_adding)
                      Text(widget.profile['displayName'] as String? ?? ''),
                    if (_approval) ...[
                      Text(
                        '${t['team_request_from']}: ${widget.accessRequest!['displayName'] ?? ''}',
                      ),
                      Text(widget.accessRequest!['email'] as String? ?? ''),
                      Text(
                        '${t['team_code']}: ${widget.profile['code'] ?? ''}',
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      t[_approval
                          ? 'team_approve_note'
                          : _adding
                          ? 'team_add_by_gmail_note'
                          : _invite
                          ? 'team_invite_note'
                          : 'team_access_change_note'],
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            t[_error!],
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    if (_loading || _saving)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: LinearProgressIndicator(
                          semanticsLabel:
                              t[_saving
                                  ? 'team_saving'
                                  : 'team_properties_loading'],
                        ),
                      ),
                    if (_loadFailed)
                      WsActions(
                        children: [
                          OutlinedButton(
                            onPressed: _loadBuildings,
                            child: Text(t['team_refresh']),
                          ),
                        ],
                      ),
                    if (_adding) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: TextFormField(
                          key: const ValueKey('access-name'),
                          controller: _name,
                          readOnly: _locked,
                          maxLength: 120,
                          decoration: InputDecoration(
                            labelText: t['team_display_name_field'],
                            errorMaxLines: 4,
                          ),
                          validator: (v) => (v?.trim() ?? '').isEmpty
                              ? t['team_required']
                              : null,
                        ),
                      ),
                      TextFormField(
                        key: const ValueKey('access-phone'),
                        controller: _phone,
                        readOnly: _locked,
                        maxLength: 40,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: t['team_phone_optional'],
                        ),
                      ),
                    ],
                    if (_invite && !_approval)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: TextFormField(
                          key: const ValueKey('access-email'),
                          controller: _email,
                          readOnly: _locked,
                          maxLength: 254,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText:
                                t[_adding ? 'team_gmail_field' : 'team_email'],
                            helperText: _adding ? t['team_gmail_help'] : null,
                            helperMaxLines: 4,
                            errorMaxLines: 4,
                          ),
                          validator: (v) =>
                              RegExp(
                                r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                              ).hasMatch(v?.trim() ?? '')
                              ? null
                              : t['team_invite_email_required'],
                        ),
                      ),
                    const SizedBox(height: 20),
                    if (!_loading && !_loadFailed && roles.isEmpty)
                      Text(t['roles_none_assignable']),
                    // Rebuilt once the roles arrive so the current role is preselected.
                    KeyedSubtree(
                      key: ValueKey('access-role-box-${roles.length}'),
                      child: DropdownButtonFormField<String>(
                        key: const ValueKey('access-role'),
                        initialValue: roles.any((r) => r['id'] == _role)
                            ? _role
                            : null,
                        isExpanded: true,
                        isDense: false,
                        itemHeight: null,
                        decoration: InputDecoration(
                          labelText: t['team_role'],
                          errorMaxLines: 4,
                        ),
                        items: [
                          for (final role in roles)
                            DropdownMenuItem(
                              value: role['id'] as String,
                              child: Text(
                                teamRoleLabel(t, role['id'], role['name']),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _locked
                            ? null
                            : (value) => setState(() => _role = value),
                        validator: (v) => v == null ? t['team_required'] : null,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Which buildings this person is assigned to. "All" also covers
                    // buildings added later; ticking every building does not.
                    Text(
                      t['team_properties_heading'],
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (final all in [true, false])
                      ListTile(
                        key: ValueKey(
                          all ? 'access-scope-all' : 'access-scope-selected',
                        ),
                        contentPadding: EdgeInsets.zero,
                        enabled: !_locked,
                        selected: _all == all,
                        leading: Icon(
                          _all == all
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        title: Text(
                          t[all
                              ? 'team_scope_all_option'
                              : 'team_scope_selected_option'],
                        ),
                        onTap: _locked
                            ? null
                            : () => setState(() => _all = all),
                      ),
                    if (!_all) ...[
                      Text(t['team_no_properties_note']),
                      if (!_loading && _buildings.isEmpty)
                        Text(t['team_no_properties']),
                      for (final building in _buildings)
                        CheckboxListTile(
                          key: ValueKey('access-building-${building['id']}'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            building['name'] as String? ??
                                building['id'] as String,
                          ),
                          value: _selected.contains(building['id']),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: _locked
                              ? null
                              : (value) => setState(() {
                                  if (value!) {
                                    _selected.add(building['id'] as String);
                                  } else {
                                    _selected.remove(building['id']);
                                  }
                                }),
                        ),
                      // Only once the list has loaded: before that every saved building
                      // would look "unavailable" for a moment.
                      if (!_loading && !_loadFailed)
                        for (final id in missing)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${t['team_property_unavailable']}: $id',
                            ),
                            value: true,
                            onChanged: _locked
                                ? null
                                : (_) => setState(() => _selected.remove(id)),
                          ),
                    ],
                    // Per-person permission switches were replaced by roles (R1).
                    // Old switches are shown as a notice and removed on save.
                    if (_retiredOverrides)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          t['team_overrides_retired'],
                          key: const ValueKey('access-overrides-retired'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                        ),
                      ),
                    if (!_invite) ...[
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        key: const ValueKey('access-status'),
                        initialValue: _status,
                        isExpanded: true,
                        isDense: false,
                        itemHeight: null,
                        decoration: InputDecoration(
                          labelText: t['team_access_status'],
                          errorMaxLines: 4,
                        ),
                        items: [
                          for (final status in [
                            'active',
                            'suspended',
                            'revoked',
                          ])
                            DropdownMenuItem(
                              value: status,
                              child: Text(t['team_status_$status']),
                            ),
                        ],
                        onChanged: _locked
                            ? null
                            : (v) => setState(() => _status = v),
                        validator: (v) => v == null ? t['team_required'] : null,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        key: const ValueKey('access-reason'),
                        controller: _reason,
                        readOnly: _locked,
                        maxLength: 500,
                        minLines: 2,
                        maxLines: 5,
                        decoration: InputDecoration(
                          labelText: t['team_access_reason'],
                          errorMaxLines: 4,
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? t['team_required']
                            : null,
                      ),
                    ],
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton(
                          onPressed: _saving || _loading || _loadFailed
                              ? null
                              : _save,
                          child: Text(
                            t[_saving
                                ? 'team_saving'
                                : _operation != null
                                ? 'team_retry_save'
                                : _adding
                                ? 'team_add_by_gmail_save'
                                : _invite
                                ? (_approval
                                      ? 'team_approve_request'
                                      : 'team_create_invite')
                                : 'team_save_access'],
                          ),
                        ),
                        OutlinedButton(
                          onPressed: _saving || _operation != null
                              ? null
                              : widget.onCancel,
                          child: Text(t['team_cancel']),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
