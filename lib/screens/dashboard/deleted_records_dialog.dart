import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'deleted_organization_recovery_dialog.dart';

class DeletedRecordsDialog extends StatefulWidget {
  final String organizationId;
  final TeamTransport transport;
  final bool canRecoverOrganization;
  const DeletedRecordsDialog({
    super.key,
    required this.organizationId,
    required this.transport,
    this.canRecoverOrganization = false,
  });
  @override
  State<DeletedRecordsDialog> createState() => _RecordsState();
}

class _RecordsState extends State<DeletedRecordsDialog> {
  List<Map<String, dynamic>>? rows;
  bool busy = false, active = false, changed = false;
  String? error, pending;
  final operations = <String, String>{};
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await widget.transport('deletedRecords', {
        'action': active ? 'inventory' : 'list',
        'organizationId': widget.organizationId,
      });
      if (mounted)
        setState(
          () => rows = (r['records'] as List)
              .map((x) => Map<String, dynamic>.from(x as Map))
              .toList(),
        );
    } catch (e) {
      if (mounted) setState(() {
        if (e is FirebaseFunctionsException && e.code == 'permission-denied') {
          rows=null;pending=null;error='record_recovery_denied';
        } else {error='record_recovery_error';}
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> act(Map<String, dynamic> row) async {
    final t = AppTranslations.of(context),
        key = '${active ? 'delete' : 'restore'}:${row['id']}';
    if (pending == null) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          title: Text(row['name'] as String),
          content: Text(
            t[active ? 'record_delete_confirm' : 'record_restore_confirm'],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t['cancel']),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t[active ? 'delete' : 'record_restore']),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    setState(() {
      busy = true;
      pending = key;
      error = null;
    });
    try {
      await widget.transport('deletedRecords', {
        'action': active ? 'delete' : 'restore',
        'organizationId': widget.organizationId,
        if (active) ...{
          'type': row['type'],
          'recordId': row['id'],
          if (['buildings', 'rooms'].contains(row['type'])) ...{
            'buildingId': row['buildingId'],
            'revision': row['revision'],
          },
        } else
          'deletedRecordId': row['id'],
        'operationId': operations.putIfAbsent(key, () => const Uuid().v4()),
      });
      if (!mounted) return;
      operations.remove(key);
      setState(() {
        pending = null;
        changed = true;
      });
      await load();
    } catch (e) {
      if (mounted && e is FirebaseFunctionsException && e.code == 'permission-denied') {
        setState(() {rows=null;pending=null;});
      }
      if (mounted && e is FirebaseFunctionsException && ['failed-precondition','aborted','invalid-argument'].contains(e.code)) {
        operations.remove(key);setState(() {pending=null;if(e.code=='aborted')rows=null;});
      }
      if (mounted)
        setState(
          () => error =
              e is FirebaseFunctionsException &&
                  const {
                    'record_recovery_denied',
                    'record_recovery_financial',
                    'record_recovery_dependencies',
                    'record_recovery_review',
                    'record_recovery_parent',
                    'record_recovery_collision',
                    'record_recovery_overlap',
                    'record_recovery_use_details',
                    'org_restore_expired',
                    'room_not_empty',
                    'property_not_empty',
                    'property_has_assignments',
                  }.contains(e.message)
              ? e.message
              : e is FirebaseFunctionsException && e.code=='permission-denied' ? 'record_recovery_denied'
              : e is FirebaseFunctionsException && e.code=='aborted' ? 'record_recovery_changed' : 'record_recovery_error',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        scrollable: true,
        title: Text(t['record_recovery_title']),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t['record_recovery_explanation']),
              if (widget.canRecoverOrganization)
                OutlinedButton(
                  onPressed: busy || pending != null
                      ? null
                      : () async {
                          final restored = await showDialog<bool>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => DeletedOrganizationRecoveryDialog(
                              transport: widget.transport,
                            ),
                          );
                          if (restored == true && mounted) {
                            setState(() => changed = true);
                            load();
                          }
                        },
                  child: Text(t['org_recovery_sources']),
                ),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(t['record_deleted']),
                    selected: !active,
                    onSelected: busy || pending != null
                        ? null
                        : (_) {
                            setState(() => active = false);
                            load();
                          },
                  ),
                  ChoiceChip(
                    label: Text(t['record_delete_records']),
                    selected: active,
                    onSelected: busy || pending != null
                        ? null
                        : (_) {
                            setState(() => active = true);
                            load();
                          },
                  ),
                ],
              ),
              if (busy) const LinearProgressIndicator(),
              if (rows?.isEmpty == true) Text(t['record_recovery_empty']),
              for (final row in rows ?? <Map<String, dynamic>>[])
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        row['name'] as String,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(t['record_type_${row['type']}']),
                      if (row['context'] is String && (row['context'] as String).isNotEmpty) Text(row['context'] as String),
                      if (row['deleteAt'] != null)
                        Text(
                          '${t['org_recovery_deadline']}: ${DateFormat.yMd(t.locale.toLanguageTag()).add_Hm().format(DateTime.parse(row['deleteAt'] as String).toLocal())}',
                        ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: OutlinedButton(
                          onPressed:
                              busy ||
                                  (pending != null &&
                                      pending !=
                                          '${active ? 'delete' : 'restore'}:${row['id']}')
                              ? null
                              : () => act(row),
                          child: Text(t[active ? 'delete' : 'record_restore']),
                        ),
                      ),
                    ],
                  ),
                ),
              if (error != null) Text(t[error!]),
              if (rows == null && !busy)
                OutlinedButton(onPressed: load, child: Text(t['team_refresh'])),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context, changed),
            child: Text(t['close']),
          ),
        ],
      ),
    );
  }
}
