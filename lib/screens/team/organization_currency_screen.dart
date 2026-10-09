import '../../services/organization_money.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';

class OrganizationCurrencyScreen extends StatefulWidget {
  final String organizationId;
  final TeamService service;
  final VoidCallback onChanged;
  const OrganizationCurrencyScreen({
    super.key,
    required this.organizationId,
    required this.service,
    required this.onChanged,
  });
  @override
  State<OrganizationCurrencyScreen> createState() =>
      _OrganizationCurrencyScreenState();
}

class _OrganizationCurrencyScreenState
    extends State<OrganizationCurrencyScreen> {
  String _currency = 'VND';
  int? _revision;
  int _generation = 0;
  bool _busy = true, _canChange = false;
  String? _message;
  Map<String, dynamic>? _pending;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant OrganizationCurrencyScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.service != widget.service) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _canChange = false;
      _revision = null;
      _pending = null;
      _message = null;
    });
    try {
      final data = await widget.service.organizationCurrency({
        'action': 'readCurrency',
        'organizationId': widget.organizationId,
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        _currency = data['currency'] as String;
        _revision = data['revision'] as int;
        _canChange = data['canChange'] == true;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _message = 'organization_currency_error');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || !_canChange || _revision == null) return;
    final generation = _generation;
    _pending ??= {
      'action': 'updateCurrency',
      'organizationId': widget.organizationId,
      'operationId': const Uuid().v4(),
      'revision': _revision,
      'currency': _currency,
    };
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final data = await widget.service.organizationCurrency(_pending!);
      if (!mounted || generation != _generation) return;
      setState(() {
        _currency = data['currency'] as String;
        _revision = data['revision'] as int;
        _pending = null;
        _message = 'organization_currency_saved';
      });
      OrganizationMoney.shared.select(widget.organizationId, _currency);
      widget.onChanged();
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        if (e is FirebaseFunctionsException &&
            [
              'permission-denied',
              'unauthenticated',
              'aborted',
              'invalid-argument',
              'already-exists',
            ].contains(e.code)) {
          _canChange = false;
          _revision = null;
          _pending = null;
          _message = e.code == 'aborted'
              ? 'organization_currency_conflict'
              : 'organization_currency_error';
        } else {
          _message = 'organization_currency_retry';
        }
      });
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t['organization_currency_help']),
        const SizedBox(height: 16),
        ListenableBuilder(
          listenable: OrganizationMoney.shared,
          builder: (context, _) {
            final money = OrganizationMoney.shared;
            final snapshot = money.forOrganization(widget.organizationId);
            final loading = money.isLoading(widget.organizationId);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (loading) const LinearProgressIndicator(),
                if (money.refreshFailed(widget.organizationId))
                  Text(t['rates_offline']),
                if (snapshot?.date != null)
                  Text('${t['reference_rates']} ${snapshot!.date} · Frankfurter'),
                OutlinedButton.icon(
                  onPressed: loading ? null : () async {
                    try {
                      await money.load(widget.organizationId, widget.service);
                    } catch (_) {
                      // The shared state exposes the failure with a retry.
                    }
                  },
                  icon: const Icon(Icons.currency_exchange),
                  label: Text(t['refresh_rates']),
                ),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_revision != null) ...[
          DropdownButtonFormField<String>(
            key: ValueKey('organization-currency-$_currency'),
            initialValue: _currency,
            isExpanded: true,
            items: const [
              'VND',
              'USD',
            ].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: _busy || !_canChange || _pending != null
                ? null
                : (v) => setState(() => _currency = v!),
          ),
          const SizedBox(height: 16),
          if (!_canChange) Text(t['organization_currency_readonly']),
          if (_canChange)
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(t['organization_currency_save']),
            ),
        ],
        if (_message != null) ...[
          const SizedBox(height: 16),
          Text(t[_message!]),
        ],
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: _busy ? null : _load,
          child: Text(t['organization_currency_reload']),
        ),
      ],
    );
  }
}
