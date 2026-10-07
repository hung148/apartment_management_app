import 'workspace_page_scope.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'ws_ui.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/app_number.dart';
import '../../utils/localizations/app_localizations.dart';
import 'property_contract_screen.dart' show contractDate;
import 'room_rates_screen.dart' show parseRoomRate;
import 'tenant_rent_history.dart';

class TenantRentScreen extends StatefulWidget {
  final String organizationId, buildingId, tenantId;
  final TeamService service;
  final VoidCallback onBack;
  const TenantRentScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.tenantId,
    required this.service,
    required this.onBack,
  });
  @override
  State<TenantRentScreen> createState() => _TenantRentScreenState();
}

class _TenantRentScreenState extends State<TenantRentScreen> {
  final _date = TextEditingController(),
      _amount = TextEditingController(),
      _reason = TextEditingController(),
      _form = GlobalKey<FormState>();
  Map<String, dynamic>? _record, _pending;
  String? _message;
  bool _busy = true, _saving = false, _cancel = false;
  bool _history = false;
  int _generation = 0;
  bool get _locked => _busy || _saving || _pending != null;
  Map<String, dynamic> get _identity => {
    'organizationId': widget.organizationId,
    'buildingId': widget.buildingId,
    'tenantId': widget.tenantId,
  };
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TenantRentScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.tenantId != widget.tenantId ||
        old.service != widget.service) {
      _pending = null;
      _saving = false;
      _history = false;
      _load();
    }
  }

  @override
  void dispose() {
    _date.dispose();
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load({bool saved = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _record = null;
      _message = null;
      _date.clear();
      _amount.clear();
      _reason.clear();
      _cancel = false;
    });
    try {
      final r = await widget.service.tenantRent({
        'action': 'read',
        ..._identity,
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        _record = Map<String, dynamic>.from(r['record'] as Map);
        _busy = false;
        _message = saved ? 'rent_plan_saved' : null;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _message = 'rent_plan_unavailable';
        });
      }
    }
  }

  Future<void> _save() async {
    if (_busy || _saving || _record == null) return;
    if (_pending == null && !_form.currentState!.validate()) return;
    _pending ??= Map.unmodifiable({
      'action': _cancel ? 'cancel' : 'schedule',
      ..._identity,
      'operationId': const Uuid().v4(),
      'revision': _record!['revision'],
      'currency': _record!['currency'],
      'timeZone': _record!['timeZone'],
      'effectiveDate': _date.text.trim(),
      'reason': _reason.text.trim(),
      if (!_cancel)
        'amountMinor': parseRoomRate(
          _amount.text,
          _record!['currency'] as String,
        ),
    });
    final generation = _generation;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await widget.service.tenantRent(Map.of(_pending!));
      if (!mounted || generation != _generation) return;
      _pending = null;
      _saving = false;
      await _load(saved: true);
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _saving = false;
        _message = 'rent_plan_uncertain';
        if (e is FirebaseFunctionsException &&
            [
              'permission-denied',
              'unauthenticated',
              'not-found',
              'aborted',
              'invalid-argument',
              'failed-precondition',
            ].contains(e.code)) {
          _pending = null;
          _record = null;
          _date.clear();
          _amount.clear();
          _reason.clear();
          _message = e.code == 'aborted'
              ? 'rent_plan_conflict'
              : 'rent_plan_unavailable';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_history) {
      return TenantRentHistory(
        organizationId: widget.organizationId,
        buildingId: widget.buildingId,
        tenantId: widget.tenantId,
        service: widget.service,
        onBack: () => setState(() => _history = false),
      );
    }
    final t = AppTranslations.of(context), r = _record;
    String money(dynamic minor) =>
        appMoneyMinor(minor as int, '${r!['currency'] ?? 'VND'}');
    Widget field(String key, String label, TextEditingController controller) =>
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label),
              const SizedBox(height: 8),
              Semantics(
                label: label,
                child: TextFormField(
                  key: ValueKey('rent-plan-$key'),
                  controller: controller,
                  enabled: !_locked,
                  maxLines: null,
                  decoration: const InputDecoration(errorMaxLines: 8),
                  validator: (value) {
                    final v = (value ?? '').trim();
                    if (key == 'date' &&
                        (!contractDate(v) ||
                            v.compareTo(r!['today'] as String) <= 0 ||
                            v.compareTo(r['startDate'] as String) < 0)) {
                      return t['rent_plan_invalid_date'];
                    }
                    if (key == 'amount' &&
                        parseRoomRate(v, r!['currency'] as String) == null) {
                      return t['lease_form_invalid_rent'];
                    }
                    if (key == 'reason' && (v.isEmpty || v.length > 1000)) {
                      return t['rent_plan_reason_required'];
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
        );
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: WorkspacePageScope.constraints(context, 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextButton(
                  onPressed: _locked ? null : widget.onBack,
                  child: Text(t['tenant_contacts_title']),
                ),
                Text(
                  t['rent_plan_title'],
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(t['rent_plan_help']),
                const SizedBox(height: 8),
                WsActions(
                  children: [
                    OutlinedButton(
                      onPressed: _locked
                          ? null
                          : () => setState(() => _history = true),
                      child: Text(t['rent_history_title']),
                    ),
                  ],
                ),
                if (_busy || _saving) const LinearProgressIndicator(),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(t[_message!]),
                    ),
                  ),
                if (r != null) ...[
                  const SizedBox(height: 12),
                  Text('${r['fullName']}'),
                  Text('${t['lease_form_timezone']}: ${r['timeZone']}'),
                  Text('${t['lease_form_today']}: ${r['today']}'),
                  Text(
                    '${t['rent_plan_current']}: ${money(r['currentMinor'])}',
                  ),
                  Text('${t['rent_plan_base']}: ${money(r['baseMinor'])}'),
                  for (final dynamic change in r['changes'] as List)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${change['effectiveDate']} — ${money(change['amountMinor'])}',
                            ),
                            Text(
                              t[(change['effectiveDate'] as String).compareTo(
                                        r['today'] as String,
                                      ) >
                                      0
                                  ? 'rent_plan_future'
                                  : 'rent_plan_effective'],
                            ),
                            if ((change['effectiveDate'] as String).compareTo(
                                  r['today'] as String,
                                ) >
                                0)
                              WsActions(
                                children: [
                                  OutlinedButton(
                                    onPressed: _locked
                                        ? null
                                        : () => setState(() {
                                            _cancel = true;
                                            _date.text =
                                                change['effectiveDate']
                                                    as String;
                                            _reason.clear();
                                          }),
                                    child: Text(t['rent_plan_choose_cancel']),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        Text(
                          t[_cancel
                              ? 'rent_plan_cancel_title'
                              : 'rent_plan_schedule_title'],
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (_cancel)
                          Text(_date.text)
                        else
                          field('date', t['rent_plan_date'], _date),
                        if (!_cancel)
                          field(
                            'amount',
                            '${t['lease_form_rent']} (${r['currency']})',
                            _amount,
                          ),
                        field('reason', t['rent_plan_reason'], _reason),
                        const SizedBox(height: 16),
                        WsActions(
                          children: [
                            FilledButton(
                              onPressed: _locked ? null : _save,
                              child: Text(
                                t[_cancel
                                    ? 'rent_plan_cancel'
                                    : 'rent_plan_save'],
                              ),
                            ),
                          ],
                        ),
                        if (_cancel)
                          TextButton(
                            onPressed: _locked
                                ? null
                                : () => setState(() {
                                    _cancel = false;
                                    _date.clear();
                                    _reason.clear();
                                  }),
                            child: Text(t['rent_plan_schedule_title']),
                          ),
                      ],
                    ),
                  ),
                ],
                if (_pending != null)
                  WsActions(
                    children: [
                      OutlinedButton(
                        onPressed: _saving ? null : _save,
                        child: Text(t['rent_plan_retry']),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                WsActions(
                  children: [
                    OutlinedButton(
                      onPressed: _locked ? null : () => _load(),
                      child: Text(t['rent_plan_reload']),
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
