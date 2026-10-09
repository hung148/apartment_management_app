import '../../services/organization_money.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/organization_settings_service.dart';
import '../../services/team_service.dart';
import '../../utils/app_router.dart';
import '../../utils/localizations/app_localizations.dart';
import 'back_steps.dart';
import 'org_location.dart';
import 'role_workspace.dart';

/// Page for a version-2 organization (U1): title bar + [RoleWorkspace].
/// Keeps the browser address in step with the open section/page/property so
/// a reload comes back to the same place, and makes Back go one step back
/// inside the organization before leaving it.
class OrgShell extends StatefulWidget {
  final String organizationId;

  /// Shown at once when known (opened from the list); loaded otherwise.
  final String? name;
  final OrgLocation? initial;
  final TeamService service;
  final OrganizationSettingsService? settings;
  final VoidCallback? onAccountSettings, onOrganizationSettings, onAccessEnded;
  const OrgShell({
    super.key,
    required this.organizationId,
    required this.service,
    this.name,
    this.initial,
    this.settings,
    this.onAccountSettings,
    this.onOrganizationSettings,
    this.onAccessEnded,
  });
  @override
  State<OrgShell> createState() => _OrgShellState();
}

class _OrgShellState extends State<OrgShell> {
  final _steps = BackSteps();
  String? _name;
  int _nameGeneration = 0;

  @override
  void initState() {
    super.initState();
    _name = widget.name;
    OrganizationMoney.shared.activate(widget.organizationId);
    OrganizationMoney.shared.addListener(_moneyChanged);
    OrganizationMoney.shared.load(widget.organizationId, widget.service).catchError((Object _) {});
    if (_name == null || _name!.isEmpty) _loadName();
  }

  @override
  void dispose() {
    OrganizationMoney.shared.removeListener(_moneyChanged);
    _steps.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant OrgShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.organizationId != widget.organizationId ||
        oldWidget.service != widget.service) {
      OrganizationMoney.shared.activate(widget.organizationId);
      OrganizationMoney.shared
          .load(widget.organizationId, widget.service)
          .catchError((Object _) {});
    }
    if (oldWidget.organizationId != widget.organizationId ||
        oldWidget.settings != widget.settings ||
        oldWidget.name != widget.name) {
      ++_nameGeneration;
      _name = widget.name;
      if (_name == null || _name!.isEmpty) _loadName();
    }
  }

  void _moneyChanged() { if (mounted) setState(() {}); }

  Future<void> _loadName() async {
    final generation = ++_nameGeneration;
    try {
      final read = await (widget.settings ?? OrganizationSettingsService())
          .read(widget.organizationId);
      if (mounted && generation == _nameGeneration) {
        setState(() => _name = read.organization.name);
      }
    } catch (_) {
      // The workspace shows the access problem; the title just stays empty.
    }
  }

  void _addressChanged(OrgLocation location) {
    if (!kIsWeb) return;
    SystemNavigator.routeInformationUpdated(
      uri: Uri.parse(location.address),
      replace: true,
    );
  }

  void _leave() {
    if(widget.onAccessEnded != null) { widget.onAccessEnded!(); return; }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed(AppRouter.dashboardScreen);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BackStepsScope(
      steps: _steps,
      child: Scaffold(
        // The workspace draws its own organization-colored top bar.
        body: Column(children: [
          if (OrganizationMoney.shared.refreshFailed(widget.organizationId))
            MaterialBanner(
              content: Semantics(liveRegion: true, child: Text(AppTranslations.of(context)['organization_currency_rates_failed'])),
              actions: [TextButton(
                onPressed: () => OrganizationMoney.shared
                    .load(widget.organizationId, widget.service)
                    .catchError((Object _) {}),
                child: Text(AppTranslations.of(context)['retry']),
              )],
            ),
          Expanded(child: RoleWorkspace(
          organizationId: widget.organizationId,
          service: widget.service,
          initial: widget.initial,
          title: _name,
          // Same as system Back: one step back inside, then leave.
          onBack: widget.onAccountSettings == null ? () => Navigator.of(context).maybePop() : null,
          onAccountSettings: widget.onAccountSettings,
          onOrganizationSettings: widget.onOrganizationSettings,
          onLocationChanged: _addressChanged,
          onLeave: _leave,
        )),
        ]),
      ),
    );
  }
}
