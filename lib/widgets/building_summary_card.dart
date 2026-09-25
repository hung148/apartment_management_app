import 'package:flutter/material.dart';

import '../models/buildings_model.dart';
import '../models/rooms_model.dart';
import '../models/tenants_model.dart';
import '../utils/localizations/app_localizations.dart';
import '../utils/app_money.dart';
import 'app_dialog.dart';

enum BuildingRoomFilter { all, occupied, vacant }

/// Counts rooms, rather than tenants, so roommates do not inflate occupancy.
class BuildingRoomSummary {
  BuildingRoomSummary(Building building, List<Room> rooms, List<Tenant> tenants)
    : rooms = rooms
          .where(
            (room) =>
                room.buildingId == building.id &&
                room.organizationId == building.organizationId,
          )
          .toList() {
    final ids = this.rooms.map((room) => room.id).toSet();
    for (final tenant in tenants) {
      if (tenant.organizationId == building.organizationId &&
          tenant.buildingId == building.id &&
          tenant.status == TenantStatus.active &&
          ids.contains(tenant.roomId)) {
        occupants.putIfAbsent(tenant.roomId, () => []).add(tenant);
      }
    }
    this.rooms.sort((a, b) => a.roomNumber.compareTo(b.roomNumber));
  }

  final List<Room> rooms;
  final Map<String, List<Tenant>> occupants = {};
  List<Room> matching(BuildingRoomFilter filter) => rooms
      .where(
        (room) => switch (filter) {
          BuildingRoomFilter.all => true,
          BuildingRoomFilter.occupied => occupants.containsKey(room.id),
          BuildingRoomFilter.vacant => !occupants.containsKey(room.id),
        },
      )
      .toList();
}

class BuildingSummaryCard extends StatelessWidget {
  const BuildingSummaryCard({
    super.key,
    required this.building,
    required this.translations,
    required this.color,
    required this.rooms,
    required this.tenants,
    required this.onManage,
    this.onEdit,
    this.onDelete,
    this.loading = false,
    this.hasError = false,
    this.onRetry,
  });

  final Building building;
  final AppTranslations translations;
  final Color color;
  final List<Room> rooms;
  final List<Tenant> tenants;
  final VoidCallback? onManage;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool loading;
  final bool hasError;
  final VoidCallback? onRetry;

  String _label(BuildingRoomFilter filter) =>
      translations[switch (filter) {
        BuildingRoomFilter.all => 'building_stat_total_rooms',
        BuildingRoomFilter.occupied => 'building_stat_rented',
        BuildingRoomFilter.vacant => 'building_stat_vacant',
      }];

  void _showRooms(
    BuildContext context,
    BuildingRoomSummary summary,
    BuildingRoomFilter filter,
  ) {
    final selected = summary.matching(filter);
    _showDetails(context, '${_label(filter)} · ${selected.length}', [
      Text(
        translations['building_occupancy_explanation'],
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      if (selected.isEmpty) Text(translations['building_no_matching_rooms']),
      for (final room in selected)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                translations.textWithParams('building_room_label', {
                  'n': room.roomNumber,
                }),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text('${room.roomType} · ${room.area} m²'),
              if (summary.occupants.containsKey(room.id))
                for (final tenant in summary.occupants[room.id]!)
                  Text(tenant.fullName)
              else
                Text(translations['building_stat_vacant']),
            ],
          ),
        ),
    ]);
  }

  void _showRental(BuildContext context) {
    final t = translations;
    String date(DateTime? value) => value == null
        ? '—'
        : MaterialLocalizations.of(context).formatMediumDate(value);
    _showDetails(context, t['building_management_rented'], [
      for (final entry in <String, String>{
        t['building_renter_name_label']: building.renterName ?? '—',
        t['building_renter_phone_label']: building.renterPhone ?? '—',
        t['building_rent_amount_label']: building.rentAmount == null
            ? '—'
            : AppMoney.format(building.rentAmount!, building.currency),
        t['building_rent_due_day_label']:
            building.rentDueDay?.toString() ?? '—',
        t['building_rent_contract_start_label']: date(
          building.rentContractStart,
        ),
        t['building_rent_contract_end_label']: date(building.rentContractEnd),
        if (building.renterNotes?.isNotEmpty == true)
          t['building_renter_notes_label']: building.renterNotes!,
      }.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.key, style: Theme.of(context).textTheme.bodySmall),
              Text(
                entry.value,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
    ]);
  }

  void _showDetails(BuildContext context, String title, List<Widget> content) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                building.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(building.address),
              Text(
                '${translations['created_at']} ${MaterialLocalizations.of(context).formatMediumDate(building.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Divider(height: 24),
              ...content,
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(translations['close']),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = translations;
    final scheme = Theme.of(context).colorScheme;
    final summary = BuildingRoomSummary(building, rooms, tenants);
    final count = summary.occupants.length;
    final pct = summary.rooms.isEmpty
        ? 0
        : (100 * count / summary.rooms.length).round();
    final actions = <(IconData, String, VoidCallback, bool)>[
      if (onManage != null)
        (
          building.isRented
              ? Icons.real_estate_agent_outlined
              : Icons.meeting_room_outlined,
          t[building.isRented ? 'building_rent_tab_label' : 'manage_rooms'],
          onManage!,
          false,
        ),
      if (onEdit != null) (Icons.edit_outlined, t['edit'], onEdit!, false),
      if (onDelete != null)
        (Icons.delete_outline, t['delete'], onDelete!, true),
    ];
    final menu = actions.isEmpty
        ? const SizedBox.shrink()
        : PopupMenuButton<int>(
            tooltip: t['building_actions'],
            icon: const Icon(Icons.more_vert),
            onSelected: (index) => actions[index].$3(),
            itemBuilder: (context) => [
              for (var i = 0; i < actions.length; i++)
                PopupMenuItem(
                  value: i,
                  child: Row(
                    children: [
                      Icon(
                        actions[i].$1,
                        size: 20,
                        color: actions[i].$4
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          actions[i].$2,
                          style: TextStyle(
                            color: actions[i].$4
                                ? scheme.error
                                : scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
    final identity = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.apartment_rounded, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                building.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                building.address,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
    final status = Text(
      building.isRented
          ? t['building_management_rented']
          : '${pct == 100 ? t['building_status_full'] : t['building_status_active']} · $pct%',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
      ),
    );

    final stats = building.isRented
        ? <Widget>[
            _Stat(
              value: building.rentAmount == null
                  ? '—'
                  : AppMoney.format(building.rentAmount!, building.currency),
              label: t['building_rent_amount_label'],
              onTap: () => _showRental(context),
            ),
            _Stat(
              value: building.rentDueDay?.toString() ?? '—',
              label: t['building_rent_due_day_label'],
              onTap: () => _showRental(context),
            ),
          ]
        : loading
        ? <Widget>[
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(t['loading']),
            ),
          ]
        : hasError
        ? <Widget>[
            Text(t['building_details_load_error']),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(t['retry']),
            ),
          ]
        : <Widget>[
            for (final filter in BuildingRoomFilter.values)
              _Stat(
                key: ValueKey(filter),
                value: '${summary.matching(filter).length}',
                label: _label(filter),
                onTap: () => _showRooms(context, summary, filter),
              ),
          ];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            // Reserve enough width for translated labels and large currency values.
            final horizontal = constraints.maxWidth >= 760 * scale;
            if (horizontal) {
              return Row(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 240 * scale),
                    child: identity,
                  ),
                  const SizedBox(width: 16),
                  ...stats.expand((stat) => [stat, const SizedBox(width: 8)]),
                  const Spacer(),
                  if (building.isRented || (!loading && !hasError)) ...[
                    const SizedBox(width: 8),
                    status,
                  ],
                  menu,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: identity),
                    menu,
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: stats,
                ),
                if (building.isRented || (!loading && !hasError)) ...[
                  const SizedBox(height: 8),
                  status,
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    super.key,
    required this.value,
    required this.label,
    required this.onTap,
  });
  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
