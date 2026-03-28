import 'dart:async';

import 'package:apartment_management_project_2/utils/app_localizations.dart';
import 'package:apartment_management_project_2/widgets/date_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:apartment_management_project_2/models/tenants_model.dart';
import 'package:apartment_management_project_2/models/buildings_model.dart';
import 'package:apartment_management_project_2/models/rooms_model.dart';
import 'package:apartment_management_project_2/models/membership_model.dart';
import 'package:apartment_management_project_2/models/organization_model.dart';
import 'package:apartment_management_project_2/services/tenants_service.dart';
import 'package:apartment_management_project_2/services/building_service.dart';
import 'package:apartment_management_project_2/services/room_service.dart';
import 'package:apartment_management_project_2/services/organization_service.dart';
import 'package:apartment_management_project_2/services/auth_service.dart';

class TenantsTab extends StatefulWidget {
  final Organization organization;
  final TenantService tenantService;
  final BuildingService buildingService;
  final RoomService roomService;
  final OrganizationService organizationService;
  final AuthService authService;
  final VoidCallback? onChanged;

  const TenantsTab({
    Key? key,
    required this.organization,
    required this.tenantService,
    required this.buildingService,
    required this.roomService,
    required this.organizationService,
    required this.authService,
    this.onChanged,
  }) : super(key: key);

  @override
  State<TenantsTab> createState() => _TenantsTabState();
}

class _TenantsTabState extends State<TenantsTab>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _searchController = TextEditingController();
  late Future<List<dynamic>> _initialFuture;

  int _overlayCount = 0;

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
  bool _isDismissing = false;

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _resizeDebounceTimer?.cancel();
    _resizeDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final screenWidth = MediaQuery.sizeOf(context).width;
      final screenHeight = MediaQuery.sizeOf(context).height;
      if (screenWidth < 360 || screenHeight < 600) {
        _dismissAllOverlays();
      }
    });
  }

  Future<void> _dismissAllOverlays() async {
    if (!mounted || _isDismissing) return;
    _isDismissing = true;
    try {
      final nav = Navigator.of(context);
      while (nav.canPop()) {
        nav.pop();
        await Future.delayed(const Duration(milliseconds: 50));
        if (!mounted) break;
      }
    } finally {
      _isDismissing = false;
    }
  }

  Future<T?> _showTrackedDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) async {
    _overlayCount++;
    try {
      return await showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: builder,
      );
    } finally {
      if (mounted) _overlayCount--;
    }
  }

  Future<T?> _showTrackedBottomSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    ShapeBorder? shape,
    BoxConstraints? constraints,
  }) async {
    _overlayCount++;
    try {
      return await showModalBottomSheet<T>(
        context: context,
        isScrollControlled: isScrollControlled,
        shape: shape,
        constraints: constraints,
        builder: builder,
      );
    } finally {
      if (mounted) _overlayCount--;
    }
  }

  Map<String, List<Tenant>> _getRoomToTenantsMap(List<Tenant> allTenants) {
    final map = <String, List<Tenant>>{};
    for (var t in allTenants) {
      if (t.status == TenantStatus.active) {
        map.putIfAbsent(t.roomId, () => []).add(t);
      }
    }
    return map;
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
    setState(() {
      _initialFuture = Future.wait([
        _getAllTenants(),
        _getBuildings(),
        _getAllRooms(),
        _getMyMembership(),
      ]);
    });
    final data = await _initialFuture;
    _allTenants = List<Tenant>.from(data[0] as List<Tenant>);
    _buildings = List<Building>.from(data[1] as List<Building>);
    _rooms = List<Room>.from(data[2] as List<Room>);
    _membership = data[3] as Membership?;
  }

  String _formatCurrency(double value) {
    final f = NumberFormat.currency(
        locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    return f.format(value);
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  // ─── Localised vehicle type display name ───────────────────────────────────
  String _getVehicleTypeDisplayName(VehicleType type) {
    final t = AppTranslations.of(context);
    switch (type) {
      case VehicleType.motorcycle:
        return t['tenant_vehicle_motorcycle'];
      case VehicleType.car:
        return t['tenant_vehicle_car'];
      case VehicleType.bicycle:
        return t['tenant_vehicle_bicycle'];
      case VehicleType.electricBike:
        return t['tenant_vehicle_electric_bike'];
      case VehicleType.other:
        return t['tenant_vehicle_other'];
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
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

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _searchController,
                builder: (context, value, child) {
                  return TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: t['tenant_search_hint'],
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: value.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                },
              ),
            ),

            if (isAdmin)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showAddTenantDialog(buildings, rooms),
                    icon: const Icon(Icons.person_add),
                    label: Text(t['tenant_add_button']),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 16),

            Expanded(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _searchController,
                builder: (context, value, child) {
                  final query = value.text;
                  final tenants = _filterTenants(allTenants, query);

                  if (tenants.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            query.isEmpty
                                ? Icons.people_outline
                                : Icons.search_off,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            query.isEmpty
                                ? t['tenant_no_tenants']
                                : t['tenant_no_results'],
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 16),
                          ),
                          if (query.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              t['tenant_try_other_keyword'],
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: [
                      if (query.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  size: 16, color: Colors.grey.shade600),
                              const SizedBox(width: 8),
                              Text(
                                t.textWithParams('tenant_found_results',
                                    {'count': tenants.length}),
                                style: TextStyle(
                                    color: Colors.grey.shade600, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: tenants.length,
                          itemBuilder: (context, index) {
                            final tenant = tenants[index];
                            return _buildTenantCard(tenant, isAdmin);
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // ─── Tenant card ───────────────────────────────────────────────────────────
  Widget _buildTenantCard(Tenant tenant, bool isAdmin) {
    final t = AppTranslations.of(context);

    late final Building building;
    late final Room room;
    late final String displayBuildingName;
    late final String displayRoomNumber;

    final bool isMovedOut = tenant.status == TenantStatus.moveOut;

    if (isMovedOut &&
        tenant.lastBuildingName != null &&
        tenant.lastRoomNumber != null) {
      displayBuildingName = tenant.lastBuildingName!;
      displayRoomNumber = tenant.lastRoomNumber!;

      building = Building(
        id: '',
        organizationId: '',
        name: displayBuildingName,
        address: '',
        createdAt: DateTime.now(),
      );

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
      building = _buildings.firstWhere(
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isMovedOut ? Colors.grey.shade50 : null,
      child: InkWell(
        onTap: canNavigate
            ? () {
                Navigator.pushNamed(
                  context,
                  '/room-detail',
                  arguments: {
                    'room': room,
                    'organization': widget.organization,
                  },
                );
              }
            : () => _showTenantDetailDialog(
                tenant, displayBuildingName, displayRoomNumber),
        onLongPress: isAdmin
            ? () => _showTenantOptionsMenu(tenant, isMovedOut)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: tenant.isMainTenant
                    ? Colors.blue.shade100
                    : Colors.grey.shade200,
                child: Text(
                  tenant.fullName.isNotEmpty
                      ? tenant.fullName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: tenant.isMainTenant
                        ? Colors.blue.shade700
                        : Colors.grey.shade700,
                  ),
                ),
              ),
              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tenant.fullName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        if (tenant.isMainTenant)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              t['tenant_main_tenant_badge'],
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (tenant.occupation != null) ...[
                      Row(
                        children: [
                          Icon(Icons.work,
                              size: 16, color: Colors.grey.shade700),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              tenant.occupation!,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: canNavigate
                            ? Colors.blue.shade50
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 18,
                            color: canNavigate
                                ? Colors.blue.shade700
                                : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  canNavigate
                                      ? t['tenant_location_label']
                                      : t['tenant_previous_location_label'],
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  t.textWithParams(
                                      'tenant_location_value', {
                                    'building': displayBuildingName,
                                    'room': displayRoomNumber,
                                  }),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: canNavigate
                                        ? Colors.blue.shade900
                                        : Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (canNavigate)
                            Icon(Icons.arrow_forward_ios,
                                size: 14, color: Colors.blue.shade700),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Icon(Icons.phone,
                            size: 16, color: Colors.grey.shade700),
                        const SizedBox(width: 6),
                        Text(
                          tenant.phoneNumber,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),

                    if (tenant.monthlyRent != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _formatCurrency(tenant.monthlyRent!),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Text(
                          t['tenant_status_label'],
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getTenantStatusColor(tenant.status)
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            tenant.getStatusDisplayName(),
                            style: TextStyle(
                              fontSize: 12,
                              color: _getTenantStatusColor(tenant.status),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (tenant.previousRentals != null &&
                            tenant.previousRentals!.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.history,
                                    size: 12,
                                    color: Colors.orange.shade700),
                                const SizedBox(width: 4),
                                Text(
                                  '${tenant.previousRentals!.length}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),

                    if (tenant.vehicles != null &&
                        tenant.vehicles!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.directions_car,
                                size: 14, color: Colors.purple.shade700),
                            const SizedBox(width: 4),
                            Text(
                              t.textWithParams('tenant_vehicle_count',
                                  {'count': tenant.vehicles!.length}),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.purple.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              if (isAdmin)
                IconButton(
                  icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
                  onPressed: () =>
                      _showTenantOptionsMenu(tenant, isMovedOut),
                  tooltip: t['tenant_options_tooltip'],
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Tenant> _filterTenants(List<Tenant> tenants, String query) {
    if (query.isEmpty) return tenants;
    final searchLower = query.toLowerCase().trim();
    return tenants.where((tenant) {
      if (tenant.fullName.toLowerCase().contains(searchLower)) return true;
      if (tenant.phoneNumber.contains(searchLower)) return true;
      if (tenant.email != null &&
          tenant.email!.toLowerCase().contains(searchLower)) return true;
      if (tenant.nationalId != null &&
          tenant.nationalId!.contains(searchLower)) return true;
      if (tenant.occupation != null &&
          tenant.occupation!.toLowerCase().contains(searchLower)) return true;
      if (tenant.workplace != null &&
          tenant.workplace!.toLowerCase().contains(searchLower)) return true;
      return false;
    }).toList();
  }

  // =========================
  // TENANT DETAIL DIALOG
  // =========================
  void _showTenantDetailDialog(
      Tenant tenant, String buildingName, String roomNumber) {
    final t = AppTranslations.of(context);
    final isPhone = MediaQuery.of(context).size.width < 600;
    final bool isMovedOut = tenant.status == TenantStatus.moveOut;

    _showTrackedDialog(
      context: context,
      builder: (context) {
        final t = AppTranslations.of(context);
        return Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isPhone
                  ? MediaQuery.of(context).size.width * 0.95
                  : MediaQuery.of(context).size.width * 0.7,
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            child: AlertDialog(
              title: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: tenant.isMainTenant
                        ? Colors.blue.shade100
                        : Colors.grey.shade200,
                    child: Text(
                      tenant.fullName[0].toUpperCase(),
                      style: TextStyle(
                        color: tenant.isMainTenant
                            ? Colors.blue.shade700
                            : Colors.grey.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tenant.fullName,
                            style: const TextStyle(fontSize: 18)),
                        if (tenant.isMainTenant)
                          Text(
                            t['tenant_main_tenant_badge'],
                            style: TextStyle(
                                fontSize: 12, color: Colors.blue.shade700),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Location
                      _buildDetailSection(
                        isMovedOut
                            ? t['tenant_detail_previous_location']
                            : t['tenant_detail_location'],
                        [
                          _buildDetailRow(
                              t['tenant_detail_building'], buildingName),
                          _buildDetailRow(
                              t['tenant_detail_room'], roomNumber),
                        ],
                      ),
                      const Divider(),

                      // Contact
                      _buildDetailSection(
                          t['tenant_detail_contact_section'], [
                        _buildDetailRow(
                            t['tenant_detail_phone'], tenant.phoneNumber),
                        if (tenant.email != null)
                          _buildDetailRow(
                              t['tenant_detail_email'], tenant.email!),
                      ]),
                      const Divider(),

                      // Personal
                      _buildDetailSection(
                          t['tenant_detail_personal_section'], [
                        if (tenant.gender != null)
                          _buildDetailRow(t['tenant_detail_gender'],
                              tenant.getGenderDisplayName()!),
                        if (tenant.nationalId != null)
                          _buildDetailRow(
                              t['tenant_detail_national_id'],
                              tenant.nationalId!),
                        if (tenant.occupation != null)
                          _buildDetailRow(t['tenant_detail_occupation'],
                              tenant.occupation!),
                        if (tenant.workplace != null)
                          _buildDetailRow(t['tenant_detail_workplace'],
                              tenant.workplace!),
                      ]),

                      // Rental info (not moved out)
                      if (!isMovedOut) ...[
                        const Divider(),
                        _buildDetailSection(
                            t['tenant_detail_rental_section'], [
                          _buildDetailRow(t['tenant_detail_move_in_date'],
                              _formatDate(tenant.moveInDate)),
                          _buildDetailRow(
                              t['tenant_detail_days_living'],
                              t.textWithParams('tenant_detail_days_value',
                                  {'days': tenant.daysLiving})),
                          if (tenant.monthlyRent != null)
                            _buildDetailRow(t['tenant_detail_monthly_rent'],
                                _formatCurrency(tenant.monthlyRent!)),
                          if (tenant.deposit != null)
                            _buildDetailRow(t['tenant_detail_deposit'],
                                _formatCurrency(tenant.deposit!)),
                          if (tenant.apartmentType != null &&
                              tenant.apartmentType!.isNotEmpty)
                            _buildDetailRow(
                                t['tenant_detail_apartment_type'],
                                tenant.apartmentType!),
                          if (tenant.apartmentArea != null &&
                              tenant.apartmentArea! > 0)
                            _buildDetailRow(
                                t['tenant_detail_area'],
                                t.textWithParams(
                                    'tenant_detail_area_value',
                                    {'area': tenant.apartmentArea})),
                        ]),
                      ],

                      // Move-out info
                      if (isMovedOut && tenant.moveOutDate != null) ...[
                        const Divider(),
                        _buildDetailSection(
                            t['tenant_detail_moveout_section'], [
                          _buildDetailRow(
                              t['tenant_detail_move_out_date'],
                              _formatDate(tenant.moveOutDate!)),
                          _buildDetailRow(
                              t['tenant_detail_duration'],
                              t.textWithParams('tenant_detail_days_value', {
                                'days': tenant.moveOutDate!
                                    .difference(tenant.moveInDate)
                                    .inDays
                              })),
                          if (tenant.contractTerminationReason != null)
                            _buildDetailRow(
                                t['tenant_detail_reason'],
                                tenant.contractTerminationReason!),
                          if (tenant.notes != null &&
                              tenant.notes!.isNotEmpty)
                            _buildDetailRow(
                                t['tenant_detail_notes'], tenant.notes!),
                        ]),
                      ],

                      // Contract
                      if (tenant.contractStartDate != null ||
                          tenant.contractEndDate != null) ...[
                        const Divider(),
                        _buildDetailSection(
                            t['tenant_detail_contract_section'], [
                          if (tenant.contractStartDate != null)
                            _buildDetailRow(
                                t['tenant_detail_contract_start'],
                                _formatDate(tenant.contractStartDate!)),
                          if (tenant.contractEndDate != null)
                            _buildDetailRow(
                              isMovedOut
                                  ? t['tenant_detail_contract_end_date']
                                  : t['tenant_detail_contract_end'],
                              _formatDate(tenant.contractEndDate!),
                            ),
                          if (isMovedOut) ...[
                            _buildDetailRow(
                                t['tenant_detail_contract_status'],
                                tenant.getContractStatusDisplayName()),
                            if (tenant.moveOutDate != null &&
                                tenant.contractEndDate != null)
                              _buildDetailRow(
                                tenant.moveOutDate!.isBefore(
                                        tenant.contractEndDate!)
                                    ? t['tenant_detail_early_termination']
                                    : t['tenant_detail_end_label'],
                                tenant.moveOutDate!.isBefore(
                                        tenant.contractEndDate!)
                                    ? t.textWithParams(
                                        'tenant_detail_days_early', {
                                        'days': tenant.contractEndDate!
                                            .difference(tenant.moveOutDate!)
                                            .inDays
                                      })
                                    : t['tenant_detail_on_time'],
                              ),
                          ] else ...[
                            if (tenant.daysUntilContractEnd != null)
                              _buildDetailRow(
                                  t['tenant_detail_remaining'],
                                  t.textWithParams(
                                      'tenant_detail_days_value', {
                                    'days': tenant.daysUntilContractEnd
                                  })),
                          ],
                        ]),
                      ],

                      // Vehicles
                      if (tenant.vehicles != null &&
                          tenant.vehicles!.isNotEmpty) ...[
                        const Divider(),
                        _buildDetailSection(
                          t.textWithParams('tenant_detail_vehicles_section',
                              {'count': tenant.vehicles!.length}),
                          [
                            ...tenant.vehicles!.map((vehicle) => Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 8),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.shade50,
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                                _getVehicleIcon(
                                                    vehicle.type),
                                                size: 16,
                                                color: Colors
                                                    .purple.shade700),
                                            const SizedBox(width: 8),
                                            Text(
                                              vehicle.licensePlate,
                                              style: TextStyle(
                                                fontWeight:
                                                    FontWeight.bold,
                                                color: Colors
                                                    .purple.shade900,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (vehicle.brand != null ||
                                            vehicle.model != null)
                                          Text(
                                            '${vehicle.brand ?? ''} ${vehicle.model ?? ''}'
                                                .trim(),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color:
                                                  Colors.grey.shade700,
                                            ),
                                          ),
                                        if (vehicle.isParkingRegistered &&
                                            vehicle.parkingSpot != null)
                                          Text(
                                            t.textWithParams(
                                                'tenant_vehicle_parking_spot',
                                                {'spot': vehicle.parkingSpot!}),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color:
                                                  Colors.green.shade700,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                )),
                          ],
                        ),
                      ],

                      // Rental history
                      if (tenant.previousRentals != null &&
                          tenant.previousRentals!.isNotEmpty) ...[
                        const Divider(),
                        _buildDetailSection(
                          t.textWithParams(
                              'tenant_detail_history_section',
                              {'count': tenant.previousRentals!.length}),
                          [
                            ...tenant.previousRentals!.map((rental) =>
                                Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 8),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade50,
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          t.textWithParams(
                                              'tenant_location_value', {
                                            'building': rental.buildingName,
                                            'room': rental.roomNumber,
                                          }),
                                          style: const TextStyle(
                                              fontWeight:
                                                  FontWeight.bold),
                                        ),
                                        Text(
                                          t.textWithParams(
                                              'tenant_detail_history_dates',
                                              {
                                                'from': _formatDate(
                                                    rental.moveInDate),
                                                'to': _formatDate(
                                                    rental.moveOutDate),
                                              }),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        Text(
                                          t.textWithParams(
                                              'tenant_detail_days_value',
                                              {'days': rental.duration}),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )),
                          ],
                        ),
                      ],

                      // Status
                      const Divider(),
                      _buildDetailRow(t['tenant_detail_status'],
                          tenant.getStatusDisplayName()),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(t['close']),
                ),
                if (_membership != null && _membership!.role == 'admin')
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _showTenantOptionsMenu(tenant, isMovedOut);
                    },
                    child: Text(t['tenant_options_label']),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // =========================
  // TENANT OPTIONS MENU
  // =========================
  Future<void> _showTenantOptionsMenu(
      Tenant tenant, bool isMovedOut) async {
    final t = AppTranslations.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isLargeScreen = screenWidth >= 600;

    List<Widget> menuItems = [
      ListTile(
        leading: const Icon(Icons.info_outline),
        title: Text(t['tenant_menu_view_detail']),
        onTap: () {
          Navigator.pop(context);
          final building = _buildings.firstWhere(
            (b) => b.id == tenant.buildingId,
            orElse: () => Building(
              id: '',
              organizationId: '',
              name: tenant.lastBuildingName ?? t['tenant_unknown'],
              address: '',
              createdAt: DateTime.now(),
            ),
          );
          final room = _rooms.firstWhere(
            (r) => r.id == tenant.roomId,
            orElse: () => Room(
              id: '',
              roomType: '',
              area: 0.0,
              organizationId: '',
              buildingId: '',
              roomNumber: tenant.lastRoomNumber ?? '?',
              createdAt: DateTime.now(),
            ),
          );
          _showTenantDetailDialog(tenant, building.name, room.roomNumber);
        },
      ),
      ListTile(
        leading: const Icon(Icons.edit),
        title: Text(t['tenant_menu_edit']),
        onTap: () {
          Navigator.pop(context);
          _showEditTenantDialog(tenant);
        },
      ),
      ListTile(
        leading: const Icon(Icons.move_up),
        title: Text(t['tenant_menu_move_room']),
        onTap: () {
          Navigator.pop(context);
          _showMoveRoomDialog(tenant);
        },
      ),
      if (!isMovedOut)
        ListTile(
          leading: const Icon(Icons.logout),
          title: Text(t['tenant_menu_move_out']),
          onTap: () {
            Navigator.pop(context);
            _showMoveOutDialog(tenant);
          },
        ),
      ListTile(
        leading: const Icon(Icons.directions_car),
        title: Text(t['tenant_menu_vehicles']),
        subtitle: tenant.vehicles != null && tenant.vehicles!.isNotEmpty
            ? Text(t.textWithParams('tenant_vehicle_count',
                {'count': tenant.vehicles!.length}))
            : null,
        onTap: () {
          Navigator.pop(context);
          _showVehicleManagementDialog(tenant);
        },
      ),
      ListTile(
        leading: const Icon(Icons.history),
        title: Text(t['tenant_menu_rental_history']),
        onTap: () {
          Navigator.pop(context);
          _showRentalHistoryDialog(tenant);
        },
      ),
      ListTile(
        leading: Icon(Icons.delete, color: Colors.red.shade700),
        title: Text(t['tenant_menu_delete'],
            style: TextStyle(color: Colors.red.shade700)),
        onTap: () {
          Navigator.pop(context);
          _confirmDeleteTenant(tenant);
        },
      ),
    ];

    if (isLargeScreen) {
      await _showTrackedDialog(
        context: context,
        builder: (context) {
          final t = AppTranslations.of(context);
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
                horizontal: 40.0, vertical: 24.0),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: SizedBox(
              width: 360,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: Text(
                        t['tenant_options_label'],
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const Divider(height: 0),
                    ...menuItems,
                  ],
                ),
              ),
            ),
          );
        },
      );
    } else {
      await _showTrackedBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: menuItems,
          ),
        ),
      );
    }
  }

  // =========================
  // VEHICLE MANAGEMENT
  // =========================
  Future<void> _showVehicleManagementDialog(Tenant tenant) async {
    final t = AppTranslations.of(context);
    final isPhone = MediaQuery.of(context).size.width < 600;

    await _showTrackedDialog(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isPhone
                ? MediaQuery.of(context).size.width * 0.95
                : MediaQuery.of(context).size.width * 0.7,
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              final t = AppTranslations.of(context);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.directions_car),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t['tenant_vehicle_manage_title'],
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold),
                              ),
                              Text(
                                tenant.fullName,
                                style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          tooltip: t['tenant_vehicle_add_tooltip'],
                          onPressed: () async {
                            try {
                              final result =
                                  await _showAddVehicleDialog();
                              if (result != null) {
                                final success =
                                    await widget.tenantService.addVehicle(
                                  tenant.id,
                                  result,
                                );
                                if (success) {
                                  await _refreshAll();
                                  final updatedTenant =
                                      await widget.tenantService
                                          .getTenantById(tenant.id);
                                  if (updatedTenant != null) {
                                    setDialogState(() {
                                      tenant = updatedTenant;
                                    });
                                  }
                                  if (mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(
                                      content: Text(
                                          t['tenant_vehicle_added']),
                                    ));
                                  }
                                } else {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(
                                      content: Text(
                                          t['tenant_vehicle_add_error']),
                                      backgroundColor: Colors.red,
                                    ));
                                  }
                                }
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                  content: Text(t.textWithParams(
                                      'tenant_error', {'error': e})),
                                  backgroundColor: Colors.red,
                                ));
                              }
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: tenant.vehicles == null ||
                            tenant.vehicles!.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                const Icon(
                                    Icons.directions_car_outlined,
                                    size: 48,
                                    color: Colors.grey),
                                const SizedBox(height: 12),
                                Text(t['tenant_vehicle_empty']),
                              ],
                            ),
                          )
                        : FutureBuilder<Tenant?>(
                            future: widget.tenantService
                                .getTenantById(tenant.id),
                            builder: (context, snapshot) {
                              final currentTenant =
                                  snapshot.data ?? tenant;
                              return ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount:
                                    currentTenant.vehicles?.length ?? 0,
                                separatorBuilder: (_, __) =>
                                    const Divider(),
                                itemBuilder: (context, index) {
                                  final vehicle =
                                      currentTenant.vehicles![index];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          Colors.purple.shade100,
                                      child: Icon(
                                        _getVehicleIcon(vehicle.type),
                                        color: Colors.purple.shade700,
                                      ),
                                    ),
                                    title: Text(
                                      vehicle.licensePlate,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            '${vehicle.getTypeDisplayName()}${vehicle.brand != null ? ' • ${vehicle.brand}' : ''}'),
                                        if (vehicle.isParkingRegistered &&
                                            vehicle.parkingSpot != null)
                                          Text(
                                            t.textWithParams(
                                                'tenant_vehicle_parking_spot',
                                                {'spot': vehicle.parkingSpot!}),
                                            style: TextStyle(
                                              color:
                                                  Colors.green.shade700,
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                    trailing: PopupMenuButton(
                                      itemBuilder: (context) {
                                        final t =
                                            AppTranslations.of(context);
                                        return [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Row(children: [
                                              const Icon(Icons.edit,
                                                  size: 20),
                                              const SizedBox(width: 8),
                                              Text(t['tenant_vehicle_menu_edit']),
                                            ]),
                                          ),
                                          if (!vehicle.isParkingRegistered)
                                            PopupMenuItem(
                                              value: 'parking',
                                              child: Row(children: [
                                                const Icon(
                                                    Icons.local_parking,
                                                    size: 20),
                                                const SizedBox(width: 8),
                                                Text(t['tenant_vehicle_menu_register_parking']),
                                              ]),
                                            )
                                          else
                                            PopupMenuItem(
                                              value: 'unparking',
                                              child: Row(children: [
                                                const Icon(Icons.cancel,
                                                    size: 20),
                                                const SizedBox(width: 8),
                                                Text(t['tenant_vehicle_menu_unregister_parking']),
                                              ]),
                                            ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Row(children: [
                                              Icon(Icons.delete,
                                                  size: 20,
                                                  color: Colors.red
                                                      .shade700),
                                              const SizedBox(width: 8),
                                              Text(
                                                  t['tenant_vehicle_menu_delete'],
                                                  style: TextStyle(
                                                      color: Colors.red
                                                          .shade700)),
                                            ]),
                                          ),
                                        ];
                                      },
                                      onSelected: (value) async {
                                        final t =
                                            AppTranslations.of(context);
                                        if (value == 'edit') {
                                          final result =
                                              await _showEditVehicleDialog(
                                                  vehicle);
                                          if (result != null) {
                                            final success = await widget
                                                .tenantService
                                                .updateVehicle(
                                                    tenant.id,
                                                    index,
                                                    result);
                                            if (success) {
                                              await _refreshAll();
                                              setDialogState(() {});
                                              if (mounted) {
                                                ScaffoldMessenger.of(
                                                        context)
                                                    .showSnackBar(SnackBar(
                                                  content: Text(t[
                                                      'tenant_vehicle_updated']),
                                                ));
                                              }
                                            }
                                          }
                                        } else if (value == 'parking') {
                                          final spot =
                                              await _showParkingSpotDialog();
                                          if (spot != null) {
                                            final success = await widget
                                                .tenantService
                                                .registerParkingSpot(
                                                    tenant.id, index, spot);
                                            if (success) {
                                              await _refreshAll();
                                              setDialogState(() {});
                                              if (mounted) {
                                                ScaffoldMessenger.of(
                                                        context)
                                                    .showSnackBar(SnackBar(
                                                  content: Text(t[
                                                      'tenant_vehicle_parking_registered']),
                                                ));
                                              }
                                            }
                                          }
                                        } else if (value == 'unparking') {
                                          final success = await widget
                                              .tenantService
                                              .unregisterParkingSpot(
                                                  tenant.id, index);
                                          if (success) {
                                            await _refreshAll();
                                            setDialogState(() {});
                                            if (mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(SnackBar(
                                                content: Text(t[
                                                    'tenant_vehicle_parking_unregistered']),
                                              ));
                                            }
                                          }
                                        } else if (value == 'delete') {
                                          final ok =
                                              await _showTrackedDialog<
                                                  bool>(
                                            context: context,
                                            builder: (context) {
                                              final t = AppTranslations
                                                  .of(context);
                                              return AlertDialog(
                                                title: Text(t[
                                                    'tenant_vehicle_delete_title']),
                                                content: Text(t.textWithParams(
                                                    'tenant_vehicle_delete_confirm',
                                                    {'plate': vehicle.licensePlate})),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context,
                                                            false),
                                                    child:
                                                        Text(t['cancel']),
                                                  ),
                                                  ElevatedButton(
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                            backgroundColor:
                                                                Colors.red),
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, true),
                                                    child: Text(
                                                        t['delete']),
                                                  ),
                                                ],
                                              );
                                            },
                                          );
                                          if (ok == true) {
                                            final success = await widget
                                                .tenantService
                                                .removeVehicle(
                                                    tenant.id, index);
                                            if (success) {
                                              await _refreshAll();
                                              setDialogState(() {});
                                              if (mounted) {
                                                ScaffoldMessenger.of(
                                                        context)
                                                    .showSnackBar(SnackBar(
                                                  content: Text(t[
                                                      'tenant_vehicle_deleted']),
                                                ));
                                              }
                                            }
                                          }
                                        }
                                      },
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await _refreshAll();
  }

  Future<VehicleInfo?> _showAddVehicleDialog() async {
    final licensePlateController = TextEditingController();
    final brandController = TextEditingController();
    final modelController = TextEditingController();
    final colorController = TextEditingController();
    VehicleType selectedType = VehicleType.motorcycle;

    try {
      return await _showTrackedDialog<VehicleInfo>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            final t = AppTranslations.of(context);
            return AlertDialog(
              title: Text(t['tenant_vehicle_add_title']),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: licensePlateController,
                      maxLength: 11,
                      decoration: InputDecoration(
                        counterText: '',
                        labelText: t['tenant_vehicle_plate_label'],
                        hintText: '29A-12345',
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<VehicleType>(
                      initialValue: selectedType,
                      decoration: InputDecoration(
                          labelText: t['tenant_vehicle_type_label']),
                      items: VehicleType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(_getVehicleTypeDisplayName(type)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => selectedType = value);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: brandController,
                      maxLength: 30,
                      decoration: InputDecoration(
                        counterText: '',
                        labelText: t['tenant_vehicle_brand_label'],
                        hintText: 'Honda, Yamaha, Toyota...',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: modelController,
                      maxLength: 50,
                      decoration: InputDecoration(
                        counterText: '',
                        labelText: t['tenant_vehicle_model_label'],
                        hintText: 'Wave, Vision, Vios...',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: colorController,
                      maxLength: 30,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        counterText: '',
                        labelText: t['tenant_vehicle_color_label'],
                        hintText: t['tenant_vehicle_color_hint'],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(t['cancel'])),
                ElevatedButton(
                  onPressed: () {
                    if (licensePlateController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(t['tenant_vehicle_plate_required']),
                      ));
                      return;
                    }
                    Navigator.pop(
                      context,
                      VehicleInfo(
                        licensePlate: licensePlateController.text
                            .trim()
                            .toUpperCase(),
                        type: selectedType,
                        brand: brandController.text.trim().isEmpty
                            ? null
                            : brandController.text.trim(),
                        model: modelController.text.trim().isEmpty
                            ? null
                            : modelController.text.trim(),
                        color: colorController.text.trim().isEmpty
                            ? null
                            : colorController.text.trim(),
                      ),
                    );
                  },
                  child: Text(t['tenant_vehicle_add_action']),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      licensePlateController.dispose();
      brandController.dispose();
      modelController.dispose();
      colorController.dispose();
    }
  }

  Future<VehicleInfo?> _showEditVehicleDialog(VehicleInfo vehicle) async {
    final licensePlateController =
        TextEditingController(text: vehicle.licensePlate);
    final brandController = TextEditingController(text: vehicle.brand);
    final modelController = TextEditingController(text: vehicle.model);
    final colorController = TextEditingController(text: vehicle.color);
    VehicleType selectedType = vehicle.type;

    try {
      return await _showTrackedDialog<VehicleInfo>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            final t = AppTranslations.of(context);
            return AlertDialog(
              title: Text(t['tenant_vehicle_edit_title']),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: licensePlateController,
                      maxLength: 12,
                      decoration: InputDecoration(
                        counterText: '',
                        labelText: t['tenant_vehicle_plate_label'],
                      ),
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[a-zA-Z0-9\-\.]')),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<VehicleType>(
                      initialValue: selectedType,
                      decoration: InputDecoration(
                          labelText: t['tenant_vehicle_type_label']),
                      items: VehicleType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(_getVehicleTypeDisplayName(type)),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => selectedType = value);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: brandController,
                      maxLength: 30,
                      decoration: InputDecoration(
                          counterText: '',
                          labelText: t['tenant_vehicle_brand_label']),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: modelController,
                      maxLength: 50,
                      decoration: InputDecoration(
                          counterText: '',
                          labelText: t['tenant_vehicle_model_label']),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: colorController,
                      maxLength: 30,
                      decoration: InputDecoration(
                          counterText: '',
                          labelText: t['tenant_vehicle_color_label']),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(t['cancel'])),
                ElevatedButton(
                  onPressed: () {
                    if (licensePlateController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content:
                            Text(t['tenant_vehicle_plate_required']),
                      ));
                      return;
                    }
                    Navigator.pop(
                      context,
                      VehicleInfo(
                        licensePlate: licensePlateController.text
                            .trim()
                            .toUpperCase(),
                        type: selectedType,
                        brand: brandController.text.trim().isEmpty
                            ? null
                            : brandController.text.trim(),
                        model: modelController.text.trim().isEmpty
                            ? null
                            : modelController.text.trim(),
                        color: colorController.text.trim().isEmpty
                            ? null
                            : colorController.text.trim(),
                        isParkingRegistered: vehicle.isParkingRegistered,
                        parkingSpot: vehicle.parkingSpot,
                      ),
                    );
                  },
                  child: Text(t['tenant_vehicle_save_action']),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      licensePlateController.dispose();
      brandController.dispose();
      modelController.dispose();
      colorController.dispose();
    }
  }

  Future<String?> _showParkingSpotDialog() async {
    final controller = TextEditingController();
    try {
      return await _showTrackedDialog<String>(
        context: context,
        builder: (context) {
          final t = AppTranslations.of(context);
          return AlertDialog(
            title: Text(t['tenant_parking_register_title']),
            content: TextField(
              controller: controller,
              maxLength: 10,
              decoration: InputDecoration(
                counterText: '',
                labelText: t['tenant_parking_spot_label'],
                hintText: 'A1, B2, C3...',
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(t['cancel'])),
              ElevatedButton(
                onPressed: () {
                  if (controller.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(t['tenant_parking_spot_required']),
                    ));
                    return;
                  }
                  Navigator.pop(
                      context, controller.text.trim().toUpperCase());
                },
                child: Text(t['tenant_parking_register_action']),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  IconData _getVehicleIcon(VehicleType type) {
    switch (type) {
      case VehicleType.motorcycle:
        return Icons.two_wheeler;
      case VehicleType.car:
        return Icons.directions_car;
      case VehicleType.bicycle:
        return Icons.pedal_bike;
      case VehicleType.electricBike:
        return Icons.electric_bike;
      case VehicleType.other:
        return Icons.local_shipping;
    }
  }

  // =========================
  // RENTAL HISTORY DIALOG
  // =========================
  Future<void> _showRentalHistoryDialog(Tenant tenant) async {
    final isPhone = MediaQuery.of(context).size.width < 600;

    await _showTrackedDialog(
      context: context,
      builder: (context) {
        final t = AppTranslations.of(context);
        return Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isPhone
                  ? MediaQuery.of(context).size.width * 0.95
                  : MediaQuery.of(context).size.width * 0.7,
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.history),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t['tenant_rental_history_title'],
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: tenant.previousRentals == null ||
                          tenant.previousRentals!.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.history,
                                  size: 48, color: Colors.grey),
                              const SizedBox(height: 12),
                              Text(t['tenant_rental_history_empty']),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: tenant.previousRentals!.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (context, i) {
                            final r = tenant.previousRentals![i];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.orange.shade100,
                                child: Icon(Icons.home,
                                    color: Colors.orange.shade700),
                              ),
                              title: Text(t.textWithParams(
                                  'tenant_location_value', {
                                'building': r.buildingName,
                                'room': r.roomNumber,
                              })),
                              subtitle: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.textWithParams(
                                        'tenant_detail_history_dates', {
                                      'from': DateFormat.yMd()
                                          .format(r.moveInDate),
                                      'to': DateFormat.yMd()
                                          .format(r.moveOutDate),
                                    }),
                                    style:
                                        const TextStyle(fontSize: 13),
                                  ),
                                  Text(
                                    t.textWithParams(
                                        'tenant_detail_days_value',
                                        {'days': r.duration}),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  // =========================
  // EDIT TENANT DIALOG
  // =========================
  Future<void> _showEditTenantDialog(Tenant tenant) async {
    final buildings = await _getBuildings();
    final allRooms = await _getAllRooms();
    if (!mounted) return;
    final t = AppTranslations.of(context);
    final isPhone = MediaQuery.of(context).size.width < 600;

    final nameController =
        TextEditingController(text: tenant.fullName);
    final phoneController =
        TextEditingController(text: tenant.phoneNumber);
    final emailController =
        TextEditingController(text: tenant.email);
    final nationalIdController =
        TextEditingController(text: tenant.nationalId);
    final occupationController =
        TextEditingController(text: tenant.occupation);
    final workplaceController =
        TextEditingController(text: tenant.workplace);
    final monthlyRentController =
        TextEditingController(text: tenant.monthlyRent?.toString() ?? '');
    final areaController =
        TextEditingController(text: tenant.apartmentArea?.toString() ?? '');
    final typeController =
        TextEditingController(text: tenant.apartmentType ?? '');

    DateTime editedMoveInDate = tenant.moveInDate;

    final result = await _showTrackedDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final t = AppTranslations.of(context);
          return AlertDialog(
            title: Text(t['tenant_edit_title']),
            content: SizedBox(
              width: isPhone ? double.maxFinite : 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildInputField(nameController,
                        t['tenant_field_name'], Icons.person,
                        maxLength: 100),
                    _buildInputField(
                        phoneController,
                        t['tenant_field_phone'],
                        Icons.phone,
                        keyboardType: TextInputType.phone,
                        maxLength: 15),
                    _buildInputField(
                        monthlyRentController,
                        t['tenant_field_rent'],
                        Icons.money,
                        suffix: '₫',
                        keyboardType: TextInputType.number,
                        maxLength: 12),
                    const Divider(height: 32),
                    LocalizedDatePicker(
                      labelText: t['tenant_field_move_in_date'],
                      initialDate: editedMoveInDate,
                      required: true,
                      prefixIcon: Icons.calendar_today,
                      onDateChanged: (date) {
                        if (date != null) {
                          setDialogState(
                              () => editedMoveInDate = date);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(t['tenant_section_invoice_apt'],
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                            child: _buildInputField(
                                typeController,
                                t['tenant_field_apt_type'],
                                Icons.category,
                                maxLength: 50)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _buildInputField(
                                areaController,
                                t['tenant_field_area'],
                                Icons.square_foot,
                                suffix: 'm²',
                                keyboardType: TextInputType.number,
                                maxLength: 6)),
                      ],
                    ),
                    _buildInputField(emailController,
                        t['tenant_field_email'], Icons.email,
                        maxLength: 100),
                    _buildInputField(
                        nationalIdController,
                        t['tenant_field_national_id'],
                        Icons.badge,
                        maxLength: 12),
                    _buildInputField(occupationController,
                        t['tenant_field_occupation'], Icons.work,
                        maxLength: 100),
                    _buildInputField(
                        workplaceController,
                        t['tenant_field_workplace'],
                        Icons.location_city,
                        maxLength: 150),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(t['cancel'])),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, {
                    'fullName': nameController.text.trim(),
                    'phoneNumber': phoneController.text.trim(),
                    'email': emailController.text.trim().isEmpty
                        ? null
                        : emailController.text.trim(),
                    'nationalId':
                        nationalIdController.text.trim().isEmpty
                            ? null
                            : nationalIdController.text.trim(),
                    'occupation':
                        occupationController.text.trim().isEmpty
                            ? null
                            : occupationController.text.trim(),
                    'workplace':
                        workplaceController.text.trim().isEmpty
                            ? null
                            : workplaceController.text.trim(),
                    'monthlyRent': double.tryParse(
                        monthlyRentController.text.trim()),
                    'apartmentArea':
                        double.tryParse(areaController.text.trim()),
                    'apartmentType': typeController.text.trim(),
                  });
                },
                child: Text(t['tenant_edit_save']),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      await widget.tenantService.updateTenant(tenant.id, result);
      if (!mounted) return;
      _refreshAll();
      widget.onChanged?.call();
    }
  }

  Widget _buildInputField(
    TextEditingController controller,
    String label,
    IconData icon, {
    String? suffix,
    TextInputType? keyboardType,
    int? maxLength,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLength: maxLength,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          suffixText: suffix,
          border: const OutlineInputBorder(),
          isDense: true,
          counterText: maxLength != null ? null : '',
        ),
      ),
    );
  }

  // =========================
  // MOVE ROOM DIALOG
  // =========================
  Future<void> _showMoveRoomDialog(Tenant tenant) async {
    String? selectedBuildingId =
        tenant.buildingId.isNotEmpty ? tenant.buildingId : null;
    String? selectedRoomId =
        tenant.roomId.isNotEmpty ? tenant.roomId : null;

    final result = await _showTrackedDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final t = AppTranslations.of(context);
          final availableRooms = _rooms
              .where((r) => r.buildingId == selectedBuildingId)
              .toList();

          return AlertDialog(
            title: Text(t['tenant_move_room_title']),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedBuildingId,
                  decoration: InputDecoration(
                      labelText: t['tenant_move_room_building'],
                      border: const OutlineInputBorder()),
                  items: _buildings
                      .map((b) => DropdownMenuItem(
                          value: b.id, child: Text(b.name)))
                      .toList(),
                  onChanged: (val) {
                    setDialogState(() {
                      selectedBuildingId = val;
                      selectedRoomId = null;
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedRoomId,
                  decoration: InputDecoration(
                      labelText: t['tenant_move_room_room'],
                      border: const OutlineInputBorder()),
                  items: availableRooms
                      .map((r) => DropdownMenuItem(
                          value: r.id,
                          child: Text('${r.roomNumber} (${r.roomType})')))
                      .toList(),
                  onChanged: (val) =>
                      setDialogState(() => selectedRoomId = val),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(t['cancel'])),
              ElevatedButton(
                onPressed: (selectedBuildingId == null ||
                        selectedRoomId == null)
                    ? null
                    : () => Navigator.pop(context, true),
                child: Text(t['tenant_move_room_confirm']),
              ),
            ],
          );
        },
      ),
    );

    if (result == true &&
        selectedBuildingId != null &&
        selectedRoomId != null) {
      if (selectedRoomId == tenant.roomId) return;
      final t = AppTranslations.of(context);
      final success = await widget.tenantService.moveTenantToRoom(
          tenant.id, selectedBuildingId!, selectedRoomId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success
              ? t['tenant_move_room_success']
              : t['tenant_move_room_error']),
          backgroundColor: success ? Colors.green : Colors.red,
        ));
        _refreshAll();
        widget.onChanged?.call();
      }
    }
  }

  // =========================
  // MOVE OUT DIALOG
  // =========================
  Future<void> _showMoveOutDialog(Tenant tenant) async {
    DateTime selectedDate = DateTime.now();
    String? selectedReason;

    final result = await _showTrackedDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final t = AppTranslations.of(context);

          // Build reason list inside builder so it's localised
          final reasonOptions = [
            t['tenant_moveout_reason_1'],
            t['tenant_moveout_reason_2'],
            t['tenant_moveout_reason_3'],
            t['tenant_moveout_reason_4'],
            t['tenant_moveout_reason_5'],
          ];
          selectedReason ??= reasonOptions.first;

          return AlertDialog(
            title: Text(t['tenant_moveout_title']),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.textWithParams('tenant_moveout_confirm',
                    {'name': tenant.fullName})),
                const SizedBox(height: 16),
                LocalizedDatePicker(
                  labelText: t['tenant_moveout_date_label'],
                  initialDate: selectedDate,
                  required: true,
                  prefixIcon: Icons.calendar_today,
                  onDateChanged: (date) {
                    if (date != null) {
                      setDialogState(() => selectedDate = date);
                    }
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedReason,
                  decoration: InputDecoration(
                    labelText: t['tenant_moveout_reason_label'],
                    border: const OutlineInputBorder(),
                  ),
                  items: reasonOptions
                      .map((reason) => DropdownMenuItem(
                          value: reason, child: Text(reason)))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => selectedReason = value),
                ),
                if (tenant.contractEndDate != null &&
                    selectedDate
                        .isBefore(tenant.contractEndDate!)) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: Colors.orange.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber,
                            color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t.textWithParams(
                                'tenant_moveout_early_warning', {
                              'days': tenant.contractEndDate!
                                  .difference(selectedDate)
                                  .inDays
                            }),
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.orange.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(t['cancel'])),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, {
                  'date': selectedDate,
                  'reason': selectedReason,
                }),
                child: Text(t['tenant_moveout_confirm_action']),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      final t = AppTranslations.of(context);
      final success = await widget.tenantService.markTenantAsMovedOut(
        tenant.id,
        moveOutDate: result['date'],
        moveOutReason: result['reason'],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            success ? t['tenant_moveout_success'] : t['tenant_moveout_failed']),
      ));
      await _refreshAll();
    }
  }

  // =========================
  // DELETE TENANT
  // =========================
  Future<void> _confirmDeleteTenant(Tenant tenant) async {
    final ok = await _showTrackedDialog<bool>(
      context: context,
      builder: (context) {
        final t = AppTranslations.of(context);
        return AlertDialog(
          title: Text(t['tenant_delete_title']),
          content: Text(t.textWithParams(
              'tenant_delete_confirm', {'name': tenant.fullName})),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t['cancel'])),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: Text(t['delete']),
            ),
          ],
        );
      },
    );

    if (ok == true) {
      final t = AppTranslations.of(context);
      final success =
          await widget.tenantService.deleteTenant(tenant.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success
            ? t['tenant_delete_success']
            : t['tenant_delete_failed']),
      ));
      await _refreshAll();
    }
  }

  // =========================
  // ADD TENANT DIALOG
  // =========================
  Future<void> _showAddTenantDialog(
      List<Building> buildings, List<Room> allRooms) async {
    final isPhone = MediaQuery.of(context).size.width < 600;

    final Set<String> occupiedRoomIds = _allTenants
        .where((t) => t.status == TenantStatus.active && t.isMainTenant)
        .map((t) => t.roomId)
        .toSet();

    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final nationalIdController = TextEditingController();
    final occupationController = TextEditingController();
    final workplaceController = TextEditingController();
    final monthlyRentController = TextEditingController();
    final areaController = TextEditingController();
    final typeController = TextEditingController();

    String? selectedBuildingId =
        buildings.isNotEmpty ? buildings.first.id : null;
    String? selectedRoomId;
    TenantStatus selectedStatus = TenantStatus.active;
    bool isMainTenant = true;
    DateTime moveInDate = DateTime.now();

    final result = await _showTrackedDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final t = AppTranslations.of(context);
          final availableRooms = allRooms
              .where((r) => r.buildingId == selectedBuildingId)
              .toList();

          return Dialog(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isPhone
                    ? MediaQuery.of(context).size.width * 0.95
                    : MediaQuery.of(context).size.width * 0.7,
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: AlertDialog(
                title: Text(t['tenant_add_title']),
                contentPadding:
                    const EdgeInsets.fromLTRB(24, 20, 24, 0),
                content: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildInputField(nameController,
                            t['tenant_field_name_required'], Icons.person,
                            maxLength: 100),
                        _buildInputField(
                            phoneController,
                            t['tenant_field_phone_required'],
                            Icons.phone,
                            keyboardType: TextInputType.phone,
                            maxLength: 15),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: selectedBuildingId,
                          decoration: InputDecoration(
                              labelText: t['tenant_field_building'],
                              border: const OutlineInputBorder()),
                          items: buildings
                              .map((b) => DropdownMenuItem(
                                  value: b.id, child: Text(b.name)))
                              .toList(),
                          onChanged: (val) =>
                              setDialogState(() {
                            selectedBuildingId = val;
                            selectedRoomId = null;
                          }),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: selectedRoomId,
                          decoration: InputDecoration(
                              labelText: t['tenant_field_room'],
                              border: const OutlineInputBorder()),
                          items: availableRooms.map((room) {
                            final bool isOccupied =
                                occupiedRoomIds.contains(room.id);
                            return DropdownMenuItem(
                              value: room.id,
                              child: Text(
                                t.textWithParams(
                                    isOccupied
                                        ? 'tenant_room_occupied'
                                        : 'tenant_room_vacant',
                                    {'number': room.roomNumber}),
                                style: TextStyle(
                                  color: isOccupied
                                      ? Colors.red
                                      : Colors.green.shade700,
                                  fontWeight: isOccupied
                                      ? FontWeight.normal
                                      : FontWeight.bold,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            final room = allRooms.firstWhere((r) => r.id == val);
                            print('Selected room: ${room.roomNumber}, area: ${room.area}, type: ${room.roomType}');
                            setDialogState(() {
                              selectedRoomId = val;
                              areaController.text = room.area.toString();
                              typeController.text = room.roomType;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<
                                  TenantStatus>(
                                value: selectedStatus,
                                decoration: InputDecoration(
                                    labelText:
                                        t['tenant_field_status'],
                                    border:
                                        const OutlineInputBorder()),
                                items: TenantStatus.values.map((s) {
                                  String label =
                                      t['tenant_status_active'];
                                  if (s == TenantStatus.inactive) {
                                    label =
                                        t['tenant_status_inactive'];
                                  }
                                  if (s == TenantStatus.moveOut) {
                                    label =
                                        t['tenant_status_moved_out'];
                                  }
                                  return DropdownMenuItem(
                                      value: s, child: Text(label));
                                }).toList(),
                                onChanged: (val) => setDialogState(
                                    () => selectedStatus = val!),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: CheckboxListTile(
                                title: Text(
                                    t['tenant_field_main_tenant'],
                                    style: const TextStyle(
                                        fontSize: 14)),
                                value: isMainTenant,
                                onChanged: (val) =>
                                    setDialogState(() =>
                                        isMainTenant = val ?? true),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildInputField(
                            monthlyRentController,
                            t['tenant_field_rent_required'],
                            Icons.money,
                            suffix: '₫',
                            keyboardType: TextInputType.number,
                            maxLength: 12),
                        const Divider(height: 32),
                        Text(t['tenant_section_invoice_apt'],
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                                child: _buildInputField(
                                    typeController,
                                    t['tenant_field_apt_type'],
                                    Icons.category,
                                    maxLength: 50)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: _buildInputField(
                                    areaController,
                                    t['tenant_field_area'],
                                    Icons.square_foot,
                                    suffix: 'm²',
                                    keyboardType:
                                        TextInputType.number,
                                    maxLength: 6)),
                          ],
                        ),
                        _buildInputField(emailController,
                            t['tenant_field_email'], Icons.email,
                            keyboardType:
                                TextInputType.emailAddress,
                            maxLength: 100),
                        _buildInputField(
                            nationalIdController,
                            t['tenant_field_national_id'],
                            Icons.badge,
                            maxLength: 12),
                        _buildInputField(occupationController,
                            t['tenant_field_occupation'], Icons.work,
                            maxLength: 100),
                        _buildInputField(
                            workplaceController,
                            t['tenant_field_workplace'],
                            Icons.location_city,
                            maxLength: 150),
                        const SizedBox(height: 16),
                        LocalizedDatePicker(
                          labelText: t['tenant_field_move_in_date'],
                          initialDate: moveInDate,
                          required: true,
                          prefixIcon: Icons.calendar_today,
                          onDateChanged: (date) {
                            if (date != null) {
                              setDialogState(
                                  () => moveInDate = date);
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(t['cancel'])),
                  ElevatedButton(
                    onPressed: () {
                      if (nameController.text.isEmpty ||
                          selectedRoomId == null) return;
                      Navigator.pop(context, {
                        'fullName': nameController.text.trim(),
                        'phoneNumber': phoneController.text.trim(),
                        'email': emailController.text.trim(),
                        'nationalId':
                            nationalIdController.text.trim(),
                        'occupation':
                            occupationController.text.trim(),
                        'workplace':
                            workplaceController.text.trim(),
                        'buildingId': selectedBuildingId,
                        'roomId': selectedRoomId,
                        'monthlyRent': double.tryParse(
                                monthlyRentController.text) ??
                            0,
                        'apartmentArea': double.tryParse(
                                areaController.text) ??
                            0,
                        'apartmentType': typeController.text.trim(),
                        'isMainTenant': isMainTenant,
                        'status': selectedStatus,
                        'moveInDate': moveInDate,
                      });
                    },
                    child: Text(t['tenant_add_action']),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (result != null) {
      final tenant = Tenant(
        id: '',
        organizationId: widget.organization.id,
        buildingId: result['buildingId'],
        roomId: result['roomId'],
        fullName: result['fullName'],
        phoneNumber: result['phoneNumber'],
        email: result['email'],
        nationalId: result['nationalId'],
        occupation: result['occupation'],
        workplace: result['workplace'],
        isMainTenant: result['isMainTenant'],
        monthlyRent: result['monthlyRent'],
        apartmentArea: result['apartmentArea'],
        apartmentType: result['apartmentType'],
        status: result['status'],
        moveInDate: result['moveInDate'],
        createdAt: DateTime.now(),
      );
      await widget.tenantService.addTenant(tenant);
      _refreshAll();
      widget.onChanged?.call();
    }
  }

  Color _getTenantStatusColor(TenantStatus status) {
    switch (status) {
      case TenantStatus.active:
        return Colors.green.shade700;
      case TenantStatus.inactive:
        return Colors.grey.shade700;
      case TenantStatus.moveOut:
        return Colors.blueGrey.shade700;
      case TenantStatus.suspended:
        return Colors.orange.shade700;
    }
  }
}