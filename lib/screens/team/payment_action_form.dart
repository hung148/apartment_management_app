import 'workspace_page_scope.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'ws_ui.dart';
import '../../services/payment_command_service.dart';
import '../../utils/app_number.dart';
import '../../utils/localizations/app_localizations.dart';
import 'team_display.dart';

class PaymentActionForm extends StatefulWidget {
  final String organizationId, accountId;
  final Map<String, dynamic> invoice;
  final PaymentCommandService service;
  final PaymentJournal journal;
  final VoidCallback onBack, onDenied;
  PaymentActionForm({
    super.key,
    required this.organizationId,
    required this.accountId,
    required this.invoice,
    required this.service,
    required this.onBack,
    required this.onDenied,
    PaymentJournal? journal,
  }) : journal = journal ?? PaymentJournal();
  @override
  State<PaymentActionForm> createState() => _PaymentActionFormState();
}

class _PaymentActionFormState extends State<PaymentActionForm> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController(), _reason = TextEditingController();
  PaymentOperation? _pending;
  Map<String, dynamic>? _result;
  bool _loading = true, _saving = false, _storageFailed = false;
  String _action = 'collect', _method = 'cash';
  String? _message;
  late final String _key;
  bool get _locked =>
      _loading ||
      _saving ||
      _pending != null ||
      _result != null ||
      _storageFailed;
  @override
  void initState() {
    super.initState();
    _action = widget.invoice['canCollect'] == true ? 'collect' : 'refund';
    _key = widget.journal.key(
      widget.accountId,
      widget.organizationId,
      widget.invoice['id'] as String,
    );
    _restore();
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      if (widget.accountId.isEmpty) throw StateError('No account identity');
      final pending = await widget.journal.load(_key);
      if (!mounted) return;
      if (pending != null) {
        final data = pending.payload;
        if (data['organizationId'] != widget.organizationId ||
            data['paymentId'] != widget.invoice['id'] ||
            !['collect', 'refund'].contains(data['action']) ||
            data['amountMinor'] is! int) {
          throw const FormatException('Mismatched payment');
        }
        _pending = pending;
        _action = data['action'] as String;
        _method = data['paymentMethod'] as String? ?? 'cash';
        _reason.text = data['reason'] as String? ?? '';
        _amount.text = appMoneyInputText(
          data['amountMinor'] as int,
          '${widget.invoice['currency']}',
        );
        _message = 'payment_action_uncertain';
      }
      setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _storageFailed = true;
          _message = 'payment_action_storage';
        });
      }
    }
  }

  int? _minor() {
    final minor = appParseMoney(_amount.text, '${widget.invoice['currency']}');
    return minor != null && minor > 0 ? minor : null;
  }

  Future<void> _submit() async {
    if (_loading || _saving || _storageFailed || _result != null) return;
    if (_pending == null) {
      if (!_form.currentState!.validate()) return;
      if (_action == 'collect' && widget.invoice['canCollect'] != true ||
          _action == 'refund' && widget.invoice['canRefund'] != true) {
        return;
      }
      _pending = _action == 'collect'
          ? widget.service.collect(
              organizationId: widget.organizationId,
              paymentId: widget.invoice['id'] as String,
              amountMinor: _minor()!,
              paymentMethod: _method,
            )
          : widget.service.refund(
              organizationId: widget.organizationId,
              paymentId: widget.invoice['id'] as String,
              amountMinor: _minor()!,
              reason: _reason.text.trim(),
            );
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      // This must succeed before the first network attempt or any retry.
      await widget.journal.save(_key, _pending!);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _message = 'payment_action_storage';
        });
      }
      return;
    }
    try {
      final result = await widget.service.execute(_pending!);
      // Clear only after confirmed success. A failed clear keeps the same token.
      try {
        await widget.journal.clear(_key);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _result = result;
        _saving = false;
        _message = 'payment_action_success';
      });
    } catch (error) {
      if (!mounted) return;
      if (error is FirebaseFunctionsException &&
          ['permission-denied', 'unauthenticated'].contains(error.code)) {
        setState(() {
          _saving = false;
          _storageFailed = true;
          _message = 'team_denied';
        });
        widget.onDenied();
        return;
      }
      var message = 'payment_action_uncertain';
      if (error is FirebaseFunctionsException &&
          [
            'invalid-argument',
            'failed-precondition',
            'not-found',
            'already-exists',
          ].contains(error.code)) {
        try {
          await widget.journal.clear(_key);
          _pending = null;
          message = 'payment_action_rejected';
        } catch (_) {
          message = 'payment_action_storage';
        }
      }
      if (mounted) {
        setState(() {
          _saving = false;
          _message = message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final methods = [
      'cash',
      'bankTransfer',
      'momo',
      'zalopay',
      'creditCard',
      'other',
    ];
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: WorkspacePageScope.constraints(context, 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t['payment_action_title'],
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    '${t['payment_action_invoice']}: ${widget.invoice['id']}',
                  ),
                  Text(
                    '${t['workspace_room']}: ${teamRoomLabel(widget.invoice)}',
                  ),
                  Text(t['payment_action_note']),
                  if (_loading || _saving) const LinearProgressIndicator(),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(t[_message!]),
                      ),
                    ),
                  if (_result != null) ...[
                    Text(
                      '${t['payment_action_reference']}: ${_result!['operationId']}',
                    ),
                    Text(
                      '${t['payment_action_time']}: ${_result!['recordedAt']}',
                    ),
                  ],
                  DropdownButtonFormField<String>(
                    key: ValueKey('payment-action-$_action'),
                    initialValue: _action,
                    isExpanded: true,
                    itemHeight: null,
                    decoration: InputDecoration(
                      labelText: t['payment_action_type'],
                    ),
                    items: [
                      for (final action in ['collect', 'refund'])
                        if (_pending != null && action == _action ||
                            widget.invoice[action == 'collect'
                                    ? 'canCollect'
                                    : 'canRefund'] ==
                                true)
                          DropdownMenuItem(
                            value: action,
                            child: Text(t['payment_action_$action']),
                          ),
                    ],
                    onChanged: _locked
                        ? null
                        : (v) => setState(() => _action = v!),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('payment-amount'),
                    controller: _amount,
                    readOnly: _locked,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: appMoneyInput(
                      '${widget.invoice['currency']}',
                    ),
                    decoration: InputDecoration(
                      labelText:
                          '${t['workspace_amount']} (${widget.invoice['currency']})',
                    ),
                    validator: (_) => _minor() == null
                        ? t['payment_action_invalid_amount']
                        : null,
                  ),
                  Text(t['payment_action_decimal']),
                  const SizedBox(height: 16),
                  if (_action == 'collect')
                    DropdownButtonFormField<String>(
                      initialValue: _method,
                      isExpanded: true,
                      itemHeight: null,
                      decoration: InputDecoration(
                        labelText: t['payment_action_method'],
                      ),
                      items: [
                        for (final method in methods)
                          DropdownMenuItem(
                            value: method,
                            child: Text(t['payment_action_method_$method']),
                          ),
                      ],
                      onChanged: _locked
                          ? null
                          : (v) => setState(() => _method = v!),
                    ),
                  if (_action == 'refund')
                    TextFormField(
                      key: const ValueKey('payment-reason'),
                      controller: _reason,
                      readOnly: _locked,
                      minLines: 2,
                      maxLines: 5,
                      maxLength: 500,
                      decoration: InputDecoration(
                        labelText: t['activity_reason'],
                      ),
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? t['payment_action_reason_required']
                          : null,
                    ),
                  const SizedBox(height: 16),
                  if (_result == null)
                    WsActions(
                      children: [
                        FilledButton(
                          onPressed: _loading || _saving || _storageFailed
                              ? null
                              : _submit,
                          child: Text(
                            t[_pending == null
                                ? 'payment_action_confirm'
                                : 'payment_action_retry'],
                          ),
                        ),
                      ],
                    ),
                  TextButton(
                    onPressed: _saving ? null : widget.onBack,
                    child: Text(t['payment_action_back']),
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
