import 'package:flutter/material.dart';
import '../../utils/app_number.dart';
import '../../utils/localizations/app_localizations.dart';
import 'room_rates_screen.dart' show rateFields;
import 'ws_ui.dart';

class InitialRoomDraft {
  final name = TextEditingController();
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
    },
  };
  void dispose() {
    for (final c in [name, type, area, ...prices.values]) {
      c.dispose();
    }
  }
}

class PropertyInitialRooms extends StatelessWidget {
  final List<InitialRoomDraft> rooms;
  final String currency;
  final bool locked, canSetPrices;
  final VoidCallback onAdd;
  final void Function(InitialRoomDraft) onRemove;
  const PropertyInitialRooms({
    super.key,
    required this.rooms,
    required this.currency,
    required this.locked,
    required this.canSetPrices,
    required this.onAdd,
    required this.onRemove,
  });
  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t['property_initial_rooms'],
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(t['property_initial_rooms_hint']),
        if (!canSetPrices) ...[
          const SizedBox(height: 8),
          Text(t['property_rooms_no_prices']),
        ],
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
                        return t['property_required'];
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
        const SizedBox(height: 12),
        WsActions(
          children: [
            OutlinedButton.icon(
              key: const ValueKey('property-add-room'),
              onPressed: locked || rooms.length >= 50 ? null : onAdd,
              icon: const Icon(Icons.add),
              label: Text(t['property_add_room']),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
