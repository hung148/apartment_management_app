import 'dashboard_organization_header.dart';
import 'account_menu_dialog.dart';
import '../team/org_shell.dart';
import '../team/ws_ui.dart';
import '../team/ownership_agreements_screen.dart';
import 'deleted_records_dialog.dart';
import '../team/google_drive_screen.dart';
import '../team/account_workspace_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/app_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/invitation_acceptance.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/access_request.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/dashboard_settings_button.dart';
import 'dart:ui';
import 'account_entry_gate.dart';
import 'organization_merge_dialog.dart';
import '../../services/account_entry_service.dart';

import 'package:phan_mem_quan_ly_can_ho/main.dart';
import 'package:phan_mem_quan_ly_can_ho/models/membership_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/team_access.dart';
import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/owner_model.dart';
import 'package:phan_mem_quan_ly_can_ho/services/auth_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/account_deletion_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/profile_service.dart';
import 'package:uuid/uuid.dart';
import 'package:phan_mem_quan_ly_can_ho/services/organization_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/organization_settings_service.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/app_logger.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/email_format.dart';
import 'package:phan_mem_quan_ly_can_ho/services/update_services.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_router.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/org_location.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_theme.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/loading.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'dart:async';
import '../../services/app_functions.dart';

// Dialog implementations are grouped by purpose; this file owns screen state,
// lifecycle, shared presentation helpers, and the dashboard layout.
part 'dashboard_settings_dialogs.dart';
part 'dashboard_organization_dialogs.dart';
part 'dashboard_profile_dialogs.dart';

// ─────────────────────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────────────────────
class _DS {
  static Color get primary => AppThemePalette.primary;
  static Color get primaryDeep => AppThemePalette.primaryDeep;
  static Color get primaryMid => AppThemePalette.primaryMid;
  static Color get primaryLight => AppThemePalette.primaryLight;
  static const surface      = Color(0xFFF6F7F4);
  static const card         = Colors.white;
  static const textPrimary  = Color(0xFF172D3B);
  static const textSecondary= Color(0xFF64748B);
  static const adminGold    = Color(0xFFF59E0B);
  static const adminGoldBg  = Color(0xFFFFFBEB);
  static Color get memberBlue => AppThemePalette.primary;
  static Color get memberBlueBg => AppThemePalette.primaryLight;

  static List<Color> orgGradient(String id) =>
      AppThemePalette.identityGradient(id);

  static Color orgColor(String id) => orgGradient(id)[0];

  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: AppThemePalette.primary.withValues(alpha: 0.07),
      blurRadius: 20,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 6,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> avatarGlow(String id) => [
    BoxShadow(
      color: orgColor(id).withValues(alpha: 0.35),
      blurRadius: 14,
      offset: const Offset(0, 4),
    ),
  ];
}

// ─────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final AuthService _authService = getIt<AuthService>();
  final OrganizationService _organizationService = getIt<OrganizationService>();
  // Version-2 organization settings go through the server, never direct writes.
  final OrganizationSettingsService _organizationSettings = OrganizationSettingsService();
  // Started when the ⋯ menu opens so Info/Edit usually have data by the tap.
  final Map<String, Future<OrganizationSettings>> _v2SettingsPrefetch = {};
  final UpdateService _updateService = getIt<UpdateService>();

  Future<Owner?>? _ownerFuture;
  Future<List<Organization>>? _orgsFuture;
  final Map<String, Future<Membership?>> _membershipFutures = {};

  late final AnimationController _listAnimCtrl;

  final AsyncLock _createOrgLock = AsyncLock();
  final AsyncLock _dialogLock    = AsyncLock();
  final AsyncLock _logoutLock    = AsyncLock();
  final AsyncLock _leaveOrgLock  = AsyncLock();
  final AsyncLock _deleteAccountLock = AsyncLock();
  final AsyncLock _profileLock = AsyncLock();

  bool _updateAvailable = false;
  bool _checkingUpdate  = false;
  bool _isDisposed      = false;
  Timer? _updateCheckTimer;
  Timer? _resizeDebounceTimer;
  bool  _isResizing     = false;
  Size  _lastSize       = Size.zero;
  

  final ScrollController _scrollCtrl = ScrollController();
  double _appBarOpacity = 0.0;

  // ── lifecycle ──────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _lastSize = PlatformDispatcher.instance.implicitView?.physicalSize ?? Size.zero;
    _listAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _ownerFuture = _authService.getCurrentOwner();
    // The organization list loads once, after the account check
    // (_loadAccountEntry → _refreshOrgs); loading it here too was a duplicate
    // server call on every open and reload.
    _ownerFuture?.then((owner) {
      if (owner != null && mounted) _syncEmailIfChanged(owner);
    });

    WidgetsBinding.instance.addObserver(this);

    _scrollCtrl.addListener(() {
      if (_isResizing) return;
      const double scrollFadeStart = 160.0;
      const double scrollFadeEnd   = 280.0;
      final raw = (_scrollCtrl.offset - scrollFadeStart) /
          (scrollFadeEnd - scrollFadeStart);
      final opacity = raw.clamp(0.0, 1.0);
      if ((opacity - _appBarOpacity).abs() > 0.01) {
        setState(() => _appBarOpacity = opacity);
      }
    });

    _updateCheckTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted && !_isDisposed) _backgroundUpdateCheck();
    });

    // Entry must resolve the account before showing a deep-linked workspace.
  }

  /// The organization opened from the address at start (see initState).
  String? _openedEarly;

  @override
  void dispose() {
    _listAnimCtrl.dispose();
    _scrollCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _resizeDebounceTimer?.cancel();
    _updateCheckTimer?.cancel();
    _isDisposed = true;
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final newSize = PlatformDispatcher.instance.implicitView?.physicalSize ?? Size.zero;
    if (newSize == _lastSize) return;
    _lastSize = newSize;

    if (!_isResizing && mounted) {
      // plain assignment, no rebuild:
      _isResizing = true;
      // Then force a single repaint after resize ends, not a full rebuild:
      WidgetsBinding.instance.scheduleFrame();
    }
    _resizeDebounceTimer?.cancel();
    _resizeDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _isResizing = false);

    });
  }

  // ── helpers ────────────────────────────────────────────────

  // Companion dialog groups request rebuilds through the owning State.
  void _updateDashboardState(VoidCallback update) => setState(update);

  bool _needsVerifiedEmail = false;
  bool _canCreateOrganization = false;
  bool _accountConflict = false;
  Key _entryKey = UniqueKey();

  late final _accountEntryService = AccountEntryService(transport: (name, data) async {
      final result = await appCallable(name).call(data);
      return Map<String, dynamic>.from(result.data as Map);
    });

  Future<AccountEntry> _loadAccountEntry() async {
    final entry = await _accountEntryService.load();
    _needsVerifiedEmail = entry.needsVerifiedEmail;
    // The organization opened early from the address (initState) closes
    // again when the account may not open it here: not in the list (in
    // conflict only owned organizations are listed), still waiting, or the
    // email is not verified yet. The entry screens then show why.
    final early = _openedEarly;
    if (early != null &&
        mounted &&
        (entry.needsVerifiedEmail ||
            entry.waitingIds.contains(early) ||
            !entry.workplaces.any((o) => o.id == early))) {
      _openedEarly = null;
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    // Speed (2026-10-09): the owner profile (read from the database, ~0.7 s on
    // a fresh start) only feeds the owner's organization list below; the
    // account check no longer waits for it before the workspace can open.
    unawaited(_afterOwner(entry));
    return entry;
  }

  Future<void> _afterOwner(AccountEntry entry) async {
    final Owner? owner;
    try {
      owner = await _ownerFuture;
    } catch (e) {
      // The owner's organization list shows the failure (with its retry)
      // instead of waiting forever; the workspace itself is unaffected.
      final failed = Future<List<Organization>>.error(e)..ignore();
      if (mounted) setState(() => _orgsFuture = failed);
      return;
    }
    if (owner != null && mounted) {
      // Speed (2026-10-06): the account check already listed the
      // organizations; asking the server again cost one more trip. Older
      // (version 1) organizations still load their full record.
      if (entry.workplaces.every((o) => o.accessVersion == 2)) {
        setState(() {
          _membershipFutures.clear();
          _orgsFuture = Future.value(entry.workplaces);
        });
        _listAnimCtrl.reset();
        _listAnimCtrl.forward();
      } else {
        _refreshOrgs(owner.id);
      }
    }
  }

  Future<void> _openStaffWorkplace(Organization org) async {
    // Already open from the address (opened before the list loaded).
    if (_openedEarly == org.id) {
      _openedEarly = null;
      return;
    }
    final address = AppRouter.takePendingAddress();
    if (address != null && address.contains('/org/${org.id}/')) {
      await Navigator.of(context).pushNamed(address);
    } else {
      await Navigator.of(context).pushNamed(AppRouter.oranizationScreen,
          arguments: {'organization': org});
    }
  }

  /// After a reload, reopen the organization page the address pointed at.
  /// An account in conflict (owner + staff elsewhere) still reopens its OWN
  /// organizations — it can open them by tapping anyway — but never a staff
  /// workplace; in conflict the server lists only owned organizations.
  // Kept with legacy dashboard code until production v1 migration.
  // ignore: unused_element
  Future<void> _reopenPendingAddress() async {
    final address = AppRouter.takePendingAddress();
    if (address == null || !mounted) return;
    if (_accountConflict) {
      final orgId = OrgLocation.parse(address)?.organizationId;
      if (orgId == null) return;
      List<Organization> owned;
      try {
        owned = await (_orgsFuture ?? Future.value(<Organization>[]));
      } catch (_) {
        return;
      }
      if (!mounted || !owned.any((o) => o.id == orgId)) return;
    }
    await Navigator.of(context).pushNamed(address);
  }

  void _refreshOrgs(String ownerId) {
    if (!mounted || _isDisposed) return;
    setState(() {
      _membershipFutures.clear();
      _orgsFuture = _organizationService.getUserOrganizations(ownerId);
    });
    _listAnimCtrl.reset();
    _orgsFuture?.then((_) {
      if (mounted) _listAnimCtrl.forward();
    });
  }



  Future<T?> _showTrackedDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) async {
    return await showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: builder,
    );
  }

  Future<T?> _showTrackedBottomSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    ShapeBorder? shape,
    BoxConstraints? constraints,
  }) async {
    return await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      shape: shape,
      constraints: constraints,
      builder: builder,
    );
  }

  bool   _isSmallScreen(BuildContext ctx) => MediaQuery.of(ctx).size.width < 600;
  double _getDialogWidth(BuildContext ctx) {
    final w = MediaQuery.of(ctx).size.width;
    if (w < 600)  return w * 0.92;
    if (w < 1200) return 500;
    return 600;
  }

  // ─────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => AccountEntryGate(
    key: _entryKey,
    load: _loadAccountEntry,
    onSettings: _showSettingsDialog,
    onMerge: () async {
      await showDialog<bool>(context: context, barrierDismissible: false,
        builder: (_) => OrganizationMergeDialog(transport: (name, data) async {
          final result = await appCallable(name).call(data);
          return Map<String, dynamic>.from(result.data as Map);
        }));
    },
    openWorkplace: _openStaffWorkplace,
    workspaceBuilder: _buildSingleWorkspace,
    ownerBuilder: (entry) {
      _canCreateOrganization = entry.canCreate;
      _accountConflict = entry.mode == 'conflict';
      return _buildOrganizationEntry(entry);
    },
  );

  OrgLocation? _initialWorkspace;
  String? _workspaceId;
  Organization? _accountOrganization;
  bool _accountIsOwner = false;

  Widget _buildSingleWorkspace(AccountEntry entry, Organization org) {
    _accountOrganization = org;
    _accountIsOwner = entry.mode == 'owner';
    _canCreateOrganization = false;
    if (_workspaceId != org.id) {
      _workspaceId = org.id;
      final requested = OrgLocation.parse(AppRouter.takePendingAddress());
      _initialWorkspace = requested?.organizationId == org.id ? requested : null;
    }
    if (org.accessVersion != 2) {
      return Scaffold(
        appBar: AppBar(title: Text(org.name), actions: [
          IconButton(tooltip: AppTranslations.of(context)['account_menu'], onPressed: _showSettingsDialog, icon: const Icon(Icons.person_outline)),
        ]),
        body: WsPage(children: [
          WsNotice(AppTranslations.of(context)['org_legacy_workspace'], tone: WsTone.neutral),
          FilledButton(onPressed: () => _openStaffWorkplace(org), child: Text(AppTranslations.of(context)['staff_open_workplace'])),
        ]),
      );
    }
    final initial = _initialWorkspace;
    // A Settings link opens its dialog once, including after a saved change
    // refreshes account entry. Reopening would stack a second dialog.
    if (initial?.section == 'settings') _initialWorkspace = null;
    return OrgShell(
      key: ValueKey('single-workspace-${org.id}'),
      organizationId: org.id, name: org.name, initial: initial,
      service: getIt<TeamService>(),
      onAccountSettings: _showSettingsDialog,
      onOrganizationSettings: () => _showSingleOrganizationActions(org),
      onAccessEnded: () { if (mounted) setState(() { _entryKey = UniqueKey(); }); },
    );
  }

  Widget _buildOrganizationEntry(AccountEntry entry) {
    _accountOrganization = null;
    _accountIsOwner = false;
    final t = AppTranslations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t['org_entry_title']), actions: [
        IconButton(tooltip: t['account_menu'], onPressed: _showSettingsDialog, icon: const Icon(Icons.person_outline)),
      ]),
      body: WsPage(children: [
        WsNotice(t[entry.needsVerifiedEmail ? 'team_verified_email_required' : const {'closed','suspended','waiting','deleting','review'}.contains(entry.state) ? 'org_entry_${entry.state}' : 'org_entry_explanation'], tone: WsTone.neutral),
        if (entry.canCreate && !entry.needsVerifiedEmail)
          WsActions(children: [FilledButton.icon(
            key: const ValueKey('single-create-organization'),
            onPressed: () => _dialogLock.run(_showCreateOrganizationDialog),
            icon: const Icon(Icons.add), label: Text(t['create_action']),
          )]),
        if (!entry.needsVerifiedEmail && const {'none','invited','ready'}.contains(entry.state))
          InvitationEntryButton(service: getIt<TeamService>(), onReturn: () {
            if (mounted) setState(() { _entryKey = UniqueKey(); });
          }),
        WsActions(children: [OutlinedButton(onPressed: () { setState(() { _entryKey = UniqueKey(); }); }, child: Text(t['team_refresh']))]),
      ]),
    );
  }

  Future<void> _showSingleOrganizationActions(Organization org) async {
    await _openV2Settings(org, (settings) async {
      if (_accountIsOwner && settings.canManage) {
        await _showEditOrganizationDialog(settings.organization, _authService.currentUser!.uid, information: true);
      }
    });
  }

  // Retained for legacy recovery; strict accounts never enter this list.
  // ignore: unused_element
  Widget _buildOwnerDashboard(BuildContext context) {
    Theme.of(context); // Rebuild theme-dependent custom accents.
    final isSmall = _isSmallScreen(context);
    const minWidth  = 360.0;
    const minHeight = 600.0;

    return Scaffold(
      backgroundColor: _DS.surface,
      // The identity image continues behind the compact app bar so the whole
      // top surface reads as one intentional visual area.
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context),
      body: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < minWidth || constraints.maxHeight < minHeight) {
          return _buildTooSmallWarning(context, constraints, minWidth, minHeight);
        }
        return FutureBuilder<Owner?>(
          future: _ownerFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: Loading3(size: 50));
            }
            final owner = snapshot.data;
            if (owner == null) return _buildNoUserState(context, isSmall);

            return RefreshIndicator(
              color: _DS.primary,
              onRefresh: () async {
                _refreshOrgs(owner.id);
                await _checkForUpdate();
              },
              child: CustomScrollView(
                controller: _scrollCtrl,
                slivers: [
                  SliverToBoxAdapter(child: _buildHero(context, isSmall)),
                  if (_accountConflict) SliverToBoxAdapter(child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(AppTranslations.of(context)['team_owner_account']),
                  )),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isSmall ? 16 : 20, isSmall ? 16 : 24, isSmall ? 16 : 20, 12,
                      ),
                      child: DashboardOrganizationHeader(
                        invitation: InvitationEntryButton(
                          iconOnly: true,
                          service: getIt<TeamService>(),
                          onReturn: () {
                            if (mounted) _refreshOrgs(owner.id);
                          },
                        ),
                        canCreate: _canCreateOrganization,
                        onJoin: () => _dialogLock.run(_showJoinOrganizationDialog),
                        onCreate: () => _dialogLock.run(_showCreateOrganizationDialog),
                        onAgreements: () => _dialogLock.run(() async {
                          await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => OwnershipAgreementsScreen(service: TeamService()),
                          ));
                          if (mounted) setState(() { _entryKey = UniqueKey(); });
                        }),
                        // 2026-10-06 (Tom): one Google Drive for every organization the owner owns.
                        onDrive: _canCreateOrganization
                            ? () => _dialogLock.run(() => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(title: const Text('Google Drive')),
                                  body: GoogleDriveScreen(service: getIt<TeamService>()),
                                ),
                              )))
                            : null,
                      ),
                    ),
                  ),
                  FutureBuilder<List<Organization>>(
                    future: _orgsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return SliverFillRemaining(
                          child: Center(child: CircularProgressIndicator(color: _DS.primary)),
                        );
                      }
                      final orgs = snapshot.data ?? [];
                      if (orgs.isEmpty) {
                        return SliverFillRemaining(child: _buildEmptyState(context, isSmall));
                      }
                      return SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: isSmall ? 16 : 20),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) =>
                                _buildOrgCard(context, orgs[index], owner, isSmall, index),
                            childCount: orgs.length,
                          ),
                        ),
                      );
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              ),
            );
          },
        );
      }),
    );
  }

  // ─────────────────────────────────────────────────────────
  // HERO
  // ─────────────────────────────────────────────────────────

  Widget _buildHero(BuildContext context, bool isSmall) {
    // Keep the property's visual identity image, while using a short strip so
    // it supports the dashboard instead of pushing the operational cards down.
    final heroHeight = (MediaQuery.sizeOf(context).width * 0.20)
        .clamp(isSmall ? 138.0 : 160.0, isSmall ? 170.0 : 220.0);
    return Container(
      height: heroHeight,
      // Full bleed lets the image continue under the transparent app bar and
      // reach both edges of the window.
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.zero,
        image: const DecorationImage(
          image: AssetImage('assets/image/background_image3_1920.jpg'),
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 3))],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Colors.black.withValues(alpha: 0.62), Colors.black.withValues(alpha: 0.10)],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: Text(AppTranslations.of(context).text('dashboard'),
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      actions: [DashboardSettingsButton(
        onPressed: _showSettingsDialog,
        tooltip: AppTranslations.of(context).text('settings'),
        showBadge: _updateAvailable && !_checkingUpdate,
      ), const SizedBox(width: 4)],
    );
  }

  // ─────────────────────────────────────────────────────────
  // ORG CARD
  // ─────────────────────────────────────────────────────────

  Widget _buildOrgCard(
      BuildContext context, Organization org, Owner owner, bool isSmall, int index) {
    final gradient = _DS.orgGradient(org.id);
    final delay = index * 0.12;
    final animation = CurvedAnimation(
      parent: _listAnimCtrl,
      curve: Interval(
        delay.clamp(0.0, 0.9),
        (delay + 0.4).clamp(0.0, 1.0),
        curve: Curves.easeOut,
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero)
              .animate(animation),
          child: child,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _DS.card,
          borderRadius: BorderRadius.circular(12),
          boxShadow: _DS.cardShadow,
          border: Border.all(color: const Color(0x0F000000)),
        ),
        child: FutureBuilder<Membership?>(
          future: _membershipFutures.putIfAbsent(org.id, () {
            if (FirebaseAuth.instance.currentUser == null) return Future.value(null);
            return _organizationService.getUserMembership(owner.id, org.id);
          }),
          builder: (context, snapshot) {
            final role    = snapshot.data?.role ?? 'member';
            final isV2    = org.accessVersion == 2;
            // Version 2 uses owner/administrator instead of the legacy admin role.
            final isAdmin = isV2
                ? const {'owner', 'administrator'}.contains(role)
                : role == 'admin';
            // No supported role yet (migrated member or removed role): wait for
            // an owner/administrator. Only decided once the membership has loaded.
            final waiting = isV2 &&
                snapshot.connectionState == ConnectionState.done &&
                _isWaitingMember(snapshot.data);

            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => waiting
                  ? _showWaitingForRole(org)
                  : Navigator.pushNamed(context, AppRouter.oranizationScreen,
                      arguments: {'organization': org}),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 4,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: gradient,
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(isSmall ? 14 : 16),
                          child: Row(children: [
                            Container(
                              width: isSmall ? 50 : 54,
                              height: isSmall ? 50 : 54,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: gradient,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: _DS.avatarGlow(org.id),
                              ),
                              child: Center(
                                child: Text(
                                  org.name[0].toUpperCase(),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: isSmall ? 20 : 22,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: isSmall ? 12 : 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    org.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: isSmall ? 14 : 15,
                                      color: _DS.textPrimary,
                                      letterSpacing: -0.2,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _formatDate(org.createdAt, context),
                                    style: TextStyle(
                                      color: _DS.textSecondary,
                                      fontSize: isSmall ? 11 : 12,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  // No badge until the role has loaded (2026-10-06, Tom: it
                                  // showed "Vai trò riêng" for a few seconds first).
                                  if (waiting || snapshot.data != null)
                                    _buildRoleBadge(isAdmin,
                                        label: waiting
                                            ? AppTranslations.of(context).text('team_waiting_role')
                                            : isV2 ? _v2RoleLabel(role, snapshot.data?.roleName) : null)
                                  else
                                    const SizedBox(key: ValueKey('dashboard-role-loading'), height: 22),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _showOrganizationOptions(org, owner.id, isAdmin, role,
                                  roleName: snapshot.data?.roleName, waitingMember: waiting),
                              child: Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: _DS.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0x10000000)),
                                ),
                                child: Icon(Icons.more_horiz_rounded,
                                    color: _DS.textSecondary, size: 20),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // SMALL UI PIECES
  // ─────────────────────────────────────────────────────────

  Widget _buildRoleBadge(bool isAdmin, {String? label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isAdmin ? _DS.adminGoldBg : _DS.memberBlueBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAdmin
              ? _DS.adminGold.withValues(alpha: 0.35)
              : _DS.memberBlue.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          isAdmin ? Icons.star_rounded : Icons.person_rounded,
          size: 12,
          color: isAdmin ? _DS.adminGold : _DS.memberBlue,
        ),
        const SizedBox(width: 4),
        Text(
          label ??
              (isAdmin
                  ? AppTranslations.of(context).text('admin')
                  : AppTranslations.of(context).text('member')),
          style: TextStyle(
            color: isAdmin ? _DS.adminGold : _DS.memberBlue,
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
        ),
      ]),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    bool isDestructive = false,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600, fontSize: 14,
          color: isDestructive ? Colors.red[700] : _DS.textPrimary,
        ),
      ),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(fontSize: 12, color: _DS.textSecondary))
          : null,
      onTap: onTap,
    );
  }

  Widget _buildField(
    TextEditingController ctrl,
    String label, {
    String? hint,
    required IconData icon,
    int maxLength = 100,
    int maxLines = 1,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool autofocus = false,
    String? helper,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      maxLength: maxLength,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      autofocus: autofocus,
      validator: validator,
      decoration: InputDecoration(
        counterText: '',
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: _DS.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _DS.primary, width: 1.8),
        ),
        helperText: helper,
        helperStyle: const TextStyle(fontSize: 11, color: _DS.textSecondary),
      ),
    );
  }

  Widget _buildInfoBanner(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _DS.primaryLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _DS.primary.withValues(alpha: 0.2), width: 1),
      ),
      child: Row(children: [
        Icon(Icons.info_outline_rounded, size: 18, color: _DS.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 12, color: _DS.primary, fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }

  Widget _buildWarningBanner(String text, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteWarningItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(Icons.remove_circle_outline_rounded, size: 15, color: Colors.red[600]),
        const SizedBox(width: 8),
        Flexible(child: Text(text, style: TextStyle(fontSize: 13, color: Colors.red[700]))),
      ]),
    );
  }

  Widget _buildLoadingDialog(String message) {
    return AppDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(color: _DS.primaryLight, shape: BoxShape.circle),
              child: Padding(
                padding: EdgeInsets.all(14),
                child: CircularProgressIndicator(color: _DS.primary, strokeWidth: 3),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: _DS.textPrimary),
            ),
            const SizedBox(height: 6),
            const Text('...', style: TextStyle(fontSize: 13, color: _DS.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildTooSmallWarning(BuildContext context,
      BoxConstraints constraints, double minW, double minH) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange[700]),
            const SizedBox(height: 16),
            Text(
              AppTranslations.of(context).text('window_size_too_small'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppTranslations.of(context).textWithParams('minimum_size',
                  {'width': minW.toInt(), 'height': minH.toInt()}),
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              AppTranslations.of(context).textWithParams('current_size', {
                'width': constraints.maxWidth.toInt(),
                'height': constraints.maxHeight.toInt(),
              }),
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoUserState(BuildContext context, bool isSmall) {
    return Center(
      child: Card(
        margin: EdgeInsets.all(isSmall ? 16 : 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: EdgeInsets.all(isSmall ? 20 : 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: isSmall ? 48 : 64,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(
                AppTranslations.of(context).text('user_data_not_found'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: isSmall ? 14 : 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _handleLogout,
                icon: const Icon(Icons.logout),
                label: Text(AppTranslations.of(context).text('logout_action')),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isSmall) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: _DS.primaryLight, shape: BoxShape.circle),
            child: Icon(Icons.business_outlined,
                size: isSmall ? 48 : 56, color: _DS.primary),
          ),
          const SizedBox(height: 12),
          Text(
            AppTranslations.of(context).text('no_orgs'),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: isSmall ? 18 : 20,
              color: _DS.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            AppTranslations.of(context).text('no_orgs_sub'),
            textAlign: TextAlign.center,
            style: TextStyle(color: _DS.textSecondary, fontSize: isSmall ? 13 : 14),
          ),
          // R2: staff are added by their Gmail; say which address to give the manager.
          const SizedBox(height: 12),
          Text(
            AppTranslations.of(context).textWithParams(
              _needsVerifiedEmail ? 'team_staff_verify_email' : 'team_staff_ask_manager',
              {'email': _authService.currentUser?.email ?? ''},
            ),
            key: const ValueKey('dashboard-staff-hint'),
            textAlign: TextAlign.center,
            style: TextStyle(color: _DS.textSecondary, fontSize: isSmall ? 13 : 14),
          ),
          // Join and create live in the header beside "Tổ Chức Của Bạn";
          // no second copy of those buttons here (Tom, 2026-10-02).
        ],
      ),
    );
  }

  void _showSuccessSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
      backgroundColor: Colors.green[700],
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 3),
    ));
  }

  // ─────────────────────────────────────────────────────────
  // DATE FORMATTING
  // ─────────────────────────────────────────────────────────

  String _formatDate(DateTime date, BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    if (locale == 'vi') {
      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year} '
          '${date.hour.toString().padLeft(2, '0')}:'
          '${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.month.toString().padLeft(2, '0')}/'
        '${date.day.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────
// ASYNC LOCK
// ─────────────────────────────────────────────────────────────
class AsyncLock {
  bool _locked = false;
  bool get isLocked => _locked;

  Future<void> run(Future<void> Function() action) async {
    if (_locked) return;
    _locked = true;
    try {
      await action();
    } finally {
      _locked = false;
    }
  }
}
