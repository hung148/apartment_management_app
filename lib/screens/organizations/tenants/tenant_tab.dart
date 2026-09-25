import 'package:phan_mem_quan_ly_can_ho/widgets/suggested_text_field.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/searchable_select_field.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/responsive_form_row.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/tenant_toolbar.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/tenant_summary_card.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/app_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/services/exchange_rate_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/currency_formatter.dart';
import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_theme.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/constants.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/date_picker.dart';
import 'package:phan_mem_quan_ly_can_ho/models/tenants_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/buildings_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/rooms_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/membership_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/services/tenants_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/building_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/room_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/organization_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/auth_service.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/combo_box.dart';

// This file owns tenant state, lifecycle, loading, search, and list rendering.
// Dialogs and their shared components are grouped in the companion files below.
part 'tenant_dialog_components.dart';
part 'tenant_details_dialogs.dart';
part 'tenant_management_dialogs.dart';
part 'tenant_vehicle_dialogs.dart';

// ─── Color palette ───────────────────────────────────────────────────────────
List<Color> get _tenantAccentColors => AppThemePalette.identityColors;

// ═════════════════════════════════════════════════════════════════════════════
class TenantsTab extends StatefulWidget {
  final Organization organization;
  final TenantService tenantService;
  final BuildingService buildingService;
  final RoomService roomService;
  final OrganizationService organizationService;
  final AuthService authService;
  final VoidCallback? onChanged;

  const TenantsTab({
    super.key, 
    required this.organization,
    required this.tenantService,
    required this.buildingService,
    required this.roomService,
    required this.organizationService,
    required this.authService,
    this.onChanged,
  });

  @override
  State<TenantsTab> createState() => _TenantsTabState();
}

class _TenantsTabState extends State<TenantsTab>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _searchController = TextEditingController();
  late Future<List<dynamic>> _initialFuture;


  List<Tenant> _allTenants = [];
  List<Building> _buildings = [];
  List<Room> _rooms = [];
  Membership? _membership;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialFuture = Future.wait([
      _getAllTenants(),
      _getBuildings(),
      _getAllRooms(),
      _getMyMembership(),
    ]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  Timer? _resizeDebounceTimer;

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _resizeDebounceTimer?.cancel();
    _resizeDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;

    });
  }



  Future<T?> _showTrackedDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) async {
    try {
      final route = DialogRoute<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: builder,
      );
      final result = await Navigator.of(context, rootNavigator: true).push(route);
      // Caller-owned controllers must outlive the closing animation.
      await route.completed;
      return result;
    } finally {
    }
  }

  Future<T?> _showTrackedBottomSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    ShapeBorder? shape,
    BoxConstraints? constraints,
  }) async {
    try {
      return await showModalBottomSheet<T>(
        context: context,
        isScrollControlled: isScrollControlled,
        shape: shape,
        constraints: constraints,
        builder: builder,
      );
    } finally {
    }
  }

  Future<List<Tenant>> _getAllTenants() =>
      widget.tenantService.getOrganizationTenants(widget.organization.id);
  Future<List<Building>> _getBuildings() =>
      widget.buildingService.getOrganizationBuildings(widget.organization.id);
  Future<List<Room>> _getAllRooms() =>
      widget.roomService.getOrganizationRooms(widget.organization.id);
  Future<Membership?> _getMyMembership() {
    final userId = widget.authService.currentUser?.uid;
    if (userId == null) return Future.value(null);
    return widget.organizationService
        .getUserMembership(userId, widget.organization.id);
  }

  Future<void> _refreshAll() async {
    final future = Future.wait([
      _getAllTenants(),
      _getBuildings(),
      _getAllRooms(),
      _getMyMembership(),
    ]);
    
    setState(() {
      _initialFuture = future;
    });
    
    final data = await future;  // await the local, not _initialFuture
    if (!mounted) return;
    
    setState(() {
      _allTenants = List<Tenant>.from(data[0] as List<Tenant>);
      _buildings = List<Building>.from(data[1] as List<Building>);
      _rooms = List<Room>.from(data[2] as List<Room>);
      _membership = data[3] as Membership?;
    });
  }

  String _formatCurrency(double amount, [String currency = 'VND']) => ReportingMoney.format(widget.organization.id, amount, currency);

  String _formatDate(DateTime date) =>
      DateFormat(AppTranslations.of(context).dateFormat).format(date);

  // ─── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild theme-dependent custom accents.
    super.build(context);
    final t = AppTranslations.of(context);

    return FutureBuilder<List<dynamic>>(
      future: _initialFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData) {
          return Center(child: Text(t['tenant_no_data']));
        }

        final allTenants = snapshot.data![0] as List<Tenant>;
        final buildings = snapshot.data![1] as List<Building>;
        final rooms = snapshot.data![2] as List<Room>;
        final membership = snapshot.data![3] as Membership?;

        _allTenants = allTenants;
        _buildings = buildings;
        _rooms = rooms;
        _membership = membership;

        final isAdmin = membership != null && membership.role == 'admin';

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TenantToolbar(
                    counts: [
                      for (final status in [TenantStatus.active, TenantStatus.inactive, TenantStatus.moveOut])
                        allTenants.where((tenant) => tenant.status == status).length,
                    ],
                    searchController: _searchController,
                    onAdd: isAdmin ? () => _showAddTenantDialog(buildings, rooms) : null,
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchController,
              builder: (context, value, _) {
                final query = value.text;
                final tenants = _filterTenants(allTenants, query);

                if (tenants.isEmpty) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: AppThemePalette.primaryLight,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              query.isEmpty
                                  ? Icons.people_outline_rounded
                                  : Icons.search_off_rounded,
                              size: 36,
                              color: AppThemePalette.primary,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            query.isEmpty
                                ? t['tenant_no_tenants']
                                : t['tenant_no_results'],
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700),
                          ),
                          if (query.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              t['tenant_try_other_keyword'],
                              style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 13),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }

                return SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Row(
                          children: [
                            Container(
                              width: 3,
                              height: 14,
                              decoration: BoxDecoration(
                                color: AppThemePalette.primary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              t['tenants_tab'].toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            const Spacer(),
                            if (query.isNotEmpty)
                              Text(
                                t.textWithParams(
                                    'tenant_found_results',
                                    {'count': tenants.length}),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600),
                              )
                            else
                              Text(
                                '${tenants.length}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final tenant = tenants[index];
                            final color = _tenantAccentColors[
                                index % _tenantAccentColors.length];
                            return _buildTenantCard(
                                tenant, isAdmin, color);
                          },
                          childCount: tenants.length,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  // ─── Tenant card ──────────────────────────────────────────────────────────────
  Widget _buildTenantCard(
      Tenant tenant, bool isAdmin, Color accentColor) {
    final t = AppTranslations.of(context);
    final bool isMovedOut = tenant.status == TenantStatus.moveOut;

    late final String displayBuildingName;
    late final String displayRoomNumber;
    late final Room room;

    if (isMovedOut &&
        tenant.lastBuildingName != null &&
        tenant.lastRoomNumber != null) {
      displayBuildingName = tenant.lastBuildingName!;
      displayRoomNumber = tenant.lastRoomNumber!;
      room = Room(
        id: '',
        area: 0.0,
        roomType: '',
        organizationId: '',
        buildingId: '',
        roomNumber: displayRoomNumber,
        createdAt: DateTime.now(),
      );
    } else {
      final building = _buildings.firstWhere(
        (b) => b.id == tenant.buildingId,
        orElse: () => Building(
          id: '',
          organizationId: '',
          name: t['tenant_unknown'],
          address: '',
          createdAt: DateTime.now(),
        ),
      );
      room = _rooms.firstWhere(
        (r) => r.id == tenant.roomId,
        orElse: () => Room(
          id: '',
          roomType: '',
          area: 0.0,
          organizationId: '',
          buildingId: '',
          roomNumber: '?',
          createdAt: DateTime.now(),
        ),
      );
      displayBuildingName = building.name;
      displayRoomNumber = room.roomNumber;
    }

    final bool canNavigate = !isMovedOut && room.id.isNotEmpty;
    return TenantSummaryCard(
      tenant: tenant,
      translations: t,
      accentColor: accentColor,
      buildingName: displayBuildingName,
      roomNumber: displayRoomNumber,
      onDetails: () => _showTenantDetailDialog(
          tenant, displayBuildingName, displayRoomNumber),
      onRoom: canNavigate ? () => Navigator.pushNamed(
          context, '/room-detail', arguments: {
            'room': room,
            'organization': widget.organization,
          }) : null,
      onOptions: isAdmin ? () => _showTenantOptionsMenu(tenant, isMovedOut) : null,
      onHistory: () => _showRentalHistoryDialog(tenant),
    );
  }

  List<Tenant> _filterTenants(List<Tenant> tenants, String query) {
    if (query.isEmpty) return tenants;
    final searchLower = query.toLowerCase().trim();
    return tenants.where((tenant) {
      if (tenant.fullName.toLowerCase().contains(searchLower))
        {return true;}
      if (tenant.phoneNumber.contains(searchLower)) return true;
      if (tenant.email != null &&
          tenant.email!.toLowerCase().contains(searchLower)) {return true;}
      if (tenant.nationalId != null &&
          tenant.nationalId!.contains(searchLower)) {return true;}
      if (tenant.occupation != null &&
          tenant.occupation!.toLowerCase().contains(searchLower))
        {return true;}
      if (tenant.workplace != null &&
          tenant.workplace!.toLowerCase().contains(searchLower))
        {return true;}
      return false;
    }).toList();
  }

  Color _getTenantStatusColor(TenantStatus status) {
    switch (status) {
      case TenantStatus.active:
        return const Color(0xFF3B6D11);
      case TenantStatus.inactive:
        return const Color(0xFF854F0B);
      case TenantStatus.moveOut:
        return Colors.blueGrey.shade600;
      case TenantStatus.suspended:
        return const Color(0xFFDC2626);
    }
  }
}

