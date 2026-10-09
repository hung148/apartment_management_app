import '../../utils/money_conversion.dart';
import '../../services/organization_money.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import 'back_steps.dart';
import 'service_fee_text.dart';
import 'ws_ui.dart';
import '../../utils/app_number.dart';

/// B5: the property's service fees (defaults for every room).
class ServiceFeesScreen extends StatefulWidget {
  final String organizationId, buildingId;
  final TeamService service;
  const ServiceFeesScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.service,
  });
  @override
  State<ServiceFeesScreen> createState() => _ServiceFeesScreenState();
}

class _ServiceFeesScreenState extends State<ServiceFeesScreen> {
  Map<String, dynamic>? _record;
  bool _busy = true;
  String? _error, _saved;

  /// The fee being edited; an empty map means a new fee.
  Map<String, dynamic>? _editing;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ServiceFeesScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.service != widget.service) {
      _editing = null;
      _saved = null;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.service.serviceFees({
        'action': 'read',
        'organizationId': widget.organizationId,
        'buildingId': widget.buildingId,
      });
      if (!mounted || generation != _generation) return;
      setState(
        () => _record = Map<String, dynamic>.from(data['record'] as Map),
      );
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _record = null;
        _error = FeeText(context).error(e);
      });
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  void _close({String? saved}) {
    setState(() {
      _editing = null;
      _saved = saved;
    });
    _load();
  }

  /// Dated changes after today, so nobody is surprised by them.
  List<String> _upcoming(FeeText x, Map fee, String currency) {
    final today = _record?['today'] as String?;
    if (today == null) return const [];
    return [
      for (final v in (fee['versions'] as List).cast<Map>())
        if ((v['effectiveDate'] as String).compareTo(today) > 0)
          v['active'] == true
              ? x.tr(
                  'From ${v['effectiveDate']}: ${x.rate(fee, v, currency)}',
                  'Từ ${v['effectiveDate']}: ${x.rate(fee, v, currency)}',
                )
              : x.tr(
                  'Stops from ${v['effectiveDate']}',
                  'Ngừng thu từ ${v['effectiveDate']}',
                ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final x = FeeText(context), record = _record;
    if (_editing != null && record != null) {
      return BackStep(
        onBack: () => _close(),
        child: ServiceFeeEditor(
          key: ValueKey('fee-editor-${_editing!['id'] ?? 'new'}'),
          organizationId: widget.organizationId,
          buildingId: widget.buildingId,
          service: widget.service,
          currency: record['currency'] as String? ?? 'VND',
          today: record['today'] as String?,
          revision: record['revision'] as int,
          fee: _editing!.isEmpty ? null : _editing,
          onDone: (message) => _close(saved: message),
          onCancel: () => _close(),
        ),
      );
    }
    final fees = (record?['fees'] as List? ?? const []).cast<Map>();
    final canPrice = record?['canPrice'] == true;
    final currency = record?['currency'] as String? ?? 'VND';
    return WsPage(
      children: [
        WsHeader(
          title: x.tr('Service fees', 'Phí dịch vụ'),
          help: x.tr(
            'Defaults for every room in this property. Room-only prices are set from the room list.',
            'Áp dụng cho mọi phòng của tòa nhà. Giá riêng từng phòng đặt trong danh sách phòng.',
          ),
          actions: [
            if (canPrice)
              FilledButton.icon(
                key: const ValueKey('fee-add'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _saved = null;
                        _editing = {};
                      }),
                icon: const Icon(Icons.add, size: 18),
                label: Text(x.tr('Add fee', 'Thêm phí')),
              ),
          ],
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(),
          ),
        if (_saved != null)
          Semantics(
            liveRegion: true,
            child: WsNotice(_saved!, tone: WsTone.good),
          ),
        if (_error != null) ...[
          Semantics(liveRegion: true, child: WsNotice(_error!)),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton(
              onPressed: _busy ? null : _load,
              child: Text(x.tr('Retry', 'Thử lại')),
            ),
          ),
        ],
        if (record != null && !_busy && fees.isEmpty)
          WsEmpty(
            icon: Icons.receipt_long_outlined,
            message: x.tr('No service fees yet.', 'Chưa có phí dịch vụ.'),
          ),
        for (final fee in fees)
          WsRecord(
            key: ValueKey('fee-${fee['id']}'),
            title: fee['name'] as String,
            pill: WsPill(x.basis(fee['basis'] as String), tone: WsTone.info),
            details: [
              x.terms(fee, fee['current'] as Map?, currency),
              if (fee['current'] != null && fee['basis'] != 'quantity')
                x.rule((fee['current'] as Map)['rule'] as Map?),
              ..._upcoming(x, fee, currency),
            ],
            actions: [
              if (canPrice)
                OutlinedButton(
                  key: ValueKey('fee-edit-${fee['id']}'),
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _saved = null;
                          _editing = Map<String, dynamic>.from(fee);
                        }),
                  child: Text(x.tr('Change', 'Thay đổi')),
                ),
            ],
          ),
      ],
    );
  }
}

/// New fee, or a dated change (new price, rule or stop) to an existing one.
class ServiceFeeEditor extends StatefulWidget {
  final String organizationId, buildingId, currency;
  final String? today;
  final int revision;
  final Map<String, dynamic>? fee;
  final TeamService service;
  final ValueChanged<String> onDone;
  final VoidCallback onCancel;
  const ServiceFeeEditor({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.service,
    required this.currency,
    required this.today,
    required this.revision,
    required this.fee,
    required this.onDone,
    required this.onCancel,
  });
  @override
  State<ServiceFeeEditor> createState() => _ServiceFeeEditorState();
}

class _ServiceFeeEditorState extends State<ServiceFeeEditor> {
  late final MoneyForm _money = MoneyForm(OrganizationMoney.shared.forOrganization(widget.organizationId));
  String get _inputCurrency => _money.currency(widget.currency);
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _unit = TextEditingController(),
      _date = TextEditingController(),
      _rate = TextEditingController(),
      _included = TextEditingController(text: '0'),
      _reason = TextEditingController();
  final _stepDays = <TextEditingController>[],
      _stepPercent = <TextEditingController>[];
  String _basis = 'person', _mode = 'days', _checkDay = 'first';
  bool _active = true, _busy = false;
  int _rounding = 0;

  /// Kept for an exact retry when the result of a save is unknown.
  Map<String, dynamic>? _pending;
  String? _error;

  bool get _creating => widget.fee == null;
  bool get _locked => _busy || _pending != null;
  List<int> get _roundings => _inputCurrency == 'USD'
      ? const [0, 5, 10, 50, 100]
      : const [0, 100, 500, 1000];

  @override
  void initState() {
    super.initState();
    final fee = widget.fee;
    _date.text = widget.today ?? '';
    // Start at the first date that can still change (after what was billed).
    final billed = fee?['billedThrough'] as String?;
    if (billed != null && billed.compareTo(_date.text) > 0) _date.text = billed;
    if (fee != null) {
      _name.text = fee['name'] as String;
      _unit.text = fee['unitLabel'] as String? ?? '';
      _basis = fee['basis'] as String;
      // Start from what applies now (or the latest charged version), so a
      // change is a small edit rather than retyping everything.
      final versions = (fee['versions'] as List).cast<Map>();
      final base =
          (fee['current'] as Map?) ??
          versions.lastWhere(
            (v) => v['active'] == true,
            orElse: () => const {},
          );
      if (base['rateMinor'] != null) {
        final minor = base['rateMinor'] as int;
        _money.set(_rate, minor, base['currency'] as String? ?? widget.currency);
        _included.text = '${base['includedPeople'] ?? 0}';
        final originalRounding = base['roundingMinor'] as int? ?? 0;
        final rounding = _money.conversion?.convertMinor(
          originalRounding, base['currency'] as String? ?? widget.currency,
          _inputCurrency,
        ) ?? originalRounding;
        _rounding = _roundings.contains(rounding)
            ? rounding
            : 0;
        final rule = base['rule'] as Map?;
        if (rule != null) {
          _mode = rule['mode'] as String;
          if (_mode == 'checkDate') _checkDay = rule['day'] as String;
          if (_mode == 'thresholds') {
            _setSteps([
              for (final s in (rule['steps'] as List).cast<Map>())
                [s['minDays'] as int, s['percent'] as int],
            ]);
          }
        }
      }
    }
    if (_stepDays.isEmpty) {
      _setSteps(const [
        [15, 100],
      ]);
    }
  }

  void _setSteps(List<List<int>> steps) {
    for (final c in [..._stepDays, ..._stepPercent]) {
      c.dispose();
    }
    _stepDays
      ..clear()
      ..addAll([for (final s in steps) TextEditingController(text: '${s[0]}')]);
    _stepPercent
      ..clear()
      ..addAll([for (final s in steps) TextEditingController(text: '${s[1]}')]);
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _unit,
      _date,
      _rate,
      _included,
      _reason,
      ..._stepDays,
      ..._stepPercent,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic>? _rule() {
    if (_basis == 'quantity') return null;
    if (_mode == 'days') return {'mode': 'days'};
    if (_mode == 'checkDate') return {'mode': 'checkDate', 'day': _checkDay};
    return {
      'mode': 'thresholds',
      'steps': [
        for (var i = 0; i < _stepDays.length; i++)
          {
            'minDays': int.parse(_stepDays[i].text.trim()),
            'percent': int.parse(_stepPercent[i].text.trim()),
          },
      ],
    };
  }

  String? _stepsError(FeeText x) {
    if (!_active || _basis == 'quantity' || _mode != 'thresholds') return null;
    var days = 0, percent = 0;
    for (var i = 0; i < _stepDays.length; i++) {
      final d = int.tryParse(_stepDays[i].text.trim());
      final p = int.tryParse(_stepPercent[i].text.trim());
      if (d == null || p == null || d < 1 || d > 366 || p < 1 || p > 100) {
        return x.tr(
          'Each step needs days (1–366) and a percent (1–100).',
          'Mỗi mốc cần số ngày (1–366) và phần trăm (1–100).',
        );
      }
      if (d <= days || p <= percent) {
        return x.tr(
          'Each step needs more days and a higher percent than the one before.',
          'Mỗi mốc sau phải nhiều ngày hơn và phần trăm cao hơn mốc trước.',
        );
      }
      days = d;
      percent = p;
    }
    return null;
  }

  Future<void> _save() async {
    final x = FeeText(context);
    if (_busy) return;
    if (_pending == null) {
      final stepsError = _stepsError(x);
      final valid = _form.currentState!.validate();
      if (!valid || stepsError != null) {
        setState(() => _error = stepsError);
        return;
      }
      final version = !_active
          ? {'effectiveDate': _date.text.trim(), 'active': false}
          : {
              'effectiveDate': _date.text.trim(),
              'active': true,
              'rateMinor': appParseMoney(_rate.text, _inputCurrency),
              'rule': _rule(),
              'includedPeople': _basis == 'person'
                  ? int.parse(_included.text.trim())
                  : 0,
              'roundingMinor': _rounding,
            };
      _pending = {
        'action': 'define',
        'inputCurrency': _inputCurrency,
        'organizationId': widget.organizationId,
        'buildingId': widget.buildingId,
        'operationId': const Uuid().v4(),
        'revision': widget.revision,
        'reason': _reason.text.trim(),
        'feeId': widget.fee?['id'],
        'name': _name.text.trim(),
        'basis': _basis,
        'unitLabel': _basis == 'quantity' ? _unit.text.trim() : '',
        'version': version,
      };
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.serviceFees(_pending!);
      if (!mounted) return;
      _pending = null;
      widget.onDone(
        _creating
            ? x.tr('Fee added.', 'Đã thêm phí.')
            : x.tr('Change saved.', 'Đã lưu thay đổi.'),
      );
    } catch (e) {
      if (!mounted) return;
      final uncertain = FeeText.uncertain(e);
      setState(() {
        if (!uncertain) _pending = null;
        _error = x.error(e, uncertain: uncertain);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename() async {
    final fee = widget.fee;
    if (fee == null || _locked) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RenameDialog(
        service: widget.service,
        organizationId: widget.organizationId,
        buildingId: widget.buildingId,
        revision: widget.revision,
        fee: fee,
      ),
    );
    if (saved == true && mounted) {
      widget.onDone(FeeText(context).tr('Name saved.', 'Đã lưu tên.'));
    }
  }

  /// "Example (30-day period): a person who moved in on day 21 pays …".
  String? _example(FeeText x) {
    if (!_active || _basis == 'quantity') return null;
    final rate = appParseMoney(_rate.text, _inputCurrency);
    if (rate == null || _stepsError(x) != null) return null;
    double share;
    if (_mode == 'days') {
      share = 10 / 30;
    } else if (_mode == 'checkDate') {
      share = _checkDay == 'first' ? 0 : 1;
    } else {
      var percent = 0;
      for (var i = 0; i < _stepDays.length; i++) {
        if ((int.tryParse(_stepDays[i].text.trim()) ?? 999) <= 10) {
          percent = int.tryParse(_stepPercent[i].text.trim()) ?? 0;
        }
      }
      share = percent / 100;
    }
    var minor = (rate * share).round();
    if (_rounding > 1) {
      minor = ((minor + _rounding ~/ 2) ~/ _rounding) * _rounding;
    }
    final who = _basis == 'person'
        ? x.tr('a person who moved in on day 21', 'người vào ở từ ngày 21')
        : x.tr('a lease that started on day 21', 'hợp đồng bắt đầu từ ngày 21');
    return x.tr(
      'Example (30-day period): $who pays ${x.money(minor, _inputCurrency)}.',
      'Ví dụ (kỳ 30 ngày): $who trả ${x.money(minor, _inputCurrency)}.',
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? Function(String)? check,
    bool number = false,
    bool money = false,
    Key? key,
    String? hint,
    int? maxLength,
  }) => TextFormField(
    key: key,
    controller: c,
    enabled: !_locked,
    maxLength: maxLength,
    keyboardType: number || money
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    inputFormatters: money ? appMoneyInput(_inputCurrency) : null,
    decoration: InputDecoration(labelText: label, hintText: hint),
    onChanged: (_) => setState(() {}),
    validator: (v) => check?.call((v ?? '').trim()),
  );

  Widget _chips(List<Widget> chips) =>
      Wrap(spacing: WsSpace.sm, runSpacing: WsSpace.sm, children: chips);

  Widget _help(String text) => Padding(
    padding: const EdgeInsets.only(top: WsSpace.xs),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );

  @override
  Widget build(BuildContext context) {
    final x = FeeText(context), fee = widget.fee;
    final required = x.tr('Required', 'Bắt buộc');
    final billed = fee?['billedThrough'] as String?;
    final example = _example(x);
    return WsPage(
      maxWidth: 760,
      children: [
        WsHeader(
          back: WsBack(
            label: x.tr('Service fees', 'Phí dịch vụ'),
            onPressed: _locked ? null : widget.onCancel,
          ),
          title: _creating
              ? x.tr('Add fee', 'Thêm phí')
              : fee!['name'] as String,
          help: _creating
              ? null
              : x.tr(
                  'A change applies from its date. Invoices already made keep their price.',
                  'Thay đổi áp dụng từ ngày đã chọn. Hóa đơn đã lập giữ nguyên giá cũ.',
                ),
          actions: [
            if (!_creating)
              OutlinedButton(
                key: const ValueKey('fee-rename'),
                onPressed: _locked ? null : _rename,
                child: Text(x.tr('Rename', 'Đổi tên')),
              ),
          ],
        ),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_creating)
                WsSection(
                  title: x.tr('Fee', 'Phí'),
                  children: [
                    _field(
                      _name,
                      x.tr('Name', 'Tên phí'),
                      key: const ValueKey('fee-name'),
                      hint: x.tr('e.g. Rubbish, Parking', 'VD: Rác, Gửi xe'),
                      maxLength: 80,
                      check: (v) => v.isEmpty ? required : null,
                    ),
                    const SizedBox(height: WsSpace.sm),
                    Text(
                      x.tr('Charged', 'Cách thu'),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: WsSpace.xs),
                    _chips([
                      for (final b in const ['person', 'room', 'quantity'])
                        ChoiceChip(
                          key: ValueKey('fee-basis-$b'),
                          label: Text(x.basis(b)),
                          selected: _basis == b,
                          onSelected: _locked
                              ? null
                              : (_) => setState(() => _basis = b),
                        ),
                    ]),
                    _help(switch (_basis) {
                      'person' => x.tr(
                        'Each person in the room pays (e.g. rubbish, water per head).',
                        'Mỗi người trong phòng trả (VD: rác, nước theo đầu người).',
                      ),
                      'room' => x.tr(
                        'Each room pays once (e.g. internet, cleaning).',
                        'Mỗi phòng trả một lần (VD: internet, vệ sinh).',
                      ),
                      _ => x.tr(
                        'Charged by an amount entered each time (e.g. laundry kg).',
                        'Thu theo số lượng nhập mỗi lần (VD: giặt theo kg).',
                      ),
                    }),
                    if (_basis == 'quantity') ...[
                      const SizedBox(height: WsSpace.md),
                      _field(
                        _unit,
                        x.tr('Unit', 'Đơn vị'),
                        key: const ValueKey('fee-unit'),
                        hint: x.tr('e.g. kg, day', 'VD: kg, ngày'),
                        maxLength: 20,
                      ),
                    ],
                  ],
                ),
              WsSection(
                title: _creating
                    ? x.tr('Price', 'Giá')
                    : x.tr('Change from a date', 'Thay đổi từ ngày'),
                children: [
                  if (billed != null)
                    WsNotice(
                      x.tr(
                        'Invoices cover days before $billed. Choose $billed or later.',
                        'Hóa đơn đã lập cho các ngày trước $billed. Chọn từ ngày $billed trở đi.',
                      ),
                      tone: WsTone.info,
                    ),
                  _field(
                    _date,
                    x.tr('From (YYYY-MM-DD)', 'Áp dụng từ (YYYY-MM-DD)'),
                    key: const ValueKey('fee-date'),
                    check: (v) => !feeDate(v)
                        ? x.tr('Enter a valid date.', 'Nhập ngày hợp lệ.')
                        : billed != null && v.compareTo(billed) < 0
                        ? x.tr(
                            'Choose $billed or later.',
                            'Chọn từ $billed trở đi.',
                          )
                        : null,
                  ),
                  if (!_creating) ...[
                    const SizedBox(height: WsSpace.sm),
                    _chips([
                      ChoiceChip(
                        key: const ValueKey('fee-active'),
                        label: Text(x.tr('New price', 'Giá mới')),
                        selected: _active,
                        onSelected: _locked
                            ? null
                            : (_) => setState(() => _active = true),
                      ),
                      ChoiceChip(
                        key: const ValueKey('fee-stop'),
                        label: Text(x.tr('Stop charging', 'Ngừng thu')),
                        selected: !_active,
                        onSelected: _locked
                            ? null
                            : (_) => setState(() => _active = false),
                      ),
                    ]),
                  ],
                  if (_active) ...[
                    const SizedBox(height: WsSpace.md),
                    WsFieldRow(
                      children: [
                        _field(
                          _rate,
                          _basis == 'quantity'
                              ? x.tr(
                                  'Price per unit ($_inputCurrency)',
                                  'Giá mỗi đơn vị ($_inputCurrency)',
                                )
                              : _basis == 'person'
                              ? x.tr(
                                  'Per person, full period ($_inputCurrency)',
                                  'Mỗi người, đủ kỳ ($_inputCurrency)',
                                )
                              : x.tr(
                                  'Per room, full period ($_inputCurrency)',
                                  'Mỗi phòng, đủ kỳ ($_inputCurrency)',
                                ),
                          key: const ValueKey('fee-rate'),
                          money: true,
                          check: (v) => _money.parse(_rate, widget.currency) == null
                              ? x.tr(
                                  'Enter an amount of 0 or more.',
                                  'Nhập số tiền từ 0 trở lên.',
                                )
                              : null,
                        ),
                        // Short chips wrap at any width and text size (a
                        // dropdown overflowed at 130%/200% text).
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              x.tr('Round each line to', 'Làm tròn mỗi dòng'),
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: WsSpace.xs),
                            _chips([
                              for (final r in _roundings)
                                ChoiceChip(
                                  key: ValueKey('fee-rounding-$r'),
                                  label: Text(
                                    r == 0
                                        ? x.tr('None', 'Không')
                                        : x.money(r, _inputCurrency),
                                  ),
                                  selected: _rounding == r,
                                  onSelected: _locked
                                      ? null
                                      : (_) => setState(() => _rounding = r),
                                ),
                            ]),
                          ],
                        ),
                      ],
                    ),
                    if (_basis == 'person') ...[
                      const SizedBox(height: WsSpace.md),
                      _field(
                        _included,
                        x.tr('People included free', 'Số người miễn phí'),
                        key: const ValueKey('fee-included'),
                        number: true,
                        check: (v) {
                          final n = int.tryParse(v);
                          return n == null || n < 0 || n > 20
                              ? x.tr('Enter 0–20.', 'Nhập từ 0 đến 20.')
                              : null;
                        },
                      ),
                      _help(
                        x.tr(
                          '0 = everyone pays. Otherwise the earliest people to move in are free and the fee starts from the next person.',
                          '0 = ai cũng trả. Nếu lớn hơn 0, những người vào ở sớm nhất được miễn; phí tính từ người tiếp theo.',
                        ),
                      ),
                    ],
                  ],
                ],
              ),
              if (_active && _basis != 'quantity')
                WsSection(
                  title: x.tr('Partial periods', 'Khi ở không đủ kỳ'),
                  children: [
                    _chips([
                      for (final (mode, label) in [
                        ('days', x.tr('By days stayed', 'Theo số ngày ở')),
                        ('thresholds', x.tr('By day steps', 'Theo mốc ngày')),
                        ('checkDate', x.tr('By check date', 'Theo ngày chốt')),
                      ])
                        ChoiceChip(
                          key: ValueKey('fee-mode-$mode'),
                          label: Text(label),
                          selected: _mode == mode,
                          onSelected: _locked
                              ? null
                              : (_) => setState(() => _mode = mode),
                        ),
                    ]),
                    _help(switch (_mode) {
                      'days' => x.tr(
                        'Pays for the days actually stayed: 10 of 30 days pays 1/3.',
                        'Trả theo số ngày ở thật: ở 10/30 ngày trả 1/3.',
                      ),
                      'checkDate' => x.tr(
                        'Only people present on the chosen day pay, in full.',
                        'Chỉ người có mặt vào ngày chốt phải trả, trả đủ.',
                      ),
                      _ => x.tr(
                        'Pays a set percent from a number of days. Fewer days than the first step pays nothing; a whole period always pays in full.',
                        'Ở từ số ngày nào thì trả bao nhiêu phần trăm. Ít hơn mốc đầu thì không trả; ở đủ kỳ luôn trả đủ.',
                      ),
                    }),
                    if (_mode == 'thresholds') ...[
                      const SizedBox(height: WsSpace.md),
                      _chips([
                        for (final (label, steps) in [
                          (
                            x.tr('Any day = full', 'Có ở là đủ'),
                            const [
                              [1, 100],
                            ],
                          ),
                          (
                            x.tr('15+ days = full', 'Từ 15 ngày'),
                            const [
                              [15, 100],
                            ],
                          ),
                          (
                            x.tr('Half / full', 'Nửa / đủ'),
                            const [
                              [1, 50],
                              [15, 100],
                            ],
                          ),
                        ])
                          ActionChip(
                            label: Text(label),
                            onPressed: _locked
                                ? null
                                : () => setState(() => _setSteps(steps)),
                          ),
                      ]),
                      const SizedBox(height: WsSpace.md),
                      for (var i = 0; i < _stepDays.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: WsSpace.sm),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _field(
                                  _stepDays[i],
                                  x.tr('From day', 'Từ ngày thứ'),
                                  key: ValueKey('fee-step-days-$i'),
                                  number: true,
                                ),
                              ),
                              const SizedBox(width: WsSpace.sm),
                              Expanded(
                                child: _field(
                                  _stepPercent[i],
                                  x.tr('Pays %', 'Trả %'),
                                  key: ValueKey('fee-step-percent-$i'),
                                  number: true,
                                ),
                              ),
                              IconButton(
                                tooltip: x.tr('Remove step', 'Bỏ mốc'),
                                onPressed: _locked || _stepDays.length == 1
                                    ? null
                                    : () => setState(() {
                                        _stepDays.removeAt(i).dispose();
                                        _stepPercent.removeAt(i).dispose();
                                      }),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                            ],
                          ),
                        ),
                      if (_stepDays.length < 6)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: _locked
                                ? null
                                : () => setState(() {
                                    _stepDays.add(TextEditingController());
                                    _stepPercent.add(TextEditingController());
                                  }),
                            icon: const Icon(Icons.add, size: 18),
                            label: Text(x.tr('Add step', 'Thêm mốc')),
                          ),
                        ),
                    ],
                    if (_mode == 'checkDate') ...[
                      const SizedBox(height: WsSpace.md),
                      _chips([
                        ChoiceChip(
                          key: const ValueKey('fee-check-first'),
                          label: Text(x.tr('First day', 'Ngày đầu kỳ')),
                          selected: _checkDay == 'first',
                          onSelected: _locked
                              ? null
                              : (_) => setState(() => _checkDay = 'first'),
                        ),
                        ChoiceChip(
                          key: const ValueKey('fee-check-last'),
                          label: Text(x.tr('Last day', 'Ngày cuối kỳ')),
                          selected: _checkDay == 'last',
                          onSelected: _locked
                              ? null
                              : (_) => setState(() => _checkDay = 'last'),
                        ),
                      ]),
                    ],
                    if (example != null) ...[
                      const SizedBox(height: WsSpace.md),
                      WsNotice(example, tone: WsTone.info),
                    ],
                  ],
                ),
              WsSection(
                title: x.tr('Reason', 'Lý do'),
                children: [
                  _field(
                    _reason,
                    x.tr('Reason for this change', 'Lý do thay đổi'),
                    key: const ValueKey('fee-reason'),
                    maxLength: 1000,
                    check: (v) => v.isEmpty ? required : null,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Semantics(liveRegion: true, child: WsNotice(_error!)),
        WsActions(
          children: [
            TextButton(
              onPressed: _busy ? null : widget.onCancel,
              child: Text(x.tr('Cancel', 'Hủy')),
            ),
            FilledButton(
              key: const ValueKey('fee-save'),
              onPressed: _busy ? null : _save,
              child: Text(
                _pending != null
                    ? x.tr('Retry', 'Thử lại')
                    : x.tr('Save', 'Lưu'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RenameDialog extends StatefulWidget {
  final TeamService service;
  final String organizationId, buildingId;
  final int revision;
  final Map<String, dynamic> fee;
  const _RenameDialog({
    required this.service,
    required this.organizationId,
    required this.buildingId,
    required this.revision,
    required this.fee,
  });
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.fee['name'] as String);
  late final _unit = TextEditingController(
    text: widget.fee['unitLabel'] as String? ?? '',
  );
  final _reason = TextEditingController();
  Map<String, dynamic>? _pending;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final x = FeeText(context);
    if (_busy || (_pending == null && !_form.currentState!.validate())) return;
    _pending ??= {
      'action': 'rename',
      'organizationId': widget.organizationId,
      'buildingId': widget.buildingId,
      'operationId': const Uuid().v4(),
      'revision': widget.revision,
      'reason': _reason.text.trim(),
      'feeId': widget.fee['id'],
      'name': _name.text.trim(),
      'unitLabel': widget.fee['basis'] == 'quantity' ? _unit.text.trim() : '',
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.serviceFees(_pending!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final uncertain = FeeText.uncertain(e);
      setState(() {
        if (!uncertain) _pending = null;
        _error = x.error(e, uncertain: uncertain);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final x = FeeText(context), required = x.tr('Required', 'Bắt buộc');
    final locked = _busy || _pending != null;
    return AlertDialog(
      scrollable: true,
      title: Text(x.tr('Rename fee', 'Đổi tên phí')),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              x.tr(
                'Invoices already made keep the old name.',
                'Hóa đơn đã lập giữ tên cũ.',
              ),
            ),
            const SizedBox(height: WsSpace.lg),
            TextFormField(
              key: const ValueKey('fee-rename-name'),
              controller: _name,
              enabled: !locked,
              maxLength: 80,
              decoration: InputDecoration(labelText: x.tr('Name', 'Tên phí')),
              validator: (v) => (v ?? '').trim().isEmpty ? required : null,
            ),
            if (widget.fee['basis'] == 'quantity') ...[
              const SizedBox(height: WsSpace.sm),
              TextFormField(
                controller: _unit,
                enabled: !locked,
                maxLength: 20,
                decoration: InputDecoration(labelText: x.tr('Unit', 'Đơn vị')),
              ),
            ],
            const SizedBox(height: WsSpace.sm),
            TextFormField(
              key: const ValueKey('fee-rename-reason'),
              controller: _reason,
              enabled: !locked,
              maxLength: 1000,
              decoration: InputDecoration(labelText: x.tr('Reason', 'Lý do')),
              validator: (v) => (v ?? '').trim().isEmpty ? required : null,
            ),
            if (_error != null) WsNotice(_error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(x.tr('Close', 'Đóng')),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(
            _pending != null ? x.tr('Retry', 'Thử lại') : x.tr('Save', 'Lưu'),
          ),
        ),
      ],
    );
  }
}
