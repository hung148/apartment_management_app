import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/app_number.dart';
import '../../utils/localizations/app_localizations.dart';
import 'room_rates_screen.dart' show rateFields;
import 'ws_ui.dart';

/// Most rooms a list can hold before saving (server limit).
const maxRoomDrafts = 200;

class InitialRoomDraft {
  /// [defaults]: the building prices the row starts with
  /// ('roomPrice' / 'nightlyPrice' → typed text), PRICE_DEFAULTS.md.
  InitialRoomDraft({Map<String, String> defaults = const {}}) {
    for (final field in rateFields) {
      prices[field]!.text = defaults[field] ?? '';
    }
  }
  final name = TextEditingController();

  /// A blank name counts as an error only after the person typed in it or
  /// tried to save: the page form re-checks every field on each change, and
  /// new rows start blank, so untouched rows must not turn red.
  bool showRequired = false;
  final type = TextEditingController();
  final area = TextEditingController();
  final prices = {
    for (final field in rateFields) field: TextEditingController(),
  };
  Map<String, dynamic> toMap(String currency) => {
    'roomNumber': name.text.trim(),
    'roomType': type.text.trim(),
    'area': area.text.trim().isEmpty ? null : appParseQuantity(area.text),
    'ratesMinor': {
      for (final field in rateFields)
        field: prices[field]!.text.trim().isEmpty
            ? null
            : appParseMoney(prices[field]!.text, currency),
      // No flat price per hour any more (2026-10-26); the server still
      // expects the field.
      'hourlyPrice': null,
    },
  };
  void dispose() {
    for (final c in [name, type, area, ...prices.values]) {
      c.dispose();
    }
  }
}

/// Room list to fill in before saving. The person types how many rooms
/// they want, taps "Create list", and fills in each room (2026-10-23, Tom:
/// the old prefix / floor / shared-price generator was too complicated).
class PropertyInitialRooms extends StatelessWidget {
  final List<InitialRoomDraft> rooms;
  final String currency;
  final String? title, hint;
  final bool locked, canSetPrices, autofocusCount;

  /// Building prices new rows start with (see [InitialRoomDraft]).
  final Map<String, String> defaults;
  final VoidCallback onAdd;
  final void Function(List<InitialRoomDraft>) onGenerate;
  final void Function(InitialRoomDraft) onRemove;
  const PropertyInitialRooms({
    super.key,
    required this.rooms,
    required this.currency,
    this.title,
    this.hint,
    required this.locked,
    required this.canSetPrices,
    required this.onAdd,
    required this.onGenerate,
    required this.onRemove,
    this.autofocusCount = false,
    this.defaults = const {},
  });
  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title ?? t['property_initial_rooms'],
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(hint ?? t['property_initial_rooms_hint']),
        if (!canSetPrices) ...[
          const SizedBox(height: 8),
          Text(t['property_rooms_no_prices']),
        ],
        const SizedBox(height: 16),
        RoomCountRow(
          existing: rooms.length,
          locked: locked,
          autofocus: autofocusCount,
          onCreate: (count) =>
              onGenerate(
                List.generate(
                  count,
                  (_) => InitialRoomDraft(
                    defaults: canSetPrices ? defaults : const {},
                  ),
                ),
              ),
        ),
        for (final (index, room) in rooms.indexed) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                key: ObjectKey(room),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${t['property_room_label']} ${index + 1}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        key: ValueKey('initial-room-remove-$index'),
                        tooltip: t['property_remove_room'],
                        onPressed: locked ? null : () => onRemove(room),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: ValueKey('initial-room-name-$index'),
                    controller: room.name,
                    onChanged: (_) => room.showRequired = true,
                    enabled: !locked,
                    maxLength: 80,
                    minLines: 1,
                    maxLines: null,
                    decoration: InputDecoration(
                      labelText: t['property_room_name'],
                      errorMaxLines: 4,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return room.showRequired
                            ? t['property_required']
                            : null;
                      }
                      if (rooms
                              .where(
                                (r) =>
                                    r.name.text.trim().toLowerCase() ==
                                    v.trim().toLowerCase(),
                              )
                              .length >
                          1) {
                        return t['property_room_duplicate'];
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(t['property_room_type']),
                  const SizedBox(height: 8),
                  Semantics(
                    label: t['property_room_type'],
                    child: TextFormField(
                      key: ValueKey('initial-room-type-$index'),
                      controller: room.type,
                      enabled: !locked,
                      maxLength: 160,
                      minLines: 1,
                      maxLines: null,
                      decoration: InputDecoration(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(t['property_room_area_optional']),
                  const SizedBox(height: 8),
                  Semantics(
                    label: t['property_room_area_optional'],
                    child: TextFormField(
                      key: ValueKey('initial-room-area-$index'),
                      controller: room.area,
                      enabled: !locked,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(errorMaxLines: 4),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final n = appParseQuantity(v);
                        return n == null || n <= 0 || n > 100000
                            ? t['property_invalid_amount']
                            : null;
                      },
                    ),
                  ),
                  if (canSetPrices)
                    for (final field in rateFields) ...[
                      const SizedBox(height: 16),
                      Text('${t['rates_$field']} ($currency)'),
                      const SizedBox(height: 8),
                      Semantics(
                        label: '${t['rates_$field']} ($currency)',
                        child: TextFormField(
                          key: ValueKey('initial-room-$field-$index'),
                          controller: room.prices[field],
                          enabled: !locked,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: appMoneyInput(currency),
                          decoration: InputDecoration(
                            errorMaxLines: 4,
                            helperText: t['property_optional'],
                            helperMaxLines: 3,
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return null;
                            final n = appParseMoney(v, currency);
                            return n == null || n <= 0
                                ? t['property_invalid_amount']
                                : null;
                          },
                        ),
                      ),
                    ],
                ],
              ),
            ),
          ),
        ],
        if (rooms.isNotEmpty) ...[
          const SizedBox(height: 12),
          WsActions(
            children: [
              OutlinedButton.icon(
                key: const ValueKey('property-add-room'),
                onPressed: locked || rooms.length >= maxRoomDrafts
                    ? null
                    : onAdd,
                icon: const Icon(Icons.add),
                label: Text(t['property_add_room']),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}

/// "Number of rooms" + "Create list". Has its own form so an empty count
/// never blocks saving the page.
class RoomCountRow extends StatefulWidget {
  final int existing;
  final bool locked, autofocus;
  final ValueChanged<int> onCreate;
  const RoomCountRow({
    super.key,
    required this.existing,
    required this.locked,
    required this.onCreate,
    this.autofocus = false,
  });
  @override
  State<RoomCountRow> createState() => _RoomCountRowState();
}

class _RoomCountRowState extends State<RoomCountRow> {
  final _form = GlobalKey<FormState>();
  final _count = TextEditingController();
  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  bool get _full => widget.existing >= maxRoomDrafts;

  void _create() {
    if (widget.locked || _full) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    widget.onCreate(int.parse(_count.text.trim()));
    _count.clear();
    _form.currentState?.reset();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final field = TextFormField(
      key: const ValueKey('rooms-count'),
      controller: _count,
      enabled: !widget.locked && !_full,
      autofocus: widget.autofocus,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(3),
      ],
      decoration: InputDecoration(
        labelText: t['rooms_count'],
        errorMaxLines: 4,
      ),
      validator: (v) {
        final n = int.tryParse(v?.trim() ?? '');
        return n == null || n < 1 || n > maxRoomDrafts - widget.existing
            ? t['rooms_count_invalid']
            : null;
      },
      onFieldSubmitted: (_) => _create(),
    );
    final button = FilledButton.tonalIcon(
      key: const ValueKey('rooms-make-list'),
      onPressed: widget.locked || _full ? null : _create,
      icon: const Icon(Icons.playlist_add),
      label: Text(t['rooms_make_list'], maxLines: 1, softWrap: false),
    );
    return Form(
      key: _form,
      child: LayoutBuilder(
        builder: (context, box) {
          // Narrow screens / large text: the button gets its own line.
          final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
          if (box.maxWidth < 300 * textScale) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                field,
                const SizedBox(height: 8),
                Align(alignment: AlignmentDirectional.centerEnd, child: button),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: field),
              const SizedBox(width: 12),
              Padding(padding: const EdgeInsets.only(top: 6), child: button),
            ],
          );
        },
      ),
    );
  }
}
