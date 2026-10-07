import 'workspace_page_scope.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';

/// Edits employment information only. The server owns account linkage and access.
class StaffEditor extends StatefulWidget {
  final String organizationId;
  final TeamService service;
  final Map<String, dynamic>? profile;
  final VoidCallback onSaved, onCancel, onAccessDenied;
  const StaffEditor({
    super.key,
    required this.organizationId,
    required this.service,
    this.profile,
    required this.onSaved,
    required this.onCancel,
    required this.onAccessDenied,
  });

  @override
  State<StaffEditor> createState() => _StaffEditorState();
}

class _StaffEditorState extends State<StaffEditor> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  late final Map<String, TextEditingController> _fields;
  late bool _active;
  bool _saving = false;
  String? _error;
  TeamOperation? _operation;
  bool get _locked => _saving || _operation != null;

  @override
  void initState() {
    super.initState();
    _fields = {
      for (final key in ['displayName', 'code', 'email', 'phone'])
        key: TextEditingController(text: widget.profile?[key] as String? ?? ''),
    };
    _active =
        widget.profile == null ||
        widget.profile!['employmentStatus'] == 'active';
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _showFeedback() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_operation == null) {
      if (!_form.currentState!.validate()) {
        _showFeedback();
        return;
      }
      _operation = widget.service.prepare(
        widget.organizationId,
        TeamAction.saveStaff,
        {
          if (widget.profile != null) 'staffId': widget.profile!['id'],
          'profile': {
            for (final field in _fields.entries)
              field.key: field.value.text.trim(),
            'employmentStatus': _active ? 'active' : 'inactive',
            // Preserve the existing optional color; this form does not edit it.
            'color': widget.profile?['color'] ?? '',
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
      await widget.service.execute(_operation!);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _operation = null;
      });
      widget.onSaved();
    } catch (error) {
      if (!mounted) return;
      var message = 'team_save_uncertain';
      if (error is FirebaseFunctionsException) {
        if (error.code == 'unauthenticated' ||
            (error.code == 'permission-denied' &&
                error.message != 'team_role_protected')) {
          setState(() {
            _saving = false;
            _operation = null;
          });
          widget.onAccessDenied();
          return;
        }
        // Only explicit server rejections unlock the draft. Transport failures
        // retain the exact immutable operation for an idempotent retry.
        if ([
          'invalid-argument',
          'already-exists',
          'failed-precondition',
          'not-found',
          'permission-denied',
        ].contains(error.code)) {
          _operation = null;
          message = switch (error.message) {
            'team_staff_code_exists' => 'team_code_exists',
            'team_role_protected' => 'team_profile_protected',
            'team_record_not_found' => 'team_profile_missing',
            _ => 'team_save_rejected',
          };
        }
      }
      setState(() {
        _saving = false;
        _error = message;
      });
      _showFeedback();
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
                      t[widget.profile == null
                          ? 'team_add_staff'
                          : 'team_edit_staff'],
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(t['team_profile_only']),
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
                    if (_saving)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: LinearProgressIndicator(
                          semanticsLabel: t['team_saving'],
                        ),
                      ),
                    for (final field in _fields.entries)
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: TextFormField(
                          key: ValueKey('staff-${field.key}'),
                          controller: field.value,
                          readOnly: _locked,
                          maxLength: switch (field.key) {
                            'displayName' => 120,
                            'email' => 254,
                            _ => 40,
                          },
                          keyboardType: field.key == 'email'
                              ? TextInputType.emailAddress
                              : field.key == 'phone'
                              ? TextInputType.phone
                              : TextInputType.text,
                          decoration: InputDecoration(
                            labelText: t['team_${field.key}'],
                            errorMaxLines: 4,
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (['displayName', 'code'].contains(field.key) &&
                                text.isEmpty) {
                              return t['team_required'];
                            }
                            if (field.key == 'email' &&
                                text.isNotEmpty &&
                                !RegExp(
                                  r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                ).hasMatch(text)) {
                              return t['team_invalid_email'];
                            }
                            return null;
                          },
                        ),
                      ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(t['team_employed']),
                      value: _active,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: _locked
                          ? null
                          : (value) => setState(() => _active = value!),
                    ),
                    Text(t['team_employment_note']),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          child: Text(
                            t[_saving
                                ? 'team_saving'
                                : _operation != null
                                ? 'team_retry_save'
                                : 'team_save_profile'],
                          ),
                        ),
                        OutlinedButton(
                          onPressed: _locked ? null : widget.onCancel,
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
