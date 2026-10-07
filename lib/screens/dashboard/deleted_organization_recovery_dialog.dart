import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';

class DeletedOrganizationRecoveryDialog extends StatefulWidget {
  final TeamTransport transport;
  const DeletedOrganizationRecoveryDialog({super.key, required this.transport});
  @override
  State<DeletedOrganizationRecoveryDialog> createState() => _RecoveryState();
}

class _RecoveryState extends State<DeletedOrganizationRecoveryDialog> {
  List<Map<String, dynamic>>? _rows;
  String? _error, _pending;
  final _operations = <String, String>{};
  bool _busy = false, _changed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  String message(Object e) {
    final key = e is FirebaseFunctionsException ? e.message : null;
    return const {
          'org_restore_expired',
          'org_merge_changed',
          'org_merge_owner_only',
          'org_merge_version_review',
          'org_merge_access_review',
          'org_merge_drive_review',
          'org_merge_cross_link',
          'org_merge_maintenance_required',
          'account_deletion_in_progress',
          'request_rate_limited',
        }.contains(key)
        ? key!
        : 'org_recovery_error';
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.transport('mergeMyOrganizations', {
        'action': 'recoveryList',
      });
      if (mounted)
        setState(
          () => _rows = (result['organizations'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
        );
    } catch (e) {
      if (mounted) setState(() => _error = message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(Map<String, dynamic> row) async {
    final t = AppTranslations.of(context), id = row['id'] as String;
    if (_busy) return;
    if (_pending == null) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          title: Text('${t['org_recovery_confirm']}: ${row['name']}'),
          content: Text(t['org_recovery_explanation']),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t['cancel']),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t['org_recovery_action']),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _pending = id;
      _error = null;
    });
    final operation = _operations.putIfAbsent(id, () => const Uuid().v4());
    try {
      await widget.transport('mergeMyOrganizations', {
        'action': 'recover',
        'sourceOrganizationId': id,
        'operationId': operation,
      });
      if (!mounted) return;
      setState(() {
        _changed = true;
        _pending = null;
      });
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        title: Text(t['org_recovery_title']),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t['org_recovery_explanation']),
              if (_changed) Padding(padding: const EdgeInsets.only(top: 16), child: Text(t['org_recovery_success'])),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(),
                ),
              if (_rows?.isEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(t['org_recovery_empty']),
                ),
              for (final row in _rows ?? <Map<String, dynamic>>[])
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        row['name'] as String,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${t['org_recovery_deadline']}: ${DateFormat.yMd(t.locale.toLanguageTag()).add_Hm().format(DateTime.parse(row['deleteAt'] as String).toLocal())}',
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: FilledButton(
                          onPressed:
                              _busy ||
                                  (_pending != null && _pending != row['id'])
                              ? null
                              : () => _restore(row),
                          child: Text(
                            t[_pending == row['id']
                                ? 'team_refresh'
                                : 'org_recovery_action'],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_error != null) Text(t[_error!]),
              if (_rows == null && !_busy)
                OutlinedButton(
                  onPressed: _load,
                  child: Text(t['team_refresh']),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, _changed),
            child: Text(t['close']),
          ),
        ],
      ),
    );
  }
}
