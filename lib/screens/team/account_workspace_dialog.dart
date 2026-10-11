import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/team_access.dart';
import '../../services/team_service.dart';
import '../../services/organization_settings_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'google_drive_screen.dart';
import 'ownership_transfer_screen.dart';
import 'payment_accounts_screen.dart';
import 'sheet_import_screen.dart';
import 'ws_ui.dart';
import 'organization_currency_screen.dart';

/// The former Settings destinations, now actions in the Account menu.
class AccountWorkspaceOption {
  final String id, labelKey;
  final IconData icon;
  final bool Function(TeamAccess) allowed;
  const AccountWorkspaceOption(this.id, this.labelKey, this.icon, this.allowed);
  String label(BuildContext context) => id == 'drive'
      ? 'Google Drive'
      : id == 'accounts'
      ? paymentAccountsTitle(context)
      : AppTranslations.of(context)[labelKey];
}

final accountWorkspaceOptions = <AccountWorkspaceOption>[
  AccountWorkspaceOption(
    'ownership',
    'org_transfer_title',
    Icons.swap_horiz,
    (a) => a.isOwner || a.allows(TeamPermission.readOwnActivity),
  ),
  AccountWorkspaceOption('drive', '', Icons.cloud_outlined, (a) => a.isOwner),
  AccountWorkspaceOption(
    'accounts',
    '',
    Icons.account_balance_outlined,
    (a) => a.allows(TeamPermission.manageOrganization),
  ),
  AccountWorkspaceOption('currency', 'organization_currency', Icons.currency_exchange, (a) => true),
  AccountWorkspaceOption(
    'import',
    'nav_import',
    Icons.upload_file_outlined,
    (a) => a.isOwner,
  ),
];

/// The saved access shows the menu at once (2026-10-10, Tom); a fresh check
/// runs on every opening and replaces it. Every action is checked again by
/// the server, so a stale copy can only show a button the server refuses.
class AccountWorkspaceButtons extends StatefulWidget {
  final String organizationId;
  final TeamService service;
  final Widget Function(AccountWorkspaceOption, VoidCallback) tile;
  final FutureOr<void> Function(AccountWorkspaceOption) onOpen;
  final void Function(Future<Map<String, dynamic>?>)? onOwnershipPrefetch;
  const AccountWorkspaceButtons({
    super.key,
    required this.organizationId,
    required this.service,
    required this.tile,
    required this.onOpen,
    this.onOwnershipPrefetch,
  });
  @override
  State<AccountWorkspaceButtons> createState() =>
      _AccountWorkspaceButtonsState();
}

class _AccountWorkspaceButtonsState extends State<AccountWorkspaceButtons> {
  late Future<Map<String, dynamic>?> _access;
  Map<String, dynamic>? _saved;
  bool _opening = false;
  @override
  void initState() {
    super.initState();
    _access = _loadAccess();
    widget.service.savedMyAccess(widget.organizationId).then((saved) {
      if (saved != null && mounted) setState(() => _saved = saved);
    }, onError: (Object _) {});
  }

  Future<Map<String, dynamic>?> _loadAccess() async {
    final data = await widget.service.myAccess(widget.organizationId);
    // The next refresh (after a page closes) shows this answer meanwhile.
    _saved = data;
    final access = TeamAccess.fromMap(data ?? {});
    if (mounted &&
        access.status == 'active' &&
        access.role != null &&
        accountWorkspaceOptions.first.allowed(access) &&
        widget.onOwnershipPrefetch != null) {
      widget.onOwnershipPrefetch!(
        widget.service
            .transferOrganization({
              'action': 'read',
              'organizationId': widget.organizationId,
            })
            .then<Map<String, dynamic>?>(
              (value) => value,
              onError: (Object _) => null,
            ),
      );
    }
    return data;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
    future: _access,
    builder: (context, snapshot) {
      final waiting = snapshot.connectionState != ConnectionState.done;
      if (waiting && _saved == null) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(),
        );
      }
      if (!waiting && snapshot.hasError) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(AppTranslations.of(context)['workspace_denied']),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => setState(() {
                  _access = _loadAccess();
                }),
                child: Text(AppTranslations.of(context)['team_refresh']),
              ),
            ],
          ),
        );
      }
      final access = TeamAccess.fromMap(
        (waiting ? _saved : snapshot.data) ?? {},
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (access.status == 'active' && access.role != null)
            for (final option in accountWorkspaceOptions)
              if (option.allowed(access))
                widget.tile(option, () async {
                  if (_opening) return;
                  _opening = true;
                  try {
                    await widget.onOpen(option);
                  } finally {
                    _opening = false;
                    if (mounted)
                      setState(() {
                        _access = _loadAccess();
                      });
                  }
                }),
        ],
      );
    },
  );
}

Future<void> showAccountWorkspaceDialog(
  BuildContext context, {
  required AccountWorkspaceOption option,
  required String organizationId,
  required TeamService service,
  required VoidCallback onChanged,
  OrganizationSettingsService? settings,
  Future<Map<String, dynamic>?>? ownershipRead,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) => AccountWorkspaceDialog(
    option: option,
    organizationId: organizationId,
    service: service,
    onChanged: onChanged,
    settings: settings,
    ownershipRead: ownershipRead,
  ),
);

/// A bounded viewport, with the form's own scrolling and a persistent Close.
class AccountWorkspaceDialog extends StatelessWidget {
  final AccountWorkspaceOption option;
  final String organizationId;
  final TeamService service;
  final VoidCallback onChanged;
  final OrganizationSettingsService? settings;
  final Future<PickedSheet?> Function()? pickImportFile;
  final Future<Map<String, dynamic>?>? ownershipRead;
  const AccountWorkspaceDialog({
    super.key,
    required this.option,
    required this.organizationId,
    required this.service,
    required this.onChanged,
    this.settings,
    this.pickImportFile,
    this.ownershipRead,
  });
  @override
  Widget build(BuildContext context) {
    final Widget page = switch (option.id) {
      'ownership' => OwnershipTransferScreen(
        organizationId: organizationId,
        service: service,
        onChanged: onChanged,
        initialRead: ownershipRead,
      ),
      'currency' => OrganizationCurrencyScreen(organizationId: organizationId, service: service, onChanged: onChanged),
      'drive' => GoogleDriveScreen(service: service, onChanged: onChanged),
      'accounts' => PaymentAccountsScreen(
        organizationId: organizationId,
        settings: settings,
        onChanged: onChanged,
      ),
      'import' => SheetImportScreen(
        organizationId: organizationId,
        service: service,
        onChanged: onChanged,
        pickFile: pickImportFile,
      ),
      _ => const SizedBox.shrink(),
    };
    final base = Theme.of(context);
    final theme = workspaceTheme(base);
    // Preserve the application's font in the compact button styles too.
    final label = TextStyle(
      fontFamily: base.textTheme.labelLarge?.fontFamily,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );
    return Theme(
      data: theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: theme.filledButtonTheme.style?.copyWith(
            textStyle: WidgetStatePropertyAll(label),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: theme.outlinedButtonTheme.style?.copyWith(
            textStyle: WidgetStatePropertyAll(label),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: theme.textButtonTheme.style?.copyWith(
            textStyle: WidgetStatePropertyAll(label),
          ),
        ),
      ),
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: SizedBox(
          width: 780,
          height:
              (MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).bottom -
                      40)
                  .clamp(0, 720),
          child: Column(
            children: [
              Expanded(child: page),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const ValueKey('account-workspace-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(AppTranslations.of(context)['close']),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
