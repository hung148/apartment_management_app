import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../../models/team_access.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';

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
  final _reason = TextEditingController();
  TeamRole? _role;
  String? _status, _error;
  bool _all = false, _loading = true, _saving = false;
  bool _loadFailed = false;
  final Set<String> _selected = {};
  final Map<TeamPermission, bool> _overrides = {};
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
      _overrides.addAll(access.overrides);
      if (['active', 'suspended', 'revoked'].contains(access.status)) {
        _status = access.status;
      }
    }
    _loadBuildings();
  }

  @override
  void dispose() {
    _email.dispose();
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

  bool _denied(Object error) =>
      error is FirebaseFunctionsException &&
      ['permission-denied', 'unauthenticated'].contains(error.code);

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
        overrides: _overrides,
      );
      if (!widget.actor.canManageAccessOf(_role) ||
          TeamPermission.values.any(
            (p) => grant.allows(p) && !widget.actor.allows(p),
          )) {
        _feedback('team_grant_exceeds');
        return;
      }
      final access = grant.toMap()..remove('status');
      _operation = widget.service.prepare(
        widget.organizationId,
        _approval
            ? TeamAction.reviewRequest
            : _invite
            ? TeamAction.invite
            : TeamAction.setAccess,
        {
          'access': access,
          if (_approval) ...{
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
    final roles = TeamRole.values
        .where((role) => widget.actor.canManageAccessOf(role))
        .toList();
    final missing = _selected.where(
      (id) => !_buildings.any((b) => b['id'] == id),
    );
    return PopScope(
      canPop: !_saving && _operation == null,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
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
                          : _invite
                          ? 'team_invite'
                          : 'team_manage_access'],
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
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
                      OutlinedButton(
                        onPressed: _loadBuildings,
                        child: Text(t['team_refresh']),
                      ),
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
                            labelText: t['team_email'],
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
                    DropdownButtonFormField<TeamRole>(
                      key: const ValueKey('access-role'),
                      initialValue: roles.contains(_role) ? _role : null,
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
                            value: role,
                            child: Text(t['team_role_${role.name}']),
                          ),
                      ],
                      onChanged: _locked
                          ? null
                          : (value) => setState(() => _role = value),
                      validator: (v) => v == null ? t['team_required'] : null,
                    ),
                    const SizedBox(height: 20),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(t['team_all_properties']),
                      subtitle: Text(t['team_future_properties']),
                      value: _all,
                      onChanged: _locked
                          ? null
                          : (value) => setState(() => _all = value!),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    if (!_all) ...[
                      Text(
                        t['team_selected_properties'],
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
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
                      for (final id in missing)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${t['team_property_unavailable']}: $id'),
                          value: true,
                          onChanged: _locked
                              ? null
                              : (_) => setState(() => _selected.remove(id)),
                        ),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      t['team_overrides'],
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (final permission in TeamAccess.overridable)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('access-${permission.name}'),
                          initialValue: _overrides.containsKey(permission)
                              ? (_overrides[permission]! ? 'allow' : 'deny')
                              : 'default',
                          isExpanded: true,
                          isDense: false,
                          itemHeight: null,
                          decoration: InputDecoration(
                            labelText: t['team_permission_${permission.name}'],
                            helperText: _role == null
                                ? null
                                : t[TeamAccess.defaults(
                                        _role,
                                      ).contains(permission)
                                      ? 'team_default_allowed'
                                      : 'team_default_denied'],
                            helperMaxLines: 3,
                          ),
                          items: [
                            for (final option in ['default', 'allow', 'deny'])
                              DropdownMenuItem(
                                value: option,
                                child: Text(t['team_override_$option']),
                              ),
                          ],
                          onChanged: _locked
                              ? null
                              : (value) => setState(() {
                                  if (value == 'default') {
                                    _overrides.remove(permission);
                                  } else {
                                    _overrides[permission] = value == 'allow';
                                  }
                                }),
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
