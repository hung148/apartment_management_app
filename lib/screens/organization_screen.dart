import 'dart:async';
import 'dart:io';

import 'package:apartment_management_project_2/main.dart';
import 'package:apartment_management_project_2/models/buildings_model.dart';
import 'package:apartment_management_project_2/models/membership_model.dart';
import 'package:apartment_management_project_2/models/organization_model.dart';
import 'package:apartment_management_project_2/models/tenants_model.dart';
import 'package:apartment_management_project_2/models/payment_model.dart';
import 'package:apartment_management_project_2/models/rooms_model.dart';
import 'package:apartment_management_project_2/screens/building/building_dialog.dart';
import 'package:apartment_management_project_2/screens/payment/delete_payment_dialog.dart';
import 'package:apartment_management_project_2/screens/payment/payment_dialog.dart';
import 'package:apartment_management_project_2/screens/payment/view_edit_dialogs.dart';
import 'package:apartment_management_project_2/screens/organizations/tenant_tab.dart';
import 'package:apartment_management_project_2/services/auth_service.dart';
import 'package:apartment_management_project_2/services/building_service.dart';
import 'package:apartment_management_project_2/services/organization_service.dart';
import 'package:apartment_management_project_2/services/tenants_service.dart';
import 'package:apartment_management_project_2/services/payments_service.dart';
import 'package:apartment_management_project_2/services/payments_notifier.dart';
import 'package:apartment_management_project_2/services/room_service.dart';
import 'package:apartment_management_project_2/widgets/shared.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

// Helper class for invoice line items
class InvoiceLineItem {
  String id;
  PaymentType type;
  double amount;
  String? description;

  InvoiceLineItem({
    required this.id,
    required this.type,
    required this.amount,
    this.description,
  });
}

class OrganizationScreen extends StatefulWidget {
  final Organization organization;
  const OrganizationScreen({
    required this.organization,
    super.key,
  });

  @override
  State<OrganizationScreen> createState() => _OrganizationScreenState();
}

class _OrganizationScreenState extends State<OrganizationScreen> with WidgetsBindingObserver {
  
  // Track how many overlays (dialogs/bottom sheets) are currently open
  int _overlayCount = 0;

  bool _isSmallScreen(BuildContext context) => MediaQuery.of(context).size.width < 600;
  bool _isMediumScreen(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 600 && width < 1200;
  }

  double _getDialogWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 600) return screenWidth * 0.95;
    if (screenWidth < 1200) return 600;
    return 800;
  }

  EdgeInsets _getResponsivePadding(BuildContext context) {
    return EdgeInsets.all(_isSmallScreen(context) ? 12.0 : 16.0);
  }

  Widget _buildMinimumSizeWarning(BuildContext context, BoxConstraints constraints) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange[700]),
            const SizedBox(height: 16),
            Text(
              'Kích thước cửa sổ quá nhỏ',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Kích thước tối thiểu: 360x600',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Hiện tại: ${constraints.maxWidth.toInt()}x${constraints.maxHeight.toInt()}',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  final OrganizationService _orgService = getIt<OrganizationService>();
  final AuthService _authService = getIt<AuthService>();
  final BuildingService _buildingService = getIt<BuildingService>();
  final TenantService _tenantService = getIt<TenantService>();
  final PaymentService _paymentService = getIt<PaymentService>();
  final PaymentsNotifier _paymentsNotifier = getIt<PaymentsNotifier>();
  final RoomService _roomService = getIt<RoomService>();
  
  String? _selectedBuildingId; // For occupancy trend chart
  String? _selectedOccupancyBuildingId;
  
  final TextEditingController _searchController = TextEditingController();
  
  Future<List<dynamic>>? _statsFuture;

  void _refreshStats() {
    if (!mounted) return;
    setState(() {
      _statsFuture = Future.wait([
        _getAllTenants(),
        _getAllPayments(),
        _getBuildings(),
        _getAllRooms(),
      ]);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Load payments when the screen initializes
    _paymentsNotifier.loadPayments(widget.organization.id);

    // Initial load
    _refreshStats();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  // Debounce timer for resize handling
  Timer? _resizeDebounceTimer;

  // Guard to prevent overlapping dismiss calls
  bool _isDismissing = false;

  // ─── Called whenever screen size / metrics change ───
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Cancel any pending debounce before setting a new one
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

  // Pops all open dialogs/bottom sheets by popping until only the base route remains.
  Future<void> _dismissAllOverlays() async {
    if (!mounted || _isDismissing) return;
    _isDismissing = true;

    try {
      final nav = Navigator.of(context);
      while (nav.canPop()) {
        nav.pop();
        // Yield to the framework between each pop so it can finish
        // destroying the previous overlay before we pop the next one.
        // This prevents back-to-back surface destruction that triggers EGL errors.
        await Future.delayed(const Duration(milliseconds: 50));
        if (!mounted) break;
      }
    } finally {
      _isDismissing = false;
    }
  }

  // ─── Overlay helpers ───

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

  String? inviteCode;
  bool loadingInvite = false;

  String? get _userId => _authService.currentUser?.uid;

  Future<Membership?> _getMyMembership() {
    if (_userId == null) return Future.value(null);

    return _orgService.getUserMembership(
      _userId!,
      widget.organization.id,
    );
  }

  Future<List<Membership>> _getMembers() {
    return _orgService.getOrganizationMembers(widget.organization.id);
  }

  Future<List<Building>> _getBuildings() {
    return _buildingService.getOrganizationBuildings(widget.organization.id);
  }

  Future<List<Tenant>> _getAllTenants() {
    return _tenantService.getOrganizationTenants(widget.organization.id);
  }

  Future<List<Payment>> _getAllPayments() {
    return _paymentService.getOrganizationPayments(widget.organization.id);
  }

  Future<List<Room>> _getAllRooms() {
    return _roomService.getOrganizationRooms(widget.organization.id);
  }

  Future<void> _loadInviteCode() async {
    if (_userId == null) return;

    setState(() => loadingInvite = true);

    final code = await _orgService.getInviteCode(
      _userId!,
      widget.organization.id,
    );

    setState(() {
      inviteCode = code;
      loadingInvite = false;
    });
  }

  // ========================================
  // BUILDING DIALOGS
  // ========================================
  Future<void> _showAddBuildingDialog() async {
    final result = await _showTrackedDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const BuildingDialog(
        isEditMode: false,
      ),
    );

    if (result != null && mounted) {
      // Show loading indicator
      _showTrackedDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      try {
        // ✅ CHANGED: Use addBuildingFromDialogResult instead of addBuilding
        // This saves the room configuration (floors, prefix, etc.) to Firestore
        final buildingId = await _buildingService.addBuildingFromDialogResult(
          organizationId: widget.organization.id,
          dialogResult: result,
        );

        if (buildingId == null) {
          throw Exception('Failed to create building');
        }

        // Generate and add rooms if enabled
        if (result['autoGenerateRooms'] == true) {
          final rooms = await _roomService.generateRoomsFromConfig(
            organizationId: widget.organization.id,
            buildingId: buildingId,
            config: result,
          );

          await _roomService.addMultipleRooms(rooms);

          final totalRooms = rooms.length;
          
          // Close loading dialog
          if (mounted) Navigator.of(context).pop();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Thêm toà nhà và $totalRooms phòng thành công'),
                backgroundColor: Colors.green,
              ),
            );
            setState(() {}); // Refresh the list
          }
        } else {
          // Close loading dialog
          if (mounted) Navigator.of(context).pop();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Thêm toà nhà thành công'),
                backgroundColor: Colors.green,
              ),
            );
            setState(() {}); // Refresh building list
            _refreshStats(); 
          }
        }
      } catch (e) {
        // Close loading dialog
        if (mounted) Navigator.of(context).pop();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _showEditBuildingDialog(Building building) async {

    final result = await _showTrackedDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => BuildingDialog(
        isEditMode: true,
        initialName: building.name,
        initialAddress: building.address,
        initialFloors: building.floors,
        initialRoomPrefix: building.roomPrefix, // Pass null if it doesn't exist
        initialUniformRooms: building.uniformRooms,
        // Đối với chế độ Đồng đều (Uniform)
        initialRoomsPerFloor: building.roomsPerFloor,
        initialRoomType: building.roomType, // Trường mới
        initialRoomArea: building.roomArea, // Trường mới
        
        // Đối với chế độ Tùy chỉnh (Custom) - Thay thế cho initialFloorRoomCounts
         initialFloorDetails: building.floorDetails,
        initialFloorRoomCounts: building.floorRoomCounts, 
      ),
    );

    if (result != null && mounted) {
      // Show loading indicator
      _showTrackedDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      try {
        // Use the new method that handles room configuration
        final success = await _buildingService.updateBuildingFromDialogResult(
          buildingId: building.id,
          dialogResult: result,
        );

        if (!success) {
          throw Exception('Failed to update building');
        }

        // Generate and add rooms if enabled
        if (result['autoGenerateRooms'] == true) {
          final rooms = await _roomService.generateRoomsFromConfig(
            organizationId: widget.organization.id,
            buildingId: building.id,
            config: result,
          );

          final addSuccess = await _roomService.addMultipleRooms(rooms);
          
          if (!addSuccess) {
            throw Exception('Failed to add rooms');
          }

          final totalRooms = rooms.length;
          
          // Close loading dialog
          if (mounted) Navigator.of(context).pop();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Cập nhật toà nhà và thêm $totalRooms phòng thành công'),
                backgroundColor: Colors.green,
              ),
            );
            setState(() {}); // Refresh the list
          }
        } else {
          // Close loading dialog
          if (mounted) Navigator.of(context).pop();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cập nhật toà nhà thành công'),
                backgroundColor: Colors.green,
              ),
            );
            setState(() {}); // Refresh the list
          }
        }
      } catch (e) {
        // Close loading dialog
        if (mounted) Navigator.of(context).pop();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteBuilding(Building building) async {
    final tenants = await _tenantService.getBuildingTenants(building.id);
    final activeTenants = tenants.where((t) =>
        t.status == TenantStatus.active ||
        t.status == TenantStatus.inactive ||
        t.status == TenantStatus.suspended).toList();

    final dialogWidth = _getDialogWidth(context); // assume this returns e.g. 500–560
    final contentPadding = _getResponsivePadding(context);

    final confirm = await _showTrackedDialog<bool>(
      context: context,
      builder: (context) {
        final dialogBg = Theme.of(context).dialogTheme.backgroundColor ??
            Theme.of(context).colorScheme.surface;

        return Dialog(
          backgroundColor: Colors.transparent,           // ← key fix: no extra wide surface
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          constraints: BoxConstraints(
            maxWidth: 400,                        // ← enforces your desired max
            minWidth: 320,                                // reasonable minimum
          ),
          child: Material(
            color: dialogBg,
            elevation: 24,                                // gives card-like shadow
            shadowColor: Colors.black.withValues(alpha: 0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,                 // clean rounded corners
            child: SingleChildScrollView(                 // safe for tall content
              child: Padding(
                padding: contentPadding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      'Xóa Toà Nhà',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    SizedBox(height: _isSmallScreen(context) ? 12 : 16),

                    // Question
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: Text(
                        'Bạn có chắc muốn xóa "${building.name}"?',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        softWrap: true,
                      ),
                    ),
                    SizedBox(height: _isSmallScreen(context) ? 12 : 16),

                    const Text(
                      'Thao tác này sẽ:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: _isSmallScreen(context) ? 8 : 12),

                    // Delete rooms row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.delete_outline,
                            size: 20, color: Colors.red),
                        const SizedBox(width: 8),
                        Flexible(
                          fit: FlexFit.loose,
                          child: Text(
                            'Xóa tất cả phòng trong toà nhà',
                            style: TextStyle(
                                fontSize: _isSmallScreen(context) ? 13 : 14),
                            softWrap: true,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: _isSmallScreen(context) ? 8 : 12),

                    if (activeTenants.isNotEmpty) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person_off_outlined,
                              size: 20, color: Colors.orange),
                          const SizedBox(width: 8),
                          Flexible(
                            fit: FlexFit.loose,
                            child: Text(
                              'Đánh dấu ${activeTenants.length} người thuê là "Đã chuyển đi"',
                              style: TextStyle(
                                  fontSize: _isSmallScreen(context) ? 13 : 14),
                              softWrap: true,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: _isSmallScreen(context) ? 10 : 12),
                      Container(
                        padding: EdgeInsets.all(_isSmallScreen(context) ? 10 : 12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.info_outline,
                                size: 20, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Flexible(
                              fit: FlexFit.loose,
                              child: Text(
                                'Thông tin người thuê sẽ được lưu giữ để tham khảo',
                                style: TextStyle(
                                    fontSize: _isSmallScreen(context) ? 12 : 13),
                                softWrap: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Buttons
                    SizedBox(height: _isSmallScreen(context) ? 12 : 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OverflowBar(
                        alignment: MainAxisAlignment.end,
                        spacing: 8,
                        overflowSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Hủy'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Xóa'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (confirm != true || !mounted) return;

    _showTrackedDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await _buildingService.deleteBuildingWithRoomsAndTenants(building.id);
      if (!mounted) return;
      Navigator.of(context).pop(); // close loading

      if (result['rooms']! > 0 || result['tenants']! > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Đã xóa toà nhà\n'
              '• ${result['rooms']} phòng đã bị xóa\n'
              '• ${result['tenants']} người thuê đã được đánh dấu "Đã chuyển đi"',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
        setState(() {});
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể xóa toà nhà')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    }
  }


  // ========================================
  // FORMAT HELPERS
  // ========================================
  String _formatCurrency(double amount) {
    final formatter = NumberFormat('#,###', 'vi_VN');
    return '${formatter.format(amount)} ₫';
  }

  Color _getPaymentStatusColor(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.pending:
        return Colors.orange;
      case PaymentStatus.paid:
        return Colors.green;
      case PaymentStatus.overdue:
        return Colors.red;
      case PaymentStatus.cancelled:
        return Colors.grey;
      case PaymentStatus.refunded:
        return Colors.purple;
      case PaymentStatus.partial:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Check minimum size
        if (constraints.maxWidth < minWidth || constraints.maxHeight < minHeight) {
          return Scaffold(
            body: _buildMinimumSizeWarning(context, constraints),
          );
        }
        
        // Normal content
        return DefaultTabController(
          length: 5,
          child: Scaffold(
            appBar: AppBar(
              title: Text(widget.organization.name),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(kToolbarHeight),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Calculate if tabs will fit
                    // Rough estimate: each tab needs about 120 pixels
                    const estimatedTabWidth = 120.0;
                    const numberOfTabs = 5;
                    final totalEstimatedWidth = estimatedTabWidth * numberOfTabs;
                    final shouldScroll = constraints.maxWidth < totalEstimatedWidth;

                    return TabBar(
                      isScrollable: shouldScroll,
                      labelStyle: const TextStyle(fontSize: 12),
                      tabs: const [
                        Tab(icon: Icon(Icons.apartment), text: 'Toà nhà'),
                        Tab(icon: Icon(Icons.people), text: 'Người thuê'),
                        Tab(icon: Icon(Icons.receipt_long), text: 'Hóa đơn'),
                        Tab(icon: Icon(Icons.bar_chart), text: 'Thống kê'),
                        Tab(icon: Icon(Icons.group), text: 'Thành viên'),
                      ],
                    );
                  },
                ),
              ),
            ),
            body: TabBarView(
              children: [
                _buildBuildingsTab(),
                  TenantsTab(
                  organization: widget.organization,
                  tenantService: _tenantService,
                  buildingService: _buildingService,
                  roomService: _roomService,
                  organizationService: _orgService,
                  authService: _authService, // use your field name
                  onChanged: () => _refreshStats(),
                ),
                _buildPaymentsTab(),
                _buildStatisticsTab(),
                _buildMembersTab(),
              ],
            ),
          ),
        );
      },
    );
  }

  // ========================================
  // BUILDINGS TAB
  // ========================================
  Widget _buildBuildingsTab() {
    return FutureBuilder<Membership?>(
      future: _getMyMembership(),
      builder: (context, membershipSnapshot) {
        final isAdmin = membershipSnapshot.hasData &&
            membershipSnapshot.data!.role == 'admin';

        return Column(
          children: [
            // Add Building Button (Admin Only)
            if (isAdmin)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _showAddBuildingDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm toà nhà'),
                  ),
                ),
              ),

            // Buildings List
            Expanded(
              child: FutureBuilder<List<Building>>(
                future: _getBuildings(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.apartment, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'Không tìm thấy toà nhà nào',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  }

                  final buildings = snapshot.data!;

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: buildings.length,
                    itemBuilder: (context, index) {
                      final building = buildings[index];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.blue,
                            child: Icon(Icons.apartment, color: Colors.white),
                          ),
                          title: Text(
                            building.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(building.address),
                              const SizedBox(height: 4),
                              Text(
                                'Tạo lúc ${_formatDate(building.createdAt)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          trailing: isAdmin
                              ? Builder(
                                  builder: (BuildContext context) {
                                    return IconButton(
                                      icon: const Icon(Icons.more_vert),
                                      onPressed: () {
                                        final RenderBox button = context.findRenderObject() as RenderBox;
                                        final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
                                        final RelativeRect position = RelativeRect.fromRect(
                                          Rect.fromPoints(
                                            button.localToGlobal(Offset.zero, ancestor: overlay) + const Offset(0, 48),
                                            button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
                                          ),
                                          Offset.zero & overlay.size,
                                        );

                                        showMenu<String>(
                                          context: context,
                                          position: position,
                                          items: [
                                            const PopupMenuItem(
                                              value: 'rooms',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.meeting_room, size: 20),
                                                  SizedBox(width: 8),
                                                  Text('Quản lý phòng'),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'edit',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.edit, size: 20),
                                                  SizedBox(width: 8),
                                                  Text('Chỉnh sửa'),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.delete, size: 20, color: Colors.red),
                                                  SizedBox(width: 8),
                                                  Text('Xoá', style: TextStyle(color: Colors.red)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ).then((value) {
                                          if (value == 'edit') {
                                            _showEditBuildingDialog(building);
                                          } else if (value == 'delete') {
                                            _deleteBuilding(building);
                                          } else if (value == 'rooms') {
                                            Navigator.pushNamed(
                                              context,
                                              '/building-rooms',
                                              arguments: {
                                                'building': building,
                                                'organization': widget.organization,
                                              },
                                            );
                                          }
                                        });
                                      },
                                    );
                                  },
                                )
                              : IconButton(
                                  icon: const Icon(Icons.arrow_forward_ios, size: 16),
                                  onPressed: () {
                                    Navigator.pushNamed(
                                      context,
                                      '/building-rooms',
                                      arguments: {
                                        'building': building,
                                        'organization': widget.organization,
                                      },
                                    );
                                  },
                                ),
                          onTap: () {
                            Navigator.pushNamed(
                              context,
                              '/building-rooms',
                              arguments: {
                                'building': building,
                                'organization': widget.organization,
                              },
                            );
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
    );
  }

  // ========================================
  // PAYMENTS TAB
  // ========================================
  Widget _buildPaymentsTab() {
    return ListenableBuilder(
      listenable: _paymentsNotifier,
      builder: (context, _) {
        final allPayments = _paymentsNotifier.payments;
        
        if (allPayments.isEmpty) {
          return FutureBuilder<Membership?>(
            future: _getMyMembership(),
            builder: (context, membershipSnapshot) {
              final isAdmin = membershipSnapshot.hasData &&
                  membershipSnapshot.data!.role == 'admin';

              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'Chưa có hóa đơn nào',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    if (isAdmin)
                      ElevatedButton.icon(
                        onPressed: _showAddPaymentDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Thêm Hóa Đơn'),
                      ),
                  ],
                ),
              );
            },
          );
        }

        final sortedPayments = List<Payment>.from(allPayments);
        sortedPayments.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        return FutureBuilder<Membership?>(
          future: _getMyMembership(),
          builder: (context, membershipSnapshot) {
            final isAdmin = membershipSnapshot.hasData &&
                membershipSnapshot.data!.role == 'admin';

            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Search with ValueListenableBuilder (no reload on type)
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _searchController,
                    builder: (context, value, child) {
                      return Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'Tìm kiếm hóa đơn...',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: value.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear),
                                        onPressed: () => _searchController.clear(),
                                      )
                                    : null,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Only show add button for admins
                          if (isAdmin)
                            ElevatedButton.icon(
                              onPressed: _showAddPaymentDialog,
                              icon: const Icon(Icons.add),
                              label: const Text('Thêm'),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  // Payments List
                  Expanded(
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _searchController,
                      builder: (context, value, child) {
                        return _buildPaymentsList(sortedPayments, value.text, isAdmin);
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

Widget _buildPaymentsList(List<Payment> allPayments, String searchText, bool isAdmin) {
  final searchTerm = searchText.toLowerCase();
  
  // Filter payments based on search term
  final filteredPayments = allPayments.where((payment) {
    if (searchTerm.isEmpty) return true;
    
    return (payment.tenantName?.toLowerCase() ?? '').contains(searchTerm) ||
           payment.totalAmount.toString().contains(searchTerm) ||
           payment.getTypeDisplayName().toLowerCase().contains(searchTerm);
  }).toList();

  if (filteredPayments.isEmpty) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            searchTerm.isEmpty ? Icons.receipt_long_outlined : Icons.search_off,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            searchTerm.isEmpty ? 'Chưa có hóa đơn nào' : 'Không tìm thấy hóa đơn',
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
        ],
      ),
    );
  }

  if (searchTerm.isNotEmpty) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Text(
                'Tìm thấy ${filteredPayments.length} hóa đơn',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildPaymentsListView(filteredPayments, isAdmin),
        ),
      ],
    );
  }

  return _buildPaymentsListView(filteredPayments, isAdmin);
}

  Widget _buildPaymentsListView(List<Payment> payments, bool isAdmin) {
    return ListView.builder(
      itemCount: payments.length,
      itemBuilder: (context, index) {
        final payment = payments[index];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getPaymentStatusColor(payment.status).withOpacity(0.2),
              child: Icon(
                payment.status == PaymentStatus.paid 
                    ? Icons.check_circle
                    : payment.isOverdue
                        ? Icons.warning
                        : Icons.pending,
                color: _getPaymentStatusColor(payment.status),
              ),
            ),
            title: Text(
              payment.getTypeDisplayName(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('Người thuê: ${payment.tenantName}'),
                const SizedBox(height: 2),
                Text('Số tiền: ${_formatCurrency(payment.totalAmount)}'),
                const SizedBox(height: 2),
                Text('Hạn: ${DateFormat('dd/MM/yyyy').format(payment.dueDate)}'),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getPaymentStatusColor(payment.status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    payment.getStatusDisplayName(),
                    style: TextStyle(
                      fontSize: 11,
                      color: _getPaymentStatusColor(payment.status),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            trailing: isAdmin
                ? Builder(
                    builder: (BuildContext context) {
                      return IconButton(
                        icon: const Icon(Icons.more_vert),
                        onPressed: () {
                          final RenderBox button = context.findRenderObject() as RenderBox;
                          final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
                          final RelativeRect position = RelativeRect.fromRect(
                            Rect.fromPoints(
                              button.localToGlobal(Offset.zero, ancestor: overlay) + const Offset(0, 48),
                              button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
                            ),
                            Offset.zero & overlay.size,
                          );

                          showMenu<String>(
                            context: context,
                            position: position,
                            items: [
                              const PopupMenuItem(
                                value: 'view',
                                child: Row(
                                  children: [
                                    Icon(Icons.visibility, size: 20),
                                    SizedBox(width: 8),
                                    Text('Xem Chi Tiết'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit, size: 20),
                                    SizedBox(width: 8),
                                    Text('Chỉnh Sửa'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, size: 20, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('Xóa', style: TextStyle(color: Colors.red)),
                                  ],
                                ),
                              ),
                            ],
                          ).then((value) {
                            if (value == 'view') {
                              _showPaymentDetailsDialog(payment, isAdmin);
                            } else if (value == 'edit') {
                              _showEditPaymentDialog(payment);
                            } else if (value == 'delete') {
                              _confirmDeletePayment(payment);
                            }
                          });
                        },
                      );
                    },
                  )
                : IconButton(
                    icon: const Icon(Icons.info_outline),
                    onPressed: () {
                      _showPaymentDetailsDialog(payment, isAdmin);
                    },
                  ),
          ),
        );
      },
    );
  }

  void _showPaymentDetailsDialog(Payment payment, bool isAdmin) {
  _showTrackedDialog(
    context: context,
    builder: (context) => ViewPaymentDetailsDialog(
      payment: payment,
      isAdmin: isAdmin,
      roomService: _roomService,
      buildingService: _buildingService,
      organization: widget.organization,
      paymentService: _paymentService,
      onEdit: () => _showEditPaymentDialog(payment),
    ),
  );
}

  void _showAddPaymentDialog() {
    _showTrackedDialog(
      context: context,
      builder: (context) => ImprovedPaymentFormDialog(
        organization: widget.organization,
        buildingService: _buildingService,
        roomService: _roomService,
        tenantService: _tenantService,
        paymentService: _paymentService,
      ),
    ).then((result) {
      print('Dialog closed with result: $result');
      if (result == true) {
        // Refresh the payment list from database
        print('Add payment dialog returned true, refreshing payments');
        _paymentsNotifier.refreshPayments(widget.organization.id);
      }
    });
  }

  void _showEditPaymentDialog(Payment payment) {
    _showTrackedDialog(
      context: context,
      builder: (context) => EditPaymentDialog(
        payment: payment,
        organization: widget.organization,
        buildingService: _buildingService,
        roomService: _roomService,
        tenantService: _tenantService,
        paymentService: _paymentService,
      ),
    ).then((result) {
      if (result == true) {
        // Refresh the payment list from database
        _paymentsNotifier.refreshPayments(widget.organization.id);
      }
    });
  }

  void _confirmDeletePayment(Payment payment) {
    _showTrackedDialog(
      context: context,
      builder: (context) => DeletePaymentDialog(
        payment: payment,
        paymentService: _paymentService,
        onDeleted: () {
          // Refresh the payment list from database
          _paymentsNotifier.refreshPayments(widget.organization.id);
        },
      ),
    );
  }

  // ========================================
  // STATISTICS TAB
  // ========================================
  Widget _buildStatisticsTab() {
    return ListenableBuilder(
      listenable: _paymentsNotifier,
      builder: (context, _) {
        return FutureBuilder<List<dynamic>>(
          future: _statsFuture,
          builder: (context, snapshot) {
          // ONLY show the loading spinner on the VERY FIRST load
          if (snapshot.connectionState == ConnectionState.waiting && snapshot.data == null) {
            return const Center(child: CircularProgressIndicator());
          }

            if (!snapshot.hasData) {
              return const Center(child: Text('Không có dữ liệu'));
            }

            final tenants = snapshot.data![0] as List<Tenant>;
            final payments = _paymentsNotifier.payments;
            final buildings = snapshot.data![2] as List<Building>;
            final rooms = snapshot.data![3] as List<Room>;

            // Calculate statistics
            final activeTenants = tenants.where((t) => t.status == TenantStatus.active).length;
            
            final totalPayments = payments.length;
            final paidPayments = payments.where((p) => p.status == PaymentStatus.paid).length;
            final pendingPayments = payments.where((p) => p.status == PaymentStatus.pending).length;
            final overduePayments = payments.where((p) => p.isOverdue).length;
            
            final totalRevenue = payments.fold<double>(0, (sum, p) {
              // If status is 'paid' but paidAmount is accidentally 0, fallback to totalWithAllFees
              if (p.status == PaymentStatus.paid && p.paidAmount == 0) {
                return sum + p.totalWithAllFees;
              }
              return sum + p.paidAmount;
            });
            
            final pendingRevenue = payments.fold<double>(0, (sum, p) {
              // We ignore Paid (remaining is 0) and Cancelled (we don't expect to collect it)
              if (p.status == PaymentStatus.paid || p.status == PaymentStatus.cancelled) {
                return sum;
              }
              
              // For Pending, Overdue, and Partial, use the model property
              return sum + p.remainingAmount;
            });

            // Calculate monthly revenue for chart
            final monthlyRevenue = _calculateMonthlyRevenue(payments);
            
            // Calculate building occupancy with real room data
            final buildingOccupancy = _calculateBuildingOccupancy(buildings, rooms, tenants);

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tổng quan',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Buildings & Tenants
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'Toà nhà',
                          buildings.length.toString(),
                          Icons.apartment,
                          Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          'Người thuê',
                          '$activeTenants',
                          Icons.people,
                          Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // Payments Overview
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'Đã thanh toán',
                          paidPayments.toString(),
                          Icons.check_circle,
                          Colors.green,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          'Chưa thanh toán',
                          pendingPayments.toString(),
                          Icons.pending,
                          Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'Quá hạn',
                          overduePayments.toString(),
                          Icons.warning,
                          Colors.red,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          'Tổng hóa đơn',
                          totalPayments.toString(),
                          Icons.receipt_long,
                          Colors.purple,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  const Text(
                    'Doanh thu',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Revenue Cards
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.attach_money, color: Colors.green.shade700),
                              const SizedBox(width: 8),
                              const Text(
                                'Đã thu',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatCurrency(totalRevenue),
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.schedule, color: Colors.orange.shade700),
                              const SizedBox(width: 8),
                              const Text(
                                'Chưa thu',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatCurrency(pendingRevenue),
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Monthly Revenue Chart
                  const SizedBox(height: 24),
                  const Text(
                    'Doanh thu theo tháng',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildMonthlyRevenueChart(monthlyRevenue),
                  
                  // Building Occupancy Chart
                  const SizedBox(height: 24),
                  const Text(
                    'Tỷ lệ lấp đầy theo toà nhà hiện tại',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildBuildingOccupancyChart(buildingOccupancy, buildings),
                  
                  // Monthly Occupancy Trend Chart
                  const SizedBox(height: 24),
                  const Text(
                    'Xu hướng lấp đầy theo tháng',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildMonthlyOccupancyTrendChart(buildings, rooms, tenants),
                  const SizedBox(height: 32),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.table_chart_outlined, size: 20),
                          label: const Text('Xuất Excel'),
                          onPressed: () => _exportStatisticsToExcel(
                            buildings: buildings, 
                            tenants: tenants, 
                            rooms: rooms, 
                            payments: payments,
                            organizationName: widget.organization.name,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                          label: const Text('Xuất PDF'),
                          onPressed: () => _exportStatisticsToPdf(
                            buildings: buildings, 
                            tenants: tenants, 
                            rooms: rooms, 
                            payments: payments,
                            organizationName: widget.organization.name,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      }
    );
  }

  // ===========================================================================
// COMPLETE ENHANCED PDF EXPORT FUNCTION
// ===========================================================================
// Replace your existing _exportStatisticsToPdf function with this one
// (Should be around line 1126 in your organization_screen.dart)
// ===========================================================================

Future<void> _exportStatisticsToPdf({
  required List<Building> buildings,
  required List<Tenant> tenants,
  required List<Room> rooms,
  required List<Payment> payments,
  String? organizationName,
}) async {
  final ttf = await PdfFontService.getFont();
  
  // Show progress indicator
  if (mounted) {
    _showTrackedDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }

  try {
    // ============================================
    // FORMATTERS
    // ============================================
    final currencyFormatter = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    final dateFormatter = DateFormat('dd/MM/yyyy – HH:mm');

    // ============================================
    // CALCULATE COMPREHENSIVE STATISTICS
    // ============================================
    
    // Overall stats
    final totalBuildings = buildings.length;
    final totalRooms = rooms.length;
    final activeTenants = tenants.where((t) => t.status == TenantStatus.active).length;
    final inactiveTenants = tenants.where((t) => t.status == TenantStatus.inactive).length;
    final movedOutTenants = tenants.where((t) => t.status == TenantStatus.moveOut).length;
    final suspendedTenants = tenants.where((t) => t.status == TenantStatus.suspended).length;
    
    // Payment stats
    final paidPayments = payments.where((p) => p.status == PaymentStatus.paid).toList();
    final pendingPayments = payments.where((p) => p.status == PaymentStatus.pending).toList();
    final overduePayments = payments.where((p) => p.isOverdue).toList();
    final cancelledPayments = payments.where((p) => p.status == PaymentStatus.cancelled).toList();
    
    final totalRevenue = paidPayments.fold<double>(0, (sum, p) {
      if (p.status == PaymentStatus.paid) {
        // If it's fully paid, take the totalAmount (or paidAmount if it's set)
        return sum + (p.paidAmount > 0 ? p.paidAmount : p.totalAmount);
      }
      return sum + p.paidAmount;
    });
    final pendingRevenue = payments.fold<double>(0, (sum, p) {
      // We ignore Paid (remaining is 0) and Cancelled (we don't expect to collect it)
      if (p.status == PaymentStatus.paid || p.status == PaymentStatus.cancelled) {
        return sum;
      }
      
      // For Pending, Overdue, and Partial, use the model property
      return sum + p.remainingAmount;
    });
    final overdueRevenue = payments.fold<double>(0, (sum, p) {
      // We ignore Paid (remaining is 0) and Cancelled (we don't expect to collect it)
      if (p.status == PaymentStatus.paid || p.status == PaymentStatus.cancelled) {
        return sum;
      }
      
      // For Pending, Overdue, and Partial, use the model property
      return sum + p.remainingAmount;
    });
    
    // Monthly revenue calculation
    final monthlyRevenue = _calculateMonthlyRevenue(payments);
    
    // Building-specific stats
    final Map<String, _BuildingStats> statsByBuilding = {};
    for (final b in buildings) {
      statsByBuilding[b.id] = _BuildingStats(
        buildingId: b.id,
        buildingName: b.name,
        totalRooms: 0,
        occupiedRooms: 0,
        revenue: 0.0,
      );
    }

    for (final r in rooms) {
      final s = statsByBuilding[r.buildingId];
      if (s != null) s.totalRooms += 1;
    }

    for (final t in tenants) {
      if (t.buildingId.isEmpty) continue;
      if (t.status == TenantStatus.active) {
        final s = statsByBuilding[t.buildingId];
        if (s != null) s.occupiedRooms += 1;
      }
    }

    for (final pmt in paidPayments) {
      if (pmt.buildingId.isNotEmpty) {
        final s = statsByBuilding[pmt.buildingId];
        if (s != null) s.revenue += pmt.paidAmount;
      } else if (pmt.roomId.isNotEmpty) {
        final room = rooms.firstWhere(
          (r) => r.id == pmt.roomId, 
          orElse: () => Room(id: '', area: 0.0, roomType: '', organizationId: '', buildingId: '', roomNumber: '', createdAt: DateTime.now())
        );
        if (room.id.isNotEmpty) {
          final s = statsByBuilding[room.buildingId];
          if (s != null) s.revenue += pmt.paidAmount;
        }
      }
    }

    // Build building table rows
    final List<List<String>> buildingTableRows = [];
    int grandTotalRooms = 0;
    int grandOccupied = 0;
    double grandRevenue = 0.0;

    for (final s in statsByBuilding.values) {
      final emptyRooms = (s.totalRooms - s.occupiedRooms).clamp(0, s.totalRooms);
      final occupancyRate = s.totalRooms > 0 
          ? ((s.occupiedRooms / s.totalRooms) * 100).toStringAsFixed(1) 
          : '0.0';
      
      buildingTableRows.add([
        s.buildingName,
        s.totalRooms.toString(),
        s.occupiedRooms.toString(),
        emptyRooms.toString(),
        '$occupancyRate%',
        currencyFormatter.format(s.revenue),
      ]);

      grandTotalRooms += s.totalRooms;
      grandOccupied += s.occupiedRooms;
      grandRevenue += s.revenue;
    }

    buildingTableRows.sort((a, b) => a[0].compareTo(b[0]));

    // ============================================
    // PDF SETUP
    // ============================================
    final pdf = pw.Document();
    
    // Text styles
    final titleStyle = pw.TextStyle(font: ttf, fontSize: 18, fontWeight: pw.FontWeight.bold);
    final heading1Style = pw.TextStyle(font: ttf, fontSize: 14, fontWeight: pw.FontWeight.bold);
    final heading2Style = pw.TextStyle(font: ttf, fontSize: 12, fontWeight: pw.FontWeight.bold);
    final baseTextStyle = pw.TextStyle(font: ttf, fontSize: 10);
    final smallTextStyle = pw.TextStyle(font: ttf, fontSize: 9);
    final smallGrey = pw.TextStyle(font: ttf, fontSize: 9, color: PdfColors.grey600);
    final boldTextStyle = pw.TextStyle(font: ttf, fontSize: 10, fontWeight: pw.FontWeight.bold);

    // Helper function to create stat boxes
    pw.Widget buildStatBox(String label, String value, {PdfColor color = PdfColors.blue}) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: color.shade(0.1),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          border: pw.Border.all(color: color, width: 1),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: pw.TextStyle(font: ttf, fontSize: 9, color: PdfColors.grey700)),
            pw.SizedBox(height: 4),
            pw.Text(value, style: pw.TextStyle(font: ttf, fontSize: 14, fontWeight: pw.FontWeight.bold, color: color)),
          ],
        ),
      );
    }

    // ============================================
    // PAGE 1: EXECUTIVE SUMMARY
    // ============================================
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(organizationName ?? 'Tổ chức', style: titleStyle),
                      pw.SizedBox(height: 4),
                      pw.Text('BÁO CÁO THỐNG KÊ TỔNG QUAN', style: heading1Style),
                      pw.SizedBox(height: 4),
                      pw.Text('Ngày tạo: ${dateFormatter.format(DateTime.now())}', style: smallGrey),
                    ],
                  ),
                ],
              ),
              
              pw.SizedBox(height: 24),
              pw.Divider(thickness: 2),
              pw.SizedBox(height: 24),

              // Overview Section
              pw.Text('1. TỔNG QUAN', style: heading1Style),
              pw.SizedBox(height: 16),
              
              // Stats Grid Row 1
              pw.Row(
                children: [
                  pw.Expanded(child: buildStatBox('Toà nhà', totalBuildings.toString(), color: PdfColors.blue)),
                  pw.SizedBox(width: 12),
                  pw.Expanded(child: buildStatBox('Tổng phòng', totalRooms.toString(), color: PdfColors.teal)),
                  pw.SizedBox(width: 12),
                  pw.Expanded(child: buildStatBox('Đang thuê', activeTenants.toString(), color: PdfColors.green)),
                ],
              ),
              
              pw.SizedBox(height: 12),
              
              // Stats Grid Row 2
              pw.Row(
                children: [
                  pw.Expanded(child: buildStatBox('Tỷ lệ lấp đầy', totalRooms > 0 ? '${((activeTenants / totalRooms) * 100).toStringAsFixed(1)}%' : '0%', color: PdfColors.purple)),
                  pw.SizedBox(width: 12),
                  pw.Expanded(child: buildStatBox('Phòng trống', '${totalRooms - activeTenants}', color: PdfColors.orange)),
                  pw.SizedBox(width: 12),
                  pw.Expanded(child: buildStatBox('Đã chuyển đi', movedOutTenants.toString(), color: PdfColors.grey)),
                ],
              ),

              pw.SizedBox(height: 24),

              // Tenant Status Breakdown
              pw.Text('2. TÌNH TRẠNG NGƯỜI THUÊ', style: heading1Style),
              pw.SizedBox(height: 12),
              
              pw.TableHelper.fromTextArray(
                headers: ['Trạng thái', 'Số lượng', 'Tỷ lệ'],
                data: [
                  ['Đang hoạt động', activeTenants.toString(), tenants.isNotEmpty ? '${((activeTenants / tenants.length) * 100).toStringAsFixed(1)}%' : '0%'],
                  ['Không hoạt động', inactiveTenants.toString(), tenants.isNotEmpty ? '${((inactiveTenants / tenants.length) * 100).toStringAsFixed(1)}%' : '0%'],
                  ['Đã chuyển đi', movedOutTenants.toString(), tenants.isNotEmpty ? '${((movedOutTenants / tenants.length) * 100).toStringAsFixed(1)}%' : '0%'],
                  ['Bị đình chỉ', suspendedTenants.toString(), tenants.isNotEmpty ? '${((suspendedTenants / tenants.length) * 100).toStringAsFixed(1)}%' : '0%'],
                  ['TỔNG', tenants.length.toString(), '100%'],
                ],
                headerStyle: pw.TextStyle(font: ttf, fontWeight: pw.FontWeight.bold, fontSize: 10),
                headerDecoration: pw.BoxDecoration(color: PdfColors.blue50),
                cellStyle: baseTextStyle,
                cellAlignment: pw.Alignment.centerLeft,
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(2),
                },
                border: pw.TableBorder.all(color: PdfColors.grey300),
              ),

              pw.SizedBox(height: 24),

              // Payment Summary
              pw.Text('3. TỔNG KẾT THANH TOÁN', style: heading1Style),
              pw.SizedBox(height: 12),
              
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(16),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.green50,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                        border: pw.Border.all(color: PdfColors.green, width: 2),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Row(
                            children: [
                              pw.Text('Đã thu', style: heading2Style.copyWith(color: PdfColors.green)),
                            ],
                          ),
                          pw.SizedBox(height: 8),
                          pw.Text(currencyFormatter.format(totalRevenue), 
                            style: pw.TextStyle(font: ttf, fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.green)),
                          pw.SizedBox(height: 4),
                          pw.Text('${paidPayments.length} hóa đơn', style: smallTextStyle.copyWith(color: PdfColors.grey700)),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(16),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.orange50,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                        border: pw.Border.all(color: PdfColors.orange, width: 2),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Row(
                            children: [
                              pw.Text('Chưa thu', style: heading2Style.copyWith(color: PdfColors.orange)),
                            ],
                          ),
                          pw.SizedBox(height: 8),
                          pw.Text(currencyFormatter.format(pendingRevenue), 
                            style: pw.TextStyle(font: ttf, fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.orange)),
                          pw.SizedBox(height: 4),
                          pw.Text('${pendingPayments.length} hóa đơn', style: smallTextStyle.copyWith(color: PdfColors.grey700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              
              pw.SizedBox(height: 12),
              
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(16),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.red50,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                        border: pw.Border.all(color: PdfColors.red, width: 2),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Row(
                            children: [
                              pw.Text('Quá hạn', style: heading2Style.copyWith(color: PdfColors.red)),
                            ],
                          ),
                          pw.SizedBox(height: 8),
                          pw.Text(currencyFormatter.format(overdueRevenue), 
                            style: pw.TextStyle(font: ttf, fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.red)),
                          pw.SizedBox(height: 4),
                          pw.Text('${overduePayments.length} hóa đơn', style: smallTextStyle.copyWith(color: PdfColors.grey700)),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(16),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey100,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                        border: pw.Border.all(color: PdfColors.grey, width: 1),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Row(
                            children: [
                              pw.Text('Đã hủy', style: heading2Style.copyWith(color: PdfColors.grey)),
                            ],
                          ),
                          pw.SizedBox(height: 8),
                          pw.Text('${cancelledPayments.length}', 
                            style: pw.TextStyle(font: ttf, fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.grey)),
                          pw.SizedBox(height: 4),
                          pw.Text('hóa đơn', style: smallTextStyle.copyWith(color: PdfColors.grey700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              pw.Spacer(),

              // Footer
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Báo cáo được tạo tự động', style: smallGrey),
                  pw.Text('Trang 1', style: smallGrey),
                ],
              ),
            ],
          );
        },
      ),
    );

    // ============================================
    // PAGE 2: BUILDING DETAILS
    // ============================================
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('CHI TIẾT THEO TÒA NHÀ', style: heading1Style),
                  pw.Text('Trang 2', style: smallGrey),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Divider(thickness: 2),
              pw.SizedBox(height: 20),

              // Building Table
              if (buildingTableRows.isEmpty)
                pw.Center(
                  child: pw.Text('Không có dữ liệu toà nhà', 
                    style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600)),
                )
              else ...[
                pw.Table.fromTextArray(
                  headers: ['Toà nhà', 'Tổng phòng', 'Đang thuê', 'Trống', 'Tỷ lệ', 'Doanh thu'],
                  data: buildingTableRows,
                  headerStyle: pw.TextStyle(font: ttf, fontWeight: pw.FontWeight.bold, fontSize: 10),
                  headerDecoration: pw.BoxDecoration(color: PdfColors.blue50),
                  cellStyle: baseTextStyle,
                  cellAlignment: pw.Alignment.centerLeft,
                  columnWidths: {
                    0: const pw.FlexColumnWidth(3),
                    1: const pw.FlexColumnWidth(1.5),
                    2: const pw.FlexColumnWidth(1.5),
                    3: const pw.FlexColumnWidth(1.5),
                    4: const pw.FlexColumnWidth(1.5),
                    5: const pw.FlexColumnWidth(2.5),
                  },
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  cellPadding: const pw.EdgeInsets.all(8),
                ),
                
                pw.SizedBox(height: 16),
                
                // Totals
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue50,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('Tổng số toà nhà: ${statsByBuilding.length}', style: boldTextStyle),
                          pw.Text('Tổng phòng: $grandTotalRooms', style: boldTextStyle),
                          pw.Text('Tổng đang thuê: $grandOccupied', style: boldTextStyle),
                          pw.Text('Tổng doanh thu: ${currencyFormatter.format(grandRevenue)}', 
                            style: pw.TextStyle(font: ttf, fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              pw.Spacer(),

              // Footer
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Báo cáo được tạo tự động', style: smallGrey),
                  pw.Text('Trang 2', style: smallGrey),
                ],
              ),
            ],
          );
        },
      ),
    );

    // ============================================
    // PAGE 3: REVENUE ANALYSIS
    // ============================================
    if (monthlyRevenue.isNotEmpty) {
      // Validate that we have valid revenue data
      final validRevenues = monthlyRevenue.values.where((v) => v.isFinite && !v.isNaN).toList();
      
      if (validRevenues.isNotEmpty) {
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(40),
            build: (context) {
              final maxRevenue = validRevenues.reduce((a, b) => a > b ? a : b);
              final safeMaxRevenue = maxRevenue > 0 ? maxRevenue : 1.0; // Ensure non-zero
              
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Header
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('PHÂN TÍCH DOANH THU', style: heading1Style),
                      pw.Text('Trang 3', style: smallGrey),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Divider(thickness: 2),
                  pw.SizedBox(height: 20),

                  // Monthly Revenue Chart
                  pw.Text('Doanh thu 6 tháng gần nhất', style: heading2Style),
                  pw.SizedBox(height: 16),
                  
                  pw.Container(
                    height: 250,
                    padding: const pw.EdgeInsets.all(16),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                    ),
                    child: pw.Chart(
                      grid: pw.CartesianGrid(
                        xAxis: pw.FixedAxis.fromStrings(
                          monthlyRevenue.keys.toList(),
                          marginStart: 30,
                          marginEnd: 30,
                          ticks: true,
                          textStyle: smallTextStyle,
                        ),
                        yAxis: pw.FixedAxis(
                          [0, safeMaxRevenue / 2, safeMaxRevenue],
                          format: (v) {
                            final doubleValue = v.toDouble();
                            return doubleValue.isFinite && !doubleValue.isNaN 
                                ? _formatCurrencyShort(doubleValue) 
                                : '0';
                          },
                          divisions: true,
                          textStyle: smallTextStyle,
                        ),
                      ),
                      datasets: [
                        pw.BarDataSet(
                          color: PdfColors.green,
                          legend: 'Doanh thu',
                          width: 20,
                          data: monthlyRevenue.entries.map((e) {
                            final value = e.value.isFinite && !e.value.isNaN ? e.value : 0.0;
                            return pw.PointChartValue(0, value);
                          }).toList(),
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 24),

                  // Revenue Table
                  pw.Text('Chi tiết doanh thu theo tháng', style: heading2Style),
                  pw.SizedBox(height: 12),
                  
                  pw.TableHelper.fromTextArray(
                    headers: ['Tháng', 'Doanh thu', 'Tỷ lệ'],
                    data: monthlyRevenue.entries.map((e) {
                      final revenueValue = e.value.isFinite && !e.value.isNaN ? e.value : 0.0;
                      final percentage = totalRevenue > 0 
                          ? ((revenueValue / totalRevenue) * 100).toStringAsFixed(1) 
                          : '0.0';
                      return [
                        e.key,
                        currencyFormatter.format(revenueValue),
                        '$percentage%',
                      ];
                    }).toList(),
                    headerStyle: pw.TextStyle(font: ttf, fontWeight: pw.FontWeight.bold, fontSize: 10),
                    headerDecoration: pw.BoxDecoration(color: PdfColors.green50),
                    cellStyle: baseTextStyle,
                    cellAlignment: pw.Alignment.centerLeft,
                    columnWidths: {
                      0: const pw.FlexColumnWidth(2),
                      1: const pw.FlexColumnWidth(3),
                      2: const pw.FlexColumnWidth(2),
                    },
                    border: pw.TableBorder.all(color: PdfColors.grey300),
                  ),

                  pw.Spacer(),

                  // Footer
                  pw.Divider(),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Báo cáo được tạo tự động', style: smallGrey),
                      pw.Text('Trang 3', style: smallGrey),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      }
    }

    // ============================================
    // SAVE AND PRESENT PDF
    // ============================================
    final pdfBytes = await pdf.save();

    // Close progress dialog
    if (mounted) Navigator.of(context).pop();

    // Platform-specific behavior
    if (Platform.isWindows) {
      final file = await getSaveLocation(
        suggestedName: 'statistics_${DateTime.now().millisecondsSinceEpoch}.pdf',
        acceptedTypeGroups: [const XTypeGroup(label: 'PDF', extensions: ['pdf'])],
      );

      if (file == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hủy xuất PDF'))
          );
        }
        return;
      }

      final path = file.path;
      await File(path).writeAsBytes(pdfBytes);
      await Process.run('explorer', [path]);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã lưu PDF: ${p.basename(path)}'))
        );
      }
    } else {
      // Non-Windows: use printing package
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdfBytes);
    }
  } catch (e) {
    // Close progress dialog if still open
    if (mounted) Navigator.of(context).pop();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi xuất PDF: $e'))
      );
    }
  }
}

  // ===========================================================================
  // EXCEL EXPORT FUNCTION
  // ===========================================================================
  Future<void> _exportStatisticsToExcel({
    required List<Building> buildings,
    required List<Tenant> tenants,
    required List<Room> rooms,
    required List<Payment> payments,
    String? organizationName,
  }) async {
    // Show progress indicator
    if (mounted) {
      _showTrackedDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      // ============================================
      // FORMATTERS
      // ============================================
      final currencyFormatter = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
      final dateFormatter = DateFormat('dd/MM/yyyy – HH:mm');

      // ============================================
      // CALCULATE COMPREHENSIVE STATISTICS
      // ============================================
      
      // Overall stats
      final totalBuildings = buildings.length;
      final totalRooms = rooms.length;
      final activeTenants = tenants.where((t) => t.status == TenantStatus.active).length;
      final inactiveTenants = tenants.where((t) => t.status == TenantStatus.inactive).length;
      final movedOutTenants = tenants.where((t) => t.status == TenantStatus.moveOut).length;
      final suspendedTenants = tenants.where((t) => t.status == TenantStatus.suspended).length;
      
      // Payment stats
      final paidPayments = payments.where((p) => p.status == PaymentStatus.paid).toList();
      final pendingPayments = payments.where((p) => p.status == PaymentStatus.pending).toList();
      final overduePayments = payments.where((p) => p.isOverdue).toList();
      final cancelledPayments = payments.where((p) => p.status == PaymentStatus.cancelled).toList();
      
      final totalRevenue = payments.fold<double>(0, (sum, p) {
        // If status is 'paid' but paidAmount is accidentally 0, fallback to totalWithAllFees
        if (p.status == PaymentStatus.paid && p.paidAmount == 0) {
          return sum + p.totalWithAllFees;
        }
        return sum + p.paidAmount;
      });
      final pendingRevenue = payments.fold<double>(0, (sum, p) {
        // We ignore Paid (remaining is 0) and Cancelled (we don't expect to collect it)
        if (p.status == PaymentStatus.paid || p.status == PaymentStatus.cancelled) {
          return sum;
        }
        
        // For Pending, Overdue, and Partial, use the model property
        return sum + p.remainingAmount;
      });
      final overdueRevenue =  payments.fold<double>(0, (sum, p) {
        // We ignore Paid (remaining is 0) and Cancelled (we don't expect to collect it)
        if (p.status == PaymentStatus.paid || p.status == PaymentStatus.cancelled) {
          return sum;
        }
        
        // For Pending, Overdue, and Partial, use the model property
        return sum + p.remainingAmount;
      });
      
      // Building-specific stats
      final Map<String, _BuildingStats> statsByBuilding = {};
      for (final b in buildings) {
        statsByBuilding[b.id] = _BuildingStats(
          buildingId: b.id,
          buildingName: b.name,
          totalRooms: 0,
          occupiedRooms: 0,
          revenue: 0.0,
        );
      }

      for (final r in rooms) {
        final s = statsByBuilding[r.buildingId];
        if (s != null) s.totalRooms += 1;
      }

      for (final t in tenants) {
        if (t.buildingId.isEmpty) continue;
        if (t.status == TenantStatus.active) {
          final s = statsByBuilding[t.buildingId];
          if (s != null) s.occupiedRooms += 1;
        }
      }

      for (final pmt in paidPayments) {
        if (pmt.buildingId.isNotEmpty) {
          final s = statsByBuilding[pmt.buildingId];
          if (s != null) s.revenue += pmt.paidAmount;
        } else if (pmt.roomId.isNotEmpty) {
          final room = rooms.firstWhere(
            (r) => r.id == pmt.roomId, 
            orElse: () => Room(id: '', area: 0.0, roomType: '', organizationId: '', buildingId: '', roomNumber: '', createdAt: DateTime.now())
          );
          if (room.id.isNotEmpty) {
            final s = statsByBuilding[room.buildingId];
            if (s != null) s.revenue += pmt.paidAmount;
          }
        }
      }

      // Build building table rows
      final List<List<dynamic>> buildingTableRows = [];
      int grandTotalRooms = 0;
      int grandOccupied = 0;
      double grandRevenue = 0.0;

      for (final s in statsByBuilding.values) {
        final emptyRooms = (s.totalRooms - s.occupiedRooms).clamp(0, s.totalRooms);
        final occupancyRate = s.totalRooms > 0 
            ? ((s.occupiedRooms / s.totalRooms) * 100).toStringAsFixed(1) 
            : '0.0';
        
        buildingTableRows.add([
          s.buildingName,
          s.totalRooms,
          s.occupiedRooms,
          emptyRooms,
          '$occupancyRate%',
          s.revenue,
        ]);

        grandTotalRooms += s.totalRooms;
        grandOccupied += s.occupiedRooms;
        grandRevenue += s.revenue;
      }

      buildingTableRows.sort((a, b) => a[0].toString().compareTo(b[0].toString()));

      // ============================================
      // CREATE EXCEL WORKBOOK
      // ============================================
      var excel = Excel.createExcel();
      
      // Remove default sheet
      excel.delete('Sheet1');

      // ============================================
      // SHEET 1: EXECUTIVE SUMMARY
      // ============================================
      var summarySheet = excel['Tổng Quan'];
      
      int row = -1;
      
      // Title and Header
      row++;
      summarySheet.merge(CellIndex.indexByString('A${row + 1}'), CellIndex.indexByString('F${row + 1}'));
      var titleCell = summarySheet.cell(CellIndex.indexByString('A${row + 1}'));
      titleCell.value = TextCellValue(organizationName ?? 'Tổ chức');
      titleCell.cellStyle = CellStyle(bold: true, fontSize: 16);

      row++;
      summarySheet.merge(CellIndex.indexByString('A${row + 1}'), CellIndex.indexByString('F${row + 1}'));
      var headerCell = summarySheet.cell(CellIndex.indexByString('A${row + 1}'));
      headerCell.value = TextCellValue('BÁO CÁO THỐNG KÊ TỔNG QUAN');
      headerCell.cellStyle = CellStyle(bold: true, fontSize: 14);

      row++;
      summarySheet.merge(CellIndex.indexByString('A${row + 1}'), CellIndex.indexByString('F${row + 1}'));
      var dateCell = summarySheet.cell(CellIndex.indexByString('A${row + 1}'));
      dateCell.value = TextCellValue('Ngày tạo: ${dateFormatter.format(DateTime.now())}');
      dateCell.cellStyle = CellStyle(italic: true);
      row += 2;

      // Section 1: Overall Statistics
      var sectionCell = summarySheet.cell(CellIndex.indexByString('A${row + 1}'));
      sectionCell.value = TextCellValue('1. TỔNG QUAN');
      sectionCell.cellStyle = CellStyle(bold: true, fontSize: 12);
      row += 2;

      // Create stat cards data
      final statsData = [
        ['Toà nhà', totalBuildings, 'Tổng phòng', totalRooms],
        ['Đang thuê', activeTenants, 'Tỷ lệ lấp đầy', totalRooms > 0 ? '${((activeTenants / totalRooms) * 100).toStringAsFixed(1)}%' : '0%'],
        ['Phòng trống', totalRooms - activeTenants, 'Đã chuyển đi', movedOutTenants],
      ];

      for (var statRow in statsData) {
        var cell1 = summarySheet.cell(CellIndex.indexByString('A${row + 1}'));
        cell1.value = TextCellValue(statRow[0].toString());
        cell1.cellStyle = CellStyle(bold: true);
        
        var cell2 = summarySheet.cell(CellIndex.indexByString('B${row + 1}'));
        cell2.value = TextCellValue(statRow[1].toString());
        
        var cell3 = summarySheet.cell(CellIndex.indexByString('C${row + 1}'));
        cell3.value = TextCellValue(statRow[2].toString());
        cell3.cellStyle = CellStyle(bold: true);
        
        var cell4 = summarySheet.cell(CellIndex.indexByString('D${row + 1}'));
        cell4.value = TextCellValue(statRow[3].toString());
        
        row++;
      }

      row += 2;

      // Section 2: Tenant Status
      var tenantSectionCell = summarySheet.cell(CellIndex.indexByString('A${row + 1}'));
      tenantSectionCell.value = TextCellValue('2. TÌNH TRẠNG NGƯỜI THUÊ');
      tenantSectionCell.cellStyle = CellStyle(bold: true, fontSize: 12);
      row += 2;

      // Tenant status headers
      final tenantHeaders = ['Trạng thái', 'Số lượng', 'Tỷ lệ'];
      for (int i = 0; i < tenantHeaders.length; i++) {
        var cell = summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row));
        cell.value = TextCellValue(tenantHeaders[i]);
        cell.cellStyle = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('FF0099FF'));
      }
      row++;

      // Tenant status data
      final tenantStatusData = [
        ['Đang hoạt động', activeTenants, tenants.isNotEmpty ? '${((activeTenants / tenants.length) * 100).toStringAsFixed(1)}%' : '0%'],
        ['Không hoạt động', inactiveTenants, tenants.isNotEmpty ? '${((inactiveTenants / tenants.length) * 100).toStringAsFixed(1)}%' : '0%'],
        ['Đã chuyển đi', movedOutTenants, tenants.isNotEmpty ? '${((movedOutTenants / tenants.length) * 100).toStringAsFixed(1)}%' : '0%'],
        ['Bị đình chỉ', suspendedTenants, tenants.isNotEmpty ? '${((suspendedTenants / tenants.length) * 100).toStringAsFixed(1)}%' : '0%'],
        ['TỔNG', tenants.length, '100%'],
      ];

      for (var statusRow in tenantStatusData) {
        for (int i = 0; i < statusRow.length; i++) {
          var cell = summarySheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row));
          cell.value = TextCellValue(statusRow[i].toString());
          if (statusRow[0] == 'TỔNG') {
            cell.cellStyle = CellStyle(bold: true);
          }
        }
        row++;
      }

      row += 2;

      // Section 3: Payment Summary
      var paymentSectionCell = summarySheet.cell(CellIndex.indexByString('A${row + 1}'));
      paymentSectionCell.value = TextCellValue('3. TỔNG KẾT THANH TOÁN');
      paymentSectionCell.cellStyle = CellStyle(bold: true, fontSize: 12);
      row += 2;

      final paymentSummaryData = [
        ['Đã thu', currencyFormatter.format(totalRevenue), 'Số hóa đơn', paidPayments.length],
        ['Chưa thu', currencyFormatter.format(pendingRevenue), 'Số hóa đơn', pendingPayments.length],
        ['Quá hạn', currencyFormatter.format(overdueRevenue), 'Số hóa đơn', overduePayments.length],
        ['Đã hủy', cancelledPayments.length, 'Số hóa đơn', ''],
      ];

      for (var paymentRow in paymentSummaryData) {
        var cell1 = summarySheet.cell(CellIndex.indexByString('A${row + 1}'));
        cell1.value = TextCellValue(paymentRow[0].toString());
        cell1.cellStyle = CellStyle(bold: true);
        
        var cell2 = summarySheet.cell(CellIndex.indexByString('B${row + 1}'));
        cell2.value = TextCellValue(paymentRow[1].toString());
        
        var cell3 = summarySheet.cell(CellIndex.indexByString('C${row + 1}'));
        cell3.value = TextCellValue(paymentRow[2].toString());
        cell3.cellStyle = CellStyle(bold: true);
        
        var cell4 = summarySheet.cell(CellIndex.indexByString('D${row + 1}'));
        cell4.value = TextCellValue(paymentRow[3].toString());
        
        row++;
      }

      // ============================================
      // SHEET 2: BUILDING DETAILS
      // ============================================
      var buildingSheet = excel['Chi Tiết Tòa Nhà'];
      
      row = -1;
      
      // Header
      row++;
      var buildingTitleCell = buildingSheet.cell(CellIndex.indexByString('A${row + 1}'));
      buildingTitleCell.value = TextCellValue('CHI TIẾT THEO TÒA NHÀ');
      buildingTitleCell.cellStyle = CellStyle(bold: true, fontSize: 14);
      row += 2;

      // Building table headers
      final buildingHeaders = ['Toà nhà', 'Tổng phòng', 'Đang thuê', 'Trống', 'Tỷ lệ', 'Doanh thu'];
      for (int i = 0; i < buildingHeaders.length; i++) {
        var cell = buildingSheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row));
        cell.value = TextCellValue(buildingHeaders[i]);
        cell.cellStyle = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('FF0099FF'));
      }
      row++;

      // Building table data
      for (var buildingRow in buildingTableRows) {
        var cell0 = buildingSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
        cell0.value = TextCellValue(buildingRow[0].toString());
        
        var cell1 = buildingSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row));
        cell1.value = IntCellValue(buildingRow[1] as int);
        
        var cell2 = buildingSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row));
        cell2.value = IntCellValue(buildingRow[2] as int);
        
        var cell3 = buildingSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row));
        cell3.value = IntCellValue(buildingRow[3] as int);
        
        var cell4 = buildingSheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row));
        cell4.value = TextCellValue(buildingRow[4].toString());
        
        var cell5 = buildingSheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row));
        cell5.value = DoubleCellValue(buildingRow[5] as double);
        
        row++;
      }

      // Totals row
      row++;
      var totalLabelCell = buildingSheet.cell(CellIndex.indexByString('A${row + 1}'));
      totalLabelCell.value = TextCellValue('TỔNG CỘNG');
      totalLabelCell.cellStyle = CellStyle(bold: true);

      var totalRoomsCell = buildingSheet.cell(CellIndex.indexByString('B${row + 1}'));
      totalRoomsCell.value = IntCellValue(grandTotalRooms);
      totalRoomsCell.cellStyle = CellStyle(bold: true);

      var totalOccupiedCell = buildingSheet.cell(CellIndex.indexByString('C${row + 1}'));
      totalOccupiedCell.value = IntCellValue(grandOccupied);
      totalOccupiedCell.cellStyle = CellStyle(bold: true);

      var totalEmptyCell = buildingSheet.cell(CellIndex.indexByString('D${row + 1}'));
      totalEmptyCell.value = IntCellValue(grandTotalRooms - grandOccupied);
      totalEmptyCell.cellStyle = CellStyle(bold: true);

      var totalRevenueCell = buildingSheet.cell(CellIndex.indexByString('F${row + 1}'));
      totalRevenueCell.value = DoubleCellValue(grandRevenue);
      totalRevenueCell.cellStyle = CellStyle(bold: true);

      // ============================================
      // SHEET 3: DETAILED PAYMENTS
      // ============================================
      var paymentsSheet = excel['Thanh Toán Chi Tiết'];
      
      row = -1;
      
      row++;
      var paymentsTitleCell = paymentsSheet.cell(CellIndex.indexByString('A${row + 1}'));
      paymentsTitleCell.value = TextCellValue('DANH SÁCH THANH TOÁN CHI TIẾT');
      paymentsTitleCell.cellStyle = CellStyle(bold: true, fontSize: 14);
      row += 2;

      // Payment table headers
      final paymentHeaders = ['Mã thanh toán', 'Số tiền', 'Trạng thái', 'Ngày thanh toán', 'Ngày quá hạn', 'Ghi chú'];
      for (int i = 0; i < paymentHeaders.length; i++) {
        var cell = paymentsSheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row));
        cell.value = TextCellValue(paymentHeaders[i]);
        cell.cellStyle = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('FFFF9900'));
      }
      row++;

      // Payment data - sorted by date (newest first)
      final sortedPayments = List<Payment>.from(payments);
      sortedPayments.sort((a, b) {
        final dateA = a.createdAt;
        final dateB = b.createdAt;
        return dateB.compareTo(dateA);
      });

      for (var payment in sortedPayments) {
        var cell0 = paymentsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
        cell0.value = TextCellValue(payment.id);
        
        var cell1 = paymentsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row));
        cell1.value = DoubleCellValue(payment.totalAmount);
        
        var cell2 = paymentsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row));
        final statusText = payment.status == PaymentStatus.paid ? 'Đã thanh toán' :
                          payment.status == PaymentStatus.pending ? 'Chưa thanh toán' :
                          payment.status == PaymentStatus.cancelled ? 'Đã hủy' : 'Khác';
        cell2.value = TextCellValue(statusText);
        
        var cell3 = paymentsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row));
        final paidDateText = payment.paidAt != null ? DateFormat('dd/MM/yyyy').format(payment.paidAt!) : '';
        cell3.value = TextCellValue(paidDateText);
        
        var cell4 = paymentsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row));
        final dueDateText = DateFormat('dd/MM/yyyy').format(payment.dueDate);
        cell4.value = TextCellValue(dueDateText);
        
        var cell5 = paymentsSheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row));
        cell5.value = TextCellValue(payment.notes ?? '');
        
        row++;
      }

      // ============================================
      // AUTO-FIT COLUMNS FOR ALL SHEETS
      // ============================================
      // Set auto-fit column widths for all sheets
      for (var sheet in excel.sheets.keys) {
        var sheetObject = excel[sheet];
        
        // Get the maximum column index used in this sheet
        int maxCol = 0;
        for (var row in sheetObject.rows) {
          if (row.isNotEmpty) {
            maxCol = maxCol < row.length ? row.length : maxCol;
          }
        }
        
        // Set auto-fit width for each column
        for (int col = 0; col < maxCol; col++) {
          sheetObject.setColumnAutoFit(col);
        }
      }

      // ============================================
      // SAVE EXCEL FILE
      // ============================================
      final excelBytes = excel.encode();
      
      // Close progress dialog
      if (mounted) Navigator.of(context).pop();

      // Platform-specific behavior
      if (Platform.isWindows) {
        final file = await getSaveLocation(
          suggestedName: 'statistics_${DateTime.now().millisecondsSinceEpoch}.xlsx',
          acceptedTypeGroups: [const XTypeGroup(label: 'Excel', extensions: ['xlsx'])],
        );

        if (file == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Hủy xuất Excel'))
            );
          }
          return;
        }

        final path = file.path;
        await File(path).writeAsBytes(excelBytes!);
        await Process.run('explorer', [path]);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Đã lưu Excel: ${p.basename(path)}'))
          );
        }
      } else {
        // For other platforms, show a snackbar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tệp Excel đã được tạo'))
          );
        }
      }
    } catch (e) {
      // Close progress dialog if still open
      if (mounted) Navigator.of(context).pop();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi xuất Excel: $e'))
        );
      }
    }
  }

  Map<String, double> _calculateMonthlyRevenue(List<Payment> payments) {
    final Map<String, double> monthlyRevenue = {};
    final now = DateTime.now();
    
    // Get last 6 months
    for (int i = 5; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final monthKey = DateFormat('MM/yyyy').format(month);
      monthlyRevenue[monthKey] = 0;
    }
    
    // Calculate revenue for each month
    for (var payment in payments.where((p) => p.status == PaymentStatus.paid)) {
    // Use paidAt if available, otherwise fallback to createdAt so it still shows on the chart
    final dateToUse = payment.paidAt ?? payment.createdAt; 
    final monthKey = DateFormat('MM/yyyy').format(dateToUse);
    
    if (monthlyRevenue.containsKey(monthKey)) {
      // Fallback: If paidAmount is 0 but status is paid, use totalAmount
      double amount = payment.paidAmount > 0 ? payment.paidAmount : payment.totalWithAllFees;
      monthlyRevenue[monthKey] = (monthlyRevenue[monthKey] ?? 0) + amount;
    }
  }
    
    return monthlyRevenue;
  }

  Map<String, Map<String, dynamic>> _calculateBuildingOccupancy(
    List<Building> buildings,
    List<Room> rooms,
    List<Tenant> tenants,
  ) {
    final Map<String, Map<String, dynamic>> occupancy = {};
    
    // Track occurrences for display names only
    final Map<String, int> nameOccurrences = {};
    for (var b in buildings) {
      nameOccurrences[b.name] = (nameOccurrences[b.name] ?? 0) + 1;
    }
    final Map<String, int> nameCounters = {};
    
    for (var building in buildings) {
      final totalRooms = rooms.where((r) => r.buildingId == building.id).length;
      final occupiedRooms = rooms
          .where((r) => r.buildingId == building.id)
          .where((room) => tenants.any((t) => t.roomId == room.id && t.status == TenantStatus.active))
          .length;
      
      final percentage = totalRooms > 0 ? (occupiedRooms / totalRooms * 100) : 0.0;
      
      // Create unique display name for the UI
      String displayName = building.name;
      if (nameOccurrences[building.name]! > 1) {
        nameCounters[building.name] = (nameCounters[building.name] ?? 0) + 1;
        displayName = '${building.name} (${nameCounters[building.name]})';
      }
      
      // KEY CHANGE: Use building.id as the key
      occupancy[building.id] = {
        'name': displayName, // Store the name here
        'occupied': occupiedRooms,
        'total': totalRooms,
        'percentage': percentage,
      };
    }
    return occupancy;
  }

  Map<String, double> _calculateMonthlyOccupancyTrend(
    String buildingId,
    List<Room> rooms,
    List<Tenant> tenants,
  ) {
    final Map<String, double> monthlyOccupancy = {};
    final now = DateTime.now();

    // 1. Get total rooms for this building
    final buildingRooms = rooms.where((r) => r.buildingId == buildingId).toList();
    final totalRooms = buildingRooms.length;
    if (totalRooms == 0) return monthlyOccupancy;

    // 2. Loop through the last 12 months
    for (int i = 11; i >= 0; i--) {
      final monthDate = DateTime(now.year, now.month - i, 1);
      final monthEnd = DateTime(monthDate.year, monthDate.month + 1, 0); // Last day of that month
      final monthKey = DateFormat('MM/yyyy').format(monthDate);

      // 3. Count tenants who were "living there" during that month
      final activeTenantsCount = tenants.where((tenant) {
        if (tenant.buildingId != buildingId) return false;

        // Check if they had moved in by the end of this month
        final hasMovedIn = tenant.moveInDate.isBefore(monthEnd) || 
                          tenant.moveInDate.isAtSameMomentAs(monthEnd);

        // logic: If they are currently ACTIVE, they were active in the past (post-move-in)
        // If they are moveOut, they were only active IF we knew their moveOutDate.
        // For now, we count currently Active tenants in their historical months.
        final isCurrentlyActive = tenant.status == TenantStatus.active;

        return hasMovedIn && isCurrentlyActive;
      }).length;

      double occupancyRate = (activeTenantsCount.toDouble() / totalRooms.toDouble() * 100);
      monthlyOccupancy[monthKey] = occupancyRate;
    }

    return monthlyOccupancy;
  }

  Widget _buildMonthlyRevenueChart(Map<String, double> monthlyRevenue) {
    if (monthlyRevenue.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(
              'Chưa có dữ liệu doanh thu',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        ),
      );
    }

    final maxRevenue = monthlyRevenue.values.reduce((a, b) => a > b ? a : b);
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Chart
            SizedBox(
              height: 200,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: monthlyRevenue.entries.map((entry) {
                  final barHeight = maxRevenue > 0 
                      ? (entry.value / maxRevenue * 150).clamp(5.0, 150.0)
                      : 5.0;
                  
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            _formatCurrencyShort(entry.value),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: barHeight,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Colors.green.shade700,
                                  Colors.green.shade300,
                                ],
                              ),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            entry.key,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBuildingOccupancyChart(Map<String, Map<String, dynamic>> occupancy, List<Building> buildings) {
    if (occupancy.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: Text('Chưa có dữ liệu toà nhà')),
        ),
      );
    }

    // Filter occupancy data based on selected building ID
    Map<String, Map<String, dynamic>> displayOccupancy;
    
    if (_selectedOccupancyBuildingId == null) {
      // Show all buildings
      displayOccupancy = occupancy;
    } else {
      // Show only the selected building using its ID as the key
      if (occupancy.containsKey(_selectedOccupancyBuildingId)) {
        displayOccupancy = {
          _selectedOccupancyBuildingId!: occupancy[_selectedOccupancyBuildingId]!
        };
      } else {
        displayOccupancy = {};
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dropdown Filter
            Row(
              children: [
                const Text(
                  'Lọc theo toà nhà:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    value: _selectedOccupancyBuildingId,
                    hint: const Text('Tất cả toà nhà'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Tất cả toà nhà'),
                      ),
                      ...buildings.map((building) {
                        return DropdownMenuItem<String?>(
                          value: building.id,
                          child: Text(building.name),
                        );
                      }),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedOccupancyBuildingId = value;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Occupancy Bars
            ...displayOccupancy.entries.map((entry) {
              final data = entry.value;
              
              final String buildingName = data['name'] ?? "Không xác định";
              
              final percentage = (data['percentage'] as num).toDouble();
              final occupied = data['occupied'] as int;
              final total = data['total'] as int;
              
              Color barColor = percentage >= 80 ? Colors.green : (percentage >= 50 ? Colors.orange : Colors.red);
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            buildingName, // Displays the name (e.g. "Toà A")
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Text(
                          '$occupied/$total (${percentage.toStringAsFixed(0)}%)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: barColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: percentage / 100,
                        backgroundColor: Colors.grey[200],
                        color: barColor,
                        minHeight: 12,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyOccupancyTrendChart(
    List<Building> buildings,
    List<Room> rooms,
    List<Tenant> tenants,
  ) {
    if (buildings.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(
              'Chưa có dữ liệu toà nhà',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        ),
      );
    }

    // Set default selected building if not set
    if (_selectedBuildingId == null || !buildings.any((b) => b.id == _selectedBuildingId)) {
      // Use WidgetsBinding to avoid calling setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selectedBuildingId = buildings.first.id;
          });
        }
      });
      // For this frame, use the first building
      _selectedBuildingId = buildings.first.id;
    }

    final selectedBuilding = buildings.firstWhere(
      (b) => b.id == _selectedBuildingId,
      orElse: () => buildings.first,
    );

    final monthlyOccupancy = _calculateMonthlyOccupancyTrend(
      selectedBuilding.id,
      rooms,
      tenants,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Building Selector
            Row(
              children: [
                const Text(
                  'Chọn toà nhà:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text('Chọn tòa nhà'),

                    // ✅ Value must exist in items or be null
                    value: buildings.any((b) => b.id == _selectedBuildingId)
                        ? _selectedBuildingId
                        : null,

                    items: buildings.map((building) {
                      return DropdownMenuItem<String>(
                        value: building.id,
                        child: Text(building.name),
                      );
                    }).toList(),

                    onChanged: (value) {
                      setState(() {
                        _selectedBuildingId = value;
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Chart
            if (monthlyOccupancy.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Text(
                    'Chưa có dữ liệu cho toà nhà này',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              )
            else
              SizedBox(
                height: 220,
                child: Column(
                  children: [
                    // Y-axis label
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Tỷ lệ lấp đầy (%)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: monthlyOccupancy.entries.map((entry) {
                          final occupancyRate = entry.value;
                          final barHeight = (occupancyRate / 100 * 150).clamp(5.0, 150.0);
                          
                          Color barColor;
                          if (occupancyRate >= 80) {
                            barColor = Colors.green;
                          } else if (occupancyRate >= 50) {
                            barColor = Colors.orange;
                          } else {
                            barColor = Colors.red;
                          }
                          
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    '${occupancyRate.toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    height: barHeight,
                                    decoration: BoxDecoration(
                                      color: barColor,
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(4),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    entry.key.split('/')[0], // Show only month
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatCurrencyShort(double amount) {
    if (amount >= 1000000000) {
      return '${(amount / 1000000000).toStringAsFixed(1)}B';
    } else if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}M';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(0)}K';
    }
    return amount.toStringAsFixed(0);
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========================================
  // MEMBERS TAB
  // ========================================
  Widget _buildMembersTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// ===== ADMIN ACTIONS =====
          FutureBuilder<Membership?>(
            future: _getMyMembership(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();

              final membership = snapshot.data!;
              if (membership.role != 'admin') return const SizedBox();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ElevatedButton(
                    onPressed: loadingInvite ? null : _loadInviteCode,
                    child: const Text("Lấy mã mời"),
                  ),
                  if (inviteCode != null) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      "Mã mời: $inviteCode",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  const Divider(height: 32),
                ],
              );
            },
          ),

          /// ===== MEMBERS LIST =====
          const Text(
            "Thành viên",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: FutureBuilder<List<Membership>>(
              future: _getMembers(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text("Không tìm thấy thành viên."));
                }

                final members = snapshot.data!;

                return ListView.builder(
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    
                    return FutureBuilder(
                      future: _authService.getOwnerData(member.ownerId),
                      builder: (context, ownerSnapshot) {
                        if (ownerSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.person),
                              ),
                              title: const Text('Đang tải...'),
                              subtitle: Text(member.role.toUpperCase()),
                            ),
                          );
                        }

                        final ownerName = ownerSnapshot.data?.name ??
                            ownerSnapshot.data?.email ??
                            member.ownerId;

                        final ownerEmail = ownerSnapshot.data?.email;
                        final roleText = member.role == 'admin' ? 'Quản trị viên' : 'Thành viên';

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: member.role == 'admin'
                                  ? Colors.orange
                                  : Colors.blue,
                              child: Icon(
                                member.role == 'admin'
                                    ? Icons.admin_panel_settings
                                    : Icons.person,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              ownerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  roleText,
                                  style: TextStyle(
                                    color: member.role == 'admin'
                                        ? Colors.orange
                                        : Colors.grey,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                if (ownerEmail != null)
                                  Text(
                                    ownerEmail,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: FutureBuilder<Membership?>(
                              future: _getMyMembership(),
                              builder: (context, myMembershipSnapshot) {
                                if (!myMembershipSnapshot.hasData) {
                                  return member.status == 'active'
                                      ? const Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                          size: 20,
                                        )
                                      : const Icon(
                                          Icons.pending,
                                          color: Colors.orange,
                                          size: 20,
                                        );
                                }
                                
                                final myMembership = myMembershipSnapshot.data!;
                                
                                if (myMembership.role != 'admin') {
                                  return member.status == 'active'
                                      ? const Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                          size: 20,
                                        )
                                      : const Icon(
                                          Icons.pending,
                                          color: Colors.orange,
                                          size: 20,
                                        );
                                }
                                
                                if (member.ownerId == myMembership.ownerId) {
                                  return const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 20,
                                  );
                                }
                                
                                return Builder(
                                  builder: (BuildContext context) {
                                    return IconButton(
                                      icon: const Icon(Icons.more_vert),
                                      onPressed: () {
                                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                                        final RenderBox button = context.findRenderObject() as RenderBox;
                                        final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
                                        final RelativeRect position = RelativeRect.fromRect(
                                          Rect.fromPoints(
                                            button.localToGlobal(Offset.zero, ancestor: overlay) + const Offset(0, 48),
                                            button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
                                          ),
                                          Offset.zero & overlay.size,
                                        );

                                        showMenu<String>(
                                          context: context,
                                          position: position,
                                          items: [
                                            if (member.role == 'member')
                                              const PopupMenuItem(
                                                value: 'promote',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.arrow_upward, size: 20),
                                                    SizedBox(width: 8),
                                                    Text('Thăng cấp Admin'),
                                                  ],
                                                ),
                                              ),
                                            if (member.role == 'admin')
                                            const PopupMenuItem(
                                              value: 'remove',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.remove_circle, size: 20, color: Colors.red),
                                                  SizedBox(width: 8),
                                                  Text('Xóa khỏi tổ chức', style: TextStyle(color: Colors.red)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ).then((value) async {
                                          if (value == 'promote') {
                                            final success = await _orgService.promoteMemberToAdmin(
                                              currentAdminId: myMembership.ownerId,
                                              memberIdToPromote: member.ownerId,
                                              orgId: widget.organization.id,
                                            );
                                            if (success && mounted) {
                                              scaffoldMessenger.showSnackBar(
                                                const SnackBar(content: Text('Đã thăng cấp thành admin')),
                                              );
                                              setState(() {});
                                            }
                                          } else if (value == 'remove') {
                                            final confirm = await _showTrackedDialog<bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: const Text('Xác nhận xóa'),
                                                content: Text('Bạn có chắc muốn xóa $ownerName khỏi tổ chức?'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(context, false),
                                                    child: const Text('Hủy'),
                                                  ),
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(context, true),
                                                    child: const Text('Xóa', style: TextStyle(color: Colors.red)),
                                                  ),
                                                ],
                                              ),
                                            );
                                            
                                            if (confirm == true) {
                                              final success = await _orgService.leaveOrganization(
                                                member.ownerId,
                                                widget.organization.id,
                                              );
                                              if (success && mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('Đã xóa thành viên')),
                                                );
                                                setState(() {});
                                              }
                                            }
                                          }
                                        });
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ========================================
  // HELPER METHODS
  // ========================================

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'hôm nay';
    } else if (difference.inDays == 1) {
      return 'hôm qua';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ngày trước';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks tuần trước';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months tháng trước';
    } else {
      final years = (difference.inDays / 365).floor();
      return '$years năm trước';
    }
  }
}

// Small helper class to aggregate building stats
class _BuildingStats {
  final String buildingId;
  final String buildingName;
  int totalRooms;
  int occupiedRooms;
  double revenue;

  _BuildingStats({
    required this.buildingId,
    required this.buildingName,
    required this.totalRooms,
    required this.occupiedRooms,
    required this.revenue,
  });
}
