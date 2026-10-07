import 'package:flutter/material.dart';
import '../../utils/localizations/app_localizations.dart';
import 'utility_readings_screen.dart' show meterMilli;
import '../../utils/app_number.dart';

bool utilityDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final parsed = DateTime.tryParse(value);
  return parsed != null && parsed.toIso8601String().substring(0, 10) == value;
}

class UtilityTariffForm extends StatefulWidget {
  final String currency;
  final bool locked;
  final Future<void> Function(Map<String, dynamic>) onSave;
  const UtilityTariffForm({
    super.key,
    required this.currency,
    required this.locked,
    required this.onSave,
  });
  @override
  State<UtilityTariffForm> createState() => _UtilityTariffFormState();
}

class _UtilityTariffFormState extends State<UtilityTariffForm> {
  final _form = GlobalKey<FormState>();
  final _date = TextEditingController(), _reason = TextEditingController();
  final _limits = <TextEditingController>[TextEditingController()];
  final _prices = <TextEditingController>[TextEditingController()];
  String _scope = 'room';
  bool _default = false;
  String tr(String en, String vi) =>
      AppTranslations.of(context).locale.languageCode == 'vi' ? vi : en;
  int? price(String s) => appParseMoney(s, widget.currency);
  @override
  void dispose() {
    for (final c in [_date, _reason, ..._limits, ..._prices]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (widget.locked || !_form.currentState!.validate()) return;
    await widget.onSave({
      'tariffScope': _scope,
      'effectiveDate': _date.text.trim(),
      'reason': _reason.text.trim(),
      'tariff': _default
          ? null
          : {
              'currency': widget.currency,
              'bands': [
                for (var i = 0; i < _prices.length; i++)
                  {
                    'throughMilli': i == _prices.length - 1
                        ? null
                        : meterMilli(_limits[i].text),
                    'priceMinor': price(_prices[i].text),
                  },
              ],
            },
    });
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('Tariff setup', 'Thiết lập đơn giá'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final scope in ['room', 'property'])
              ChoiceChip(
                selected: _scope == scope,
                label: Text(
                  scope == 'room'
                      ? tr('Room', 'Phòng')
                      : tr('Property', 'Tòa nhà'),
                ),
                onSelected: widget.locked
                    ? null
                    : (_) => setState(() {
                        _scope = scope;
                        _default = false;
                      }),
              ),
          ],
        ),
        Text(
          _scope == 'property'
              ? tr(
                  'Default for rooms without an override.',
                  'Mặc định cho các phòng chưa có giá riêng.',
                )
              : tr(
                  'An override applies only to this room.',
                  'Giá riêng chỉ áp dụng cho phòng này.',
                ),
        ),
        if (_scope == 'room')
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _default,
            title: Text(
              tr('Use property default', 'Dùng giá mặc định của tòa nhà'),
            ),
            onChanged: widget.locked
                ? null
                : (v) => setState(() => _default = v!),
          ),
        const SizedBox(height: 12),
        Text(tr('Effective date', 'Ngày áp dụng')),
        TextFormField(
          controller: _date,
          enabled: !widget.locked,
          decoration: const InputDecoration(hintText: 'YYYY-MM-DD'),
          validator: (v) => utilityDate((v ?? '').trim())
              ? null
              : tr('Enter a valid date.', 'Nhập ngày hợp lệ.'),
        ),
        const SizedBox(height: 12),
        Text(
          tr(
            'Take a reading on each price-change date. Consumption is never estimated across prices.',
            'Ghi chỉ số vào mỗi ngày đổi giá. Không ước tính mức tiêu thụ giữa các mức giá.',
          ),
        ),
        if (!_default) ...[
          for (var i = 0; i < _prices.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${tr('Tier', 'Bậc')} ${i + 1}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (i < _prices.length - 1) ...[
                    Text(tr('Total usage up to', 'Tổng mức tiêu thụ đến')),
                    TextFormField(
                      controller: _limits[i],
                      enabled: !widget.locked,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        final n = meterMilli(v ?? ''),
                            previous = i == 0
                                ? 0
                                : meterMilli(_limits[i - 1].text);
                        return n != null && previous != null && n > previous
                            ? null
                            : tr(
                                'Use an increasing positive limit.',
                                'Nhập giới hạn dương tăng dần.',
                              );
                      },
                    ),
                  ] else
                    Text(
                      tr('All remaining usage', 'Toàn bộ mức tiêu thụ còn lại'),
                    ),
                  Text(
                    '${tr('Price per unit', 'Đơn giá mỗi đơn vị')} (${widget.currency})',
                  ),
                  TextFormField(
                    controller: _prices[i],
                    enabled: !widget.locked,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: appMoneyInput(widget.currency),
                    validator: (v) => price(v ?? '') != null
                        ? null
                        : tr(
                            'Enter a valid non-negative price.',
                            'Nhập đơn giá không âm hợp lệ.',
                          ),
                  ),
                ],
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: widget.locked || _prices.length >= 12
                    ? null
                    : () => setState(() {
                        _limits.add(TextEditingController());
                        _prices.add(TextEditingController());
                      }),
                child: Text(tr('Add tier', 'Thêm bậc')),
              ),
              if (_prices.length > 1)
                TextButton(
                  onPressed: widget.locked
                      ? null
                      : () => setState(() {
                          _limits.removeLast().dispose();
                          _prices.removeLast().dispose();
                        }),
                  child: Text(tr('Remove', 'Bỏ bậc')),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Text(tr('Reason', 'Lý do')),
        TextFormField(
          controller: _reason,
          enabled: !widget.locked,
          maxLength: 1000,
          validator: (v) =>
              (v ?? '').trim().isEmpty ? tr('Required', 'Bắt buộc') : null,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: widget.locked ? null : save,
            child: Text(tr('Save price', 'Lưu giá')),
          ),
        ),
      ],
    ),
  );
}
