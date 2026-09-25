import 'package:flutter/material.dart';
import '../utils/localizations/app_localizations.dart';
import 'compact_summary_toolbar.dart';

/// Compact tenant totals with actions that remain visible on narrow screens.
class TenantToolbar extends StatelessWidget {
  const TenantToolbar({
    super.key,
    required this.counts,
    required this.searchController,
    this.onAdd,
  });

  final List<int> counts;
  final TextEditingController searchController;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    return CompactSummaryToolbar(
      values: counts.map((count) => '$count').toList(),
      labels: [
        t['tenant_status_active'],
        t['tenant_status_inactive'],
        t['tenant_status_moved_out'],
      ],
      icons: const [
        Icons.person_rounded,
        Icons.pause_circle_outline,
        Icons.logout_rounded,
      ],
      searchController: searchController,
      searchTitle: t['tenant_search_title'],
      searchHint: t['tenant_search_hint'],
      addLabel: t['tenant_add_button'],
      addIcon: Icons.person_add_rounded,
      actionKeyPrefix: 'tenant',
      onAdd: onAdd,
    );
  }
}
