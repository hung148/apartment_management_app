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
  AccountWorkspaceOption(
    'import',
    'nav_import',
    Icons.upload_file_outlined,
    (a) => a.isOwner,
  ),
];

/// Refresh authorization on every menu opening; never show saved owner access.
class AccountWorkspaceButtons extends StatefulWidget {
  final String organizationId;
  final TeamService service;
  final Widget Function(AccountWorkspaceOption, VoidCallback) tile;
  final void Function(AccountWorkspaceOption) onOpen;
  const AccountWorkspaceButtons({
    super.key,
    required this.organizationId,
    required this.service,
    required this.tile,
    required this.onOpen,
  });
  @override
  State<AccountWorkspaceButtons> createState() =>
      _AccountWorkspaceButtonsState();
}

class _AccountWorkspaceButtonsState extends State<AccountWorkspaceButtons> {
  late Future<Map<String, dynamic>?> _access;
  bool _opening = false;
  @override
  void initState() {
    super.initState();
    _access = widget.service.myAccess(widget.organizationId);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
    future: _access,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(),
        );
      }
      if (snapshot.hasError) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(AppTranslations.of(context)['workspace_denied']),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => setState(() {
                  _access = widget.service.myAccess(widget.organizationId);
                }),
                child: Text(AppTranslations.of(context)['team_refresh']),
              ),
            ],
          ),
        );
      }
      final access = TeamAccess.fromMap(snapshot.data ?? {});
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (access.status == 'active' && access.role != null)
            for (final option in accountWorkspaceOptions)
              if (option.allowed(access))
                widget.tile(option, () {
                  if (_opening) return;
                  _opening = true;
                  widget.onOpen(option);
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
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) => AccountWorkspaceDialog(
    option: option,
    organizationId: organizationId,
    service: service,
    onChanged: onChanged,
    settings: settings,
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
  const AccountWorkspaceDialog({
    super.key,
    required this.option,
    required this.organizationId,
    required this.service,
    required this.onChanged,
    this.settings,
    this.pickImportFile,
  });
  @override
  Widget build(BuildContext context) {
    final Widget page = switch (option.id) {
      'ownership' => OwnershipTransferScreen(
        organizationId: organizationId,
        service: service,
        onChanged: onChanged,
      ),
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
