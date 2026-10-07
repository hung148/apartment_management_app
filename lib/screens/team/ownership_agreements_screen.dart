import 'package:flutter/material.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'ws_ui.dart';

/// Compatibility destination for old in-app links. Historical agreements
/// cannot be proposed, approved, or used to grant access.
class OwnershipAgreementsScreen extends StatelessWidget {
  final String? organizationId;
  final TeamService service;
  final bool embedded;
  const OwnershipAgreementsScreen({super.key, this.organizationId,
    required this.service, this.embedded = false});
  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final body = WsPage(children: [WsNotice(t['organization_governance_retired'], tone: WsTone.neutral)]);
    return embedded ? body : Scaffold(appBar: AppBar(title: Text(t['org_entry_title'])), body: body);
  }
}
