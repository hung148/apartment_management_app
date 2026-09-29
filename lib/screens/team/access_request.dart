import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';

class AccessRequestScreen extends StatefulWidget {
  final TeamService service;
  final VoidCallback onBack;
  const AccessRequestScreen({
    super.key,
    required this.service,
    required this.onBack,
  });
  @override
  State<AccessRequestScreen> createState() => _AccessRequestScreenState();
}

class _AccessRequestScreenState extends State<AccessRequestScreen> {
  final _org = TextEditingController(),
      _code = TextEditingController(),
      _name = TextEditingController();
  final _scroll = ScrollController();
  TeamOperation? _operation;
  List<Map<String, dynamic>> _records = [];
  bool _busy = false;
  String? _message;
  bool get _locked => _busy || _operation != null;
  @override
  void dispose() {
    _org.dispose();
    _code.dispose();
    _name.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed(String _) => setState(() {
    _records = [];
    _message = null;
  });
  Future<void> _run(bool submit) async {
    if (_busy) return;
    final org = _org.text.trim();
    if (org.isEmpty ||
        org.contains('/') ||
        (submit && (_code.text.trim().isEmpty || _name.text.trim().isEmpty))) {
      setState(() => _message = 'team_request_required');
      if (_scroll.hasClients) _scroll.jumpTo(0);
      return;
    }
    if (submit) {
      _operation ??= widget.service.prepare(org, TeamAction.requestAccess, {
        'inviteCode': _code.text.trim(),
        'displayName': _name.text.trim(),
      });
    }
    setState(() {
      _busy = true;
      _records = [];
      _message = null;
    });
    try {
      if (submit) {
        await widget.service.execute(_operation!);
        _operation = null;
        if (!mounted) return;
        setState(() => _message = 'team_request_sent');
      }
      final rows = <Map<String, dynamic>>[];
      String? cursor;
      do {
        final page = await widget.service.page(
          org,
          TeamView.myRequests,
          cursor: cursor,
        );
        rows.addAll(page.records);
        cursor = page.nextCursor;
      } while (cursor != null);
      if (!mounted) return;
      setState(() {
        _records = rows;
        _message ??= rows.isEmpty ? 'team_request_empty' : null;
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
        if (rejected) _operation = null;
        _records = [];
        _message = _operation != null
            ? 'team_save_uncertain'
            : rejected
            ? 'team_request_rejected'
            : 'team_request_read_failed';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
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
                  Text(
                    t['team_request_access'],
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(t['team_request_help']),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(t[_message!]),
                      ),
                    ),
                  if (_busy) const LinearProgressIndicator(),
                  for (final field in <String, TextEditingController>{
                    'team_request_org': _org,
                    'team_request_code': _code,
                    'team_request_name': _name,
                  }.entries)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: TextField(
                        key: ValueKey(field.key),
                        controller: field.value,
                        readOnly: _locked,
                        onChanged: _changed,
                        maxLength: field.key == 'team_request_name' ? 120 : 128,
                        decoration: InputDecoration(labelText: t[field.key]),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : () => _run(true),
                    child: Text(
                      t[_operation == null
                          ? 'team_request_submit'
                          : 'team_retry_save'],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _locked ? null : () => _run(false),
                    child: Text(t['team_request_status']),
                  ),
                  for (final record in _records)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(record['displayName'] as String? ?? ''),
                            Text(record['email'] as String? ?? ''),
                            Text(t['team_status_${record['status']}']),
                            Text(
                              t[record['status'] == 'approved'
                                  ? 'team_request_approved_help'
                                  : record['status'] == 'rejected'
                                  ? 'team_request_denied_help'
                                  : 'team_request_pending_help'],
                            ),
                          ],
                        ),
                      ),
                    ),
                  TextButton(
                    onPressed: _locked ? null : widget.onBack,
                    child: Text(t['team_back_dashboard']),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
