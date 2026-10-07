import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import '../../utils/localizations/app_localizations.dart';
import '../../widgets/app_dialog.dart';

/// Replace Account with its child, then rebuild a fresh Account menu on return.
/// The route check also prevents rapid taps from opening multiple children.
Future<void> openAccountChild(
  BuildContext menuContext, {
  required Future<void> Function() open,
  required VoidCallback reopen,
  required bool Function() canReopen,
}) async {
  if (!menuContext.mounted || ModalRoute.of(menuContext)?.isCurrent != true)
    return;
  Navigator.of(menuContext).pop();
  try {
    await open();
  } finally {
    if (canReopen()) reopen();
  }
}

class AccountMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconBg, iconColor;
  const AccountMenuTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconBg,
    this.iconColor,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg ?? AppThemePalette.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: iconColor ?? AppThemePalette.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF172D3B),
              ),
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: Colors.grey.withValues(alpha: .5),
          ),
        ],
      ),
    ),
  );
}

/// Keep Account's close reachable while the menu body scrolls.
class AccountMenuDialog extends StatelessWidget {
  final double maxWidth;
  final List<Widget> children;
  const AccountMenuDialog({
    super.key,
    required this.maxWidth,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => AppDialog(
    elevation: 0,
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppThemePalette.primaryMid, AppThemePalette.primaryDeep],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.person_outline,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppTranslations.of(context)['account_menu'],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: const ValueKey('account-menu-close'),
                tooltip: AppTranslations.of(context)['close'],
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ],
    ),
  );
}
