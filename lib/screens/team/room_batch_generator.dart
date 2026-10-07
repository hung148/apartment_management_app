import 'package:flutter/material.dart';
import '../../utils/app_number.dart';
import '../../utils/localizations/app_localizations.dart';
import 'property_initial_rooms.dart';
import 'room_rates_screen.dart' show rateFields;
import 'ws_ui.dart';

Future<List<InitialRoomDraft>?> generateRoomBatch(
  BuildContext context, {
  required String currency,
  required bool canSetPrices,
  required List<InitialRoomDraft> existing,
}) => showDialog<List<InitialRoomDraft>>(
  context: context,
  builder: (_) => _RoomBatchGenerator(
    currency: currency,
    canSetPrices: canSetPrices,
    existing: existing,
  ),
);

class _RoomBatchGenerator extends StatefulWidget {
  final String currency;
  final bool canSetPrices;
  final List<InitialRoomDraft> existing;
  const _RoomBatchGenerator({
    required this.currency,
    required this.canSetPrices,
    required this.existing,
  });
  @override
  State<_RoomBatchGenerator> createState() => _RoomBatchGeneratorState();
}

class _RoomBatchGeneratorState extends State<_RoomBatchGenerator> {
  final _form = GlobalKey<FormState>();
  final _prefix = TextEditingController();
  final _start = TextEditingController(text: '101');
  final _count = TextEditingController(text: '1');
  final _firstFloor = TextEditingController(text: '1');
  final _floors = TextEditingController(text: '1');
  final _perFloor = TextEditingController(text: '1');
  bool _byFloor = false;
  final _prices = {for (final key in rateFields) key: TextEditingController()};
  String? _error;
  @override
  void dispose() {
    for (final c in [
      _prefix,
      _start,
      _count,
      _firstFloor,
      _floors,
      _perFloor,
      ..._prices.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _generate() {
    if (!_form.currentState!.validate()) return;
    final names = <String>[];
    if (_byFloor) {
      final first = int.parse(_firstFloor.text),
          floors = int.parse(_floors.text),
          perFloor = int.parse(_perFloor.text);
      for (var floor = first; floor < first + floors; floor++) {
        for (var room = 1; room <= perFloor; room++) {
          names.add(
            '${_prefix.text.trim()}$floor${room.toString().padLeft(2, '0')}',
          );
        }
      }
    } else {
      final start = int.parse(_start.text), count = int.parse(_count.text);
      names.addAll(
        List.generate(
          count,
          (i) =>
              '${_prefix.text.trim()}${(start + i).toString().padLeft(_start.text.length, '0')}',
        ),
      );
    }
    final taken = widget.existing
        .map((r) => r.name.text.trim().toLowerCase())
        .toSet();
    if (names.any((n) => taken.contains(n.toLowerCase()))) {
      setState(() => _error = 'property_room_duplicate');
      return;
    }
    final rows = names.map((name) {
      final r = InitialRoomDraft()..name.text = name;
      if (widget.canSetPrices) {
        for (final key in rateFields) {
          r.prices[key]!.text = _prices[key]!.text;
        }
      }
      return r;
    }).toList();
    Navigator.of(context).pop(rows);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    Widget field(
      String key,
      TextEditingController controller, {
      bool number = false,
      String? Function(String?)? validate,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t[key]),
          const SizedBox(height: 8),
          Semantics(
            label: t[key],
            child: TextFormField(
              key: ValueKey(key),
              controller: controller,
              keyboardType: number ? TextInputType.number : TextInputType.text,
              decoration: const InputDecoration(errorMaxLines: 5),
              validator: validate,
            ),
          ),
        ],
      ),
    );
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t['rooms_generate'],
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: t['close'],
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(t['rooms_generate_hint']),
                      const SizedBox(height: 16),
                      field(
                        'rooms_prefix',
                        _prefix,
                        validate: (v) => (v?.trim().length ?? 0) > 60
                            ? t['property_invalid_amount']
                            : null,
                      ),
                      SwitchListTile.adaptive(
                        key: const ValueKey('rooms-by-floor'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(t['rooms_by_floor']),
                        subtitle: Text(t['rooms_floor_example']),
                        value: _byFloor,
                        onChanged: (value) => setState(() {
                          _byFloor = value;
                          _error = null;
                        }),
                      ),
                      const SizedBox(height: 16),
                      if (_byFloor) ...[
                        field(
                          'rooms_first_floor',
                          _firstFloor,
                          number: true,
                          validate: (v) {
                            final n = int.tryParse(v ?? '');
                            return n == null || n < 0 || n > 999
                                ? t['property_invalid_amount']
                                : null;
                          },
                        ),
                        field(
                          'rooms_floors',
                          _floors,
                          number: true,
                          validate: (v) {
                            final n = int.tryParse(v ?? '');
                            return n == null || n < 1 || n > 50
                                ? t['rooms_count_invalid']
                                : null;
                          },
                        ),
                        field(
                          'rooms_per_floor',
                          _perFloor,
                          number: true,
                          validate: (v) {
                            final n = int.tryParse(v ?? ''),
                                floors = int.tryParse(_floors.text);
                            return n == null ||
                                    n < 1 ||
                                    n > 50 ||
                                    floors == null ||
                                    n * floors > 50 - widget.existing.length
                                ? t['rooms_count_invalid']
                                : null;
                          },
                        ),
                      ] else ...[
                        field(
                          'rooms_start',
                          _start,
                          number: true,
                          validate: (v) =>
                              RegExp(r'^\d{1,8}$').hasMatch(v ?? '')
                              ? null
                              : t['property_invalid_amount'],
                        ),
                        field(
                          'rooms_count',
                          _count,
                          number: true,
                          validate: (v) {
                            final n = int.tryParse(v ?? '');
                            return n == null ||
                                    n < 1 ||
                                    n > 50 - widget.existing.length
                                ? t['rooms_count_invalid']
                                : null;
                          },
                        ),
                      ],
                      if (widget.canSetPrices) ...[
                        Text(t['rooms_shared_prices']),
                        const SizedBox(height: 12),
                        for (final key in rateFields) ...[
                          Text('${t['rates_$key']} (${widget.currency})'),
                          const SizedBox(height: 8),
                          Semantics(
                            label: '${t['rates_$key']} (${widget.currency})',
                            child: TextFormField(
                              key: ValueKey('batch-$key'),
                              controller: _prices[key],
                              inputFormatters: appMoneyInput(widget.currency),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                errorMaxLines: 5,
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return null;
                                final n = appParseMoney(v, widget.currency);
                                return n == null || n <= 0
                                    ? t['property_invalid_amount']
                                    : null;
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],
                      if (_error != null) ...[
                        Text(t[_error!]),
                        const SizedBox(height: 12),
                      ],
                      WsActions(
                        children: [
                          FilledButton(
                            onPressed: _generate,
                            child: Text(t['rooms_add_list']),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
