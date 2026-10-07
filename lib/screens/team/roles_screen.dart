import 'workspace_page_scope.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../../models/team_access.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'back_steps.dart';
import 'team_display.dart';

/// Roles and permissions (R1). Lists the organization's roles and edits one
/// with a permission x scope grid. Everything shown here is a hint; the
/// `orgRoles` callable re-checks every save.
class RolesScreen extends StatefulWidget {
  final String organizationId;
  final TeamService service;
  final TeamAccess actor;
  final VoidCallback onBack;
  final VoidCallback onAccessDenied;
  const RolesScreen({
    super.key,
    required this.organizationId,
    required this.service,
    required this.actor,
    required this.onBack,
    required this.onAccessDenied,
  });

  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
  List<Map<String, dynamic>> _roles = [];
  bool _canCreate = false, _loading = true, _failed = false;
  String? _notice;
  bool _noticeIsError = false;
  // Editor: null = list. {} with no id = new role.
  Map<String, dynamic>? _editing;
  int _editorGeneration = 0;
  final Set<String> _deleting = {};
  // Shown inside the editor when it was reopened (e.g. someone else saved first).
  String? _editorNotice;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _lostAccess(Object error) =>
      error is FirebaseFunctionsException &&
      (error.code == 'unauthenticated' ||
          (error.code == 'permission-denied' &&
              serverReason(error, const ['team_access_denied']).isNotEmpty));

  Future<void> _load({String? reopen}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final data = await widget.service.roles(widget.organizationId);
      if (!mounted || generation != _generation) return;
      final roles = [
        for (final r in (data['roles'] as List? ?? const []))
          Map<String, dynamic>.from(r as Map),
      ];
      setState(() {
        _roles = roles;
        _canCreate = data['canCreate'] == true;
        _loading = false;
        if (reopen != null) {
          final fresh = roles.where((r) => r['id'] == reopen).firstOrNull;
          _editing = fresh;
          _editorNotice = fresh == null ? null : 'roles_changed';
          _editorGeneration++;
        }
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      if (_lostAccess(error)) {
        widget.onAccessDenied();
        return;
      }
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _show(String key, {bool error = false}) => setState(() {
    _notice = key;
    _noticeIsError = error;
  });

  String _label(AppTranslations t, Map<String, dynamic> role) =>
      teamRoleLabel(t, role['id'], role['name']);

  Future<void> _delete(Map<String, dynamic> role) async {
    final id = role['id'] as String;
    if (_deleting.contains(id)) return;
    final t = AppTranslations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t['roles_delete']),
        content: Text(
          t.textWithParams('roles_delete_confirm', {'name': _label(t, role)}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t['team_cancel']),
          ),
          FilledButton(
            key: const ValueKey('role-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t['roles_delete']),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _deleting.add(id);
      _notice = null;
    });
    final operation = widget.service.prepareRole(
      widget.organizationId,
      'delete',
      {'roleId': id, 'expectedRevision': role['revision'] ?? 0},
    );
    try {
      await widget.service.executeRole(operation);
      if (!mounted) return;
      _deleting.remove(id);
      _show('roles_deleted');
      await _load();
    } catch (error) {
      if (!mounted) return;
      _deleting.remove(id);
      if (_lostAccess(error)) {
        widget.onAccessDenied();
        return;
      }
      _show(_errorKey(error), error: true);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final editing = _editing;
    if (editing != null) {
      final existing = editing['id'] != null;
      final used = <String>{
        for (final r in _roles)
          if (r['id'] != editing['id']) _label(t, r).toLowerCase(),
      };
      return RoleEditor(
        key: ValueKey(
          'role-editor-${editing['id'] ?? 'new'}-$_editorGeneration',
        ),
        organizationId: widget.organizationId,
        service: widget.service,
        actor: widget.actor,
        role: existing ? editing : null,
        startFrom: _roles.where((r) => r['fixed'] != true).toList(),
        usedNames: used,
        notice: _editorNotice,
        onCancel: () => setState(() {
          _editing = null;
          _editorNotice = null;
        }),
        onAccessDenied: widget.onAccessDenied,
        onSaved: () {
          setState(() {
            _editing = null;
            _editorNotice = null;
          });
          _show('roles_saved');
          _load();
        },
        onChangedElsewhere: () {
          _show('roles_changed', error: true);
          _load(reopen: editing['id'] as String?);
        },
      );
    }
    final theme = Theme.of(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: WorkspacePageScope.constraints(context, 960),
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back),
                    label: Text(t['team_back']),
                  ),
                ),
                Text(t['roles_title'], style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(t['roles_intro']),
                const SizedBox(height: 4),
                Text(t['roles_scope_help'], style: theme.textTheme.bodySmall),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        t[_notice!],
                        key: const ValueKey('roles-notice'),
                        style: TextStyle(
                          color: _noticeIsError
                              ? theme.colorScheme.error
                              : Colors.green.shade700,
                        ),
                      ),
                    ),
                  ),
                if (_loading)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(
                      semanticsLabel: t['roles_loading'],
                    ),
                  ),
                if (_failed) ...[
                  const SizedBox(height: 16),
                  Text(
                    t['roles_load_error'],
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: _load,
                      child: Text(t['roles_retry']),
                    ),
                  ),
                ],
                if (_canCreate && !_failed)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        key: const ValueKey('roles-new'),
                        onPressed: _loading
                            ? null
                            : () => setState(() {
                                _notice = null;
                                _editorNotice = null;
                                _editing = {};
                                _editorGeneration++;
                              }),
                        icon: const Icon(Icons.add),
                        label: Text(t['roles_new']),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                for (final role in _roles) _card(context, t, role),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(
    BuildContext context,
    AppTranslations t,
    Map<String, dynamic> role,
  ) {
    final theme = Theme.of(context);
    final grants = TeamPolicy.parse(role['grants']);
    final color = _parseColor(role['color']);
    final members = role['members'] as int? ?? 0;
    final invites = role['pendingInvitations'] as int? ?? 0;
    final fixed = role['fixed'] == true;
    final id = role['id'] as String;
    return Card(
      key: ValueKey('role-card-$id'),
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: CircleAvatar(radius: 8, backgroundColor: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _label(t, role),
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        [
                          t[TeamPolicy.isTemplate(role['template'])
                              ? 'roles_template'
                              : 'roles_custom'],
                          t.textWithParams('roles_people', {'count': members}),
                          if (invites > 0)
                            t.textWithParams('roles_invites', {
                              'count': invites,
                            }),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              fixed
                  ? t['roles_owner_fixed']
                  : grants.isEmpty
                  ? t['roles_no_permissions']
                  : grants.keys
                        .map((p) => t['team_permission_${p.name}'])
                        .join(', '),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            if (!fixed)
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    key: ValueKey('role-open-$id'),
                    onPressed: _loading
                        ? null
                        : () => setState(() {
                            _notice = null;
                            _editorNotice = null;
                            _editing = role;
                            _editorGeneration++;
                          }),
                    child: Text(
                      t[role['canEdit'] == true ? 'roles_edit' : 'roles_view'],
                    ),
                  ),
                  if (role['canEdit'] == true)
                    TextButton(
                      key: ValueKey('role-delete-$id'),
                      onPressed:
                          role['canDelete'] == true &&
                              !_deleting.contains(id) &&
                              !_loading
                          ? () => _delete(role)
                          : null,
                      child: Text(t['roles_delete']),
                    ),
                ],
              ),
            if (!fixed && role['canEdit'] == true && role['canDelete'] != true)
              Text(
                t.textWithParams('roles_delete_in_use', {
                  'count': members + invites,
                }),
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

Color _parseColor(Object? value) {
  if (value is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
    return Color(0xFF000000 | int.parse(value.substring(1), radix: 16));
  }
  return Colors.grey;
}

const _roleReasons = [
  'role_changed',
  'role_name_exists',
  'role_limit_reached',
  'role_edit_denied',
  'role_too_many_members',
  'role_not_found',
  'role_in_use',
  'role_invalid_name',
];

String _errorKey(Object error) {
  if (error is! FirebaseFunctionsException) return 'roles_uncertain';
  return switch (serverReason(error, _roleReasons)) {
    'role_changed' => 'roles_changed',
    'role_name_exists' => 'roles_name_exists',
    'role_limit_reached' => 'roles_limit',
    'role_edit_denied' => 'roles_denied',
    'role_too_many_members' => 'roles_too_many',
    'role_not_found' => 'roles_not_found',
    'role_in_use' => 'roles_delete_in_use_short',
    'role_invalid_name' => 'roles_name_required',
    _ =>
      const {
            'unavailable',
            'deadline-exceeded',
            'internal',
            'unknown',
          }.contains(error.code)
          ? 'roles_uncertain'
          : 'team_access_rejected',
  };
}

/// Edits (or creates) one role. Keeps its operation across retries so a
/// double tap or a lost response never saves twice.
class RoleEditor extends StatefulWidget {
  final String organizationId;
  final TeamService service;
  final TeamAccess actor;
  final Map<String, dynamic>? role;
  final List<Map<String, dynamic>> startFrom;
  final Set<String> usedNames;

  /// A message to show when the editor opens (translation key).
  final String? notice;
  final VoidCallback onCancel, onSaved, onAccessDenied, onChangedElsewhere;
  const RoleEditor({
    super.key,
    required this.organizationId,
    required this.service,
    required this.actor,
    required this.role,
    required this.startFrom,
    required this.usedNames,
    this.notice,
    required this.onCancel,
    required this.onSaved,
    required this.onAccessDenied,
    required this.onChangedElsewhere,
  });

  @override
  State<RoleEditor> createState() => _RoleEditorState();
}

class _RoleEditorState extends State<RoleEditor> {
  static const swatches = [
    '#3949AB',
    '#1E88E5',
    '#00897B',
    '#43A047',
    '#FDD835',
    '#F4511E',
    '#E53935',
    '#8E24AA',
    '#6D4C41',
    '#546E7A',
  ];
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  late final TextEditingController _name;
  late String _color;
  late Map<TeamPermission, GrantScope> _grants;
  String? _initial;
  String? _error;
  // Server reason not known to the app, shown under the message for support.
  String? _detail;
  bool _saving = false;
  TeamOperation? _operation;

  bool get _creating => widget.role == null;
  bool get _editable => _creating || widget.role!['canEdit'] == true;
  bool get _dirty => _initial != null && _snapshot() != _initial;
  bool get _template => TeamPolicy.isTemplate(widget.role?['template']);

  @override
  void initState() {
    super.initState();
    final role = widget.role;
    _name = TextEditingController(text: role?['name'] as String? ?? '');
    _color = role?['color'] as String? ?? swatches.first;
    _grants = Map.of(TeamPolicy.parse(role?['grants']));
    _initial = _snapshot();
    _error = widget.notice;
  }

  @override
  void dispose() {
    _name.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _snapshot() =>
      '${_name.text.trim()}|$_color|${TeamPolicy.encode(_grants).entries.map((e) => '${e.key}=${e.value}').toList()..sort()}';

  /// The widest scope this account may give for a permission (null = none).
  GrantScope? _maxGive(TeamPermission p) {
    if (!widget.actor.isOwner &&
        widget.actor.role != 'coOwner' &&
        (p == TeamPermission.manageRoles ||
            p == TeamPermission.assignAdditionalWorkplace))
      return null; // only the owner gives it
    final mine = widget.actor.grants[p];
    if (mine == null) return null;
    if (mine == GrantScope.managed &&
        widget.actor.allBuildings &&
        TeamPolicy.scopes[p]!.contains(GrantScope.all)) {
      return GrantScope.all;
    }
    return mine;
  }

  bool _canGive(TeamPermission p, GrantScope s) {
    final max = _maxGive(p);
    return max != null && max.index >= s.index;
  }

  void _startFrom(Map<String, dynamic>? source) {
    setState(() {
      _operation = null;
      _grants = source == null
          ? {}
          : Map.of(TeamPolicy.parse(source['grants']));
      // Drop anything this account cannot give.
      _grants.removeWhere((p, s) => !_canGive(p, s));
    });
  }

  void _feedback(String key, [String? detail]) {
    setState(() {
      _error = key;
      _detail = detail;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  Future<void> _save() async {
    if (_saving || !_editable) return;
    if (_operation == null) {
      if (!_form.currentState!.validate()) {
        _feedback('roles_name_required');
        return;
      }
      if (_grants.entries.any((e) => !_canGive(e.key, e.value))) {
        _feedback('roles_denied');
        return;
      }
      _operation = widget.service.prepareRole(widget.organizationId, 'save', {
        if (!_creating) 'roleId': widget.role!['id'],
        if (!_creating) 'expectedRevision': widget.role!['revision'] ?? 0,
        'name': _name.text.trim(),
        'color': _color,
        'grants': TeamPolicy.encode(_grants),
      });
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.executeRole(_operation!);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _operation = null;
      });
      widget.onSaved();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (error is FirebaseFunctionsException) {
        if (error.code == 'unauthenticated' ||
            (error.code == 'permission-denied' &&
                serverReason(error, const ['team_access_denied']).isNotEmpty)) {
          widget.onAccessDenied();
          return;
        }
        if (serverReason(error, const [
          'role_changed',
          'role_not_found',
        ]).isNotEmpty) {
          _operation = null;
          widget.onChangedElsewhere();
          return;
        }
        // A definite answer: the next save is a new operation.
        if (!const {
          'unavailable',
          'deadline-exceeded',
          'internal',
          'unknown',
        }.contains(error.code)) {
          _operation = null;
        }
      }
      final key = _errorKey(error);
      _feedback(
        key,
        key == 'team_access_rejected' && error is FirebaseFunctionsException
            ? '${error.code}: ${error.message}'
            : null,
      );
    }
  }

  Future<void> _leave() async {
    if (_saving) return;
    if (!_dirty) {
      widget.onCancel();
      return;
    }
    final t = AppTranslations.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t['roles_discard']),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t['roles_keep']),
          ),
          FilledButton(
            key: const ValueKey('role-discard'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t['roles_discard_yes']),
          ),
        ],
      ),
    );
    if (discard == true && mounted) widget.onCancel();
  }

  /// Back asks before discarding edits. Inside the organization workspace
  /// this is one back step (U1); elsewhere it guards the route.
  Widget _backGuard(BuildContext context, Widget child) =>
      BackSteps.of(context) != null
      ? BackStep(onBack: _leave, child: child)
      : PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _leave();
          },
          child: child,
        );

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final theme = Theme.of(context);
    final role = widget.role;
    final members = role?['members'] as int? ?? 0;
    final locked = _saving || !_editable;
    return _backGuard(
      context,
      SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: WorkspacePageScope.constraints(context, 960),
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _saving ? null : _leave,
                        icon: const Icon(Icons.arrow_back),
                        label: Text(t['team_back']),
                      ),
                    ),
                    Text(
                      _creating
                          ? t['roles_new']
                          : teamRoleLabel(t, role!['id'], role['name']),
                      style: theme.textTheme.headlineSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t['roles_scope_help'],
                      style: theme.textTheme.bodySmall,
                    ),
                    if (!_editable)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(t['roles_read_only']),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            t[_error!],
                            key: const ValueKey('role-error'),
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      ),
                    if (_error != null && _detail != null)
                      SelectableText(
                        _detail!,
                        style: theme.textTheme.bodySmall,
                      ),
                    if (_saving)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(
                          semanticsLabel: t['roles_saving'],
                        ),
                      ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const ValueKey('role-name'),
                      controller: _name,
                      readOnly: locked,
                      maxLength: 40,
                      decoration: InputDecoration(
                        labelText: t['roles_name'],
                        // A starter role with no name of its own shows the translated name.
                        hintText: _template
                            ? teamRoleLabel(t, widget.role!['template'])
                            : null,
                        errorMaxLines: 3,
                      ),
                      onChanged: (_) => setState(() => _operation = null),
                      validator: (v) {
                        final name = v?.trim() ?? '';
                        if ((name.isEmpty && !_template) || name.length > 40)
                          return t['roles_name_required'];
                        if (name.isNotEmpty &&
                            widget.usedNames.contains(name.toLowerCase())) {
                          return t['roles_name_exists'];
                        }
                        return null;
                      },
                    ),
                    Text(t['roles_color'], style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final hex in swatches)
                          Semantics(
                            button: true,
                            selected: _color == hex,
                            label: hex,
                            child: InkWell(
                              key: ValueKey('role-color-$hex'),
                              customBorder: const CircleBorder(),
                              onTap: locked
                                  ? null
                                  : () => setState(() {
                                      _color = hex;
                                      _operation = null;
                                    }),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: _parseColor(hex),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _color == hex
                                        ? theme.colorScheme.onSurface
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                                child: _color == hex
                                    ? const Icon(
                                        Icons.check,
                                        size: 18,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (_creating && widget.startFrom.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        key: const ValueKey('role-start-from'),
                        initialValue: '',
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: t['roles_start_from'],
                        ),
                        items: [
                          DropdownMenuItem(
                            value: '',
                            child: Text(t['roles_blank']),
                          ),
                          for (final r in widget.startFrom)
                            DropdownMenuItem(
                              value: r['id'] as String,
                              child: Text(
                                teamRoleLabel(t, r['id'], r['name']),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: locked
                            ? null
                            : (id) => _startFrom(
                                widget.startFrom
                                    .where((r) => r['id'] == id)
                                    .firstOrNull,
                              ),
                      ),
                    ],
                    for (final group in TeamPolicy.groups.entries) ...[
                      const SizedBox(height: 20),
                      Text(
                        t['role_group_${group.key}'],
                        style: theme.textTheme.titleMedium,
                      ),
                      const Divider(),
                      for (final p in group.value)
                        _permissionRow(t, theme, p, locked),
                    ],
                    if (!_creating && members > 0 && _editable)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          t.textWithParams('roles_affects', {'count': members}),
                          style: TextStyle(color: theme.colorScheme.tertiary),
                        ),
                      ),
                    const SizedBox(height: 20),
                    if (_editable)
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton(
                            key: const ValueKey('role-save'),
                            onPressed: _saving ? null : _save,
                            child: Text(
                              t[_saving
                                  ? 'roles_saving'
                                  : _operation != null
                                  ? 'team_retry_save'
                                  : 'roles_save'],
                            ),
                          ),
                          OutlinedButton(
                            onPressed: _saving ? null : _leave,
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

  Widget _permissionRow(
    AppTranslations t,
    ThemeData theme,
    TeamPermission p,
    bool locked,
  ) {
    final scopes = TeamPolicy.scopes[p]!;
    final onOff = scopes.length == 1;
    final current = _grants[p];
    // Off, then narrow to wide, so the row reads left to right.
    final options = <GrantScope?>[null, ...scopes.reversed];
    String label(GrantScope? s) => s == null
        ? t['role_scope_off']
        : onOff
        ? t['role_scope_on']
        : t['role_scope_${s.name}'];
    final chips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final s in options)
          ChoiceChip(
            key: ValueKey('role-${p.name}-${s?.name ?? 'off'}'),
            label: Text(label(s)),
            selected: current == s,
            onSelected: locked || (s != null && !_canGive(p, s))
                ? null
                : (_) => setState(() {
                    _operation = null;
                    if (s == null) {
                      _grants.remove(p);
                    } else {
                      _grants[p] = s;
                    }
                  }),
          ),
      ],
    );
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t['team_permission_${p.name}']),
        if (p == TeamPermission.manageRoles)
          Text(t['roles_manage_roles_note'], style: theme.textTheme.bodySmall),
        if (p == TeamPermission.assignAdditionalWorkplace)
          Text(
            t['roles_additional_workplace_note'],
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth >= 640
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: title),
                  const SizedBox(width: 12),
                  Expanded(flex: 3, child: chips),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 4), chips],
              ),
      ),
    );
  }
}
