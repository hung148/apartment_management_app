// Building price defaults (PRICE_DEFAULTS.md, Tom 2026-10-26): monthly rent,
// nightly price, electricity per kWh, water per month (fills the lease form)
// and the hourly price templates.
// New building: [BuildingPriceDraft] + [BuildingPriceFields]; the room rows
// start with these prices. Edit building: [BuildingPricesEditor] — rooms that
// follow the building change with it; rooms with their own price are listed
// (one checklist per changed price) and a ticked room follows from then on.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/app_number.dart';
import '../../utils/localizations/app_localizations.dart';
import 'ws_ui.dart';

String _w(BuildContext c, String en, String vi) =>
    AppTranslations.of(c).locale.languageCode == 'vi' ? vi : en;

final _dateShape = RegExp(r'^\d{4}-\d{2}-\d{2}$');
bool _validDate(String v) {
  if (!_dateShape.hasMatch(v)) return false;
  final d = DateTime.tryParse('${v}T00:00:00Z');
  return d != null && d.toIso8601String().startsWith(v);
}

String _dm(String date) =>
    '${date.substring(8)}/${date.substring(5, 7)}/${date.substring(0, 4)}';

/// An hourly price template: name + one price per successive hour (the last
/// one repeats), as in the booking form.
class HourTemplateDraft {
  final String id;
  final String name;
  final List<int> hourPricesMinor;
  const HourTemplateDraft(this.id, this.name, this.hourPricesMinor);
  Map<String, dynamic> toMap() => {
    'templateId': id,
    'name': name,
    'hourPricesMinor': hourPricesMinor,
  };
}

/// The new-building form's prices (kept by the page, sent with "create").
class BuildingPriceDraft {
  final roomPrice = TextEditingController();
  final nightlyPrice = TextEditingController();
  final electricity = TextEditingController();
  final water = TextEditingController();
  String waterBasis = 'person';
  final templates = <HourTemplateDraft>[];

  /// The room prices last passed on to the room rows (rows still showing
  /// these get the next one).
  final applied = <String, String>{'roomPrice': '', 'nightlyPrice': ''};

  /// Prices the room rows start with ('roomPrice' / 'nightlyPrice' → text).
  Map<String, String> get roomDefaults => {
    'roomPrice': roomPrice.text,
    'nightlyPrice': nightlyPrice.text,
  };

  int? _minor(TextEditingController c, String currency) {
    final v = appParseMoney(c.text, currency);
    return v != null && v > 0 ? v : null;
  }

  Map<String, dynamic> defaults(String currency) => {
    'roomPriceMinor': _minor(roomPrice, currency),
    'nightlyPriceMinor': _minor(nightlyPrice, currency),
    'waterMonthMinor': _minor(water, currency),
    'waterBasis': waterBasis,
  };
  int? electricityMinor(String currency) => _minor(electricity, currency);

  void dispose() {
    for (final c in [roomPrice, nightlyPrice, electricity, water]) {
      c.dispose();
    }
  }
}

Widget _moneyField(
  BuildContext context, {
  required Key key,
  required String label,
  required TextEditingController controller,
  required String currency,
  required bool enabled,
  ValueChanged<String>? onChanged,
}) => TextFormField(
  key: key,
  controller: controller,
  enabled: enabled,
  keyboardType: const TextInputType.numberWithOptions(decimal: true),
  inputFormatters: appMoneyInput(currency),
  onChanged: onChanged,
  decoration: InputDecoration(labelText: label, errorMaxLines: 3),
  validator: (v) {
    if ((v ?? '').trim().isEmpty) return null;
    final minor = appParseMoney(v!, currency);
    return minor == null || minor <= 0
        ? _w(context, 'Enter an amount above 0.', 'Nhập số tiền lớn hơn 0.')
        : null;
  },
);

Widget _waterBasis(
  BuildContext context,
  String value,
  bool enabled,
  ValueChanged<String> onChanged,
) => Wrap(
  spacing: WsSpace.sm,
  children: [
    for (final (v, en, vi) in [
      ('person', 'Per person', 'Mỗi người'),
      ('room', 'Whole room', 'Cả phòng'),
    ])
      ChoiceChip(
        key: ValueKey('building-water-$v'),
        label: Text(_w(context, en, vi)),
        selected: value == v,
        onSelected: enabled ? (_) => onChanged(v) : null,
      ),
  ],
);

/// New building: the price fields and the hourly templates (created right
/// after the building).
class BuildingPriceFields extends StatelessWidget {
  final BuildingPriceDraft draft;
  final String currency;
  final bool locked;

  /// The room rows follow what is typed here (rows still showing the old
  /// building price get the new one).
  final void Function(String field, String oldText, String newText)
  onRoomDefaultChanged;
  final VoidCallback onChanged;
  const BuildingPriceFields({
    super.key,
    required this.draft,
    required this.currency,
    required this.locked,
    required this.onRoomDefaultChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget roomField(String field, TextEditingController c, String label) =>
        _moneyField(
          context,
          key: ValueKey('building-$field'),
          label: '$label ($currency)',
          controller: c,
          currency: currency,
          enabled: !locked,
          onChanged: (v) {
            final old = draft.applied[field] ?? '';
            draft.applied[field] = v;
            onRoomDefaultChanged(field, old, v);
          },
        );
    return WsSection(
      key: const ValueKey('building-prices'),
      title: _w(context, 'Building prices', 'Giá của cơ sở'),
      icon: Icons.sell_outlined,
      children: [
        Text(
          _w(
            context,
            'Every room starts with these prices. A room with another price keeps its own.',
            'Mọi phòng bắt đầu với các giá này. Phòng nhập giá khác sẽ giữ giá riêng.',
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: WsSpace.md),
        WsFieldRow(
          children: [
            roomField(
              'roomPrice',
              draft.roomPrice,
              _w(context, 'Monthly rent', 'Giá thuê theo tháng'),
            ),
            roomField(
              'nightlyPrice',
              draft.nightlyPrice,
              _w(context, 'Price per night', 'Giá theo đêm'),
            ),
          ],
        ),
        const SizedBox(height: WsSpace.md),
        WsFieldRow(
          children: [
            _moneyField(
              context,
              key: const ValueKey('building-electricity'),
              label: '${_w(context, 'Electricity per kWh', 'Giá điện mỗi kWh')} ($currency)',
              controller: draft.electricity,
              currency: currency,
              enabled: !locked,
            ),
            _moneyField(
              context,
              key: const ValueKey('building-water'),
              label: '${_w(context, 'Water per month', 'Tiền nước mỗi tháng')} ($currency)',
              controller: draft.water,
              currency: currency,
              enabled: !locked,
            ),
          ],
        ),
        const SizedBox(height: WsSpace.sm),
        _waterBasis(context, draft.waterBasis, !locked, (v) {
          draft.waterBasis = v;
          onChanged();
        }),
        const SizedBox(height: WsSpace.lg),
        HourTemplateList(
          templates: draft.templates,
          currency: currency,
          locked: locked,
          canEdit: true,
          onAdd: (t) async {
            draft.templates.add(t);
            onChanged();
          },
          onRemove: (t) async {
            draft.templates.remove(t);
            onChanged();
          },
        ),
      ],
    );
  }
}

/// The hourly price templates with "Thêm mẫu" and a delete per template.
class HourTemplateList extends StatelessWidget {
  final List<HourTemplateDraft> templates;
  final String currency;
  final bool locked, canEdit;
  final Future<void> Function(HourTemplateDraft) onAdd;
  final Future<void> Function(HourTemplateDraft) onRemove;
  const HourTemplateList({
    super.key,
    required this.templates,
    required this.currency,
    required this.locked,
    required this.canEdit,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String prices(List<int> p) =>
        p.map((v) => appMoneyInputText(v, currency)).join(' · ');
    return Column(
      key: const ValueKey('hour-templates'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Wrap: on narrow screens the button goes under the title.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: WsSpace.sm,
          children: [
            Text(
              _w(context, 'Hourly price templates', 'Mẫu giá theo giờ'),
              style: theme.textTheme.titleSmall,
            ),
            if (canEdit)
              TextButton.icon(
                key: const ValueKey('hour-template-add'),
                onPressed: locked || templates.length >= 20
                    ? null
                    : () async {
                        final t = await showHourTemplateDialog(
                          context,
                          currency: currency,
                          taken: {for (final t in templates) t.name},
                        );
                        if (t != null) await onAdd(t);
                      },
                icon: const Icon(Icons.add, size: 18),
                label: Text(_w(context, 'Add', 'Thêm mẫu')),
              ),
          ],
        ),
        Text(
          _w(
            context,
            'Hourly bookings pick one of these (1st hour, 2nd hour…; the last price repeats).',
            'Đặt phòng theo giờ chọn một mẫu (giờ 1, giờ 2…; giá cuối lặp lại).',
          ),
          style: theme.textTheme.bodySmall,
        ),
        if (templates.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: WsSpace.sm),
            child: Text(
              _w(context, 'No templates yet.', 'Chưa có mẫu nào.'),
              key: const ValueKey('hour-templates-empty'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        for (final t in templates)
          ListTile(
            key: ValueKey('hour-template-${t.id}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(t.name),
            subtitle: Text('${prices(t.hourPricesMinor)} $currency'),
            trailing: canEdit
                ? IconButton(
                    key: ValueKey('hour-template-remove-${t.id}'),
                    tooltip: _w(context, 'Delete', 'Xóa'),
                    onPressed: locked
                        ? null
                        : () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: Text(
                                  _w(c, 'Delete this template?', 'Xóa mẫu này?'),
                                ),
                                content: Text(
                                  _w(
                                    c,
                                    '"${t.name}" will no longer be offered. Bookings already saved keep their prices.',
                                    '"${t.name}" sẽ không còn để chọn. Đặt phòng đã lưu vẫn giữ giá của nó.',
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: Text(_w(c, 'Cancel', 'Hủy')),
                                  ),
                                  FilledButton(
                                    key: const ValueKey(
                                      'hour-template-remove-confirm',
                                    ),
                                    onPressed: () => Navigator.pop(c, true),
                                    child: Text(_w(c, 'Delete', 'Xóa')),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) await onRemove(t);
                          },
                    icon: const Icon(Icons.delete_outline),
                  )
                : null,
          ),
      ],
    );
  }
}

/// A new template: a name and one price per hour.
Future<HourTemplateDraft?> showHourTemplateDialog(
  BuildContext context, {
  required String currency,
  required Set<String> taken,
}) {
  final name = TextEditingController();
  final hours = [TextEditingController()];
  final form = GlobalKey<FormState>();
  return showDialog<HourTemplateDraft>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(_w(c, 'New hourly template', 'Mẫu giá theo giờ mới')),
        content: SizedBox(
          width: 420,
          child: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    key: const ValueKey('hour-template-name'),
                    controller: name,
                    maxLength: 80,
                    decoration: InputDecoration(
                      labelText: _w(c, 'Name', 'Tên mẫu'),
                      counterText: '',
                    ),
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty) return _w(c, 'Required', 'Bắt buộc');
                      if (taken.contains(s)) {
                        return _w(c, 'Name already used.', 'Tên đã có.');
                      }
                      return null;
                    },
                  ),
                  for (final (i, h) in hours.indexed)
                    Padding(
                      padding: const EdgeInsets.only(top: WsSpace.sm),
                      child: TextFormField(
                        key: ValueKey('hour-template-hour-$i'),
                        controller: h,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: appMoneyInput(currency),
                        decoration: InputDecoration(
                          labelText:
                              '${_w(c, 'Hour ${i + 1}', 'Giờ ${i + 1}')} ($currency)',
                        ),
                        validator: (v) {
                          final m = appParseMoney(v ?? '', currency);
                          return m == null || m <= 0
                              ? _w(c, 'Enter an amount above 0.', 'Nhập số tiền lớn hơn 0.')
                              : null;
                        },
                      ),
                    ),
                  Wrap(
                    spacing: WsSpace.sm,
                    children: [
                      TextButton(
                        key: const ValueKey('hour-template-more'),
                        onPressed: hours.length >= 24
                            ? null
                            : () => set(() => hours.add(TextEditingController())),
                        child: Text(_w(c, 'Add hour', 'Thêm giờ')),
                      ),
                      if (hours.length > 1)
                        TextButton(
                          onPressed: () => set(() => hours.removeLast()),
                          child: Text(_w(c, 'Remove last', 'Bỏ giờ cuối')),
                        ),
                    ],
                  ),
                  Text(
                    _w(c, 'The last price repeats for longer stays.', 'Giá cuối lặp lại cho các giờ sau.'),
                    style: Theme.of(c).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(_w(c, 'Cancel', 'Hủy')),
          ),
          FilledButton(
            key: const ValueKey('hour-template-save'),
            onPressed: () {
              if (!form.currentState!.validate()) return;
              Navigator.pop(
                c,
                HourTemplateDraft(const Uuid().v4().replaceAll('-', ''), name.text.trim(), [
                  for (final h in hours) appParseMoney(h.text, currency)!,
                ]),
              );
            },
            child: Text(_w(c, 'Save', 'Lưu')),
          ),
        ],
      ),
    ),
  );
}

/// Edit building: the prices, their checklists and the hourly templates.
class BuildingPricesEditor extends StatefulWidget {
  final TeamService service;
  final String organizationId, buildingId;

  /// The saved building room prices, after every load (new room rows on the
  /// page start with them).
  final ValueChanged<Map<String, String>>? onDefaults;
  const BuildingPricesEditor({
    super.key,
    required this.service,
    required this.organizationId,
    required this.buildingId,
    this.onDefaults,
  });
  @override
  State<BuildingPricesEditor> createState() => _BuildingPricesEditorState();
}

class _BuildingPricesEditorState extends State<BuildingPricesEditor> {
  final _draft = BuildingPriceDraft();
  final _from = TextEditingController();
  final _form = GlobalKey<FormState>();
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _pending;
  bool _busy = false, _saving = false;
  String? _message;
  bool _error = false, _good = false;
  int _generation = 0;

  String w(String en, String vi) => _w(context, en, vi);
  String get _currency => _data?['currency'] as String? ?? 'VND';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _draft.dispose();
    _from.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _scope => {
    'organizationId': widget.organizationId,
    'buildingId': widget.buildingId,
  };

  void _fill(TextEditingController c, Object? minor) => c.text = minor == null
      ? ''
      : appMoneyInputText((minor as num).toInt(), _currency);

  Future<void> _load({String? message, bool good = true}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = false;
      _message = message;
      _good = message != null && good;
    });
    try {
      final r = await widget.service.propertyDetails({
        'action': 'readPrices',
        ..._scope,
      });
      if (!mounted || generation != _generation) return;
      final data = Map<String, dynamic>.from(r['record'] as Map);
      setState(() {
        _data = data;
        final d = Map<String, dynamic>.from(data['defaults'] as Map);
        _fill(_draft.roomPrice, d['roomPriceMinor']);
        _fill(_draft.nightlyPrice, d['nightlyPriceMinor']);
        _fill(_draft.water, d['waterMonthMinor']);
        _draft.waterBasis = d['waterBasis'] as String? ?? 'person';
        final e = Map<String, dynamic>.from(data['electricity'] as Map);
        _fill(_draft.electricity, e['priceMinor']);
        _from.text = data['today'] as String;
        _draft.templates
          ..clear()
          ..addAll([
            for (final t in (data['hourTemplates'] as List).cast<Map>())
              HourTemplateDraft(
                t['id'] as String,
                t['name'] as String,
                (t['hourPricesMinor'] as List).cast<num>().map((v) => v.toInt()).toList(),
              ),
          ]);
      });
      widget.onDefaults?.call(_draft.roomDefaults);
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _error = true);
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  int? _minor(TextEditingController c) {
    final v = appParseMoney(c.text, _currency);
    return v != null && v > 0 ? v : null;
  }

  /// One checklist: the rooms with their own price for this kind.
  Future<List<String>?> _checklist(
    String title,
    List<Map<String, dynamic>> rooms,
    String Function(Map<String, dynamic>) current,
    String next,
  ) {
    final picked = <String>{};
    return showDialog<List<String>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          key: const ValueKey('price-checklist'),
          title: Text(title),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _w(
                    c,
                    'These rooms have their own price. Tick the ones that should take $next and follow the building from now on.',
                    'Các phòng này có giá riêng. Chọn phòng nhận giá mới $next và theo giá của cơ sở từ nay.',
                  ),
                  style: Theme.of(c).textTheme.bodySmall,
                ),
                CheckboxListTile(
                  key: const ValueKey('price-checklist-all'),
                  contentPadding: EdgeInsets.zero,
                  value: picked.length == rooms.length
                      ? true
                      : picked.isEmpty
                      ? false
                      : null,
                  tristate: true,
                  title: Text(_w(c, 'All rooms', 'Tất cả phòng')),
                  onChanged: (_) => set(() {
                    if (picked.length == rooms.length) {
                      picked.clear();
                    } else {
                      picked.addAll(rooms.map((r) => r['id'] as String));
                    }
                  }),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final r in rooms)
                        CheckboxListTile(
                          key: ValueKey('price-checklist-${r['id']}'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: picked.contains(r['id']),
                          title: Text('${_w(c, 'Room', 'Phòng')} ${r['roomNumber']}'),
                          subtitle: Text(current(r)),
                          onChanged: (v) => set(
                            () => v == true
                                ? picked.add(r['id'] as String)
                                : picked.remove(r['id']),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(_w(c, 'Cancel', 'Hủy')),
            ),
            FilledButton(
              key: const ValueKey('price-checklist-apply'),
              onPressed: () => Navigator.pop(c, picked.toList()),
              child: Text(
                picked.isEmpty
                    ? _w(c, 'None of them', 'Không phòng nào')
                    : _w(c, 'Apply to ${picked.length}', 'Áp dụng cho ${picked.length}'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final data = _data;
    if (data == null || _saving) return;
    if (_pending == null) {
      if (!_form.currentState!.validate()) return;
      final old = Map<String, dynamic>.from(data['defaults'] as Map);
      final defaults = _draft.defaults(_currency);
      final rooms = [
        for (final r in (data['rooms'] as List)) Map<String, dynamic>.from(r as Map),
      ].where((r) => r['currency'] == _currency).toList();
      final apply = <String, List<String>>{
        'roomPrice': [],
        'nightlyPrice': [],
        'electricity': [],
      };
      // One checklist per changed price (Tom, 2026-10-26).
      for (final (kind, en, vi) in [
        ('roomPrice', 'monthly rent', 'giá thuê tháng'),
        ('nightlyPrice', 'price per night', 'giá đêm'),
      ]) {
        final next = defaults['${kind}Minor'] as int?;
        if (next == null || next == old['${kind}Minor']) continue;
        // Rooms with no price take it without being asked (Tom, 2026-10-28).
        final own = rooms
            .where(
              (r) =>
                  (r['follows'] as Map)[kind] != true && r['${kind}Minor'] != null,
            )
            .toList();
        if (own.isEmpty) continue;
        final picked = await _checklist(
          w('New $en for rooms with their own price?', 'Áp dụng $vi mới cho phòng có giá riêng?'),
          own,
          (r) =>
              '${appMoneyInputText(r['${kind}Minor'] as int, _currency)} $_currency',
          '${appMoneyInputText(next, _currency)} $_currency',
        );
        if (picked == null || !mounted) return; // cancelled: nothing saved
        apply[kind] = picked;
      }
      final e = Map<String, dynamic>.from(data['electricity'] as Map);
      final power = _minor(_draft.electricity);
      final powerChanged = power != null && power != e['priceMinor'];
      if (powerChanged) {
        final own = rooms.where((r) => (r['electricity'] as Map)['own'] == true).toList();
        if (own.isNotEmpty) {
          final picked = await _checklist(
            w('New electricity price for rooms with their own price?', 'Áp dụng giá điện mới cho phòng có giá riêng?'),
            own,
            (r) {
              final p = (r['electricity'] as Map)['ownPriceMinor'] as int?;
              return p == null
                  ? w('Tiered price', 'Giá bậc thang')
                  : '${appMoneyInputText(p, _currency)} $_currency/kWh';
            },
            '${appMoneyInputText(power, _currency)} $_currency/kWh',
          );
          if (picked == null || !mounted) return;
          apply['electricity'] = picked;
        }
      }
      _pending = Map.unmodifiable({
        'action': 'savePrices',
        ..._scope,
        'operationId': const Uuid().v4(),
        'revision': data['revision'],
        'defaults': defaults,
        'electricity': powerChanged
            ? {
                'priceMinor': power,
                'effectiveDate': _from.text.trim(),
                'propertyRevision': e['propertyRevision'],
              }
            : null,
        'apply': apply,
      });
    }
    final generation = _generation;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final r = await widget.service.propertyDetails(Map.of(_pending!));
      if (!mounted || generation != _generation) return;
      _pending = null;
      _saving = false;
      final n = (r['rooms'] as num?)?.toInt() ?? 0;
      await _load(
        message: w('Saved. $n room(s) updated.', 'Đã lưu. $n phòng được cập nhật.'),
      );
    } catch (e) {
      if (!mounted || generation != _generation) return;
      final key = e is FirebaseFunctionsException ? '${e.message}' : '';
      final code = e is FirebaseFunctionsException ? e.code : '';
      setState(() {
        if (code != 'unavailable' && code != 'deadline-exceeded' && code != '') {
          _pending = null; // refused: change and try again
        }
        _message = switch (key) {
          'price_changed' => w('Someone else changed these prices. They were reloaded.', 'Đã có người khác sửa giá. Đã tải lại.'),
          'utility_tariff_past_reading' || 'price_electricity_before_reading' => w(
            'Electricity: pick a date after the last meter reading.',
            'Giá điện: chọn ngày sau lần ghi chỉ số gần nhất.',
          ),
          'utility_tariff_date_exists' => w('Electricity: there is already a price from that date.', 'Giá điện: đã có giá từ ngày này.'),
          'price_room_currency' => w('A room uses another currency.', 'Có phòng dùng loại tiền khác.'),
          'lease_backdate_owner_admin_required' => w('Dates before today need "Enter past dates".', 'Ngày trước hôm nay cần quyền "Nhập ngày trong quá khứ".'),
          _ when code == 'permission-denied' => w('You cannot change prices.', 'Bạn không có quyền đổi giá.'),
          _ => w('Could not save. Check the connection and try again.', 'Không lưu được. Kiểm tra kết nối rồi thử lại.'),
        };
        _good = false;
        _saving = false;
      });
      if (key == 'price_changed') _load(message: _message, good: false);
    }
  }

  Future<void> _template(HourTemplateDraft t, {bool remove = false}) async {
    setState(() => _saving = true);
    try {
      await widget.service.bookingWorkspace({
        'action': 'hourTemplates',
        ..._scope,
        'templateId': t.id,
        if (remove) 'remove': true else ...{'name': t.name, 'hourPricesMinor': t.hourPricesMinor},
      });
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = w('Could not save the template.', 'Không lưu được mẫu.');
          _good = false;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final locked = _busy || _saving;
    final canPrice = data?['canPrice'] == true;
    final e = data == null ? null : Map<String, dynamic>.from(data['electricity'] as Map);
    final following = data == null
        ? null
        : (data['rooms'] as List).where((r) => (r as Map)['follows']['roomPrice'] == true).length;
    return WsSection(
      key: const ValueKey('building-prices'),
      title: w('Building prices', 'Giá của cơ sở'),
      icon: Icons.sell_outlined,
      children: [
        if (_busy || _saving) const LinearProgressIndicator(),
        if (_message != null)
          WsNotice(
            _message!,
            key: const ValueKey('building-prices-message'),
            tone: _good ? WsTone.good : WsTone.bad,
          ),
        if (_error)
          WsNotice(
            w('Could not load the prices.', 'Không tải được giá.'),
            tone: WsTone.warning,
            action: TextButton(onPressed: locked ? null : _load, child: Text(w('Try again', 'Thử lại'))),
          )
        else if (data != null)
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  w(
                    'Rooms that follow the building change with it. You choose which rooms with their own price get a new price.',
                    'Phòng theo giá cơ sở đổi theo. Phòng có giá riêng: bạn chọn phòng nào nhận giá mới.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (following != null)
                  Text(
                    w(
                      '$following of ${(data['rooms'] as List).length} rooms follow the monthly rent.',
                      '$following/${(data['rooms'] as List).length} phòng theo giá thuê tháng của cơ sở.',
                    ),
                    key: const ValueKey('building-prices-following'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: WsSpace.md),
                WsFieldRow(
                  children: [
                    _moneyField(context, key: const ValueKey('building-roomPrice'), label: '${w('Monthly rent', 'Giá thuê theo tháng')} ($_currency)', controller: _draft.roomPrice, currency: _currency, enabled: canPrice && !locked),
                    _moneyField(context, key: const ValueKey('building-nightlyPrice'), label: '${w('Price per night', 'Giá theo đêm')} ($_currency)', controller: _draft.nightlyPrice, currency: _currency, enabled: canPrice && !locked),
                  ],
                ),
                const SizedBox(height: WsSpace.md),
                WsFieldRow(
                  children: [
                    _moneyField(context, key: const ValueKey('building-electricity'), label: '${w('Electricity per kWh', 'Giá điện mỗi kWh')} ($_currency)', controller: _draft.electricity, currency: _currency, enabled: canPrice && !locked, onChanged: (_) => setState(() {})),
                    TextFormField(
                      key: const ValueKey('building-electricity-from'),
                      controller: _from,
                      enabled: canPrice && !locked && _minor(_draft.electricity) != e?['priceMinor'],
                      maxLength: 10,
                      decoration: InputDecoration(labelText: w('New electricity price from (YYYY-MM-DD)', 'Giá điện mới áp dụng từ (YYYY-MM-DD)'), counterText: ''),
                      validator: (v) => _minor(_draft.electricity) != e?['priceMinor'] && !_validDate((v ?? '').trim())
                          ? w('Use the form YYYY-MM-DD.', 'Nhập theo dạng YYYY-MM-DD.')
                          : null,
                    ),
                  ],
                ),
                if (e?['tiered'] == true)
                  Text(w('Now: a tiered price (change it on a room\'s electricity page).', 'Hiện tại: giá bậc thang (sửa ở trang Điện của phòng).'), style: Theme.of(context).textTheme.bodySmall),
                if (e?['from'] != null && e?['priceMinor'] != null)
                  Text(w('Current price since ${_dm(e!['from'] as String)}.', 'Giá hiện tại từ ${_dm(e['from'] as String)}.'), style: Theme.of(context).textTheme.bodySmall),
                for (final u in (e?['upcoming'] as List? ?? const []).cast<Map>())
                  Text(
                    w('From ${_dm(u['effectiveDate'] as String)}: ${u['priceMinor'] == null ? 'tiered' : '${appMoneyInputText(u['priceMinor'] as int, _currency)} $_currency'}',
                        'Từ ${_dm(u['effectiveDate'] as String)}: ${u['priceMinor'] == null ? 'bậc thang' : '${appMoneyInputText(u['priceMinor'] as int, _currency)} $_currency'}'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: WsSpace.md),
                _moneyField(context, key: const ValueKey('building-water'), label: '${w('Water per month (fills the lease form)', 'Tiền nước mỗi tháng (điền sẵn vào hợp đồng)')} ($_currency)', controller: _draft.water, currency: _currency, enabled: canPrice && !locked),
                const SizedBox(height: WsSpace.sm),
                _waterBasis(context, _draft.waterBasis, canPrice && !locked, (v) => setState(() => _draft.waterBasis = v)),
                if (canPrice)
                  WsActions(
                    children: [
                      FilledButton(
                        key: const ValueKey('building-prices-save'),
                        onPressed: locked ? null : _save,
                        child: Text(_pending == null ? w('Save prices', 'Lưu giá') : w('Try again', 'Thử lại')),
                      ),
                    ],
                  )
                else
                  Text(w('Changing prices needs "Change prices".', 'Đổi giá cần quyền "Đổi giá".'), style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: WsSpace.lg),
                HourTemplateList(
                  templates: _draft.templates,
                  currency: _currency,
                  locked: locked,
                  canEdit: data['canSaveTemplates'] == true,
                  onAdd: (t) => _template(t),
                  onRemove: (t) => _template(t, remove: true),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
