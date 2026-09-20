import 'package:flutter/material.dart';

import '../models/tenants_model.dart';
import '../utils/app_localizations.dart';
import '../utils/app_money.dart';

/// Compact tenant identity and facts, with management actions kept at the edge.
class TenantSummaryCard extends StatelessWidget {
  const TenantSummaryCard({
    super.key,
    required this.tenant,
    required this.translations,
    required this.accentColor,
    required this.buildingName,
    required this.roomNumber,
    required this.onDetails,
    this.onRoom,
    this.onOptions,
    this.onHistory,
  });

  final Tenant tenant;
  final AppTranslations translations;
  final Color accentColor;
  final String buildingName;
  final String roomNumber;
  final VoidCallback onDetails;
  final VoidCallback? onRoom;
  final VoidCallback? onOptions;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final t = translations;
    final scheme = Theme.of(context).colorScheme;
    final movedOut = tenant.status == TenantStatus.moveOut;
    final accent = movedOut ? scheme.onSurfaceVariant : accentColor;
    final status = tenant.getStatusDisplayName(t);
    final menu = onOptions == null
        ? const SizedBox.shrink()
        : IconButton(
            tooltip: t['tenant_options_tooltip'],
            icon: const Icon(Icons.more_vert),
            onPressed: onOptions,
          );
    final identity = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onRoom ?? onDetails,
      onLongPress: onOptions,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                tenant.fullName.isEmpty
                    ? '?'
                    : tenant.fullName.characters.first.toUpperCase(),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tenant.fullName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    tenant.phoneNumber,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (tenant.occupation?.isNotEmpty == true)
                    Text(
                      tenant.occupation!,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    Widget fact(String key, String value, String label, VoidCallback onTap) =>
        _TenantFact(
          key: ValueKey(key),
          value: value,
          label: label,
          onTap: onTap,
        );
    final facts = <Widget>[
      fact(
        'tenant-location',
        t.textWithParams('tenant_location_value', {
          'building': buildingName,
          'room': roomNumber,
        }),
        t[movedOut
            ? 'tenant_previous_location_label'
            : 'tenant_location_label'],
        onRoom ?? onDetails,
      ),
      if (tenant.monthlyRent != null)
        fact(
          'tenant-rent',
          AppMoney.format(tenant.monthlyRent!, tenant.currency),
          t['tenant_detail_monthly_rent'],
          onDetails,
        ),
    ];
    final badges = Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          status,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (tenant.isMainTenant)
          Text(
            t['tenant_main_tenant_badge'],
            style: TextStyle(fontSize: 11, color: scheme.primary),
          ),
        if (tenant.vehicles?.isNotEmpty == true)
          _CountBadge(
            icon: Icons.directions_car_outlined,
            count: tenant.vehicles!.length,
            tooltip: t['tenant_menu_vehicles'],
            onTap: onDetails,
          ),
        if (tenant.previousRentals?.isNotEmpty == true)
          _CountBadge(
            icon: Icons.history,
            count: tenant.previousRentals!.length,
            tooltip: t['tenant_menu_rental_history'],
            onTap: onHistory ?? onDetails,
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              if (constraints.maxWidth >= 1050 * scale) {
                return Row(
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 240 * scale),
                      child: identity,
                    ),
                    const SizedBox(width: 16),
                    // Bound long building / room names without stretching short facts.
                    for (final item in facts) ...[
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: 220 * scale),
                        child: item,
                      ),
                      const SizedBox(width: 8),
                    ],
                    const SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: badges,
                      ),
                    ),
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
                  Wrap(spacing: 8, runSpacing: 8, children: facts),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: badges,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TenantFact extends StatelessWidget {
  const _TenantFact({
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
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
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

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.icon,
    required this.count,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final int count;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
      icon: Icon(icon, size: 16),
      label: Text('$count'),
    ),
  );
}
