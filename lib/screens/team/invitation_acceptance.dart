import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../../models/team_access.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'team_display.dart';

class InvitationEntryButton extends StatelessWidget {
  final TeamService service;
  final VoidCallback onReturn;
  const InvitationEntryButton({
    super.key,
    required this.service,
    required this.onReturn,
  });
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: OutlinedButton.icon(
      icon: const Icon(Icons.mail_outline),
      label: Text(AppTranslations.of(context)['team_accept_invitation']),
      onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (routeContext) => Scaffold(
              body: InvitationAcceptance(
                service: service,
                onBack: () => Navigator.of(routeContext).pop(),
              ),
            ),
          ),
        );
        if (context.mounted) onReturn();
      },
    ),
  );
}

class InvitationAcceptance extends StatefulWidget {
  final TeamService service;
  final VoidCallback onBack;
  const InvitationAcceptance({
    super.key,
    required this.service,
    required this.onBack,
  });
  @override
  State<InvitationAcceptance> createState() => _InvitationAcceptanceState();
}

class _InvitationAcceptanceState extends State<InvitationAcceptance> {
  final _reference = TextEditingController();
  final _scroll = ScrollController();
  Map<String, dynamic>? _preview;
  TeamOperation? _operation;
  bool _busy = false, _accepted = false;
  String? _error;
  bool get _locked => _busy || _operation != null;
  @override
  void dispose() {
    _reference.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    setState(() {
      _busy = true;
      _preview = null;
      _error = null;
    });
    try {
      final preview = await widget.service.invitation(_reference.text);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _busy = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'team_lookup_failed';
        });
      }
    }
  }

  Future<void> _accept() async {
    if (_busy || _preview == null) return;
    _operation ??= widget.service.prepare(
      _preview!['organizationId'] as String,
      TeamAction.acceptInvitation,
      {'invitationId': _preview!['invitationId']},
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.execute(_operation!);
      if (!mounted) return;
      setState(() {
        _operation = null;
        _preview = null;
        _busy = false;
        _accepted = true;
      });
    } catch (error) {
      if (!mounted) return;
      final rejected =
          error is FirebaseFunctionsException &&
          [
            'invalid-argument',
            'failed-precondition',
            'not-found',
            'already-exists',
            'permission-denied',
            'unauthenticated',
          ].contains(error.code);
      setState(() {
        _busy = false;
        _error = rejected ? 'team_accept_failed' : 'team_save_uncertain';
        if (rejected) {
          _operation = null;
          _preview = null;
        }
      });
    }
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final preview = _preview;
    final access = TeamAccess.fromMap({
      ...Map<String, dynamic>.from(preview?['access'] as Map? ?? {}),
      'status': 'active',
    });
    final properties = (preview?['properties'] as List? ?? []).cast<Map>();
    return PopScope(
      canPop: !_locked,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _locked ? null : widget.onBack,
                      icon: const Icon(Icons.arrow_back),
                      label: Text(t['team_back_dashboard']),
                    ),
                  ),
                  Text(
                    t['team_accept_invitation'],
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(t['team_accept_note']),
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
                      child: Semantics(
                        liveRegion: true,
                        child: Text(t[_error!]),
                      ),
                    ),
                  if (_accepted) ...[
                    const SizedBox(height: 24),
                    Text(t['team_invitation_accepted']),
                    FilledButton(
                      onPressed: widget.onBack,
                      child: Text(t['team_done']),
                    ),
                  ] else ...[
                    const SizedBox(height: 20),
                    TextField(
                      key: const ValueKey('invitation-reference'),
                      controller: _reference,
                      readOnly: _locked,
                      maxLength: 128,
                      onChanged: (_) => setState(() {
                        _preview = null;
                        _error = null;
                      }),
                      decoration: InputDecoration(
                        labelText: t['team_invite_reference'],
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _locked ? null : _lookup,
                      child: Text(t['team_preview_invitation']),
                    ),
                    if (preview != null) ...[
                      const SizedBox(height: 24),
                      Text(
                        preview['organizationName'] as String? ?? '',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        '${t['team_role']}: ${t['team_role_${access.role?.name}']}',
                      ),
                      Text(t['team_status_${preview['status']}']),
                      Text(
                        '${t['team_expires']}: ${teamDate(preview['expiresAt'], t)}',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        t[access.allBuildings
                            ? 'team_all_properties'
                            : 'team_selected_properties'],
                      ),
                      if (access.allBuildings)
                        Text(t['team_future_properties'])
                      else if (access.buildingIds.isEmpty)
                        Text(t['team_no_properties_note'])
                      else ...[
                        for (final id in access.buildingIds)
                          Text(
                            properties
                                        .where((p) => p['id'] == id)
                                        .firstOrNull?['name']
                                    as String? ??
                                t['team_property_unavailable'],
                          ),
                      ],
                      const SizedBox(height: 16),
                      for (final permission in TeamAccess.overridable)
                        Text(
                          '${t['team_permission_${permission.name}']}: ${t[access.allows(permission) ? 'team_override_allow' : 'team_override_deny']}',
                        ),
                      const SizedBox(height: 24),
                      if (preview['canAccept'] == true)
                        FilledButton(
                          onPressed: _busy ? null : _accept,
                          child: Text(
                            t[_operation != null
                                ? 'team_retry_save'
                                : 'team_accept_invitation'],
                          ),
                        )
                      else
                        Text(t['team_invitation_closed']),
                    ],
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
