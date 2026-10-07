import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';

/// Explicit naming/confirmation, with the same operation retained across retries.
class OrganizationMergeDialog extends StatefulWidget {
  final TeamTransport transport;
  const OrganizationMergeDialog({super.key, required this.transport});
  @override
  State<OrganizationMergeDialog> createState() =>
      _OrganizationMergeDialogState();
}

class _OrganizationMergeDialogState extends State<OrganizationMergeDialog> {
  final _name = TextEditingController();
  final _operation = const Uuid().v4();
  List<Map<String, dynamic>>? _organizations;
  final _included = <String>{};
  bool _confirmDelete = false;
  bool _busy = false;
  String? _error, _submittedName;
  @override
  void initState() {
    super.initState();
    _preview();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String _message(Object e) {
    final key = e is FirebaseFunctionsException ? e.message : null;
    return const {
          'org_merge_not_needed',
          'org_merge_owner_only',
          'org_merge_version_review',
          'org_merge_access_review',
          'org_merge_drive_review',
          'org_merge_cross_link',
          'org_merge_maintenance_required',
          'org_merge_changed',
          'org_merge_delete_confirmation',
          'org_operation_reused',
          'account_deletion_in_progress',
          'request_rate_limited',
        }.contains(key)
        ? key!
        : 'org_merge_error';
  }

  Future<void> _preview() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await widget.transport('mergeMyOrganizations', {
        'action': 'preview',
      });
      if (mounted)
        setState(() {
          _organizations = (p['organizations'] as List)
              .map((o) => Map<String, dynamic>.from(o as Map))
              .toList();
          _included.addAll(_organizations!.map((o) => o['id'] as String));
        });
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _merge() async {
    if (_busy ||
        _name.text.trim().isEmpty ||
        _included.isEmpty ||
        (_included.length < _organizations!.length && !_confirmDelete))
      return;
    setState(() {
      _busy = true;
      _error = null;
    });
    _submittedName ??= _name.text.trim();
    try {
      await widget.transport('mergeMyOrganizations', {
        'action': 'merge',
        'name': _submittedName,
        'operationId': _operation,
        'organizationIds': _organizations!.map((o) => o['id']).toList(),
        'mergeIds': _included.toList()..sort(),
        'confirmDelete': _confirmDelete,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final selected =
        _organizations?.where((o) => _included.contains(o['id'])).toList() ??
        [];
    final storedDrive = selected
        .where((o) => o['driveConnection'] == true)
        .toList();
    final settingsSource = selected.isEmpty
        ? null
        : (storedDrive.isNotEmpty ? storedDrive.first : selected.first);
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 528),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        t['org_merge_title'],
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: t['org_merge_later'],
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(t['org_merge_explanation']),
                if (_organizations != null) ...[
                  const SizedBox(height: 12),
                  if (settingsSource != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '${t['org_merge_settings_source']}: ${settingsSource['name']}',
                      ),
                    ),
                  for (final org in _organizations!)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(org['name'] as String? ?? ''),
                      subtitle: Text(
                        t[_included.contains(org['id'])
                            ? 'org_merge_keep'
                            : 'org_merge_delete'],
                      ),
                      value: _included.contains(org['id']),
                      onChanged: _busy || _submittedName != null
                          ? null
                          : (value) => setState(() {
                              if (value == true) {
                                _included.add(org['id'] as String);
                              } else {
                                _included.remove(org['id']);
                              }
                              _confirmDelete = false;
                            }),
                    ),
                  if (_included.length < _organizations!.length) ...[
                    Text(t['org_merge_delete_warning']),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(t['org_merge_delete_accept']),
                      value: _confirmDelete,
                      onChanged: _busy || _submittedName != null
                          ? null
                          : (value) =>
                                setState(() => _confirmDelete = value == true),
                    ),
                  ],
                  if (_included.isEmpty) Text(t['org_merge_choose_one']),
                  Text(t['org_merge_name']),
                  const SizedBox(height: 8),
                  Semantics(
                    label: t['org_merge_name'],
                    child: TextField(
                      controller: _name,
                      enabled: !_busy && _submittedName == null,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (_error != null) Text(t[_error!]),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: Text(t['org_merge_later']),
                    ),
                    if (_organizations == null && !_busy)
                      OutlinedButton(
                        onPressed: _preview,
                        child: Text(t['staff_refresh']),
                      ),
                    if (_organizations != null)
                      FilledButton(
                        style: _included.length < _organizations!.length
                            ? FilledButton.styleFrom(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.error,
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.onError,
                              )
                            : null,
                        onPressed:
                            _busy ||
                                _name.text.trim().isEmpty ||
                                _included.isEmpty ||
                                (_included.length < _organizations!.length &&
                                    !_confirmDelete)
                            ? null
                            : _merge,
                        child: Text(
                          t[_included.length < _organizations!.length
                              ? 'org_merge_apply'
                              : 'org_merge_confirm'],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
