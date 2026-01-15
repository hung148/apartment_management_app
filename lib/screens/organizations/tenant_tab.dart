// lib/screens/organization/tenants_tab_full.dart
//
// Full, untrimmed conversion of the tenants UI you provided into a standalone
// StatefulWidget class. This preserves the original structure, behavior and
// dialogs (no trimming). It expects the same services and models you used
// in OrganizationScreen and uses a ValueListenable-based search input so the
// list rebuilds only when the controller value changes (matching your original).
//
// Add this file to your project and import it where needed.

import 'package:flutter/material.dart';
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

  const TenantsTab({
    Key? key,
    required this.organization,
    required this.tenantService,
    required this.buildingService,
    required this.roomService,
    required this.organizationService,
    required this.authService,
  }) : super(key: key);

  @override
  State<TenantsTab> createState() => _TenantsTabState();
}

class _TenantsTabState extends State<TenantsTab> with AutomaticKeepAliveClientMixin {
  // KeepAlive so tab state persists
  @override
  bool get wantKeepAlive => true;

  // Search controller used exactly as in your original code (ValueListenableBuilder)
  final TextEditingController _searchController = TextEditingController();

  // Initial data future
  late Future<List<dynamic>> _initialFuture;

  // Cached data
  List<Tenant> _allTenants = [];
  List<Building> _buildings = [];
  List<Room> _rooms = [];
  Membership? _membership;

  @override
  void initState() {
    super.initState();
    _initialFuture = Future.wait([
      _getAllTenants(),
      _getBuildings(),
      _getAllRooms(),
      _getMyMembership(),
    ]);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Convenience wrappers to match original naming
  Future<List<Tenant>> _getAllTenants() => widget.tenantService.getOrganizationTenants(widget.organization.id);
  Future<List<Building>> _getBuildings() => widget.buildingService.getOrganizationBuildings(widget.organization.id);
  Future<List<Room>> _getAllRooms() => widget.roomService.getOrganizationRooms(widget.organization.id);
  Future<Membership?> _getMyMembership() {
    final userId = widget.authService.currentUser?.uid;
    if (userId == null) return Future.value(null);
    return widget.organizationService.getUserMembership(userId, widget.organization.id);
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
    // update caches
    _allTenants = List<Tenant>.from(data[0] as List<Tenant>);
    _buildings = List<Building>.from(data[1] as List<Building>);
    _rooms = List<Room>.from(data[2] as List<Room>);
    _membership = data[3] as Membership?;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return FutureBuilder<List<dynamic>>(
      future: _initialFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData) {
          return const Center(child: Text('Không có dữ liệu'));
        }

        // Extract and cache data (preserve original behavior)
        final allTenants = snapshot.data![0] as List<Tenant>;
        final buildings = snapshot.data![1] as List<Building>;
        final rooms = snapshot.data![2] as List<Room>;
        final membership = snapshot.data![3] as Membership?;

        // Update local caches so dialogs/actions can refresh without re-fetch
        _allTenants = allTenants;
        _buildings = buildings;
        _rooms = rooms;
        _membership = membership;

        final isAdmin = membership != null && membership.role == 'admin';

        return Column(
          children: [
            // Search Bar - No setState, just controller (ValueListenableBuilder)
            Padding(
              padding: const EdgeInsets.all(16),
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _searchController,
                builder: (context, value, child) {
                  return TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm theo tên, SĐT, email, nghề nghiệp...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: value.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                              },
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

            // Add Tenant Button (Admin Only)
            if (isAdmin)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showAddTenantDialog(buildings, rooms),
                    icon: const Icon(Icons.person_add),
                    label: const Text('Thêm người thuê'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Tenants List - Rebuilds only when search changes
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
                            query.isEmpty ? Icons.people_outline : Icons.search_off,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            query.isEmpty ? 'Chưa có người thuê nào' : 'Không tìm thấy kết quả',
                            style: const TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                          if (query.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Thử tìm kiếm với từ khóa khác',
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
                      // Results counter
                      if (query.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
                              const SizedBox(width: 8),
                              Text(
                                'Tìm thấy ${tenants.length} kết quả',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                              ),
                            ],
                          ),
                        ),

                      // List
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: tenants.length,
                          itemBuilder: (context, index) {
                            final tenant = tenants[index];

                            // Resolve building / room info
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
                                organizationId: '',
                                buildingId: '',
                                roomNumber: displayRoomNumber,
                                createdAt: DateTime.now(),
                              );
                            } else {
                              building = buildings.firstWhere(
                                (b) => b.id == tenant.buildingId,
                                orElse: () => Building(
                                  id: '',
                                  organizationId: '',
                                  name: 'Không xác định',
                                  address: '',
                                  createdAt: DateTime.now(),
                                ),
                              );

                              room = rooms.firstWhere(
                                (r) => r.id == tenant.roomId,
                                orElse: () => Room(
                                  id: '',
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
                                          arguments: room,
                                        );
                                      }
                                    : null,
                                onLongPress: isAdmin
                                    ? () => _showTenantOptionsMenu(tenant, isMovedOut)
                                    : null,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Avatar
                                      CircleAvatar(
                                        radius: 30,
                                        backgroundColor: tenant.isMainTenant
                                            ? Colors.blue.shade100
                                            : Colors.grey.shade200,
                                        child: Text(
                                          tenant.fullName.isNotEmpty ? tenant.fullName[0].toUpperCase() : '?',
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: tenant.isMainTenant ? Colors.blue.shade700 : Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),

                                      // Details
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Name + main tenant badge
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
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.blue.shade100,
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                    child: Text(
                                                      'Chủ phòng',
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

                                            // Occupation (if available)
                                            if (tenant.occupation != null) ...[
                                              Row(
                                                children: [
                                                  Icon(Icons.work, size: 16, color: Colors.grey.shade700),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      tenant.occupation!,
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        color: Colors.grey.shade700,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                            ],

                                            // Location
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: canNavigate ? Colors.blue.shade50 : Colors.grey.shade100,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.location_on,
                                                    size: 18,
                                                    color: canNavigate ? Colors.blue.shade700 : Colors.grey.shade600,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          canNavigate ? 'Vị trí' : 'Vị trí trước đây',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            color: Colors.grey.shade600,
                                                            fontWeight: FontWeight.w500,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          '$displayBuildingName - Phòng $displayRoomNumber',
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            fontWeight: FontWeight.w600,
                                                            color: canNavigate ? Colors.blue.shade900 : Colors.grey.shade700,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  if (canNavigate) Icon(Icons.arrow_forward_ios, size: 14, color: Colors.blue.shade700),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 12),

                                            // Phone
                                            Row(
                                              children: [
                                                Icon(Icons.phone, size: 16, color: Colors.grey.shade700),
                                                const SizedBox(width: 6),
                                                Text(
                                                  tenant.phoneNumber,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),

                                            // Monthly rent
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

                                            // Status badge and rental history indicator
                                            Row(
                                              children: [
                                                Text(
                                                  'Trạng thái:',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: _getTenantStatusColor(tenant.status).withOpacity(0.1),
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
                                                // Rental history indicator
                                                if (tenant.previousRentals != null && tenant.previousRentals!.isNotEmpty)
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.orange.shade100,
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(Icons.history, size: 12, color: Colors.orange.shade700),
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
                                          ],
                                        ),
                                      ),

                                      // Menu button for admin
                                      if (isAdmin)
                                        IconButton(
                                          icon: Icon(Icons.more_vert, color: Colors.grey.shade600),
                                          onPressed: () => _showTenantOptionsMenu(tenant, isMovedOut),
                                          tooltip: 'Tùy chọn',
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
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

  // Filter method (same as before)
  List<Tenant> _filterTenants(List<Tenant> tenants, String query) {
    if (query.isEmpty) return tenants;

    final searchLower = query.toLowerCase().trim();
    return tenants.where((tenant) {
      if (tenant.fullName.toLowerCase().contains(searchLower)) return true;
      if (tenant.phoneNumber.contains(searchLower)) return true;
      if (tenant.email != null && tenant.email!.toLowerCase().contains(searchLower)) return true;
      if (tenant.nationalId != null && tenant.nationalId!.contains(searchLower)) return true;
      if (tenant.occupation != null && tenant.occupation!.toLowerCase().contains(searchLower)) return true;
      if (tenant.workplace != null && tenant.workplace!.toLowerCase().contains(searchLower)) return true;
      return false;
    }).toList();
  }

  // Show options menu for tenant
  Future<void> _showTenantOptionsMenu(Tenant tenant, bool isMovedOut) async {
    await showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Edit - always available
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Chỉnh sửa thông tin'),
              onTap: () {
                Navigator.pop(context);
                _showEditTenantDialog(tenant);
              },
            ),
            ListTile(
              leading: const Icon(Icons.move_up),
              title: const Text('Chuyển phòng'),
              onTap: () {
                Navigator.pop(context);
                _showMoveRoomDialog(tenant);
              },
            ),
            // Move room - only for active tenants
            if (!isMovedOut) ...[
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Chuyển đi'),
                onTap: () {
                  Navigator.pop(context);
                  _showMoveOutDialog(tenant);
                },
              ),
            ],
            // Rental history - always available
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Lịch sử thuê phòng'),
              onTap: () {
                Navigator.pop(context);
                _showRentalHistoryDialog(tenant);
              },
            ),
            // Delete - always available
            ListTile(
              leading: Icon(Icons.delete, color: Colors.red.shade700),
              title: Text('Xóa', style: TextStyle(color: Colors.red.shade700)),
              onTap: () {
                Navigator.pop(context);
                _confirmDeleteTenant(tenant);
              },
            ),
          ],
        ),
      ),
    );
  }

  // Show rental history dialog
  Future<void> _showRentalHistoryDialog(Tenant tenant) async {
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.9,
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
                    const Expanded(
                      child: Text(
                        'Lịch sử thuê phòng',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
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
                child: tenant.previousRentals == null || tenant.previousRentals!.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history, size: 48, color: Colors.grey),
                            SizedBox(height: 12),
                            Text('Không có lịch sử thuê'),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: tenant.previousRentals!.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, i) {
                          final r = tenant.previousRentals![i];
                          final durationDays = r.duration;
                          return ListTile(
                            title: Text('${r.buildingName} - Phòng ${r.roomNumber}'),
                            subtitle: Text(
                              'Từ ${DateFormat.yMd().format(r.moveInDate)} đến ${DateFormat.yMd().format(r.moveOutDate)} • $durationDays ngày',
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  // Edit tenant dialog (keeps original behavior)
  Future<void> _showEditTenantDialog(Tenant tenant) async {
    // Fetch buildings and rooms inside the dialog (assuming they are cached/quick)
    final buildings = await _getBuildings();
    final allRooms = await _getAllRooms();

    // Resolve current building and room (similar to list item logic)
    late final Building currentBuilding;
    late final Room currentRoom;
    late final String currentBuildingName;
    late final String currentRoomNumber;

    final bool isMovedOut = tenant.status == TenantStatus.moveOut;

    if (isMovedOut &&
        tenant.lastBuildingName != null &&
        tenant.lastRoomNumber != null) {
      currentBuildingName = tenant.lastBuildingName!;
      currentRoomNumber = tenant.lastRoomNumber!;

      currentBuilding = Building(
        id: '',
        organizationId: '',
        name: currentBuildingName,
        address: '',
        createdAt: DateTime.now(),
      );

      currentRoom = Room(
        id: '',
        organizationId: '',
        buildingId: '',
        roomNumber: currentRoomNumber,
        createdAt: DateTime.now(),
      );
    } else {
      currentBuilding = buildings.firstWhere(
        (b) => b.id == tenant.buildingId,
        orElse: () => Building(
          id: '',
          organizationId: '',
          name: 'Không xác định',
          address: '',
          createdAt: DateTime.now(),
        ),
      );

      currentRoom = allRooms.firstWhere(
        (r) => r.id == tenant.roomId,
        orElse: () => Room(
          id: '',
          organizationId: '',
          buildingId: '',
          roomNumber: '?',
          createdAt: DateTime.now(),
        ),
      );

      currentBuildingName = currentBuilding.name;
      currentRoomNumber = currentRoom.roomNumber;
    }

    final nameController = TextEditingController(text: tenant.fullName);
    final phoneController = TextEditingController(text: tenant.phoneNumber);
    final emailController = TextEditingController(text: tenant.email);
    final nationalIdController = TextEditingController(text: tenant.nationalId);
    final occupationController = TextEditingController(text: tenant.occupation);
    final workplaceController = TextEditingController(text: tenant.workplace);
    final monthlyRentController = TextEditingController(
      text: tenant.monthlyRent?.toString() ?? '',
    );

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.9,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: AlertDialog(
            title: const Text('Chỉnh sửa thông tin'),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Họ và tên'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: phoneController,
                      decoration: const InputDecoration(labelText: 'Số điện thoại'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nationalIdController,
                      decoration: const InputDecoration(labelText: 'CMND/CCCD'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: occupationController,
                      decoration: const InputDecoration(labelText: 'Nghề nghiệp'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: workplaceController,
                      decoration: const InputDecoration(labelText: 'Nơi làm việc'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: monthlyRentController,
                      decoration: const InputDecoration(
                        labelText: 'Tiền thuê hàng tháng',
                        suffixText: '₫',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 24),
                    // Current location (read-only) with change button
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.location_on, size: 18, color: Colors.blue.shade700),
                              const SizedBox(width: 8),
                              const Text(
                                'Vị trí hiện tại',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1565C0),
                                ),
                              ),
                              const Spacer(),
                              if (!isMovedOut) // only show if tenant is still active
                                TextButton.icon(
                                  icon: const Icon(Icons.swap_horiz, size: 18),
                                  label: const Text('Chuyển phòng', style: TextStyle(fontSize: 13)),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.blue.shade700,
                                    padding: EdgeInsets.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () {
                                    Navigator.pop(context); // close edit dialog first
                                    _showMoveRoomDialog(tenant); // open move room dialog
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$currentBuildingName - Phòng $currentRoomNumber',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                          ),
                          if (isMovedOut)
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text(
                                '(Đã chuyển đi)',
                                style: TextStyle(color: Colors.red, fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Hủy'),
              ),
              ElevatedButton(
                onPressed: () {
                  final monthlyRent = double.tryParse(
                    monthlyRentController.text.trim(),
                  );

                  Navigator.pop(context, {
                    'fullName': nameController.text.trim(),
                    'phoneNumber': phoneController.text.trim(),
                    'email': emailController.text.trim().isEmpty
                        ? null
                        : emailController.text.trim(),
                    'nationalId': nationalIdController.text.trim().isEmpty
                        ? null
                        : nationalIdController.text.trim(),
                    'occupation': occupationController.text.trim().isEmpty
                        ? null
                        : occupationController.text.trim(),
                    'workplace': workplaceController.text.trim().isEmpty
                        ? null
                        : workplaceController.text.trim(),
                    'monthlyRent': monthlyRent,
                  });
                },
                child: const Text('Lưu'),
              ),
            ],
          ),
        ),
      ),
    );

    if (result != null && mounted) {
      final success = await widget.tenantService.updateTenant(tenant.id, result);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã cập nhật thông tin')),
        );
        setState(() {});
      }
    }
  }

  // Move room dialog
  Future<void> _showMoveRoomDialog(Tenant tenant) async {
    String? selectedBuildingId = tenant.buildingId.isNotEmpty ? tenant.buildingId : null;
    String? selectedRoomId = tenant.roomId.isNotEmpty ? tenant.roomId : null;

    List<Room> _roomsForBuilding(String? buildingId) {
      if (buildingId == null || buildingId.isEmpty) return [];
      return _rooms.where((r) => r.buildingId == buildingId).toList();
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Build unique maps to avoid duplicate DropdownMenuItem values
            final Map<String, Building> buildingById = {
              for (var b in _buildings) b.id: b
            };
            final availableRooms = _roomsForBuilding(selectedBuildingId);
            final Map<String, Room> roomById = {
              for (var r in availableRooms) r.id: r
            };

            // If selected ids are not present in the current items, clear them
            if (selectedBuildingId != null && !buildingById.containsKey(selectedBuildingId)) {
              selectedBuildingId = null;
              selectedRoomId = null;
            }
            if (selectedRoomId != null && !roomById.containsKey(selectedRoomId)) {
              selectedRoomId = null;
            }

            return AlertDialog(
              title: const Text('Chuyển phòng'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Building dropdown
                  DropdownButtonFormField<String>(
                    value: buildingById.containsKey(selectedBuildingId) ? selectedBuildingId : null,
                    decoration: const InputDecoration(labelText: 'Toà nhà mới'),
                    items: [
                      const DropdownMenuItem<String>(value: null, child: Text('Chọn toà nhà')),
                      ...buildingById.entries.map((e) => DropdownMenuItem<String>(
                            value: e.key,
                            child: Text(e.value.name),
                          )),
                    ],
                    onChanged: (val) {
                      setDialogState(() {
                        selectedBuildingId = val;
                        selectedRoomId = null; // reset room when building changes
                      });
                    },
                  ),

                  const SizedBox(height: 12),

                  // Room dropdown (filtered by building)
                  DropdownButtonFormField<String>(
                    value: roomById.containsKey(selectedRoomId) ? selectedRoomId : null,
                    decoration: const InputDecoration(labelText: 'Phòng mới'),
                    items: [
                      const DropdownMenuItem<String>(value: null, child: Text('Chọn phòng')),
                      ...roomById.entries.map((e) => DropdownMenuItem<String>(
                            value: e.key,
                            child: Text(e.value.roomNumber),
                          )),
                    ],
                    onChanged: (val) {
                      setDialogState(() {
                        selectedRoomId = val;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
                ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Chuyển')),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      if (selectedBuildingId == null || selectedRoomId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng chọn toà nhà và phòng mới')));
        return;
      }

      final success = await widget.tenantService.moveTenantToRoom(tenant.id, selectedBuildingId!, selectedRoomId!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success ? 'Đã chuyển phòng' : 'Chuyển phòng thất bại')));
      await _refreshAll();
    }
  }

  // Move out dialog
  Future<void> _showMoveOutDialog(Tenant tenant) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đánh dấu đã chuyển đi'),
        content: Text('Đánh dấu ${tenant.fullName} là đã chuyển đi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xác nhận')),
        ],
      ),
    );

    if (ok == true) {
      final success = await widget.tenantService.markTenantAsMovedOut(tenant.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success ? 'Đã đánh dấu chuyển đi' : 'Thất bại')));
      await _refreshAll();
    }
  }

  // Confirm delete tenant
  Future<void> _confirmDeleteTenant(Tenant tenant) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa người thuê'),
        content: Text('Bạn có chắc muốn xóa ${tenant.fullName}? Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
        ],
      ),
    );

    if (ok == true) {
      final success = await widget.tenantService.deleteTenant(tenant.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success ? 'Đã xóa' : 'Xóa thất bại')));
      await _refreshAll();
    }
  }

  // Utility helpers
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

  String _formatCurrency(double value) {
    final f = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    return f.format(value);
  }

  Future<void> _showAddTenantDialog(
      List<Building> buildings, List<Room> allRooms) async {
    if (buildings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng tạo toà nhà trước')),
      );
      return;
    }

    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final nationalIdController = TextEditingController();
    final occupationController = TextEditingController();
    final workplaceController = TextEditingController();
    final monthlyRentController = TextEditingController();

    String? selectedBuildingId = buildings.first.id;
    String? selectedRoomId;
    bool isMainTenant = true;
    DateTime moveInDate = DateTime.now();
    DateTime? contractEndDate;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Get rooms for selected building
          final availableRooms = allRooms
              .where((r) => r.buildingId == selectedBuildingId)
              .toList();

          return Dialog(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.9,
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: AlertDialog(
                title: const Text('Thêm Người Thuê'),
                contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                content: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Full Name
                        TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Họ và tên *',
                            hintText: 'Nguyễn Văn A',
                            hintStyle: TextStyle(
                              color: Color(0xFFBDBDBD),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Phone Number
                        TextField(
                          controller: phoneController,
                          decoration: const InputDecoration(
                            labelText: 'Số điện thoại *',
                            hintText: '0912345678',
                            hintStyle: TextStyle(
                              color: Color(0xFFBDBDBD),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 16),

                        // Email
                        TextField(
                          controller: emailController,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            hintText: 'email@example.com',
                            hintStyle: TextStyle(
                              color: Color(0xFFBDBDBD),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),

                        // National ID
                        TextField(
                          controller: nationalIdController,
                          decoration: const InputDecoration(
                            labelText: 'CMND/CCCD',
                            hintText: '001234567890',
                            hintStyle: TextStyle(
                              color: Color(0xFFBDBDBD),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Occupation
                        TextField(
                          controller: occupationController,
                          decoration: const InputDecoration(
                            labelText: 'Nghề nghiệp',
                            hintText: 'Ví dụ: Kỹ sư, Nhân viên văn phòng...',
                            hintStyle: TextStyle(
                              color: Color(0xFFBDBDBD),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Workplace
                        TextField(
                          controller: workplaceController,
                          decoration: const InputDecoration(
                            labelText: 'Nơi làm việc',
                            hintText: 'Công ty ABC, Trường XYZ...',
                            hintStyle: TextStyle(
                              color: Color(0xFFBDBDBD),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Building Selection
                        DropdownButtonFormField<String>(
                          value: selectedBuildingId,
                          decoration: const InputDecoration(
                            labelText: 'Toà nhà *',
                          ),
                          items: buildings.map((building) {
                            return DropdownMenuItem(
                              value: building.id,
                              child: Text(building.name),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedBuildingId = value;
                              selectedRoomId = null; // Reset room selection
                            });
                          },
                        ),
                        const SizedBox(height: 16),

                        // Room Selection
                        DropdownButtonFormField<String>(
                          value: selectedRoomId,
                          decoration: const InputDecoration(
                            labelText: 'Phòng *',
                          ),
                          items: availableRooms.isEmpty
                              ? [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text('Không có phòng'),
                                  )
                                ]
                              : availableRooms.map((room) {
                                  return DropdownMenuItem(
                                    value: room.id,
                                    child: Text('Phòng ${room.roomNumber}'),
                                  );
                                }).toList(),
                          onChanged: availableRooms.isEmpty
                              ? null
                              : (value) {
                                  setDialogState(() {
                                    selectedRoomId = value;
                                  });
                                },
                        ),
                        const SizedBox(height: 16),

                        // Monthly Rent
                        TextField(
                          controller: monthlyRentController,
                          decoration: const InputDecoration(
                            labelText: 'Tiền thuê hàng tháng *',
                            hintText: '5000000',
                            hintStyle: TextStyle(
                              color: Color(0xFFBDBDBD),
                              fontStyle: FontStyle.italic,
                            ),
                            suffixText: '₫',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 16),

                        // Is Main Tenant Checkbox
                        CheckboxListTile(
                          title: const Text('Chủ phòng'),
                          value: isMainTenant,
                          onChanged: (value) {
                            setDialogState(() {
                              isMainTenant = value ?? true;
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                        ),
                        const SizedBox(height: 8),

                        // Move In Date
                        ListTile(
                          title: const Text('Ngày chuyển vào *'),
                          subtitle:
                              Text(DateFormat('dd/MM/yyyy').format(moveInDate)),
                          trailing: const Icon(Icons.calendar_today),
                          contentPadding: EdgeInsets.zero,
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: moveInDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                moveInDate = picked;
                              });
                            }
                          },
                        ),

                        // Contract End Date
                        ListTile(
                          title: const Text('Ngày kết thúc hợp đồng'),
                          subtitle: Text(
                            contractEndDate != null
                                ? DateFormat('dd/MM/yyyy')
                                    .format(contractEndDate!)
                                : 'Chưa chọn',
                          ),
                          trailing: const Icon(Icons.calendar_today),
                          contentPadding: EdgeInsets.zero,
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: contractEndDate ??
                                  DateTime.now()
                                      .add(const Duration(days: 365)),
                              firstDate: moveInDate,
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                contractEndDate = picked;
                              });
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
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Hủy'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      // Validate required fields
                      if (nameController.text.trim().isEmpty ||
                          phoneController.text.trim().isEmpty ||
                          selectedRoomId == null ||
                          monthlyRentController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Vui lòng điền đầy đủ thông tin bắt buộc'),
                          ),
                        );
                        return;
                      }

                      // Parse monthly rent
                      final monthlyRent =
                          double.tryParse(monthlyRentController.text.trim());
                      if (monthlyRent == null || monthlyRent <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Tiền thuê không hợp lệ'),
                          ),
                        );
                        return;
                      }

                      Navigator.of(context).pop({
                        'fullName': nameController.text.trim(),
                        'phoneNumber': phoneController.text.trim(),
                        'email': emailController.text.trim().isEmpty
                            ? null
                            : emailController.text.trim(),
                        'nationalId': nationalIdController.text.trim().isEmpty
                            ? null
                            : nationalIdController.text.trim(),
                        'occupation': occupationController.text.trim().isEmpty
                            ? null
                            : occupationController.text.trim(),
                        'workplace': workplaceController.text.trim().isEmpty
                            ? null
                            : workplaceController.text.trim(),
                        'buildingId': selectedBuildingId,
                        'roomId': selectedRoomId,
                        'monthlyRent': monthlyRent,
                        'isMainTenant': isMainTenant,
                        'moveInDate': moveInDate,
                        'contractEndDate': contractEndDate,
                      });
                    },
                    child: const Text('Thêm'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (result != null && mounted) {
      // Create tenant object
      final tenant = Tenant(
        id: '', // Will be generated by Firestore
        organizationId: widget.organization.id,
        buildingId: result['buildingId']!,
        roomId: result['roomId']!,
        fullName: result['fullName']!,
        phoneNumber: result['phoneNumber']!,
        email: result['email'],
        nationalId: result['nationalId'],
        occupation: result['occupation'],
        workplace: result['workplace'],
        isMainTenant: result['isMainTenant']!,
        monthlyRent: result['monthlyRent']!,
        moveInDate: result['moveInDate']!,
        contractEndDate: result['contractEndDate'],
        status: TenantStatus.active,
        createdAt: DateTime.now(),
      );

      // Add tenant to database
      final tenantId = await widget.tenantService.addTenant(tenant);

      if (tenantId != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thêm người thuê thành công')),
        );
        setState(() {}); // Refresh the list
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể thêm người thuê')),
        );
      }
    }
  }
}