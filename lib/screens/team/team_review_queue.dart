import 'workspace_page_scope.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'ws_ui.dart';
import '../../models/team_access.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'access_editor.dart';
import 'team_display.dart';

class TeamReviewQueue extends StatefulWidget {
  final String organizationId;
  final TeamService service;
  final VoidCallback onBack;
  const TeamReviewQueue({
    super.key,
    required this.organizationId,
    required this.service,
    required this.onBack,
  });
  @override
  State<TeamReviewQueue> createState() => _TeamReviewQueueState();
}

class _TeamReviewQueueState extends State<TeamReviewQueue> {
  TeamView _view = TeamView.invitations;
  TeamAccess? _actor;
  List<Map<String, dynamic>> _records = [], _staff = [];
  Map<String, dynamic>? _request, _profile;
  String? _cursor, _error;
  bool _busy = false, _denied = false;
  int _generation = 0;
  TeamOperation? _operation;
  final _scroll = ScrollController();
  bool get _locked => _busy || _operation != null;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TeamReviewQueue old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.service != widget.service) {
      _operation = null;
      _request = null;
      _profile = null;
      _load();
    }
  }

  void _fail(Object error) {
    _denied =
        error is FirebaseFunctionsException &&
        ['permission-denied', 'unauthenticated'].contains(error.code);
    setState(() {
      _busy = false;
      _records = [];
      _staff = [];
      _request = null;
      _profile = null;
      _cursor = null;
      _error = _denied ? 'team_denied' : 'team_queue_error';
    });
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    final cursor = more ? _cursor : null;
    setState(() {
      _busy = true;
      _error = null;
      _denied = false;
      _request = null;
      _profile = null;
      _staff = [];
      if (!more) {
        _records = [];
        _cursor = null;
      }
    });
    try {
      final own = await widget.service.myAccess(widget.organizationId);
      if (!mounted || generation != _generation) return;
      final actor = TeamAccess.fromMap(own ?? {});
      if (!actor.allows(TeamPermission.manageTeam) || !actor.allBuildings) {
        throw FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'team_access_denied',
        );
      }
      final page = await widget.service.page(
        widget.organizationId,
        _view,
        cursor: cursor,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _actor = actor;
        _records = more ? [..._records, ...page.records] : page.records;
        _cursor = page.nextCursor;
        _busy = false;
      });
    } catch (error) {
      if (mounted && generation == _generation) _fail(error);
    }
  }

  Future<void> _chooseStaff(Map<String, dynamic> request) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _request = request;
      _staff = [];
    });
    try {
      String? cursor;
      final seen = <String>{};
      final profiles = <Map<String, dynamic>>[];
      do {
        final page = await widget.service.page(
          widget.organizationId,
          TeamView.staff,
          limit: 100,
          cursor: cursor,
        );
        if (!mounted || generation != _generation) return;
        profiles.addAll(
          page.records.where(
            (p) =>
                p['employmentStatus'] == 'active' &&
                (p['accountId'] == null || p['accountId'] == '') &&
                p['canEditProfile'] == true,
          ),
        );
        cursor = page.nextCursor;
        if (cursor != null && !seen.add(cursor)) {
          throw StateError('Repeated cursor');
        }
      } while (cursor != null);
      setState(() {
        _staff = profiles;
        _busy = false;
      });
    } catch (error) {
      if (mounted && generation == _generation) _fail(error);
    }
  }

  /// R2: fix a typo in a Gmail before the person's first sign-in.
  Future<void> _changeEmail(Map<String, dynamic> record) async {
    if (_locked) return;
    final t = AppTranslations.of(context);
    final controller = TextEditingController(
      text: record['email'] as String? ?? '',
    );
    final form = GlobalKey<FormState>();
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t['team_change_gmail']),
        content: Form(
          key: form,
          child: TextFormField(
            key: const ValueKey('invitation-email-field'),
            controller: controller,
            autofocus: true,
            maxLength: 254,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: t['team_gmail_field'],
              errorMaxLines: 3,
            ),
            validator: (v) =>
                RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v?.trim() ?? '')
                ? null
                : t['team_invite_email_required'],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t['team_cancel']),
          ),
          FilledButton(
            key: const ValueKey('invitation-email-save'),
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, controller.text.trim().toLowerCase());
              }
            },
            child: Text(t['save']),
          ),
        ],
      ),
    );
    // Not disposed here: the dialog's closing animation still uses it.
    if (email == null || !mounted || email == record['email']) return;
    await _run(TeamAction.changeInvitationEmail, {
      'invitationId': record['id'],
      'email': email,
    });
  }

  Future<void> _run([
    TeamAction? action,
    Map<String, dynamic> fields = const {},
  ]) async {
    if (_busy) return;
    final generation = _generation;
    if (_operation == null) {
      if (action == null) return;
      _operation = widget.service.prepare(
        widget.organizationId,
        action,
        fields,
      );
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.execute(_operation!);
      if (!mounted || generation != _generation) return;
      _operation = null;
      await _load();
    } catch (error) {
      if (!mounted || generation != _generation) return;
      if (error is FirebaseFunctionsException &&
          ['permission-denied', 'unauthenticated'].contains(error.code)) {
        _operation = null;
        _fail(error);
        return;
      }
      final rejected =
          error is FirebaseFunctionsException &&
          [
            'invalid-argument',
            'failed-precondition',
            'not-found',
            'already-exists',
          ].contains(error.code);
      final emailReason = serverReason(error, const [
        'team_other_employer',
        'team_same_owner_approval',
        'team_owner_account',
        'team_email_already_member',
        'team_email_already_invited',
        'team_invalid_email',
      ]);
      setState(() {
        _busy = false;
        _error = emailReason.isNotEmpty
            ? (emailReason == 'team_invalid_email'
                  ? 'team_gmail_invalid'
                  : emailReason)
            : rejected
            ? 'team_access_rejected'
            : 'team_save_uncertain';
        if (rejected) _operation = null;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    if (_profile != null && _request != null && _actor != null) {
      return AccessEditor(
        key: ValueKey(
          'approve-${widget.organizationId}-${_request!['id']}-${_profile!['id']}',
        ),
        organizationId: widget.organizationId,
        service: widget.service,
        actor: _actor!,
        profile: _profile!,
        accessRequest: _request,
        onCancel: () => setState(() => _profile = null),
        onSaved: (_) => _load(),
        onAccessDenied: () => _fail(
          FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'denied',
          ),
        ),
      );
    }
    return PopScope(
      canPop: !_locked,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: WorkspacePageScope.constraints(context, 960),
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _locked ? null : widget.onBack,
                    icon: const Icon(Icons.arrow_back),
                    label: Text(t['team_back']),
                  ),
                ),
                Text(
                  t['team_review_queue'],
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final view in [
                      TeamView.invitations,
                      TeamView.requests,
                    ])
                      OutlinedButton(
                        onPressed: _locked
                            ? null
                            : () {
                                setState(() => _view = view);
                                _load();
                              },
                        child: Text(
                          t[view == TeamView.invitations
                              ? 'team_invitations'
                              : 'team_requests'],
                        ),
                      ),
                    OutlinedButton(
                      onPressed: _locked ? null : () => _load(),
                      child: Text(t['team_refresh']),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  t[_view == TeamView.invitations
                      ? 'team_invitations'
                      : 'team_requests'],
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (_busy)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: LinearProgressIndicator(
                      semanticsLabel: t['team_loading'],
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Semantics(liveRegion: true, child: Text(t[_error!])),
                  ),
                if (_operation != null && !_busy)
                  WsActions(
                    children: [
                      FilledButton(
                        onPressed: () => _run(),
                        child: Text(t['team_retry_save']),
                      ),
                    ],
                  ),
                if (_request != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    '${t['team_request_from']}: ${_request!['displayName'] ?? ''}',
                  ),
                  Text(_request!['email'] as String? ?? ''),
                  Text(t['team_choose_staff']),
                  if (!_busy && _staff.isEmpty)
                    Text(t['team_no_eligible_staff']),
                  for (final profile in _staff)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: OutlinedButton(
                        onPressed: _locked
                            ? null
                            : () => setState(() => _profile = profile),
                        child: Text(
                          '${profile['displayName']} • ${profile['code']}',
                        ),
                      ),
                    ),
                ] else if (!_denied) ...[
                  if (!_busy && _records.isEmpty && _error == null)
                    Text(t['team_queue_empty']),
                  for (final record in _records)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (record['displayName'] != null)
                              Text(
                                record['displayName'] as String,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            Text(record['email'] as String? ?? ''),
                            Text(t['team_status_${record['status']}']),
                            if (_view == TeamView.invitations) ...[
                              SelectableText(
                                '${t['team_invite_reference']}: ${record['id']}',
                              ),
                              Text(
                                '${t['team_role']}: ${teamRoleLabel(t, (record['access'] as Map?)?['role'], (record['access'] as Map?)?['roleName'])}',
                              ),
                              // Gmail pre-approvals (R2) wait until the first sign-in.
                              // Only a pending one is waiting; accepted/revoked show no wait line.
                              if (record['status'] == 'pending')
                                Text(
                                  record['expiresAt'] == null
                                      ? t['team_waiting_first_sign_in']
                                      : '${t['team_expires']}: ${teamDate(record['expiresAt'], t)}',
                                ),
                              if (record['canRevoke'] == true)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      OutlinedButton(
                                        key: ValueKey(
                                          'invitation-email-${record['id']}',
                                        ),
                                        onPressed: _locked
                                            ? null
                                            : () => _changeEmail(record),
                                        child: Text(t['team_change_gmail']),
                                      ),
                                      OutlinedButton(
                                        onPressed: _locked
                                            ? null
                                            : () => _run(
                                                TeamAction.revokeInvitation,
                                                {'invitationId': record['id']},
                                              ),
                                        child: Text(
                                          t['team_revoke_invitation'],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ] else if (record['canReview'] == true)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    FilledButton(
                                      onPressed: _locked
                                          ? null
                                          : () => _chooseStaff(record),
                                      child: Text(t['team_review_request']),
                                    ),
                                    OutlinedButton(
                                      onPressed: _locked
                                          ? null
                                          : () =>
                                                _run(TeamAction.reviewRequest, {
                                                  'requestId': record['id'],
                                                  'decision': 'reject',
                                                }),
                                      child: Text(t['team_reject_request']),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (_cursor != null)
                    WsActions(
                      children: [
                        OutlinedButton(
                          onPressed: _locked ? null : () => _load(more: true),
                          child: Text(t['team_queue_more']),
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
