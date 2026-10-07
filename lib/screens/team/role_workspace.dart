import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/team_access.dart';
import '../../services/read_cache.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import '../calendar/room_calendar.dart';
import 'activity_history.dart';
import 'invoice_screen.dart';
import 'operational_widgets.dart';
import 'org_location.dart';
import 'payment_accounts_screen.dart';
import 'sheet_import_screen.dart';
import 'google_drive_screen.dart';
import 'ownership_transfer_screen.dart';
import 'team_display.dart';
import 'team_screen.dart';
import 'tenant_contacts_screen.dart';
import 'workspace_records.dart';
import 'ws_ui.dart';
import 'workspace_page_scope.dart';
import '../../utils/app_theme.dart';

/// Everything a page builder needs.
class WorkspaceContext {
  final String organizationId;
  final String? buildingId;
  final String accountId;
  final TeamAccess access;
  final TeamService service;

  /// Reloads access and the property list (after a property is created or
  /// deleted, or when the server says access changed).
  final VoidCallback reload;

  /// Fresh ID for the "create property" page.
  final String newPropertyId;

  /// After creating a property: reload and open its rooms.
  final ValueChanged<String> openProperty;

  /// A booking/room/tenant to open first (from the address), else null.
  final String? recordId;

  /// The page reports the record it shows (null = its list) for the address.
  final ValueChanged<String?> onRecord;
  const WorkspaceContext({
    required this.organizationId,
    required this.buildingId,
    required this.accountId,
    required this.access,
    required this.service,
    required this.reload,
    required this.newPropertyId,
    required this.openProperty,
    this.recordId,
    required this.onRecord,
  });
}

class WorkspacePage {
  final String id;
  final String Function(BuildContext context, TeamAccess access) label;

  /// Needs a chosen property.
  final bool perProperty;
  final bool Function(TeamAccess access, String? buildingId) allowed;
  final Widget Function(WorkspaceContext c) build;
  const WorkspacePage({
    required this.id,
    required this.label,
    required this.perProperty,
    required this.allowed,
    required this.build,
  });
}

class WorkspaceSection {
  final String id;
  final IconData icon;
  final String labelKey;
  final List<WorkspacePage> pages;
  const WorkspaceSection(this.id, this.icon, this.labelKey, this.pages);

  List<WorkspacePage> allowedPages(TeamAccess access, String? buildingId) => [
    for (final p in pages)
      if ((!p.perProperty || buildingId != null) &&
          p.allowed(access, buildingId))
        p,
  ];
}

String _t(BuildContext context, String key) => AppTranslations.of(context)[key];

/// The organization's sections in menu order (U1). Dashboard, Expenses and
/// Reports are added when they are built (G4/E1/E2).
final List<WorkspaceSection> workspaceSections = [
  // C1–C3: every visible property's rooms in one calendar (no property picker).
  // Who sees which property is decided per property by the server.
  WorkspaceSection('calendar', Icons.calendar_month_outlined, 'nav_calendar', [
    WorkspacePage(
      id: 'board',
      label: (c, _) => _t(c, 'nav_calendar'),
      perProperty: false,
      allowed: (a, _) => _calendarAllowed(a),
      build: (c) => RoomCalendar(
        organizationId: c.organizationId,
        accountId: c.accountId,
        service: c.service,
        access: c.access,
      ),
    ),
  ]),
  // 2026-10-04: no Đặt phòng page; bookings are made and opened on the calendar.
  // Rooms, the building layout and service fees open from the calendar now
  // (tap a room or the building name), 2026-10-03.
  WorkspaceSection('tenants', Icons.people_outline, 'nav_tenants', [
    WorkspacePage(
      id: 'list',
      label: (c, _) => _t(c, 'tenant_contacts_title'),
      perProperty: true,
      allowed: (a, b) => a.allows(TeamPermission.manageLease, buildingId: b),
      build: (c) => TenantContactsScreen(
        organizationId: c.organizationId,
        buildingId: c.buildingId!,
        service: c.service,
        initialRecordId: c.recordId,
        onRecordChanged: c.onRecord,
      ),
    ),
  ]),
  WorkspaceSection('money', Icons.payments_outlined, 'nav_money', [
    WorkspacePage(
      id: 'invoices',
      label: (c, _) => opsText(c, 'invoices'),
      perProperty: true,
      allowed: (a, b) =>
          a.allows(TeamPermission.readFinancialReports, buildingId: b),
      build: (c) => InvoiceScreen(
        organizationId: c.organizationId,
        buildingId: c.buildingId!,
        accountId: c.accountId,
        service: c.service,
      ),
    ),
    WorkspacePage(
      id: 'payments',
      label: (c, _) => _t(c, 'workspace_paymentActions'),
      perProperty: true,
      allowed: (a, b) =>
          a.allows(TeamPermission.collectPayments, buildingId: b) ||
          a.allows(TeamPermission.refundPayments, buildingId: b),
      build: (c) => WorkspaceRecords(
        organizationId: c.organizationId,
        buildingId: c.buildingId!,
        accountId: c.accountId,
        view: 'paymentActions',
        service: c.service,
        onDenied: c.reload,
      ),
    ),
    WorkspacePage(
      id: 'financial',
      label: (c, _) => _t(c, 'workspace_financial'),
      perProperty: true,
      allowed: (a, b) =>
          a.allows(TeamPermission.readFinancialReports, buildingId: b),
      build: (c) => WorkspaceRecords(
        organizationId: c.organizationId,
        buildingId: c.buildingId!,
        accountId: c.accountId,
        view: 'financial',
        service: c.service,
        onDenied: c.reload,
      ),
    ),
  ]),
  // 2026-10-05 (Tom): cleaning and problems live on the calendar for
  // everyone (cleaners see cleaning only), so their own sections are gone.
  WorkspaceSection('staff', Icons.badge_outlined, 'nav_staff', [
    WorkspacePage(
      id: 'team',
      label: (c, a) => _t(
        c,
        a.allBuildings && a.allows(TeamPermission.manageTeam)
            ? 'team_title'
            : 'team_profile',
      ),
      perProperty: false,
      allowed: (a, _) =>
          (a.allBuildings && a.allows(TeamPermission.manageTeam)) ||
          a.allows(TeamPermission.readOwnActivity),
      build: (c) =>
          TeamScreen(organizationId: c.organizationId, service: c.service),
    ),
    WorkspacePage(
      id: 'activity',
      label: (c, _) => _t(c, 'activity_title'),
      perProperty: false,
      allowed: (a, _) => a.allows(TeamPermission.readOwnActivity),
      build: (c) =>
          ActivityHistory(organizationId: c.organizationId, service: c.service),
    ),
  ]),
  WorkspaceSection('settings', Icons.settings_outlined, 'nav_settings', [
    WorkspacePage(id:'ownership',label:(c,_)=>_t(c,'org_transfer_title'),perProperty:false,
      allowed:(a,_)=>a.isOwner||a.allows(TeamPermission.readOwnActivity),
      build:(c)=>OwnershipTransferScreen(organizationId:c.organizationId,service:c.service,onChanged:c.reload)),
    WorkspacePage(
      id: 'drive', label: (c, _) => 'Google Drive', perProperty: false,
      allowed: (a, _) => a.isOwner,
      build: (c) => GoogleDriveScreen(service: c.service),
    ),
    // Building details, the whole-building contract and "new building" are on
    // the calendar now (building name / Tạo tòa nhà), 2026-10-03.
    // B8-lite: where deposits and payments are received.
    WorkspacePage(
      id: 'accounts',
      label: (c, _) => paymentAccountsTitle(c),
      perProperty: false,
      allowed: (a, _) => a.allows(TeamPermission.manageOrganization),
      build: (c) => PaymentAccountsScreen(organizationId: c.organizationId),
    ),
    // 2026-10-05 (Tom): import the old app's .xlsx export; the owner only.
    WorkspacePage(
      id: 'import',
      label: (c, _) => _t(c, 'nav_import'),
      perProperty: false,
      allowed: (a, _) => a.isOwner,
      build: (c) => SheetImportScreen(
        organizationId: c.organizationId,
        service: c.service,
      ),
    ),
  ]),
];

/// Phone bottom bar: these first (when allowed), the rest under "More".
const _mainSections = ['calendar', 'tenants', 'money'];

/// A version-2 organization: section menu (tabs in the top bar when they fit, bottom bar
/// on phones), one property picker for every section, and the chosen page.
class RoleWorkspace extends StatefulWidget {
  final String organizationId;
  final TeamService service;

  /// Section/page/property to open first (from the address).
  final OrgLocation? initial;

  /// Told whenever the shown section/page/property changes (address bar).
  final ValueChanged<OrgLocation>? onLocationChanged;

  /// Leave the organization (shown when access is gone).
  final VoidCallback? onLeave;

  /// Organization name for the top bar.
  final String? title;

  /// Top-bar back arrow (one step back, then leave).
  final VoidCallback? onBack;
  final VoidCallback? onAccountSettings, onOrganizationSettings;
  const RoleWorkspace({
    super.key,
    required this.organizationId,
    required this.service,
    this.initial,
    this.onLocationChanged,
    this.onLeave,
    this.title,
    this.onBack,
    this.onAccountSettings,
    this.onOrganizationSettings,
  });
  @override
  State<RoleWorkspace> createState() => _RoleWorkspaceState();
}

class _RoleWorkspaceState extends State<RoleWorkspace> {
  TeamAccess? _access;
  List<Map<String, dynamic>> _properties = [];
  String? _building, _section, _page;

  /// Record open in the page (address only). [_linkRecord]: the one from the
  /// address, handed to the first matching page once.
  String? _record, _linkRecord;
  String? _linkSection, _linkPage;
  String _accountId = '';
  String _newPropertyId = const Uuid().v4();
  // Tapping the section or page that is already open goes back to its list.
  int _restart = 0;
  bool _busy = true, _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _section = widget.initial?.section;
    _page = widget.initial?.page;
    _building = widget.initial?.propertyId;
    _linkRecord = widget.initial?.record;
    _linkSection = widget.initial?.section;
    _linkPage = widget.initial?.page;
    _load();
  }

  @override
  void didUpdateWidget(covariant RoleWorkspace old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.service != widget.service) {
      _section = null;
      _page = null;
      _building = null;
      _load();
    }
  }

  /// The pages show the device copy (saved role and buildings) until the
  /// server answers (2026-10-06, speed step 1).
  bool _fromSaved = false;

  void _show(
    Map<String, dynamic>? raw,
    TeamAccess access,
    List<Map<String, dynamic>> properties,
  ) {
    _access = access;
    _accountId = raw?['ownerId'] as String? ?? '';
    _properties = properties;
    // Keep the chosen property when it is still available.
    if (!properties.any((p) => p['id'] == _building)) {
      _building = properties.firstOrNull?['id'] as String?;
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    // Speed (2026-10-06, device copy): the saved role and building list open
    // the pages right away; the server's answer below replaces them. Only to
    // show: every change still goes to the server, which checks the role.
    setState(() {
      _busy = true;
      _failed = false;
    });
    // Read (decrypt) the saved copy alongside the server calls below; it is
    // shown only if the server has not answered yet.
    var answered = false;
    if (_access == null) {
      unawaited(() async {
        try {
          final raw = await widget.service.savedMyAccess(widget.organizationId);
          final list = (await widget.service.saved(
            'properties',
            widget.organizationId,
          ))?['records'];
          if (!mounted ||
              generation != _generation ||
              answered ||
              _access != null) {
            return;
          }
          final access = raw == null ? null : TeamAccess.fromMap(raw);
          if (access == null ||
              access.role == null ||
              access.status != 'active' ||
              list is! List) {
            return;
          }
          setState(() {
            _show(raw, access, [
              for (final p in list)
                if (p is Map) Map<String, dynamic>.from(p),
            ]);
            _fromSaved = true;
            _newPropertyId = const Uuid().v4();
            _settle();
          });
        } catch (_) {}
      }());
    }
    // Speed (2026-10-06): the access and the building list are asked for at
    // the same time instead of one after the other (one server trip less
    // before the first page). A failed building list is only reported once
    // the access is known, so an access problem is still shown as one.
    Future<List<Map<String, dynamic>>> loadProperties() async {
      final properties = <Map<String, dynamic>>[];
      String? cursor;
      do {
        final page = await widget.service.workspace(
          widget.organizationId,
          'properties',
          cursor: cursor,
        );
        properties.addAll(page.records);
        cursor = page.nextCursor;
      } while (cursor != null);
      return properties;
    }

    final propertiesLoad = loadProperties();
    // Never an unhandled error when the access check fails first.
    propertiesLoad.catchError((_) => <Map<String, dynamic>>[]).ignore();
    try {
      final raw = await widget.service.myAccess(widget.organizationId);
      final access = TeamAccess.fromMap(raw ?? {});
      if (access.role == null || access.status != 'active') {
        throw StateError('No active access');
      }
      final properties = await propertiesLoad;
      answered = true;
      widget.service.save('properties', widget.organizationId, {
        'records': properties,
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        _show(raw, access, properties);
        _fromSaved = false;
        _newPropertyId = const Uuid().v4();
        _busy = false;
        _settle();
      });
    } catch (e) {
      answered = true;
      // Showing the saved copy and the server is just unreachable: keep it
      // (the pages report their own failed reads). Any access problem, or a
      // failure after the server's own answer, clears the pages as before.
      if (mounted &&
          generation == _generation &&
          _fromSaved &&
          !ReadCache.isAccessError(e) &&
          e is! StateError) {
        setState(() => _busy = false);
        return;
      }
      // The saved copy must not come back next time either.
      if (_fromSaved) await widget.service.forgetSaved(widget.organizationId);
      _fromSaved = false;
      if (mounted && generation == _generation) {
        setState(() {
          _access = null;
          _properties = [];
          _failed = true;
          _busy = false;
        });
      }
    }
  }

  List<WorkspaceSection> _allowedSections(TeamAccess access) => [
    for (final s in workspaceSections)
      if (s.allowedPages(access, _building).isNotEmpty) s,
  ];

  /// Falls back to the first allowed section/page and reports the address.
  void _settle() {
    final access = _access;
    if (access == null) return;
    final sections = _allowedSections(access);
    // A new organization starts on the calendar, which offers "create the
    // first building".
    final section =
        sections.where((s) => s.id == _section).firstOrNull ??
        sections.firstOrNull;
    _section = section?.id;
    final pages = section?.allowedPages(access, _building) ?? const [];
    _page = (pages.where((p) => p.id == _page).firstOrNull ?? pages.firstOrNull)
        ?.id;
    _report();
  }

  void _report() {
    final access = _access;
    if (access == null) return;
    final section = workspaceSections
        .where((s) => s.id == _section)
        .firstOrNull;
    final pages = section?.allowedPages(access, _building) ?? const [];
    final needsProperty = pages.any((p) => p.id == _page && p.perProperty);
    widget.onLocationChanged?.call(
      OrgLocation(
        widget.organizationId,
        section: _section,
        page: _page,
        propertyId: needsProperty ? _building : null,
        record: _record,
      ),
    );
  }

  /// The address's record goes to its page once; later visits start at the list.
  String? _takeLink(String section, String page) {
    if (_linkRecord == null) return null;
    if (_linkSection != section || _linkPage != page) return null;
    final id = _linkRecord;
    _linkRecord = null;
    // Leave [_record] empty: the address was already rewritten without the
    // record while the workspace loaded, so the page's own report of what it
    // opened must count as a change and put the record back in the address.
    return id;
  }

  void _go({String? section, String? page, String? building}) {
    setState(() {
      if ((section != null && section == _section) ||
          (section == null && page != null && page == _page)) {
        _restart++;
      }
      _record = null;
      _linkRecord = null;
      if (section != null && section != _section) {
        _section = section;
        _page = null;
      }
      if (page != null) _page = page;
      if (building != null) _building = building;
      _settle();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context), access = _access;
    final base = Theme.of(context);
    final sections = access == null
        ? <WorkspaceSection>[]
        : _allowedSections(access);
    final section = sections.where((s) => s.id == _section).firstOrNull;
    final pages = access == null || section == null
        ? const <WorkspacePage>[]
        : section.allowedPages(access, _building);
    final page = pages.where((p) => p.id == _page).firstOrNull;

    Widget body;
    if (access == null) {
      body = WsPage(
        maxWidth: 480,
        children: [
          if (_busy) ...[
            const SizedBox(height: 120),
            const LinearProgressIndicator(),
          ],
          if (_failed) ...[
            const SizedBox(height: 48),
            WsEmpty(
              icon: Icons.lock_outline,
              message: t['workspace_denied'],
              action: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : _load,
                    child: Text(t['team_refresh']),
                  ),
                  if (widget.onLeave != null)
                    TextButton(
                      key: const ValueKey('workspace-leave'),
                      onPressed: widget.onLeave,
                      child: Text(t['workspace_back_to_list']),
                    ),
                ],
              ),
            ),
          ],
        ],
      );
    } else if (section == null || page == null) {
      // Nothing this role may open here yet (e.g. no property assigned).
      body = WsPage(
        maxWidth: 560,
        children: [
          const SizedBox(height: 48),
          WsEmpty(
            icon: Icons.apartment_outlined,
            message: t['workspace_no_properties'],
            action: OutlinedButton(
              onPressed: _busy ? null : _load,
              child: Text(t['team_refresh']),
            ),
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ContextStrip(
            properties: page.perProperty ? _properties : const [],
            building: _building,
            pages: pages,
            page: page.id,
            access: access,
            busy: _busy,
            onProperty: (b) => _go(building: b),
            onPage: (p) => _go(page: p),
            onReload: _load,
          ),
          SizedBox(
            height: 3,
            child: _busy ? const LinearProgressIndicator() : null,
          ),
          Expanded(
            child: WorkspacePageScope(
              child: KeyedSubtree(
                key: ValueKey(
                  '${section.id}/${page.id}/${page.perProperty ? _building : ''}/$_newPropertyId/$_restart',
                ),
                child: page.build(
                  WorkspaceContext(
                    organizationId: widget.organizationId,
                    buildingId: _building,
                    accountId: _accountId,
                    access: access,
                    service: widget.service,
                    reload: _load,
                    newPropertyId: _newPropertyId,
                    openProperty: (id) {
                      _building = id;
                      _section = 'rooms';
                      _page = null;
                      _load();
                    },
                    recordId: _takeLink(section.id, page.id),
                    onRecord: (id) {
                      if (id == _record) return;
                      _record = id;
                      _report();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Theme(
      data: workspaceTheme(base),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final inline =
              sections.length > 1 &&
              _HeaderBar.tabsFit(context, sections, constraints.maxWidth);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeaderBar(
                organizationId: widget.organizationId,
                title: widget.title ?? '',
                roleLabel: access == null
                    ? ''
                    : teamRoleLabel(t, access.role, access.roleName),
                sections: inline ? sections : const [],
                selected: _section,
                onBack: widget.onBack,
                onAccountSettings: widget.onAccountSettings,
                onOrganizationSettings: access?.allows(TeamPermission.manageOrganization) == true ? widget.onOrganizationSettings : null,
                onSelect: (s) => _go(section: s),
              ),
              Expanded(
                // Material (not a plain colored box) so list ripples show.
                child: Material(
                  color: base.scaffoldBackgroundColor,
                  child: SafeArea(top: false, bottom: inline, child: body),
                ),
              ),
              if (!inline && sections.length > 1)
                _BottomBar(
                  sections: sections,
                  selected: _section,
                  onSelect: (s) => _go(section: s),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Organization-colored top bar (like v1): back, name and role, and on wide
/// screens the section tabs as white pills.
class _HeaderBar extends StatelessWidget {
  final String organizationId;
  final String title;
  final String roleLabel;
  final List<WorkspaceSection> sections;
  final String? selected;
  final VoidCallback? onBack;
  final VoidCallback? onAccountSettings, onOrganizationSettings;
  final ValueChanged<String> onSelect;
  const _HeaderBar({
    required this.organizationId,
    required this.title,
    required this.roleLabel,
    required this.sections,
    required this.selected,
    required this.onBack,
    this.onAccountSettings,
    this.onOrganizationSettings,
    required this.onSelect,
  });

  static const _labelStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  /// Whether every tab fits on one line next to a readable title.
  static bool tabsFit(
    BuildContext context,
    List<WorkspaceSection> sections,
    double width,
  ) {
    if (width < 880) return false;
    final t = AppTranslations.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    var needed = 0.0;
    for (final s in sections) {
      final painter = TextPainter(
        text: TextSpan(text: t[s.labelKey], style: _labelStyle),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      needed += painter.width + 18 + 6 + 24 + 4;
      painter.dispose();
    }
    return needed + 260 <= width;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // repaint when the accent changes
    final colors = AppThemePalette.identityGradient(organizationId);
    final background = colors.last;
    // Like v1: the bar keeps its height; very large text is capped here.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: _bar(context, background),
    );
  }

  Widget _bar(BuildContext context, Color background) {
    return Material(
      color: background,
      child: SafeArea(
        bottom: false,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              if (onBack != null)
                IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  color: Colors.white,
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  onPressed: onBack,
                )
              else
                const SizedBox(width: 16),
              const Icon(
                Icons.apartment_outlined,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (roleLabel.isNotEmpty)
                      Text(
                        roleLabel,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if(onAccountSettings != null)
                IconButton(tooltip: AppTranslations.of(context)['account_menu'], color: Colors.white,
                  icon: const Icon(Icons.person_outline), onPressed: onAccountSettings),
              if (sections.isNotEmpty)
                Row(
                  key: const ValueKey('workspace-nav'),
                  children: [
                    for (final s in sections)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: _HeaderTab(
                          key: ValueKey('workspace-section-${s.id}'),
                          icon: s.icon,
                          label: AppTranslations.of(context)[s.labelKey],
                          selected: s.id == selected,
                          accent: background,
                          onTap: () => onSelect(s.id),
                        ),
                      ),
                    const SizedBox(width: 8),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  const _HeaderTab({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? accent : Colors.white;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  maxLines: 1,
                  style: _HeaderBar._labelStyle.copyWith(color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Property and the section's pages, under the top bar.
class _ContextStrip extends StatelessWidget {
  final List<Map<String, dynamic>> properties;
  final String? building;
  final List<WorkspacePage> pages;
  final String page;
  final TeamAccess access;
  final bool busy;
  final ValueChanged<String> onProperty, onPage;
  final VoidCallback onReload;
  const _ContextStrip({
    required this.properties,
    required this.building,
    required this.pages,
    required this.page,
    required this.access,
    required this.busy,
    required this.onProperty,
    required this.onPage,
    required this.onReload,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final theme = Theme.of(context);
    if (properties.isEmpty && pages.length < 2) return const SizedBox.shrink();
    final property = properties.isEmpty
        ? null
        : properties.length == 1
        // One property: its name, not a picker that looks disabled.
        ? Row(
            children: [
              Icon(
                Icons.apartment_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  properties.single['name'] as String? ??
                      properties.single['id'] as String,
                  key: const ValueKey('workspace-property-name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          )
        : DropdownButtonFormField<String>(
            key: ValueKey('workspace-property-$building'),
            initialValue: building,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: t['workspace_property'],
              prefixIcon: const Icon(Icons.apartment_outlined, size: 18),
            ),
            items: [
              for (final p in properties)
                DropdownMenuItem(
                  value: p['id'] as String,
                  child: Text(
                    p['name'] as String? ?? p['id'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: busy
                ? null
                : (v) {
                    if (v != null) onProperty(v);
                  },
          );
    final tabs = pages.length < 2
        ? null
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in pages)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      key: ValueKey('workspace-page-${p.id}'),
                      label: Text(p.label(context, access)),
                      selected: p.id == page,
                      onSelected: (_) => onPage(p.id),
                    ),
                  ),
              ],
            ),
          );
    final refresh = IconButton(
      tooltip: t['team_refresh'],
      onPressed: busy ? null : onReload,
      icon: const Icon(Icons.refresh, size: 20),
    );
    return Material(
      color: theme.colorScheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: LayoutBuilder(
            builder: (context, c) {
              // Wide: property on the left, page tabs next to it, one line.
              if (c.maxWidth >= 760 && property != null) {
                return Row(
                  children: [
                    SizedBox(width: 300, child: property),
                    const SizedBox(width: 16),
                    Expanded(child: tabs ?? const SizedBox.shrink()),
                    refresh,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (property != null)
                    Row(
                      children: [
                        Expanded(child: property),
                        refresh,
                      ],
                    ),
                  if (tabs != null) ...[
                    if (property != null) const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: tabs),
                        if (property == null) refresh,
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final List<WorkspaceSection> sections;
  final String? selected;
  final ValueChanged<String> onSelect;
  const _BottomBar({
    required this.sections,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final s = Theme.of(context).colorScheme;
    // Up to five fit; otherwise the four main ones (when allowed) + More.
    final ordered = [
      ...sections.where((s) => _mainSections.contains(s.id)),
      ...sections.where((s) => !_mainSections.contains(s.id)),
    ];
    final bar = ordered.length <= 5 ? ordered : ordered.take(4).toList();
    final rest = ordered.skip(bar.length).toList();
    final index = bar.indexWhere((s) => s.id == selected);
    final moreSelected = index < 0 && rest.any((s) => s.id == selected);
    // Labels stay readable at large text without breaking the bar.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: s.outlineVariant)),
        ),
        child: NavigationBar(
          height: MediaQuery.sizeOf(context).width < 420
              ? (MediaQuery.textScalerOf(context).scale(12) > 12 ? 112 : 88)
              : 64,
          backgroundColor: s.surface,
          surfaceTintColor: Colors.transparent,
          indicatorColor: s.primary.withValues(alpha: 0.14),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          selectedIndex: index >= 0 ? index : (moreSelected ? bar.length : 0),
          onDestinationSelected: (i) {
            if (i < bar.length) {
              onSelect(bar[i].id);
              return;
            }
            showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (sheet) => SafeArea(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  children: [
                    for (final s in rest)
                      ListTile(
                        key: ValueKey('workspace-more-${s.id}'),
                        leading: Icon(s.icon),
                        title: Text(t[s.labelKey]),
                        selected: s.id == selected,
                        onTap: () {
                          Navigator.pop(sheet);
                          onSelect(s.id);
                        },
                      ),
                  ],
                ),
              ),
            );
          },
          destinations: [
            for (final s in bar)
              NavigationDestination(
                key: ValueKey('workspace-section-${s.id}'),
                icon: Icon(s.icon),
                label: t[s.labelKey],
              ),
            if (rest.isNotEmpty)
              NavigationDestination(
                key: const ValueKey('workspace-section-more'),
                icon: const Icon(Icons.more_horiz),
                label: t['nav_more'],
              ),
          ],
        ),
      ),
    );
  }
}

/// Who sees the calendar (and so the problems inside bookings, leases and rooms).
bool _calendarAllowed(TeamAccess a) =>
    a.allows(TeamPermission.readBookings) ||
    a.allows(TeamPermission.createBookings) ||
    a.allows(TeamPermission.manageLease) ||
    a.allows(TeamPermission.manageProperty) ||
    // Cleaners too, with cleaning only (2026-10-05, Tom).
    a.allows(TeamPermission.readAssignedTasks);
