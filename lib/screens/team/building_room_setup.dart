import 'package:flutter/material.dart';
import '../../utils/app_number.dart';
import '../../utils/localizations/app_localizations.dart';
import 'property_initial_rooms.dart';
import 'room_rates_screen.dart' show rateFields;
import 'ws_ui.dart';

/// One set of defaults powers both the saved layout and room generation.
class BuildingRoomPlan {
  final floors = TextEditingController(text: '1');
  final prefix = TextEditingController();
  final type = TextEditingController();
  final area = TextEditingController();
  final count = TextEditingController(text: '0');
  final firstFloor = TextEditingController(text: '1');
  final prices = {for (final k in rateFields) k: TextEditingController()};
  final perFloor = <FloorRoomPlan>[];
  bool uniform = true;
  void load(Map? data) {
    floors.text = '${data?['floors'] ?? 1}';
    prefix.text = '${data?['roomPrefix'] ?? ''}';
    type.text = '${data?['roomType'] ?? ''}';
    final a = data?['roomArea'] as num?;
    area.text = a == null || a == 0 ? '' : '$a';
    final counts = (data?['floorRoomCounts'] as List?) ?? [0];
    uniform = data?['uniformRooms'] as bool? ?? (counts.toSet().length <= 1);
    count.text = '${counts.firstOrNull ?? 0}';
    for (final f in perFloor) {
      f.dispose();
    }
    perFloor.clear();
    for (final c in counts) {
      perFloor.add(FloorRoomPlan('$c'));
    }
    final overrides = data?['floorDefaults'] as List?;
    if (overrides != null) {
      for (var i = 0; i < perFloor.length && i < overrides.length; i++) {
        perFloor[i].type.text = '${overrides[i]['roomType'] ?? ''}';
        final a = overrides[i]['roomArea'] as num?;
        perFloor[i].area.text = a == null || a == 0 ? '' : '$a';
      }
    }
    firstFloor.text = '1';
    for (final p in prices.values) {
      p.clear();
    }
  }

  int get floorCount => int.tryParse(floors.text) ?? 0;
  void syncFloors() {
    if (floorCount < 1 || floorCount > 200) return;
    // Retain drafts if the user temporarily reduces the floor count.
    while (perFloor.length < floorCount) {
      perFloor.add(FloorRoomPlan(count.text));
    }
  }

  Map<String, dynamic> toMap() => {
    'uniformRooms': uniform,
    'floorDefaults': List.generate(
      floorCount,
      (i) => {
        'roomType': uniform ? '' : perFloor[i].type.text.trim(),
        'roomArea': uniform ? 0 : appParseQuantity(perFloor[i].area.text) ?? 0,
      },
    ),
    'floors': floorCount,
    'roomPrefix': prefix.text.trim(),
    'roomType': type.text.trim(),
    'roomArea': appParseQuantity(area.text) ?? 0,
    'floorRoomCounts': List.generate(
      floorCount,
      (i) => int.parse(uniform ? count.text : perFloor[i].count.text),
    ),
  };
  void dispose() {
    for (final c in [
      floors,
      prefix,
      type,
      area,
      count,
      firstFloor,
      ...prices.values,
    ]) {
      c.dispose();
    }
    for (final f in perFloor) {
      f.dispose();
    }
  }
}

class FloorRoomPlan {
  final TextEditingController count;
  final type = TextEditingController(), area = TextEditingController();
  FloorRoomPlan(String value) : count = TextEditingController(text: value);
  void dispose() {
    count.dispose();
    type.dispose();
    area.dispose();
  }
}

class BuildingRoomSetup extends StatefulWidget {
  final BuildingRoomPlan plan;
  final bool locked, canSetPrices;
  final String currency;
  final List<InitialRoomDraft> rooms;
  final ValueChanged<List<InitialRoomDraft>> onGenerate;
  const BuildingRoomSetup({
    super.key,
    required this.plan,
    required this.locked,
    required this.canSetPrices,
    required this.currency,
    required this.rooms,
    required this.onGenerate,
  });
  @override
  State<BuildingRoomSetup> createState() => _BuildingRoomSetupState();
}

class _BuildingRoomSetupState extends State<BuildingRoomSetup> {
  final _generatorForm = GlobalKey<FormState>();
  String? _error;
  BuildingRoomPlan get p => widget.plan;
  String tr(String key) => AppTranslations.of(context)[key];
  Widget field(
    String key,
    String label,
    TextEditingController c, {
    bool number = false,
    bool amount = false,
    int? max,
    String? hint,
    String? Function(String?)? validator,
    ValueChanged<String>? changed,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label),
      const SizedBox(height: 8),
      TextFormField(
        key: ValueKey(key),
        controller: c,
        enabled: !widget.locked,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        inputFormatters: amount ? appMoneyInput(widget.currency) : null,
        maxLength: max,
        minLines: 1,
        maxLines: null,
        decoration: InputDecoration(errorMaxLines: 4, hintText: hint),
        validator: validator,
        onChanged: changed,
      ),
    ],
  );
  String? integer(String? value, int min, int max) {
    final n = int.tryParse(value ?? '');
    return n == null || n < min || n > max
        ? tr('property_invalid_amount')
        : null;
  }

  String? area(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final n = appParseQuantity(value);
    return n == null || n <= 0 || n > 100000
        ? tr('property_invalid_amount')
        : null;
  }

  void generate() {
    if (!(_generatorForm.currentState?.validate() ?? false)) return;
    // The enclosing property form owns shared defaults validation.
    if (p.floorCount < 1 || p.floorCount > 200) {
      setState(() => _error = 'property_invalid_amount');
      return;
    }
    p.syncFloors();
    final counts = List.generate(
      p.floorCount,
      (i) =>
          int.tryParse(p.uniform ? p.count.text : p.perFloor[i].count.text) ??
          -1,
    );
    if (p.floorCount < 1 ||
        p.floorCount > 200 ||
        counts.any((c) => c < 0 || c > 500) ||
        p.prefix.text.length > 20 ||
        p.type.text.length > 160 ||
        area(p.area.text) != null ||
        (!p.uniform &&
            p.perFloor
                .take(p.floorCount)
                .any(
                  (f) => f.type.text.length > 160 || area(f.area.text) != null,
                ))) {
      setState(() => _error = 'property_invalid_amount');
      return;
    }
    final total = counts.fold(0, (a, b) => a + b);
    if (total < 1 || total + widget.rooms.length > 200) {
      setState(() => _error = 'rooms_count_invalid');
      return;
    }
    final first = int.parse(p.firstFloor.text);
    final rows = <InitialRoomDraft>[];
    for (var i = 0; i < counts.length; i++) {
      final custom = p.uniform ? null : p.perFloor[i];
      for (var j = 1; j <= counts[i]; j++) {
        final row = InitialRoomDraft()
          ..name.text =
              '${p.prefix.text.trim()}${first + i}${j.toString().padLeft(2, '0')}'
          ..type.text = custom != null && custom.type.text.trim().isNotEmpty
              ? custom.type.text.trim()
              : p.type.text.trim()
          ..area.text = custom != null && custom.area.text.trim().isNotEmpty
              ? custom.area.text
              : p.area.text;
        for (final k in rateFields) {
          row.prices[k]!.text = widget.canSetPrices ? p.prices[k]!.text : '';
        }
        rows.add(row);
      }
    }
    final taken = widget.rooms
        .map((r) => r.name.text.trim().toLowerCase())
        .toSet();
    if (rows.any((r) => taken.contains(r.name.text.toLowerCase()))) {
      for (final r in rows) {
        r.dispose();
      }
      setState(() => _error = 'property_room_duplicate');
      return;
    }
    setState(() => _error = null);
    widget.onGenerate(rows);
  }

  @override
  Widget build(BuildContext context) {
    p.syncFloors();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('building_section_rooms'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        WsFieldRow(
          children: [
            field(
              'setup-floors',
              tr('building_floors_label'),
              p.floors,
              number: true,
              validator: (v) => integer(v, 1, 200),
              changed: (_) => setState(p.syncFloors),
            ),
            field(
              'setup-prefix',
              tr('building_room_prefix_label'),
              p.prefix,
              max: 20,
            ),
          ],
        ),
        const SizedBox(height: 16),
        WsFieldRow(
          children: [
            field(
              'setup-type',
              tr('building_room_type_label'),
              p.type,
              max: 160,
            ),
            field(
              'setup-area',
              tr('property_room_area_optional'),
              p.area,
              number: true,
              validator: area,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in [true, false])
              ChoiceChip(
                key: ValueKey('setup-uniform-$value'),
                label: Text(tr(value ? 'building_uniform' : 'building_custom')),
                selected: p.uniform == value,
                onSelected: widget.locked
                    ? null
                    : (_) => setState(() {
                        p.syncFloors();
                        p.uniform = value;
                      }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (p.uniform)
          field(
            'setup-count',
            tr('building_rooms_per_floor_label'),
            p.count,
            number: true,
            validator: (v) {
              final invalid = integer(v, 0, 500);
              if (invalid != null) return invalid;
              final total = p.uniform
                  ? (int.tryParse(v ?? '') ?? 0) * p.floorCount
                  : p.perFloor
                        .take(p.floorCount.clamp(0, p.perFloor.length))
                        .fold<int>(
                          0,
                          (sum, f) => sum + (int.tryParse(f.count.text) ?? 0),
                        );
              return total > 10000 ? tr('property_invalid_amount') : null;
            },
          ),
        if (!p.uniform)
          for (
            var i = 0;
            i < p.floorCount.clamp(0, p.perFloor.length);
            i++
          ) ...[
            Text(
              '${tr('building_floor_label')} ${(int.tryParse(p.firstFloor.text) ?? 1) + i}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            field(
              'setup-count-$i',
              tr('building_rooms_per_floor_label'),
              p.perFloor[i].count,
              number: true,
              validator: (v) {
                final invalid = integer(v, 0, 500);
                if (invalid != null) return invalid;
                final total = p.uniform
                    ? (int.tryParse(v ?? '') ?? 0) * p.floorCount
                    : p.perFloor
                          .take(p.floorCount.clamp(0, p.perFloor.length))
                          .fold<int>(
                            0,
                            (sum, f) => sum + (int.tryParse(f.count.text) ?? 0),
                          );
                return total > 10000 ? tr('property_invalid_amount') : null;
              },
            ),
            const SizedBox(height: 16),
            WsFieldRow(
              children: [
                field(
                  'setup-type-$i',
                  tr('building_room_type_label'),
                  p.perFloor[i].type,
                  max: 160,
                  hint: p.type.text,
                ),
                field(
                  'setup-area-$i',
                  tr('property_room_area_optional'),
                  p.perFloor[i].area,
                  number: true,
                  validator: area,
                  hint: p.area.text,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        const SizedBox(height: 24),
        // Generation-only inputs must not block saving building details.
        Form(
          key: _generatorForm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field(
                'setup-first-floor',
                tr('rooms_first_floor'),
                p.firstFloor,
                number: true,
                validator: (v) => integer(v, 0, 999),
                changed: (_) => setState(() {}),
              ),
              if (widget.canSetPrices) ...[
                const SizedBox(height: 16),
                Text(tr('rooms_shared_prices')),
                const SizedBox(height: 8),
                WsFieldRow(
                  children: [
                    for (final k in rateFields)
                      field(
                        'setup-$k',
                        '${tr('rates_$k')} (${widget.currency})',
                        p.prices[k]!,
                        number: true,
                        amount: true,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? null
                            : (appParseMoney(v, widget.currency) ?? 0) <= 0
                            ? tr('property_invalid_amount')
                            : null,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12), Text(tr('building_rooms_review_hint')),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                tr(_error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        const SizedBox(height: 12),
        WsActions(
          children: [
            OutlinedButton.icon(
              key: const ValueKey('setup-generate'),
              onPressed: widget.locked ? null : generate,
              icon: const Icon(Icons.playlist_add),
              label: Text(tr('rooms_generate')),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
