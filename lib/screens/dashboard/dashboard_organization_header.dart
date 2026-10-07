import 'package:flutter/material.dart';
import '../../utils/localizations/app_localizations.dart';

/// Dashboard-only action group; keeps full headings readable at large text sizes.
class DashboardOrganizationHeader extends StatelessWidget {
  const DashboardOrganizationHeader({super.key, required this.invitation,
    required this.canCreate, required this.onJoin, required this.onCreate,
    required this.onAgreements, this.onDrive});

  final Widget invitation;
  final bool canCreate;
  final VoidCallback onJoin, onCreate, onAgreements;

  /// 2026-10-06 (Tom): Google Drive is connected once here for every
  /// organization the owner owns (null hides the button).
  final VoidCallback? onDrive;

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final colors = Theme.of(context).colorScheme;
    final heading = Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(10)),
        child: Icon(Icons.business_rounded, color: colors.primary, size: 18),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(t.text('your_organizations'),
        style: TextStyle(fontWeight: FontWeight.w800,
          fontSize: MediaQuery.sizeOf(context).width < 600 ? 17 : 19,
          letterSpacing: -0.3))),
    ]);
    final actions = Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton.outlined(tooltip: t['agreements_title'], onPressed: onAgreements,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        icon: const Icon(Icons.handshake_outlined, size: 18)),
      if (onDrive != null) ...[
        const SizedBox(width: 4),
        IconButton.outlined(key: const ValueKey('dashboard-drive'), tooltip: 'Google Drive', onPressed: onDrive,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          icon: const Icon(Icons.add_to_drive_outlined, size: 18)),
      ],
      const SizedBox(width: 4),
      invitation,
      const SizedBox(width: 4),
      IconButton.outlined(tooltip: t.text('join'), onPressed: onJoin,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        icon: const Icon(Icons.group_add_rounded, size: 18)),
      if (canCreate) ...[
        const SizedBox(width: 4),
        IconButton.filled(tooltip: t.text('create'), onPressed: onCreate,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          icon: const Icon(Icons.add_rounded, size: 18)),
      ],
    ]);
    return Row(children: [Expanded(child: heading), const SizedBox(width: 8), actions]);
  }
}
