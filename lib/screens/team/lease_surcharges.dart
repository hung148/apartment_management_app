import 'package:flutter/material.dart';
import '../../services/team_service.dart';
import '../../utils/app_number.dart';
import '../../utils/localizations/app_localizations.dart';
import 'room_rates_screen.dart' show parseRoomRate;
import 'ws_ui.dart';

/// Long-stay surcharges (phụ thu, 2026-10-04). Each line is per room or per
/// person (main tenant + people living with them), and charged every payment
/// period or once. A period invoice can still change one period's amount.
String leaseSurchargeText(BuildContext context, String key) {
  final vi = AppTranslations.of(context).locale.languageCode == 'vi';
  const labels = <String, List<String>>{
    'title': ['Surcharges', 'Phụ thu'],
    'none': ['No surcharges.', 'Không có phụ thu.'],
    'label': ['Surcharge name', 'Tên phụ thu'],
    'amount': ['Amount', 'Số tiền'],
    'perRoom': ['Per room', 'Theo phòng'],
    'perPerson': ['Per person', 'Theo người'],
    'everyPeriod': ['Every period', 'Mỗi kỳ'],
    'everyMonth': ['Every month', 'Mỗi tháng'],
    'once': ['Once', 'Một lần'],
    // Water (2026-10-04, Tom): per month, per person or for the whole room.
    'water': ['Water', 'Tiền nước'],
    'waterPrice': ['Water per month', 'Tiền nước mỗi tháng'],
    'waterPerson': ['Per person', 'Mỗi người'],
    'waterRoom': ['Whole room', 'Cả phòng'],
    'waterHelp': [
      'Optional. Each period: price × people × months.',
      'Không bắt buộc. Mỗi kỳ: giá × số người × số tháng.',
    ],
    'waterHelpRoom': [
      'Optional. Each period: price × months, whoever lives there.',
      'Không bắt buộc. Mỗi kỳ: giá × số tháng, không tính theo số người.',
    ],
    'waterNone': ['No water charge.', 'Không thu tiền nước.'],
    'waterLine': [
      '{amount} per person per month',
      '{amount} mỗi người mỗi tháng',
    ],
    'waterLineRoom': [
      '{amount} per month for the whole room',
      '{amount} mỗi tháng cho cả phòng',
    ],
    'waterClear': [
      'Leave empty to stop charging water.',
      'Để trống nếu không thu tiền nước.',
    ],
    'add': ['Add surcharge', 'Thêm phụ thu'],
    'remove': ['Remove', 'Xóa'],
    'edit': ['Edit', 'Sửa'],
    'save': ['Save', 'Lưu'],
    'cancel': ['Cancel', 'Hủy'],
    'required': ['Required', 'Bắt buộc'],
    'invalid': ['Enter an amount above 0.', 'Nhập số tiền lớn hơn 0.'],
    'saveFailed': [
      'Could not save. Reload and try again.',
      'Không lưu được. Tải lại rồi thử lại.',
    ],
    'billedOnce': ['already billed', 'đã thu'],
    'help': [
      'Charged on the period invoice. You can change the amount for one period there.',
      'Tính vào hóa đơn kỳ. Có thể đổi số tiền cho từng kỳ khi lập hóa đơn.',
    ],
  };
  final pair = labels[key];
  return pair == null ? key : pair[vi ? 1 : 0];
}

/// One surcharge line being typed.
class LeaseSurchargeDraft {
  final String? id;

  /// 'water' for the water line (per person, per month); null for phụ thu.
  final String? kind;
  final label = TextEditingController(), amount = TextEditingController();
  String basis, frequency;
  LeaseSurchargeDraft({
    this.id,
    this.kind,
    this.basis = 'room',
    this.frequency = 'period',
  });

  factory LeaseSurchargeDraft.from(Map s, String currency) {
    final d = LeaseSurchargeDraft(
      id: s['id'] as String?,
      kind: s['kind'] == 'water' ? 'water' : null,
      basis: s['basis'] == 'person' ? 'person' : 'room',
      frequency: switch (s['frequency']) {
        'once' => 'once',
        'month' => 'month',
        _ => 'period',
      },
    );
    d.label.text = '${s['label'] ?? ''}';
    final minor = s['amountMinor'];
    if (minor is int) {
      d.amount.text = appMoneyInputText(minor, currency);
    }
    return d;
  }

  void dispose() {
    label.dispose();
    amount.dispose();
  }

  /// The line for the server, or null when it is not filled in correctly.
  Map<String, dynamic>? toJson(String currency) {
    final minor = parseRoomRate(amount.text, currency);
    if (label.text.trim().isEmpty || minor == null || minor <= 0) return null;
    return {
      'id': ?id,
      'label': label.text.trim(),
      'amountMinor': minor,
      'basis': basis,
      'frequency': frequency,
      'kind': ?kind,
    };
  }
}

/// The water line among a lease's surcharges, if any.
Map? leaseWater(List<Map> surcharges) =>
    surcharges.where((s) => s['kind'] == 'water').firstOrNull;

/// The water line for the server: per month, per person ('person') or for
/// the whole room ('room').
Map<String, dynamic> leaseWaterJson(
  BuildContext context,
  int amountMinor, {
  String? id,
  String basis = 'person',
}) => {
  'id': ?id,
  'label': leaseSurchargeText(context, 'water'),
  'amountMinor': amountMinor,
  'basis': basis == 'room' ? 'room' : 'person',
  'frequency': 'month',
  'kind': 'water',
};

/// A stored line sent back unchanged (keeps its id and kind).
Map<String, dynamic> _keep(Map s) => {
  for (final k in ['id', 'label', 'amountMinor', 'basis', 'frequency', 'kind'])
    if (s[k] != null) k: s[k],
};

/// "Gửi xe · 100.000 VND · Theo phòng · Mỗi kỳ"
String leaseSurchargeLine(BuildContext context, Map s, String currency) {
  String lt(String k) => leaseSurchargeText(context, k);
  final minor = s['amountMinor'];
  final money = minor is num ? appMoneyMinor(minor, currency) : '';
  return [
    '${s['label'] ?? ''}',
    money,
    lt(s['basis'] == 'person' ? 'perPerson' : 'perRoom'),
    lt(switch (s['frequency']) {
      'once' => 'once',
      'month' => 'everyMonth',
      _ => 'everyPeriod',
    }),
  ].where((v) => v.isNotEmpty).join(' · ');
}

/// The rows of surcharges inside a form: name, amount, per room / per person,
/// every period / once. Changes the [drafts] list in place.
class LeaseSurchargeEditor extends StatelessWidget {
  final List<LeaseSurchargeDraft> drafts;
  final String currency;
  final bool enabled;
  final VoidCallback onChanged;
  final void Function(LeaseSurchargeDraft removed)? onRemoved;
  const LeaseSurchargeEditor({
    super.key,
    required this.drafts,
    required this.currency,
    required this.enabled,
    required this.onChanged,
    this.onRemoved,
  });

  @override
  Widget build(BuildContext context) {
    String lt(String k) => leaseSurchargeText(context, k);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget chip(String key, String label, bool selected, VoidCallback onTap) =>
        ChoiceChip(
          key: ValueKey(key),
          label: Text(label, maxLines: 1),
          selected: selected,
          onSelected: enabled ? (_) => onTap() : null,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (drafts.isEmpty) Text(lt('none'), style: muted),
        for (final (i, c) in drafts.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : WsSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: WsFieldRow(
                        children: [
                          TextFormField(
                            key: ValueKey('lease-surcharge-$i-label'),
                            controller: c.label,
                            enabled: enabled,
                            decoration: InputDecoration(labelText: lt('label')),
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.isEmpty) return lt('required');
                              return s.length > 80
                                  ? AppTranslations.of(
                                      context,
                                    )['tenant_contacts_long']
                                  : null;
                            },
                          ),
                          TextFormField(
                            key: ValueKey('lease-surcharge-$i-amount'),
                            controller: c.amount,
                            enabled: enabled,
                            keyboardType: TextInputType.numberWithOptions(
                              decimal: currency == 'USD',
                            ),
                            inputFormatters: appMoneyInput(currency),
                            decoration: InputDecoration(
                              labelText: '${lt('amount')} ($currency)',
                            ),
                            validator: (v) {
                              final m = parseRoomRate(v ?? '', currency);
                              return m == null || m <= 0 ? lt('invalid') : null;
                            },
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: ValueKey('lease-surcharge-$i-remove'),
                      tooltip: lt('remove'),
                      onPressed: enabled
                          ? () {
                              final removed = drafts.removeAt(i);
                              onRemoved?.call(removed);
                              onChanged();
                            }
                          : null,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: WsSpace.xs),
                Wrap(
                  spacing: WsSpace.sm,
                  runSpacing: WsSpace.xs,
                  children: [
                    chip(
                      'lease-surcharge-$i-room',
                      lt('perRoom'),
                      c.basis == 'room',
                      () {
                        c.basis = 'room';
                        onChanged();
                      },
                    ),
                    chip(
                      'lease-surcharge-$i-person',
                      lt('perPerson'),
                      c.basis == 'person',
                      () {
                        c.basis = 'person';
                        onChanged();
                      },
                    ),
                    const SizedBox(width: WsSpace.sm),
                    chip(
                      'lease-surcharge-$i-period',
                      lt('everyPeriod'),
                      c.frequency == 'period',
                      () {
                        c.frequency = 'period';
                        onChanged();
                      },
                    ),
                    chip(
                      'lease-surcharge-$i-once',
                      lt('once'),
                      c.frequency == 'once',
                      () {
                        c.frequency = 'once';
                        onChanged();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (drafts.length < 20)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('lease-add-surcharge'),
              onPressed: enabled
                  ? () {
                      drafts.add(LeaseSurchargeDraft());
                      onChanged();
                    }
                  : null,
              icon: const Icon(Icons.add, size: 18),
              label: Text(lt('add'), maxLines: 1),
            ),
          ),
        Text(lt('help'), style: muted),
      ],
    );
  }
}

/// The lease page's surcharges, with an Edit dialog.
class LeaseSurchargesSection extends StatelessWidget {
  final String organizationId, buildingId, tenantId, currency;
  final List<Map> surcharges;
  final bool canEdit;
  final TeamService service;
  final VoidCallback onSaved;
  const LeaseSurchargesSection({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.tenantId,
    required this.currency,
    required this.surcharges,
    required this.canEdit,
    required this.service,
    required this.onSaved,
  });

  Future<void> _edit(BuildContext context) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SurchargeDialog(
        organizationId: organizationId,
        buildingId: buildingId,
        tenantId: tenantId,
        currency: currency,
        surcharges: surcharges,
        service: service,
      ),
    );
    if (saved == true) onSaved();
  }

  @override
  Widget build(BuildContext context) {
    String lt(String k) => leaseSurchargeText(context, k);
    final theme = Theme.of(context);
    // Water has its own section (LeaseWaterSection).
    final surcharges = this.surcharges
        .where((s) => s['kind'] != 'water')
        .toList();
    return WsSection(
      key: const ValueKey('lease-surcharges'),
      title: lt('title'),
      icon: Icons.add_card_outlined,
      trailing: canEdit
          ? TextButton(
              key: const ValueKey('lease-surcharges-edit'),
              onPressed: () => _edit(context),
              child: Text(lt('edit'), maxLines: 1),
            )
          : null,
      children: [
        if (surcharges.isEmpty)
          Text(
            lt('none'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        for (final s in surcharges)
          Padding(
            padding: const EdgeInsets.only(bottom: WsSpace.xs),
            child: Text(leaseSurchargeLine(context, s, currency)),
          ),
      ],
    );
  }
}

class _SurchargeDialog extends StatefulWidget {
  final String organizationId, buildingId, tenantId, currency;
  final List<Map> surcharges;
  final TeamService service;
  const _SurchargeDialog({
    required this.organizationId,
    required this.buildingId,
    required this.tenantId,
    required this.currency,
    required this.surcharges,
    required this.service,
  });
  @override
  State<_SurchargeDialog> createState() => _SurchargeDialogState();
}

class _SurchargeDialogState extends State<_SurchargeDialog> {
  final _form = GlobalKey<FormState>();
  late final List<LeaseSurchargeDraft> _drafts = [
    for (final s in widget.surcharges)
      if (s['kind'] != 'water') LeaseSurchargeDraft.from(s, widget.currency),
  ];
  final _retired = <LeaseSurchargeDraft>[];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final d in [..._drafts, ..._retired]) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final rows = [
      for (final d in _drafts) d.toJson(widget.currency),
      // The water line is edited in its own section: send it back as it is.
      for (final s in widget.surcharges)
        if (s['kind'] == 'water') _keep(s),
    ];
    if (rows.contains(null)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Saving the same list twice gives the same result: no operation id needed.
      await widget.service.tenantLeases({
        'action': 'surcharges',
        'organizationId': widget.organizationId,
        'buildingId': widget.buildingId,
        'tenantId': widget.tenantId,
        'surcharges': rows,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = leaseSurchargeText(context, 'saveFailed');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String lt(String k) => leaseSurchargeText(context, k);
    // A plain Dialog (not AlertDialog): the rows use a LayoutBuilder, which
    // cannot report the intrinsic size AlertDialog asks for.
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.all(WsSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(lt('title'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: WsSpace.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_saving) const LinearProgressIndicator(),
                        if (_error != null) WsNotice(_error!),
                        LeaseSurchargeEditor(
                          drafts: _drafts,
                          currency: widget.currency,
                          enabled: !_saving,
                          onChanged: () => setState(() {}),
                          onRemoved: _retired.add,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: WsSpace.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: WsSpace.sm,
                runSpacing: WsSpace.sm,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.pop(context, false),
                    child: Text(lt('cancel'), maxLines: 1),
                  ),
                  FilledButton(
                    key: const ValueKey('lease-surcharges-save'),
                    onPressed: _saving ? null : _save,
                    child: Text(lt('save'), maxLines: 1),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The lease page's water charge (2026-10-04, Tom): per person per month, with
/// an Edit dialog. Stored as the lease's surcharge line of kind 'water'.
class LeaseWaterSection extends StatelessWidget {
  final String organizationId, buildingId, tenantId, currency;
  final List<Map> surcharges;
  final bool canEdit;
  final TeamService service;
  final VoidCallback onSaved;
  const LeaseWaterSection({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.tenantId,
    required this.currency,
    required this.surcharges,
    required this.canEdit,
    required this.service,
    required this.onSaved,
  });

  @override
  Widget build(BuildContext context) {
    String lt(String k) => leaseSurchargeText(context, k);
    final theme = Theme.of(context);
    final water = leaseWater(surcharges);
    final minor = water?['amountMinor'];
    final money = minor is num ? appMoneyMinor(minor, currency) : null;
    return WsSection(
      key: const ValueKey('lease-water'),
      title: lt('water'),
      icon: Icons.water_drop_outlined,
      trailing: canEdit
          ? TextButton(
              key: const ValueKey('lease-water-edit'),
              onPressed: () async {
                final saved = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => _WaterDialog(
                    organizationId: organizationId,
                    buildingId: buildingId,
                    tenantId: tenantId,
                    currency: currency,
                    surcharges: surcharges,
                    service: service,
                  ),
                );
                if (saved == true) onSaved();
              },
              child: Text(lt('edit'), maxLines: 1),
            )
          : null,
      children: [
        Text(
          money == null
              ? lt('waterNone')
              : lt(
                  water?['basis'] == 'room' ? 'waterLineRoom' : 'waterLine',
                ).replaceAll('{amount}', money),
          key: const ValueKey('lease-water-line'),
          style: money == null
              ? theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : null,
        ),
      ],
    );
  }
}

class _WaterDialog extends StatefulWidget {
  final String organizationId, buildingId, tenantId, currency;
  final List<Map> surcharges;
  final TeamService service;
  const _WaterDialog({
    required this.organizationId,
    required this.buildingId,
    required this.tenantId,
    required this.currency,
    required this.surcharges,
    required this.service,
  });
  @override
  State<_WaterDialog> createState() => _WaterDialogState();
}

class _WaterDialogState extends State<_WaterDialog> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: switch (leaseWater(widget.surcharges)?['amountMinor']) {
      final int m => appMoneyInputText(m, widget.currency),
      _ => '',
    },
  );
  late String _basis = leaseWater(widget.surcharges)?['basis'] == 'room'
      ? 'room'
      : 'person';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final text = _amount.text.trim();
    final minor = text.isEmpty ? null : parseRoomRate(text, widget.currency);
    final old = leaseWater(widget.surcharges);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.tenantLeases({
        'action': 'surcharges',
        'organizationId': widget.organizationId,
        'buildingId': widget.buildingId,
        'tenantId': widget.tenantId,
        'surcharges': [
          for (final s in widget.surcharges)
            if (s['kind'] != 'water') _keep(s),
          if (minor != null)
            leaseWaterJson(
              context,
              minor,
              id: old?['id'] as String?,
              basis: _basis,
            ),
        ],
      });
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = leaseSurchargeText(context, 'saveFailed');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String lt(String k) => leaseSurchargeText(context, k);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(WsSpace.lg),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  lt('water'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: WsSpace.md),
                if (_saving) const LinearProgressIndicator(),
                if (_error != null) WsNotice(_error!),
                TextFormField(
                  key: const ValueKey('lease-water-amount'),
                  controller: _amount,
                  enabled: !_saving,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: widget.currency == 'USD',
                  ),
                  inputFormatters: appMoneyInput(widget.currency),
                  decoration: InputDecoration(
                    labelText: '${lt('waterPrice')} (${widget.currency})',
                    helperText: lt('waterClear'),
                  ),
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return null;
                    final m = parseRoomRate(s, widget.currency);
                    return m == null || m <= 0 ? lt('invalid') : null;
                  },
                ),
                const SizedBox(height: WsSpace.sm),
                LeaseWaterBasis(
                  basis: _basis,
                  enabled: !_saving,
                  onChanged: (v) => setState(() => _basis = v),
                ),
                const SizedBox(height: WsSpace.md),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: WsSpace.sm,
                  runSpacing: WsSpace.sm,
                  children: [
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context, false),
                      child: Text(lt('cancel'), maxLines: 1),
                    ),
                    FilledButton(
                      key: const ValueKey('lease-water-save'),
                      onPressed: _saving ? null : _save,
                      child: Text(lt('save'), maxLines: 1),
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

/// "Mỗi người" / "Cả phòng" for the water charge, with how it is counted.
class LeaseWaterBasis extends StatelessWidget {
  final String basis;
  final bool enabled;
  final ValueChanged<String> onChanged;
  const LeaseWaterBasis({
    super.key,
    required this.basis,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    String lt(String k) => leaseSurchargeText(context, k);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: WsSpace.sm,
          runSpacing: WsSpace.xs,
          children: [
            for (final (value, label) in [
              ('person', lt('waterPerson')),
              ('room', lt('waterRoom')),
            ])
              ChoiceChip(
                key: ValueKey('lease-water-$value'),
                label: Text(label, maxLines: 1),
                selected: basis == value,
                onSelected: enabled ? (_) => onChanged(value) : null,
              ),
          ],
        ),
        const SizedBox(height: WsSpace.xs),
        Text(
          lt(basis == 'room' ? 'waterHelpRoom' : 'waterHelp'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
