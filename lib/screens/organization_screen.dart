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
import 'package:apartment_management_project_2/utils/app_localizations.dart';
import 'package:apartment_management_project_2/widgets/shared.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

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

class _OrganizationScreenState extends State<OrganizationScreen>
    with WidgetsBindingObserver {

  // Track how many overlays (dialogs/bottom sheets) are currently open
  int _overlayCount = 0;

  bool _isSmallScreen(BuildContext context) =>
      MediaQuery.of(context).size.width < 600;

  double _getDialogWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 600) return screenWidth * 0.95;
    if (screenWidth < 1200) return 600;
    return 800;
  }

  EdgeInsets _getResponsivePadding(BuildContext context) {
    return EdgeInsets.all(_isSmallScreen(context) ? 12.0 : 16.0);
  }

  Widget _buildMinimumSizeWarning(
      BuildContext context, BoxConstraints constraints) {
    final t = AppTranslations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 64, color: Colors.orange[700]),
            const SizedBox(height: 16),
            Text(
              t['window_size_too_small'],
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              t.textWithParams('minimum_size',
                  {'width': minWidth.toInt(), 'height': minHeight.toInt()}),
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              t.textWithParams('current_size', {
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

  final OrganizationService _orgService = getIt<OrganizationService>();
  final AuthService _authService = getIt<AuthService>();
  final BuildingService _buildingService = getIt<BuildingService>();
  final TenantService _tenantService = getIt<TenantService>();
  final PaymentService _paymentService = getIt<PaymentService>();
  final PaymentsNotifier _paymentsNotifier = getIt<PaymentsNotifier>();
  final RoomService _roomService = getIt<RoomService>();

  String? _selectedBuildingId;
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
    _paymentsNotifier.loadPayments(widget.organization.id);
    _refreshStats();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _resizeDebounceTimer?.cancel();
    super.dispose();
  }

  Timer? _resizeDebounceTimer;
  bool _isDismissing = false;

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _resizeDebounceTimer?.cancel();
    _resizeDebounceTimer =
        Timer(const Duration(milliseconds: 300), () {
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

  String? inviteCode;
  bool loadingInvite = false;
  bool _refreshingCode = false;

  String? get _userId => _authService.currentUser?.uid;

  Future<Membership?> _getMyMembership() {
    if (_userId == null) return Future.value(null);
    return _orgService.getUserMembership(_userId!, widget.organization.id);
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
    final code = await _orgService.getInviteCode(widget.organization.id);
    setState(() {
      inviteCode = code;
      loadingInvite = false;
    });
  }

  // ========================================
  // BUILDING DIALOGS
  // ========================================
  Future<void> _showAddBuildingDialog() async {
    final t = AppTranslations.of(context);
    final result = await _showTrackedDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const BuildingDialog(isEditMode: false),
    );

    if (result != null && mounted) {
      _showTrackedDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            const Center(child: CircularProgressIndicator()),
      );

      try {
        final buildingId =
            await _buildingService.addBuildingFromDialogResult(
          organizationId: widget.organization.id,
          dialogResult: result,
        );

        if (buildingId == null) throw Exception('Failed to create building');

        if (result['autoGenerateRooms'] == true) {
          final rooms = await _roomService.generateRoomsFromConfig(
            organizationId: widget.organization.id,
            buildingId: buildingId,
            config: result,
          );
          await _roomService.addMultipleRooms(rooms);
          final totalRooms = rooms.length;
          if (mounted) Navigator.of(context).pop();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(t.textWithParams(
                  'add_building_rooms_success', {'count': totalRooms})),
              backgroundColor: Colors.green,
            ));
            setState(() {});
          }
        } else {
          if (mounted) Navigator.of(context).pop();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(t['add_building_success']),
              backgroundColor: Colors.green,
            ));
            setState(() {});
            _refreshStats();
          }
        }
      } catch (e) {
        if (mounted) Navigator.of(context).pop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t.textWithParams('delete_building_error', {'error': e})),
            backgroundColor: Colors.red,
          ));
        }
      }
    }
  }

  Future<void> _showEditBuildingDialog(Building building) async {
    final t = AppTranslations.of(context);
    final result = await _showTrackedDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => BuildingDialog(
        isEditMode: true,
        initialName: building.name,
        initialAddress: building.address,
        initialFloors: building.floors,
        initialRoomPrefix: building.roomPrefix,
        initialUniformRooms: building.uniformRooms,
        initialRoomsPerFloor: building.roomsPerFloor,
        initialRoomType: building.roomType,
        initialRoomArea: building.roomArea,
        initialFloorDetails: building.floorDetails,
        initialFloorRoomCounts: building.floorRoomCounts,
      ),
    );

    if (result != null && mounted) {
      _showTrackedDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            const Center(child: CircularProgressIndicator()),
      );

      try {
        final success =
            await _buildingService.updateBuildingFromDialogResult(
          buildingId: building.id,
          dialogResult: result,
        );
        if (!success) throw Exception('Failed to update building');

        if (result['autoGenerateRooms'] == true) {
          final rooms = await _roomService.generateRoomsFromConfig(
            organizationId: widget.organization.id,
            buildingId: building.id,
            config: result,
          );
          final addSuccess = await _roomService.addMultipleRooms(rooms);
          if (!addSuccess) throw Exception('Failed to add rooms');
          final totalRooms = rooms.length;
          if (mounted) Navigator.of(context).pop();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(t.textWithParams(
                  'update_building_rooms_success', {'count': totalRooms})),
              backgroundColor: Colors.green,
            ));
            setState(() {});
          }
        } else {
          if (mounted) Navigator.of(context).pop();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(t['update_building_success']),
              backgroundColor: Colors.green,
            ));
            setState(() {});
          }
        }
      } catch (e) {
        if (mounted) Navigator.of(context).pop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t.textWithParams('delete_building_error', {'error': e})),
            backgroundColor: Colors.red,
          ));
        }
      }
    }
  }

  Future<void> _deleteBuilding(
      Building building, Organization organization) async {
    final t = AppTranslations.of(context);
    final tenants = await _tenantService.getBuildingTenants(
        building.id, organization.id);
    final activeTenants = tenants
        .where((tn) =>
            tn.status == TenantStatus.active ||
            tn.status == TenantStatus.inactive ||
            tn.status == TenantStatus.suspended)
        .toList();

    final contentPadding = _getResponsivePadding(context);

    final confirm = await _showTrackedDialog<bool>(
      context: context,
      builder: (context) {
        final dialogBg = Theme.of(context).dialogTheme.backgroundColor ??
            Theme.of(context).colorScheme.surface;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          constraints:
              const BoxConstraints(maxWidth: 400, minWidth: 320),
          child: Material(
            color: dialogBg,
            elevation: 24,
            shadowColor: Colors.black.withValues(alpha: 0.3),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              child: Padding(
                padding: contentPadding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppTranslations.of(context)['delete_building_title'],
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(
                        height: _isSmallScreen(context) ? 12 : 16),
                    ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: 800),
                      child: Text(
                        AppTranslations.of(context).textWithParams(
                            'delete_building_confirm',
                            {'name': building.name}),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                        softWrap: true,
                      ),
                    ),
                    SizedBox(
                        height: _isSmallScreen(context) ? 12 : 16),
                    Text(
                      AppTranslations.of(context)['delete_action_will'],
                      style:
                          const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(
                        height: _isSmallScreen(context) ? 8 : 12),
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
                            AppTranslations.of(context)[
                                'delete_all_rooms'],
                            style: TextStyle(
                                fontSize: _isSmallScreen(context)
                                    ? 13
                                    : 14),
                            softWrap: true,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                        height: _isSmallScreen(context) ? 8 : 12),
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
                              AppTranslations.of(context)
                                  .textWithParams('mark_tenants_moved',
                                      {'count': activeTenants.length}),
                              style: TextStyle(
                                  fontSize: _isSmallScreen(context)
                                      ? 13
                                      : 14),
                              softWrap: true,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                          height: _isSmallScreen(context) ? 10 : 12),
                      Container(
                        padding: EdgeInsets.all(
                            _isSmallScreen(context) ? 10 : 12),
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
                                AppTranslations.of(context)[
                                    'tenant_data_preserved'],
                                style: TextStyle(
                                    fontSize: _isSmallScreen(context)
                                        ? 12
                                        : 13),
                                softWrap: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(
                        height: _isSmallScreen(context) ? 12 : 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OverflowBar(
                        alignment: MainAxisAlignment.end,
                        spacing: 8,
                        overflowSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(context).pop(false),
                            child: Text(AppTranslations.of(context)[
                                'cancel']),
                          ),
                          ElevatedButton(
                            onPressed: () =>
                                Navigator.of(context).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            child: Text(AppTranslations.of(context)[
                                'delete']),
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
      builder: (context) =>
          const Center(child: CircularProgressIndicator()),
    );

    try {
      final result =
          await _buildingService.deleteBuildingWithRoomsAndTenants(
              building.id, widget.organization.id);
      if (!mounted) return;
      Navigator.of(context).pop();

      if (result['rooms']! > 0 || result['tenants']! > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.textWithParams('building_deleted_summary', {
              'rooms': result['rooms'],
              'tenants': result['tenants'],
            })),
            duration: const Duration(seconds: 4),
          ),
        );
        setState(() {});
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t['cannot_delete_building'])),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              t.textWithParams('delete_building_error', {'error': e})),
        ));
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

  // ========================================
  // BUILD
  // ========================================
  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < minWidth ||
            constraints.maxHeight < minHeight) {
          return Scaffold(
            body: _buildMinimumSizeWarning(context, constraints),
          );
        }
        return DefaultTabController(
          length: 5,
          child: Scaffold(
            appBar: AppBar(
              title: Text(widget.organization.name),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(kToolbarHeight),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const estimatedTabWidth = 120.0;
                    const numberOfTabs = 5;
                    final totalEstimatedWidth =
                        estimatedTabWidth * numberOfTabs;
                    final shouldScroll =
                        constraints.maxWidth < totalEstimatedWidth;
                    return TabBar(
                      isScrollable: shouldScroll,
                      labelStyle:
                          const TextStyle(fontSize: 12),
                      tabs: [
                        Tab(
                            icon: const Icon(Icons.apartment),
                            text: t['buildings_tab']),
                        Tab(
                            icon: const Icon(Icons.people),
                            text: t['tenants_tab']),
                        Tab(
                            icon: const Icon(Icons.receipt_long),
                            text: t['payments_tab']),
                        Tab(
                            icon: const Icon(Icons.bar_chart),
                            text: t['statistics_tab']),
                        Tab(
                            icon: const Icon(Icons.group),
                            text: t['members_tab']),
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
                  authService: _authService,
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
    final t = AppTranslations.of(context);
    return FutureBuilder<Membership?>(
      future: _getMyMembership(),
      builder: (context, membershipSnapshot) {
        final isAdmin = membershipSnapshot.hasData &&
            membershipSnapshot.data!.role == 'admin';
        return Column(
          children: [
            if (isAdmin)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _showAddBuildingDialog,
                    icon: const Icon(Icons.add),
                    label: Text(t['add_building']),
                  ),
                ),
              ),
            Expanded(
              child: FutureBuilder<List<Building>>(
                future: _getBuildings(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.apartment,
                              size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          Text(
                            t['no_buildings'],
                            style:
                                const TextStyle(color: Colors.grey),
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
                            child: Icon(Icons.apartment,
                                color: Colors.white),
                          ),
                          title: Text(
                            building.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16),
                          ),
                          subtitle: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(building.address),
                              const SizedBox(height: 4),
                              Text(
                                '${t['created_at']} ${_formatDate(building.createdAt)}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey),
                              ),
                            ],
                          ),
                          trailing: isAdmin
                              ? Builder(
                                  builder: (BuildContext ctx) {
                                    return IconButton(
                                      icon: const Icon(
                                          Icons.more_vert),
                                      onPressed: () {
                                        _showBuildingMenu(
                                            ctx, building);
                                      },
                                    );
                                  },
                                )
                              : IconButton(
                                  icon: const Icon(
                                      Icons.arrow_forward_ios,
                                      size: 16),
                                  onPressed: () =>
                                      _navigateToBuildingRooms(
                                          building),
                                ),
                          onTap: () =>
                              _navigateToBuildingRooms(building),
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

  void _showBuildingMenu(BuildContext ctx, Building building) {
    final t = AppTranslations.of(context);
    final RenderBox button =
        ctx.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(ctx)
        .overlay!
        .context
        .findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay) +
            const Offset(0, 48),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    showMenu<String>(
      context: ctx,
      position: position,
      items: [
        PopupMenuItem(
          value: 'rooms',
          child: Row(children: [
            const Icon(Icons.meeting_room, size: 20),
            const SizedBox(width: 8),
            Text(t['manage_rooms']),
          ]),
        ),
        PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            const Icon(Icons.edit, size: 20),
            const SizedBox(width: 8),
            Text(t['edit']),
          ]),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            const Icon(Icons.delete, size: 20, color: Colors.red),
            const SizedBox(width: 8),
            Text(t['delete'],
                style: const TextStyle(color: Colors.red)),
          ]),
        ),
      ],
    ).then((value) {
      if (value == 'edit') {
        _showEditBuildingDialog(building);
      } else if (value == 'delete') {
        _deleteBuilding(building, widget.organization);
      } else if (value == 'rooms') {
        _navigateToBuildingRooms(building);
      }
    });
  }

  void _navigateToBuildingRooms(Building building) {
    Navigator.pushNamed(
      context,
      '/building-rooms',
      arguments: {
        'building': building,
        'organization': widget.organization,
      },
    );
  }

  // ========================================
  // PAYMENTS TAB
  // ========================================
  Widget _buildPaymentsTab() {
    final t = AppTranslations.of(context);
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
                    const Icon(Icons.receipt_long_outlined,
                        size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      t['no_payments'],
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    if (isAdmin)
                      ElevatedButton.icon(
                        onPressed: _showAddPaymentDialog,
                        icon: const Icon(Icons.add),
                        label: Text(t['add_payment']),
                      ),
                  ],
                ),
              );
            },
          );
        }

        final sortedPayments = List<Payment>.from(allPayments)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        return FutureBuilder<Membership?>(
          future: _getMyMembership(),
          builder: (context, membershipSnapshot) {
            final isAdmin = membershipSnapshot.hasData &&
                membershipSnapshot.data!.role == 'admin';
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _searchController,
                    builder: (context, value, child) {
                      return Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              maxLength: 100,
                              decoration: InputDecoration(
                                counterText: '',
                                hintText: t['search_payments_hint'],
                                prefixIcon:
                                    const Icon(Icons.search),
                                suffixIcon: value.text.isNotEmpty
                                    ? IconButton(
                                        icon:
                                            const Icon(Icons.clear),
                                        onPressed: () =>
                                            _searchController
                                                .clear(),
                                      )
                                    : null,
                                border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (isAdmin)
                            ElevatedButton.icon(
                              onPressed: _showAddPaymentDialog,
                              icon: const Icon(Icons.add),
                              label: Text(t['add']),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _searchController,
                      builder: (context, value, child) {
                        return _buildPaymentsList(
                            sortedPayments, value.text, isAdmin);
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

  Widget _buildPaymentsList(
      List<Payment> allPayments, String searchText, bool isAdmin) {
    final t = AppTranslations.of(context);
    final searchTerm = searchText.toLowerCase();
    final filteredPayments = allPayments.where((payment) {
      if (searchTerm.isEmpty) return true;
      if ((payment.tenantName?.toLowerCase() ?? '')
          .contains(searchTerm)) return true;
      if (payment.totalAmount.toString().contains(searchTerm))
        return true;
      if (payment
          .getTypeDisplayName()
          .toLowerCase()
          .contains(searchTerm)) return true;
      final description = payment.description;
      if (description != null && description.contains('\n')) {
        if (description.toLowerCase().contains(searchTerm))
          return true;
      }
      return false;
    }).toList();

    if (filteredPayments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              searchTerm.isEmpty
                  ? Icons.receipt_long_outlined
                  : Icons.search_off,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              searchTerm.isEmpty
                  ? t['no_payments']
                  : t['no_payments_found'],
              style:
                  TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (searchTerm.isNotEmpty) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 0, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Text(
                  t.textWithParams('found_count_payments',
                      {'count': filteredPayments.length}),
                  style: TextStyle(
                      color: Colors.grey.shade600, fontSize: 14),
                ),
              ],
            ),
          ),
          Expanded(
              child: _buildPaymentsListView(
                  filteredPayments, isAdmin)),
        ],
      );
    }

    return _buildPaymentsListView(filteredPayments, isAdmin);
  }

  String _getPaymentTitle(Payment payment) {
    final t = AppTranslations.of(context);
    final typeKeys = {
      'rent': 'payment_type_rent',
      'electricity': 'payment_type_electricity',
      'water': 'payment_type_water',
      'internet': 'payment_type_internet',
      'parking': 'payment_type_parking',
      'maintenance': 'payment_type_maintenance',
      'deposit': 'payment_type_deposit',
      'penalty': 'payment_type_penalty',
      'other': 'payment_type_other',
    };

    final description = payment.description;
    if (description != null && description.contains('\n')) {
      final lines = description
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      final firstMatch =
          RegExp(r'^([^:]+):').firstMatch(lines.first.trim());
      final firstLabel = firstMatch?.group(1)?.trim();
      if (firstLabel != null && lines.length > 1) {
        return '$firstLabel...';
      }
    }

    final key = typeKeys[payment.type.name];
    return key != null ? t[key] : payment.getTypeDisplayName();
  }

  Widget _buildPaymentsListView(
      List<Payment> payments, bool isAdmin) {
    final t = AppTranslations.of(context);
    return ListView.builder(
      itemCount: payments.length,
      itemBuilder: (context, index) {
        final payment = payments[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getPaymentStatusColor(payment.status)
                  .withOpacity(0.2),
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
              _getPaymentTitle(payment),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('${t['tenant_label']}: ${payment.tenantName}'),
                const SizedBox(height: 2),
                Text(
                    '${t['amount_label']}: ${_formatCurrency(payment.totalAmount)}'),
                const SizedBox(height: 2),
                Text(
                    '${t['due_date_label']}: ${DateFormat('dd/MM/yyyy').format(payment.dueDate)}'),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getPaymentStatusColor(payment.status)
                        .withOpacity(0.1),
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
                    builder: (BuildContext ctx) {
                      return IconButton(
                        icon: const Icon(Icons.more_vert),
                        onPressed: () =>
                            _showPaymentMenu(ctx, payment, isAdmin),
                      );
                    },
                  )
                : IconButton(
                    icon: const Icon(Icons.info_outline),
                    onPressed: () =>
                        _showPaymentDetailsDialog(payment, isAdmin),
                  ),
          ),
        );
      },
    );
  }

  void _showPaymentMenu(
      BuildContext ctx, Payment payment, bool isAdmin) {
    final t = AppTranslations.of(context);
    final RenderBox button =
        ctx.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(ctx)
        .overlay!
        .context
        .findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay) +
            const Offset(0, 48),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    showMenu<String>(
      context: ctx,
      position: position,
      items: [
        PopupMenuItem(
          value: 'view',
          child: Row(children: [
            const Icon(Icons.visibility, size: 20),
            const SizedBox(width: 8),
            Text(t['view_details']),
          ]),
        ),
        PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            const Icon(Icons.edit, size: 20),
            const SizedBox(width: 8),
            Text(t['edit_payment']),
          ]),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            const Icon(Icons.delete, size: 20, color: Colors.red),
            const SizedBox(width: 8),
            Text(t['delete_payment'],
                style: const TextStyle(color: Colors.red)),
          ]),
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
        tenantService: _tenantService,
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
      if (result == true) {
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
        onDeleted: () =>
            _paymentsNotifier.refreshPayments(widget.organization.id),
      ),
    );
  }

  // ========================================
  // STATISTICS TAB
  // ========================================
  Widget _buildStatisticsTab() {
    final t = AppTranslations.of(context);
    return ListenableBuilder(
      listenable: _paymentsNotifier,
      builder: (context, _) {
        return FutureBuilder<List<dynamic>>(
          future: _statsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                snapshot.data == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData) {
              return Center(child: Text(t['stat_no_data']));
            }

            final tenants = snapshot.data![0] as List<Tenant>;
            final payments = _paymentsNotifier.payments;
            final buildings = snapshot.data![2] as List<Building>;
            final rooms = snapshot.data![3] as List<Room>;

            final activeTenants = tenants
                .where((tn) => tn.status == TenantStatus.active)
                .length;
            final totalPayments = payments.length;
            final paidPayments = payments
                .where((p) => p.status == PaymentStatus.paid)
                .length;
            final pendingPayments = payments
                .where((p) => p.status == PaymentStatus.pending)
                .length;
            final overduePayments =
                payments.where((p) => p.isOverdue).length;

            final totalRevenue =
                payments.fold<double>(0, (sum, p) {
              if (p.status == PaymentStatus.paid &&
                  p.paidAmount == 0) {
                return sum + p.totalWithAllFees;
              }
              return sum + p.paidAmount;
            });

            final pendingRevenue =
                payments.fold<double>(0, (sum, p) {
              if (p.status == PaymentStatus.paid ||
                  p.status == PaymentStatus.cancelled) {
                return sum;
              }
              return sum + p.remainingAmount;
            });

            final monthlyRevenue =
                _calculateMonthlyRevenue(payments);
            final buildingOccupancy =
                _calculateBuildingOccupancy(
                    buildings, rooms, tenants);

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t['stat_overview_title'],
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                          child: _buildStatCard(
                              t['stat_buildings'],
                              buildings.length.toString(),
                              Icons.apartment,
                              Colors.blue)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _buildStatCard(
                              t['stat_tenants'],
                              '$activeTenants',
                              Icons.people,
                              Colors.green)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                          child: _buildStatCard(
                              t['stat_paid'],
                              paidPayments.toString(),
                              Icons.check_circle,
                              Colors.green)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _buildStatCard(
                              t['stat_pending'],
                              pendingPayments.toString(),
                              Icons.pending,
                              Colors.orange)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                          child: _buildStatCard(
                              t['stat_overdue'],
                              overduePayments.toString(),
                              Icons.warning,
                              Colors.red)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _buildStatCard(
                              t['stat_total_payments'],
                              totalPayments.toString(),
                              Icons.receipt_long,
                              Colors.purple)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    t['stat_revenue_title'],
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.attach_money,
                                color: Colors.green.shade700),
                            const SizedBox(width: 8),
                            Text(t['stat_collected'],
                                style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey)),
                          ]),
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
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.schedule,
                                color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            Text(t['stat_uncollected'],
                                style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey)),
                          ]),
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
                  const SizedBox(height: 24),
                  Text(
                    t['stat_monthly_revenue'],
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _buildMonthlyRevenueChart(monthlyRevenue),
                  const SizedBox(height: 24),
                  Text(
                    t['stat_occupancy_by_building'],
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _buildBuildingOccupancyChart(
                      buildingOccupancy, buildings),
                  const SizedBox(height: 24),
                  Text(
                    t['stat_occupancy_trend'],
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _buildMonthlyOccupancyTrendChart(
                      buildings, rooms, tenants),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(
                              Icons.table_chart_outlined,
                              size: 20),
                          label: Text(t['export_excel']),
                          onPressed: () =>
                              _exportStatisticsToExcel(
                            buildings: buildings,
                            tenants: tenants,
                            rooms: rooms,
                            payments: payments,
                            organizationName:
                                widget.organization.name,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(
                              Icons.picture_as_pdf_outlined,
                              size: 20),
                          label: Text(t['export_pdf']),
                          onPressed: () =>
                              _exportStatisticsToPdf(
                            buildings: buildings,
                            tenants: tenants,
                            rooms: rooms,
                            payments: payments,
                            organizationName:
                                widget.organization.name,
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
      },
    );
  }

  // ========================================
  // PDF EXPORT
  // ========================================
  Future<void> _exportStatisticsToPdf({
    required List<Building> buildings,
    required List<Tenant> tenants,
    required List<Room> rooms,
    required List<Payment> payments,
    String? organizationName,
  }) async {
    final t = AppTranslations.of(context);
    final ttf = await PdfFontService.getFont();

    if (mounted) {
      _showTrackedDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      final currencyFormatter = NumberFormat.currency(
          locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
      final dateFormatter =
          DateFormat('dd/MM/yyyy – HH:mm');

      final totalBuildings = buildings.length;
      final totalRooms = rooms.length;
      final activeTenants = tenants
          .where((tn) => tn.status == TenantStatus.active)
          .length;
      final inactiveTenants = tenants
          .where((tn) => tn.status == TenantStatus.inactive)
          .length;
      final movedOutTenants = tenants
          .where((tn) => tn.status == TenantStatus.moveOut)
          .length;
      final suspendedTenants = tenants
          .where((tn) => tn.status == TenantStatus.suspended)
          .length;

      final paidPaymentsList =
          payments.where((p) => p.status == PaymentStatus.paid).toList();
      final pendingPaymentsList = payments
          .where((p) => p.status == PaymentStatus.pending)
          .toList();
      final overduePaymentsList =
          payments.where((p) => p.isOverdue).toList();
      final cancelledPaymentsList = payments
          .where((p) => p.status == PaymentStatus.cancelled)
          .toList();

      final totalRevenue =
          paidPaymentsList.fold<double>(0, (sum, p) {
        if (p.status == PaymentStatus.paid) {
          return sum +
              (p.paidAmount > 0 ? p.paidAmount : p.totalAmount);
        }
        return sum + p.paidAmount;
      });
      final pendingRevenue =
          payments.fold<double>(0, (sum, p) {
        if (p.status == PaymentStatus.paid ||
            p.status == PaymentStatus.cancelled) return sum;
        return sum + p.remainingAmount;
      });
      final overdueRevenue =
          payments.fold<double>(0, (sum, p) {
        if (p.status == PaymentStatus.paid ||
            p.status == PaymentStatus.cancelled) return sum;
        if (p.status == PaymentStatus.overdue) {
          return sum + p.remainingAmount;
        }
        return sum;
      });

      final monthlyRevenue = _calculateMonthlyRevenue(payments);

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
      for (final tn in tenants) {
        if (tn.buildingId.isEmpty) continue;
        if (tn.status == TenantStatus.active) {
          final s = statsByBuilding[tn.buildingId];
          if (s != null) s.occupiedRooms += 1;
        }
      }
      for (final pmt in paidPaymentsList) {
        if (pmt.buildingId.isNotEmpty) {
          final s = statsByBuilding[pmt.buildingId];
          if (s != null) s.revenue += pmt.paidAmount;
        } else if (pmt.roomId.isNotEmpty) {
          final room = rooms.firstWhere(
            (r) => r.id == pmt.roomId,
            orElse: () => Room(
              id: '',
              area: 0.0,
              roomType: '',
              organizationId: '',
              buildingId: '',
              roomNumber: '',
              createdAt: DateTime.now(),
            ),
          );
          if (room.id.isNotEmpty) {
            final s = statsByBuilding[room.buildingId];
            if (s != null) s.revenue += pmt.paidAmount;
          }
        }
      }

      final List<List<String>> buildingTableRows = [];
      int grandTotalRooms = 0;
      int grandOccupied = 0;
      double grandRevenue = 0.0;

      for (final s in statsByBuilding.values) {
        final emptyRooms =
            (s.totalRooms - s.occupiedRooms).clamp(0, s.totalRooms);
        final occupancyRate = s.totalRooms > 0
            ? ((s.occupiedRooms / s.totalRooms) * 100)
                .toStringAsFixed(1)
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

      // ── Styles ──────────────────────────────────────────────────────────
      final pdf = pw.Document();
      final titleStyle = pw.TextStyle(
          font: ttf, fontSize: 18, fontWeight: pw.FontWeight.bold);
      final heading1Style = pw.TextStyle(
          font: ttf, fontSize: 14, fontWeight: pw.FontWeight.bold);
      final heading2Style = pw.TextStyle(
          font: ttf, fontSize: 12, fontWeight: pw.FontWeight.bold);
      final baseTextStyle = pw.TextStyle(font: ttf, fontSize: 10);
      final smallTextStyle =
          pw.TextStyle(font: ttf, fontSize: 9);
      final smallGrey = pw.TextStyle(
          font: ttf, fontSize: 9, color: PdfColors.grey600);
      final boldTextStyle = pw.TextStyle(
          font: ttf, fontSize: 10, fontWeight: pw.FontWeight.bold);

      pw.Widget buildStatBox(String label, String value,
          {PdfColor color = PdfColors.blue}) {
        return pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: color.shade(0.1),
            borderRadius:
                const pw.BorderRadius.all(pw.Radius.circular(8)),
            border: pw.Border.all(color: color, width: 1),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label,
                  style: pw.TextStyle(
                      font: ttf,
                      fontSize: 9,
                      color: PdfColors.grey700)),
              pw.SizedBox(height: 4),
              pw.Text(value,
                  style: pw.TextStyle(
                      font: ttf,
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: color)),
            ],
          ),
        );
      }

      // ── Page 1: Executive Summary ────────────────────────────────────────
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment:
                      pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment:
                          pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(organizationName ?? '',
                            style: titleStyle),
                        pw.SizedBox(height: 4),
                        pw.Text(t['pdf_report_title'],
                            style: heading1Style),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          t.textWithParams('pdf_created_at', {
                            'date': dateFormatter
                                .format(DateTime.now())
                          }),
                          style: smallGrey,
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 24),
                pw.Divider(thickness: 2),
                pw.SizedBox(height: 24),
                pw.Text(t['pdf_section_overview'],
                    style: heading1Style),
                pw.SizedBox(height: 16),
                pw.Row(
                  children: [
                    pw.Expanded(
                        child: buildStatBox(
                            t['pdf_total_buildings'],
                            totalBuildings.toString(),
                            color: PdfColors.blue)),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                        child: buildStatBox(t['pdf_total_rooms'],
                            totalRooms.toString(),
                            color: PdfColors.teal)),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                        child: buildStatBox(
                            t['pdf_active_tenants'],
                            activeTenants.toString(),
                            color: PdfColors.green)),
                  ],
                ),
                pw.SizedBox(height: 12),
                pw.Row(
                  children: [
                    pw.Expanded(
                        child: buildStatBox(
                            t['pdf_occupancy_rate'],
                            totalRooms > 0
                                ? '${((activeTenants / totalRooms) * 100).toStringAsFixed(1)}%'
                                : '0%',
                            color: PdfColors.purple)),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                        child: buildStatBox(
                            t['pdf_empty_rooms'],
                            '${totalRooms - activeTenants}',
                            color: PdfColors.orange)),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                        child: buildStatBox(t['pdf_moved_out'],
                            movedOutTenants.toString(),
                            color: PdfColors.grey)),
                  ],
                ),
                pw.SizedBox(height: 24),
                pw.Text(t['pdf_section_tenant_status'],
                    style: heading1Style),
                pw.SizedBox(height: 12),
                pw.TableHelper.fromTextArray(
                  headers: [
                    t['pdf_tenant_col_status'],
                    t['pdf_tenant_col_count'],
                    t['pdf_tenant_col_rate'],
                  ],
                  data: [
                    [
                      t['pdf_tenant_status_active'],
                      activeTenants.toString(),
                      tenants.isNotEmpty
                          ? '${((activeTenants / tenants.length) * 100).toStringAsFixed(1)}%'
                          : '0%'
                    ],
                    [
                      t['pdf_tenant_status_inactive'],
                      inactiveTenants.toString(),
                      tenants.isNotEmpty
                          ? '${((inactiveTenants / tenants.length) * 100).toStringAsFixed(1)}%'
                          : '0%'
                    ],
                    [
                      t['pdf_tenant_status_moved'],
                      movedOutTenants.toString(),
                      tenants.isNotEmpty
                          ? '${((movedOutTenants / tenants.length) * 100).toStringAsFixed(1)}%'
                          : '0%'
                    ],
                    [
                      t['pdf_tenant_status_suspended'],
                      suspendedTenants.toString(),
                      tenants.isNotEmpty
                          ? '${((suspendedTenants / tenants.length) * 100).toStringAsFixed(1)}%'
                          : '0%'
                    ],
                    [
                      t['pdf_tenant_status_total'],
                      tenants.length.toString(),
                      '100%'
                    ],
                  ],
                  headerStyle: pw.TextStyle(
                      font: ttf,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10),
                  headerDecoration: const pw.BoxDecoration(
                      color: PdfColors.blue50),
                  cellStyle: baseTextStyle,
                  cellAlignment: pw.Alignment.centerLeft,
                  columnWidths: {
                    0: const pw.FlexColumnWidth(3),
                    1: const pw.FlexColumnWidth(2),
                    2: const pw.FlexColumnWidth(2),
                  },
                  border:
                      pw.TableBorder.all(color: PdfColors.grey300),
                ),
                pw.SizedBox(height: 24),
                pw.Text(t['pdf_section_payment_summary'],
                    style: heading1Style),
                pw.SizedBox(height: 12),
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(16),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.green50,
                          borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(8)),
                          border: pw.Border.all(
                              color: PdfColors.green, width: 2),
                        ),
                        child: pw.Column(
                          crossAxisAlignment:
                              pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(t['pdf_collected'],
                                style: heading2Style.copyWith(
                                    color: PdfColors.green)),
                            pw.SizedBox(height: 8),
                            pw.Text(
                                currencyFormatter
                                    .format(totalRevenue),
                                style: pw.TextStyle(
                                    font: ttf,
                                    fontSize: 16,
                                    fontWeight:
                                        pw.FontWeight.bold,
                                    color: PdfColors.green)),
                            pw.SizedBox(height: 4),
                            pw.Text(
                                t.textWithParams('pdf_invoices', {
                                  'count':
                                      paidPaymentsList.length
                                }),
                                style: smallTextStyle.copyWith(
                                    color: PdfColors.grey700)),
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
                          borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(8)),
                          border: pw.Border.all(
                              color: PdfColors.orange, width: 2),
                        ),
                        child: pw.Column(
                          crossAxisAlignment:
                              pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(t['pdf_uncollected'],
                                style: heading2Style.copyWith(
                                    color: PdfColors.orange)),
                            pw.SizedBox(height: 8),
                            pw.Text(
                                currencyFormatter
                                    .format(pendingRevenue),
                                style: pw.TextStyle(
                                    font: ttf,
                                    fontSize: 16,
                                    fontWeight:
                                        pw.FontWeight.bold,
                                    color: PdfColors.orange)),
                            pw.SizedBox(height: 4),
                            pw.Text(
                                t.textWithParams('pdf_invoices', {
                                  'count':
                                      pendingPaymentsList.length
                                }),
                                style: smallTextStyle.copyWith(
                                    color: PdfColors.grey700)),
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
                          borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(8)),
                          border: pw.Border.all(
                              color: PdfColors.red, width: 2),
                        ),
                        child: pw.Column(
                          crossAxisAlignment:
                              pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(t['pdf_overdue'],
                                style: heading2Style.copyWith(
                                    color: PdfColors.red)),
                            pw.SizedBox(height: 8),
                            pw.Text(
                                currencyFormatter
                                    .format(overdueRevenue),
                                style: pw.TextStyle(
                                    font: ttf,
                                    fontSize: 16,
                                    fontWeight:
                                        pw.FontWeight.bold,
                                    color: PdfColors.red)),
                            pw.SizedBox(height: 4),
                            pw.Text(
                                t.textWithParams('pdf_invoices', {
                                  'count':
                                      overduePaymentsList.length
                                }),
                                style: smallTextStyle.copyWith(
                                    color: PdfColors.grey700)),
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
                          borderRadius: const pw.BorderRadius.all(
                              pw.Radius.circular(8)),
                          border: pw.Border.all(
                              color: PdfColors.grey, width: 1),
                        ),
                        child: pw.Column(
                          crossAxisAlignment:
                              pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(t['pdf_cancelled'],
                                style: heading2Style.copyWith(
                                    color: PdfColors.grey)),
                            pw.SizedBox(height: 8),
                            pw.Text(
                                '${cancelledPaymentsList.length}',
                                style: pw.TextStyle(
                                    font: ttf,
                                    fontSize: 16,
                                    fontWeight:
                                        pw.FontWeight.bold,
                                    color: PdfColors.grey)),
                            pw.SizedBox(height: 4),
                            pw.Text(
                                t.textWithParams('pdf_invoices', {
                                  'count': cancelledPaymentsList
                                      .length
                                }),
                                style: smallTextStyle.copyWith(
                                    color: PdfColors.grey700)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                pw.Spacer(),
                pw.Divider(),
                pw.Row(
                  mainAxisAlignment:
                      pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(t['pdf_auto_generated'],
                        style: smallGrey),
                    pw.Text(
                        t.textWithParams(
                            'pdf_page', {'n': '1'}),
                        style: smallGrey),
                  ],
                ),
              ],
            );
          },
        ),
      );

      // ── Page 2: Building Details ─────────────────────────────────────────
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment:
                      pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(t['pdf_building_detail_title'],
                        style: heading1Style),
                    pw.Text(
                        t.textWithParams(
                            'pdf_page', {'n': '2'}),
                        style: smallGrey),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Divider(thickness: 2),
                pw.SizedBox(height: 20),
                if (buildingTableRows.isEmpty)
                  pw.Center(
                    child: pw.Text(t['pdf_no_building_data'],
                        style: pw.TextStyle(
                            fontSize: 12,
                            color: PdfColors.grey600)),
                  )
                else ...[
                  pw.Table.fromTextArray(
                    headers: [
                      t['pdf_building_col_name'],
                      t['pdf_building_col_total'],
                      t['pdf_building_col_occupied'],
                      t['pdf_building_col_empty'],
                      t['pdf_building_col_rate'],
                      t['pdf_building_col_revenue'],
                    ],
                    data: buildingTableRows,
                    headerStyle: pw.TextStyle(
                        font: ttf,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10),
                    headerDecoration: const pw.BoxDecoration(
                        color: PdfColors.blue50),
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
                    border: pw.TableBorder.all(
                        color: PdfColors.grey300),
                    cellPadding:
                        const pw.EdgeInsets.all(8),
                  ),
                  pw.SizedBox(height: 16),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.blue50,
                      borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(8)),
                    ),
                    child: pw.Row(
                      mainAxisAlignment:
                          pw.MainAxisAlignment.end,
                      children: [
                        pw.Column(
                          crossAxisAlignment:
                              pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text(
                                '${t['pdf_building_grand_total']}: ${statsByBuilding.length}',
                                style: boldTextStyle),
                            pw.Text(
                                '${t['pdf_building_col_total']}: $grandTotalRooms',
                                style: boldTextStyle),
                            pw.Text(
                                '${t['pdf_building_col_occupied']}: $grandOccupied',
                                style: boldTextStyle),
                            pw.Text(
                              '${t['pdf_building_col_revenue']}: ${currencyFormatter.format(grandRevenue)}',
                              style: pw.TextStyle(
                                  font: ttf,
                                  fontSize: 12,
                                  fontWeight:
                                      pw.FontWeight.bold,
                                  color: PdfColors.green),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                pw.Spacer(),
                pw.Divider(),
                pw.Row(
                  mainAxisAlignment:
                      pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(t['pdf_auto_generated'],
                        style: smallGrey),
                    pw.Text(
                        t.textWithParams(
                            'pdf_page', {'n': '2'}),
                        style: smallGrey),
                  ],
                ),
              ],
            );
          },
        ),
      );

      // ── Page 3: Revenue Analysis ─────────────────────────────────────────
      if (monthlyRevenue.isNotEmpty) {
        final validRevenues = monthlyRevenue.values
            .where((v) => v.isFinite && !v.isNaN)
            .toList();
        if (validRevenues.isNotEmpty) {
          pdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(40),
              build: (context) {
                final maxRevenue =
                    validRevenues.reduce((a, b) => a > b ? a : b);
                final safeMaxRevenue =
                    maxRevenue > 0 ? maxRevenue : 1.0;
                return pw.Column(
                  crossAxisAlignment:
                      pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment:
                          pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(t['pdf_revenue_title'],
                            style: heading1Style),
                        pw.Text(
                            t.textWithParams(
                                'pdf_page', {'n': '3'}),
                            style: smallGrey),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Divider(thickness: 2),
                    pw.SizedBox(height: 20),
                    pw.Text(t['pdf_revenue_6months'],
                        style: heading2Style),
                    pw.SizedBox(height: 16),
                    pw.Container(
                      height: 250,
                      padding: const pw.EdgeInsets.all(16),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(
                            color: PdfColors.grey300),
                        borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(8)),
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
                              final dv = v.toDouble();
                              return dv.isFinite && !dv.isNaN
                                  ? _formatCurrencyShort(dv)
                                  : '0';
                            },
                            divisions: true,
                            textStyle: smallTextStyle,
                          ),
                        ),
                        datasets: [
                          pw.BarDataSet(
                            color: PdfColors.green,
                            legend: t['pdf_revenue_col_amount'],
                            width: 20,
                            data:
                                monthlyRevenue.entries.map((e) {
                              final val = e.value.isFinite &&
                                      !e.value.isNaN
                                  ? e.value
                                  : 0.0;
                              return pw.PointChartValue(0, val);
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 24),
                    pw.Text(t['pdf_revenue_detail'],
                        style: heading2Style),
                    pw.SizedBox(height: 12),
                    pw.TableHelper.fromTextArray(
                      headers: [
                        t['pdf_revenue_col_month'],
                        t['pdf_revenue_col_amount'],
                        t['pdf_revenue_col_rate'],
                      ],
                      data: monthlyRevenue.entries.map((e) {
                        final rv = e.value.isFinite &&
                                !e.value.isNaN
                            ? e.value
                            : 0.0;
                        final pct = totalRevenue > 0
                            ? ((rv / totalRevenue) * 100)
                                .toStringAsFixed(1)
                            : '0.0';
                        return [
                          e.key,
                          currencyFormatter.format(rv),
                          '$pct%',
                        ];
                      }).toList(),
                      headerStyle: pw.TextStyle(
                          font: ttf,
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 10),
                      headerDecoration:
                          const pw.BoxDecoration(
                              color: PdfColors.green50),
                      cellStyle: baseTextStyle,
                      cellAlignment: pw.Alignment.centerLeft,
                      columnWidths: {
                        0: const pw.FlexColumnWidth(2),
                        1: const pw.FlexColumnWidth(3),
                        2: const pw.FlexColumnWidth(2),
                      },
                      border: pw.TableBorder.all(
                          color: PdfColors.grey300),
                    ),
                    pw.Spacer(),
                    pw.Divider(),
                    pw.Row(
                      mainAxisAlignment:
                          pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(t['pdf_auto_generated'],
                            style: smallGrey),
                        pw.Text(
                            t.textWithParams(
                                'pdf_page', {'n': '3'}),
                            style: smallGrey),
                      ],
                    ),
                  ],
                );
              },
            ),
          );
        }
      }

      final pdfBytes = await pdf.save();
      if (mounted) Navigator.of(context).pop();

      if (Platform.isWindows) {
        final file = await getSaveLocation(
          suggestedName:
              'statistics_${DateTime.now().millisecondsSinceEpoch}.pdf',
          acceptedTypeGroups: [
            const XTypeGroup(
                label: 'PDF', extensions: ['pdf'])
          ],
        );
        if (file == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(t['export_cancelled'])),
            );
          }
          return;
        }
        await File(file.path).writeAsBytes(pdfBytes);
        await Process.run('explorer', [file.path]);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t.textWithParams('export_pdf_saved',
                {'filename': p.basename(file.path)})),
          ));
        }
      } else {
        await Printing.layoutPdf(
            onLayout: (_) async => pdfBytes);
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t.textWithParams(
              'export_pdf_error', {'error': e})),
        ));
      }
    }
  }

  // ========================================
  // EXCEL EXPORT
  // ========================================
  Future<void> _exportStatisticsToExcel({
    required List<Building> buildings,
    required List<Tenant> tenants,
    required List<Room> rooms,
    required List<Payment> payments,
    String? organizationName,
  }) async {
    final t = AppTranslations.of(context);
    if (mounted) {
      _showTrackedDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      final currencyFormat = '#,##0 "₫"';
      final dateFormatter =
          DateFormat('dd/MM/yyyy – HH:mm');

      final activeTenants = tenants
          .where((tn) => tn.status == TenantStatus.active)
          .length;
      final inactiveTenants = tenants
          .where((tn) => tn.status == TenantStatus.inactive)
          .length;
      final movedOutTenants = tenants
          .where((tn) => tn.status == TenantStatus.moveOut)
          .length;
      final suspendedTenants = tenants
          .where((tn) => tn.status == TenantStatus.suspended)
          .length;
      final totalRooms = rooms.length;

      final paidPaymentsList =
          payments.where((p) => p.status == PaymentStatus.paid).toList();
      final pendingPaymentsList = payments
          .where((p) => p.status == PaymentStatus.pending)
          .toList();
      final overduePaymentsList =
          payments.where((p) => p.isOverdue).toList();
      final cancelledPaymentsList = payments
          .where((p) => p.status == PaymentStatus.cancelled)
          .toList();

      final totalRevenue =
          payments.fold<double>(0, (sum, p) {
        if (p.status == PaymentStatus.paid) {
          return sum +
              (p.paidAmount > 0
                  ? p.paidAmount
                  : p.totalWithAllFees);
        }
        return sum + p.paidAmount;
      });
      final pendingRevenue =
          payments.fold<double>(0, (sum, p) {
        return sum +
            (p.status != PaymentStatus.paid &&
                    p.status != PaymentStatus.cancelled
                ? p.remainingAmount
                : 0);
      });
      final overdueRevenue =
          payments.fold<double>(0, (sum, p) {
        if (p.status == PaymentStatus.paid ||
            p.status == PaymentStatus.cancelled) return sum;
        if (p.status == PaymentStatus.overdue) {
          return sum + p.remainingAmount;
        }
        return sum;
      });

      final xlsio.Workbook workbook = xlsio.Workbook();

      // ── Sheet 1: Summary ──────────────────────────────────────────────────
      final xlsio.Worksheet summarySheet =
          workbook.worksheets[0];
      summarySheet.name = t['excel_sheet_summary'];
      int rowIdx = 1;

      xlsio.Range range = summarySheet
          .getRangeByIndex(rowIdx, 1, rowIdx, 6);
      range.merge();
      range.setText(organizationName ?? '');
      range.cellStyle.bold = true;
      range.cellStyle.fontSize = 16;
      rowIdx++;

      range = summarySheet
          .getRangeByIndex(rowIdx, 1, rowIdx, 6);
      range.merge();
      range.setText(t['excel_summary_title']);
      range.cellStyle.bold = true;
      range.cellStyle.fontSize = 14;
      rowIdx++;

      summarySheet
          .getRangeByIndex(rowIdx, 1)
          .setText(t.textWithParams('excel_created_at', {
            'date': dateFormatter.format(DateTime.now())
          }));
      rowIdx += 2;

      summarySheet.getRangeByIndex(rowIdx, 1).setText('1. ${t['stat_overview_title']}');
      summarySheet
          .getRangeByIndex(rowIdx, 1)
          .cellStyle
          .bold = true;
      rowIdx += 2;

      void writeStatRow(int r, String label1, dynamic val1,
          String label2, dynamic val2) {
        summarySheet.getRangeByIndex(r, 1).setText(label1);
        summarySheet
            .getRangeByIndex(r, 1)
            .cellStyle
            .bold = true;
        summarySheet.getRangeByIndex(r, 2).setValue(val1);
        summarySheet.getRangeByIndex(r, 3).setText(label2);
        summarySheet
            .getRangeByIndex(r, 3)
            .cellStyle
            .bold = true;
        summarySheet.getRangeByIndex(r, 4).setValue(val2);
      }

      writeStatRow(rowIdx++, t['excel_stat_buildings'],
          buildings.length, t['excel_stat_rooms'], totalRooms);
      writeStatRow(
          rowIdx++,
          t['excel_stat_rented'],
          activeTenants,
          t['excel_stat_occupancy'],
          totalRooms > 0
              ? '${((activeTenants / totalRooms) * 100).toStringAsFixed(1)}%'
              : '0%');
      writeStatRow(
          rowIdx++,
          t['excel_stat_empty'],
          totalRooms - activeTenants,
          t['excel_stat_moved_out'],
          movedOutTenants);
      rowIdx += 2;

      summarySheet
          .getRangeByIndex(rowIdx, 1)
          .setText('2. ${t['pdf_section_tenant_status']}');
      summarySheet
          .getRangeByIndex(rowIdx, 1)
          .cellStyle
          .bold = true;
      rowIdx++;

      final List<String> tHeaders = [
        t['pdf_tenant_col_status'],
        t['pdf_tenant_col_count'],
        t['pdf_tenant_col_rate'],
      ];
      for (int i = 0; i < tHeaders.length; i++) {
        xlsio.Range header =
            summarySheet.getRangeByIndex(rowIdx, i + 1);
        header.setText(tHeaders[i]);
        header.cellStyle.bold = true;
        header.cellStyle.backColor = '#0099FF';
        header.cellStyle.fontColor = '#FFFFFF';
      }
      rowIdx++;

      final tenantStatusData = [
        [
          t['pdf_tenant_status_active'],
          activeTenants,
          tenants.isNotEmpty
              ? '${((activeTenants / tenants.length) * 100).toStringAsFixed(1)}%'
              : '0%'
        ],
        [
          t['pdf_tenant_status_inactive'],
          inactiveTenants,
          tenants.isNotEmpty
              ? '${((inactiveTenants / tenants.length) * 100).toStringAsFixed(1)}%'
              : '0%'
        ],
        [
          t['pdf_tenant_status_moved'],
          movedOutTenants,
          tenants.isNotEmpty
              ? '${((movedOutTenants / tenants.length) * 100).toStringAsFixed(1)}%'
              : '0%'
        ],
        [
          t['pdf_tenant_status_suspended'],
          suspendedTenants,
          tenants.isNotEmpty
              ? '${((suspendedTenants / tenants.length) * 100).toStringAsFixed(1)}%'
              : '0%'
        ],
        [t['pdf_tenant_status_total'], tenants.length, '100%'],
      ];

      for (var data in tenantStatusData) {
        summarySheet
            .getRangeByIndex(rowIdx, 1)
            .setText(data[0].toString());
        summarySheet
            .getRangeByIndex(rowIdx, 2)
            .setNumber(double.parse(data[1].toString()));
        summarySheet
            .getRangeByIndex(rowIdx, 3)
            .setText(data[2].toString());
        if (data[0] == t['pdf_tenant_status_total']) {
          summarySheet
              .getRangeByIndex(rowIdx, 1, rowIdx, 3)
              .cellStyle
              .bold = true;
        }
        rowIdx++;
      }
      rowIdx += 2;

      summarySheet
          .getRangeByIndex(rowIdx, 1)
          .setText('3. ${t['pdf_section_payment_summary']}');
      summarySheet
          .getRangeByIndex(rowIdx, 1)
          .cellStyle
          .bold = true;
      rowIdx++;

      void writeRevenueRow(int r, String label, double amount,
          String label2, int count) {
        summarySheet.getRangeByIndex(r, 1).setText(label);
        summarySheet
            .getRangeByIndex(r, 1)
            .cellStyle
            .bold = true;
        xlsio.Range valRange =
            summarySheet.getRangeByIndex(r, 2);
        valRange.setNumber(amount);
        valRange.numberFormat = currencyFormat;
        summarySheet.getRangeByIndex(r, 3).setText(label2);
        summarySheet
            .getRangeByIndex(r, 4)
            .setNumber(count.toDouble());
      }

      writeRevenueRow(rowIdx++, t['pdf_collected'],
          totalRevenue, t['pdf_invoices'].replaceAll('{{count}}', ''), paidPaymentsList.length);
      writeRevenueRow(rowIdx++, t['pdf_uncollected'],
          pendingRevenue, t['pdf_invoices'].replaceAll('{{count}}', ''), pendingPaymentsList.length);
      writeRevenueRow(rowIdx++, t['pdf_overdue'],
          overdueRevenue, t['pdf_invoices'].replaceAll('{{count}}', ''), overduePaymentsList.length);
      summarySheet
          .getRangeByIndex(rowIdx, 1)
          .setText(t['pdf_cancelled']);
      summarySheet
          .getRangeByIndex(rowIdx, 2)
          .setNumber(cancelledPaymentsList.length.toDouble());
      rowIdx++;

      // ── Sheet 2: Building Details ──────────────────────────────────────────
      final xlsio.Worksheet buildingSheet =
          workbook.worksheets.addWithName(t['excel_sheet_building']);
      int bRow = 1;
      buildingSheet
          .getRangeByIndex(bRow, 1)
          .setText(t['excel_building_title']);
      buildingSheet
          .getRangeByIndex(bRow, 1)
          .cellStyle
          .bold = true;
      buildingSheet
          .getRangeByIndex(bRow, 1)
          .cellStyle
          .fontSize = 14;
      bRow += 2;

      final List<String> bHeaders = [
        t['pdf_building_col_name'],
        t['pdf_building_col_total'],
        t['pdf_building_col_occupied'],
        t['pdf_building_col_empty'],
        t['pdf_building_col_rate'],
        t['pdf_building_col_revenue'],
      ];
      for (int i = 0; i < bHeaders.length; i++) {
        xlsio.Range header =
            buildingSheet.getRangeByIndex(bRow, i + 1);
        header.setText(bHeaders[i]);
        header.cellStyle.bold = true;
        header.cellStyle.backColor = '#0099FF';
        header.cellStyle.fontColor = '#FFFFFF';
      }
      bRow++;

      double grandRevenue = 0;
      int grandRooms = 0;
      int grandOccupied = 0;

      for (var b in buildings) {
        final bRooms =
            rooms.where((r) => r.buildingId == b.id).length;
        final bOccupied = rooms
            .where((r) =>
                r.buildingId == b.id &&
                tenants.any((tn) =>
                    tn.roomId == r.id &&
                    tn.status == TenantStatus.active))
            .length;
        final bRevenue = paidPaymentsList
            .where((p) => p.buildingId == b.id)
            .fold<double>(0, (s, p) => s + p.paidAmount);
        final rate = bRooms > 0
            ? (bOccupied / bRooms * 100).toStringAsFixed(1)
            : '0.0';

        buildingSheet.getRangeByIndex(bRow, 1).setText(b.name);
        buildingSheet
            .getRangeByIndex(bRow, 2)
            .setNumber(bRooms.toDouble());
        buildingSheet
            .getRangeByIndex(bRow, 3)
            .setNumber(bOccupied.toDouble());
        buildingSheet
            .getRangeByIndex(bRow, 4)
            .setNumber((bRooms - bOccupied).toDouble());
        buildingSheet
            .getRangeByIndex(bRow, 5)
            .setText('$rate%');
        xlsio.Range revRange =
            buildingSheet.getRangeByIndex(bRow, 6);
        revRange.setNumber(bRevenue);
        revRange.numberFormat = currencyFormat;

        grandRevenue += bRevenue;
        grandRooms += bRooms;
        grandOccupied += bOccupied;
        bRow++;
      }

      xlsio.Range totalLabel =
          buildingSheet.getRangeByIndex(bRow, 1);
      totalLabel.setText(t['excel_grand_total']);
      totalLabel.cellStyle.bold = true;
      buildingSheet
          .getRangeByIndex(bRow, 2)
          .setNumber(grandRooms.toDouble());
      buildingSheet
          .getRangeByIndex(bRow, 3)
          .setNumber(grandOccupied.toDouble());
      xlsio.Range gRevRange =
          buildingSheet.getRangeByIndex(bRow, 6);
      gRevRange.setNumber(grandRevenue);
      gRevRange.cellStyle.bold = true;
      gRevRange.numberFormat = currencyFormat;

      // ── Sheet 3: Payment Details ───────────────────────────────────────────
      final xlsio.Worksheet pSheet = workbook.worksheets
          .addWithName(t['excel_sheet_payments']);
      int pRow = 1;
      pSheet
          .getRangeByIndex(pRow, 1)
          .setText(t['excel_payments_title']);
      pSheet.getRangeByIndex(pRow, 1).cellStyle.bold = true;
      pRow += 2;

      final List<String> pHeaders = [
        t['excel_col_invoice_id'],
        t['excel_col_tenant'],
        t['excel_col_amount'],
        t['excel_col_status'],
        t['excel_col_paid_date'],
        t['excel_col_due_date'],
      ];
      for (int i = 0; i < pHeaders.length; i++) {
        xlsio.Range header =
            pSheet.getRangeByIndex(pRow, i + 1);
        header.setText(pHeaders[i]);
        header.cellStyle.bold = true;
        header.cellStyle.backColor = '#FF9900';
        header.cellStyle.fontColor = '#FFFFFF';
      }
      pRow++;

      final sortedPayments = List<Payment>.from(payments)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      for (var pm in sortedPayments) {
        pSheet.getRangeByIndex(pRow, 1).setText(pm.id);
        pSheet
            .getRangeByIndex(pRow, 2)
            .setText(pm.tenantName ?? '');
        xlsio.Range amtRange =
            pSheet.getRangeByIndex(pRow, 3);
        amtRange.setNumber(pm.totalAmount);
        amtRange.numberFormat = currencyFormat;
        pSheet
            .getRangeByIndex(pRow, 4)
            .setText(pm.getStatusDisplayName());
        pSheet.getRangeByIndex(pRow, 5).setText(pm.paidAt != null
            ? DateFormat('dd/MM/yyyy').format(pm.paidAt!)
            : '-');
        pSheet.getRangeByIndex(pRow, 6).setText(
            DateFormat('dd/MM/yyyy').format(pm.dueDate));
        pRow++;
      }

      // Auto-fit columns
      for (int i = 0; i < workbook.worksheets.count; i++) {
        for (int col = 1; col <= 10; col++) {
          workbook.worksheets[i].autoFitColumn(col);
        }
      }

      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      if (mounted) Navigator.of(context).pop();

      if (Platform.isWindows) {
        final fileLocation = await getSaveLocation(
          suggestedName:
              'statistics_${DateTime.now().millisecondsSinceEpoch}.xlsx',
          acceptedTypeGroups: [
            const XTypeGroup(
                label: 'Excel', extensions: ['xlsx'])
          ],
        );
        if (fileLocation == null) return;
        final file = File(fileLocation.path);
        await file.writeAsBytes(bytes);
        await Process.run('explorer', [fileLocation.path]);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t.textWithParams('export_excel_saved', {
              'filename': p.basename(fileLocation.path)
            })),
          ));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t['export_excel_success']),
          ));
        }
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      debugPrint('Excel Export Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t.textWithParams(
              'export_excel_error', {'error': e})),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  // ========================================
  // CHART HELPERS
  // ========================================
  Map<String, double> _calculateMonthlyRevenue(
      List<Payment> payments) {
    final Map<String, double> monthlyRevenue = {};
    final now = DateTime.now();
    for (int i = 5; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final monthKey = DateFormat('MM/yyyy').format(month);
      monthlyRevenue[monthKey] = 0;
    }
    for (var payment
        in payments.where((p) => p.status == PaymentStatus.paid)) {
      final dateToUse = payment.paidAt ?? payment.createdAt;
      final monthKey = DateFormat('MM/yyyy').format(dateToUse);
      if (monthlyRevenue.containsKey(monthKey)) {
        double amount = payment.paidAmount > 0
            ? payment.paidAmount
            : payment.totalWithAllFees;
        monthlyRevenue[monthKey] =
            (monthlyRevenue[monthKey] ?? 0) + amount;
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
    final Map<String, int> nameOccurrences = {};
    for (var b in buildings) {
      nameOccurrences[b.name] =
          (nameOccurrences[b.name] ?? 0) + 1;
    }
    final Map<String, int> nameCounters = {};
    for (var building in buildings) {
      final totalRoomsB =
          rooms.where((r) => r.buildingId == building.id).length;
      final occupiedRooms = rooms
          .where((r) => r.buildingId == building.id)
          .where((room) => tenants.any((tn) =>
              tn.roomId == room.id &&
              tn.status == TenantStatus.active))
          .length;
      final percentage = totalRoomsB > 0
          ? (occupiedRooms / totalRoomsB * 100)
          : 0.0;
      String displayName = building.name;
      if (nameOccurrences[building.name]! > 1) {
        nameCounters[building.name] =
            (nameCounters[building.name] ?? 0) + 1;
        displayName =
            '${building.name} (${nameCounters[building.name]})';
      }
      occupancy[building.id] = {
        'name': displayName,
        'occupied': occupiedRooms,
        'total': totalRoomsB,
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
    final buildingRooms =
        rooms.where((r) => r.buildingId == buildingId).toList();
    final totalRoomsB = buildingRooms.length;
    if (totalRoomsB == 0) return monthlyOccupancy;
    for (int i = 11; i >= 0; i--) {
      final monthDate =
          DateTime(now.year, now.month - i, 1);
      final monthEnd = DateTime(
          monthDate.year, monthDate.month + 1, 0);
      final monthKey =
          DateFormat('MM/yyyy').format(monthDate);
      final activeTenantsCount = tenants.where((tenant) {
        if (tenant.buildingId != buildingId) return false;
        final hasMovedIn = tenant.moveInDate
                .isBefore(monthEnd) ||
            tenant.moveInDate.isAtSameMomentAs(monthEnd);
        final isCurrentlyActive =
            tenant.status == TenantStatus.active;
        return hasMovedIn && isCurrentlyActive;
      }).length;
      monthlyOccupancy[monthKey] =
          (activeTenantsCount.toDouble() /
              totalRoomsB.toDouble() *
              100);
    }
    return monthlyOccupancy;
  }

  Widget _buildMonthlyRevenueChart(
      Map<String, double> monthlyRevenue) {
    final t = AppTranslations.of(context);
    if (monthlyRevenue.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(t['stat_no_revenue_data'],
                style: TextStyle(color: Colors.grey[600])),
          ),
        ),
      );
    }
    final maxRevenue =
        monthlyRevenue.values.reduce((a, b) => a > b ? a : b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          height: 200,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: monthlyRevenue.entries.map((entry) {
              final barHeight = maxRevenue > 0
                  ? (entry.value / maxRevenue * 150)
                      .clamp(5.0, 150.0)
                  : 5.0;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4),
                  child: Column(
                    mainAxisAlignment:
                        MainAxisAlignment.end,
                    children: [
                      Text(
                        _formatCurrencyShort(entry.value),
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold),
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
                          borderRadius:
                              const BorderRadius.vertical(
                                  top: Radius.circular(4)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        entry.key,
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildBuildingOccupancyChart(
    Map<String, Map<String, dynamic>> occupancy,
    List<Building> buildings,
  ) {
    final t = AppTranslations.of(context);
    if (occupancy.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(child: Text(t['stat_no_building_data'])),
        ),
      );
    }

    Map<String, Map<String, dynamic>> displayOccupancy;
    if (_selectedOccupancyBuildingId == null) {
      displayOccupancy = occupancy;
    } else {
      if (occupancy.containsKey(_selectedOccupancyBuildingId)) {
        displayOccupancy = {
          _selectedOccupancyBuildingId!:
              occupancy[_selectedOccupancyBuildingId]!
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
            Row(
              children: [
                Text(t['stat_filter_by_building'],
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    value: _selectedOccupancyBuildingId,
                    hint: Text(t['stat_all_buildings']),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child:
                            Text(t['stat_all_buildings']),
                      ),
                      ...buildings.map((building) {
                        return DropdownMenuItem<String?>(
                          value: building.id,
                          child: Text(building.name),
                        );
                      }),
                    ],
                    onChanged: (value) => setState(() =>
                        _selectedOccupancyBuildingId = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...displayOccupancy.entries.map((entry) {
              final data = entry.value;
              final String buildingName =
                  data['name'] ?? '';
              final percentage =
                  (data['percentage'] as num).toDouble();
              final occupied = data['occupied'] as int;
              final total = data['total'] as int;
              Color barColor = percentage >= 80
                  ? Colors.green
                  : (percentage >= 50
                      ? Colors.orange
                      : Colors.red);
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            buildingName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14),
                          ),
                        ),
                        Text(
                          '$occupied/$total (${percentage.toStringAsFixed(0)}%)',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: barColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius:
                          BorderRadius.circular(8),
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
    final t = AppTranslations.of(context);
    if (buildings.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(t['stat_no_building_data'],
                style: TextStyle(color: Colors.grey[600])),
          ),
        ),
      );
    }

    if (_selectedBuildingId == null ||
        !buildings.any((b) => b.id == _selectedBuildingId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() =>
              _selectedBuildingId = buildings.first.id);
        }
      });
      _selectedBuildingId = buildings.first.id;
    }

    final selectedBuilding = buildings.firstWhere(
      (b) => b.id == _selectedBuildingId,
      orElse: () => buildings.first,
    );

    final monthlyOccupancy = _calculateMonthlyOccupancyTrend(
        selectedBuilding.id, rooms, tenants);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(t['stat_select_building'],
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    hint: Text(t['stat_select_building']),
                    value: buildings.any(
                            (b) => b.id == _selectedBuildingId)
                        ? _selectedBuildingId
                        : null,
                    items: buildings.map((building) {
                      return DropdownMenuItem<String>(
                        value: building.id,
                        child: Text(building.name),
                      );
                    }).toList(),
                    onChanged: (value) => setState(
                        () => _selectedBuildingId = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (monthlyOccupancy.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Text(t['stat_no_building_selected'],
                      style:
                          TextStyle(color: Colors.grey[600])),
                ),
              )
            else
              SizedBox(
                height: 220,
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        t['stat_occupancy_rate'],
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.end,
                        children: monthlyOccupancy.entries
                            .map((entry) {
                          final occupancyRate = entry.value;
                          final barHeight =
                              (occupancyRate / 100 * 150)
                                  .clamp(5.0, 150.0);
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
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 2),
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.end,
                                children: [
                                  Text(
                                    '${occupancyRate.toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight:
                                            FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    height: barHeight,
                                    decoration: BoxDecoration(
                                      color: barColor,
                                      borderRadius:
                                          const BorderRadius
                                              .vertical(
                                              top: Radius
                                                  .circular(
                                                      4)),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    entry.key.split('/')[0],
                                    style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight:
                                            FontWeight.w500),
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

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
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
                  color: color),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, color: Colors.grey),
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
    final t = AppTranslations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<Membership?>(
            future: _getMyMembership(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();
              final membership = snapshot.data!;
              if (membership.role != 'admin')
                return const SizedBox();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed:
                            loadingInvite ? null : _loadInviteCode,
                        child: Text(t['get_invite_code']),
                      ),
                      if (inviteCode != null) ...[
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _refreshingCode
                              ? null
                              : () async {
                                  final confirm =
                                      await _showTrackedDialog<
                                          bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Text(t[
                                          'refresh_invite_code_title']),
                                      content: Text(t[
                                          'refresh_invite_code_body']),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(
                                                  ctx, false),
                                          child: Text(
                                              t['cancel']),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton
                                              .styleFrom(
                                            backgroundColor:
                                                Colors.orange,
                                            foregroundColor:
                                                Colors.white,
                                          ),
                                          onPressed: () =>
                                              Navigator.pop(
                                                  ctx, true),
                                          child: Text(
                                              t['refresh_action']),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm != true ||
                                      !mounted) return;

                                  setState(() =>
                                      _refreshingCode = true);
                                  try {
                                    final success = await _orgService
                                        .refreshInviteCode(
                                      membership.ownerId,
                                      widget.organization.id,
                                    );
                                    if (success && mounted) {
                                      await _loadInviteCode();
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                        content: Text(
                                            t['code_refreshed']),
                                        backgroundColor:
                                            Colors.green,
                                      ));
                                    } else if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                        content: Text(t[
                                            'cannot_refresh_code']),
                                        backgroundColor: Colors.red,
                                      ));
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() =>
                                          _refreshingCode = false);
                                    }
                                  }
                                },
                          icon: _refreshingCode
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.refresh,
                                  size: 18),
                          label: Text(t['refresh_code']),
                        ),
                      ],
                    ],
                  ),
                  if (inviteCode != null) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      '${t['invite_code_label']}: $inviteCode',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                  const Divider(height: 32),
                ],
              );
            },
          ),
          Text(
            t['members_title'],
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<Membership>>(
              future: _getMembers(),
              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator());
                }
                if (!snapshot.hasData ||
                    snapshot.data!.isEmpty) {
                  return Center(child: Text(t['no_members']));
                }
                final members = snapshot.data!;
                return ListView.builder(
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    final ownerName =
                        member.displayName.isNotEmpty
                            ? member.displayName
                            : member.email.isNotEmpty
                                ? member.email
                                : member.ownerId;
                    final roleText = member.role == 'admin'
                        ? t['member_role_admin']
                        : t['member_role_member'];
                    return Card(
                      margin:
                          const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              member.role == 'admin'
                                  ? Colors.orange
                                  : Colors.blue,
                          child: Icon(
                            member.role == 'admin'
                                ? Icons.admin_panel_settings
                                : Icons.person,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(ownerName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w500)),
                        subtitle: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
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
                            if (member.email.isNotEmpty)
                              Text(member.email,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey)),
                          ],
                        ),
                        trailing:
                            FutureBuilder<Membership?>(
                          future: _getMyMembership(),
                          builder: (context,
                              myMembershipSnapshot) {
                            if (!myMembershipSnapshot
                                .hasData) {
                              return member.status == 'active'
                                  ? const Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: 20)
                                  : const Icon(Icons.pending,
                                      color: Colors.orange,
                                      size: 20);
                            }
                            final myMembership =
                                myMembershipSnapshot.data!;
                            if (myMembership.role !=
                                'admin') {
                              return member.status == 'active'
                                  ? const Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: 20)
                                  : const Icon(Icons.pending,
                                      color: Colors.orange,
                                      size: 20);
                            }
                            if (member.ownerId ==
                                myMembership.ownerId) {
                              return const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 20);
                            }
                            return Builder(
                              builder: (BuildContext ctx) {
                                return IconButton(
                                  icon: const Icon(
                                      Icons.more_vert),
                                  onPressed: () =>
                                      _showMemberMenu(
                                          ctx,
                                          member,
                                          myMembership,
                                          ownerName),
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
            ),
          ),
        ],
      ),
    );
  }

  void _showMemberMenu(
    BuildContext ctx,
    Membership member,
    Membership myMembership,
    String ownerName,
  ) {
    final t = AppTranslations.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final RenderBox button =
        ctx.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(ctx)
        .overlay!
        .context
        .findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay) +
            const Offset(0, 48),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    showMenu<String>(
      context: ctx,
      position: position,
      items: [
        if (member.role == 'member')
          PopupMenuItem(
            value: 'promote',
            child: Row(children: [
              const Icon(Icons.arrow_upward, size: 20),
              const SizedBox(width: 8),
              Text(t['promote_to_admin']),
            ]),
          ),
        if (member.role == 'admin')
          PopupMenuItem(
            value: 'remove',
            child: Row(children: [
              const Icon(Icons.remove_circle,
                  size: 20, color: Colors.red),
              const SizedBox(width: 8),
              Text(t['remove_from_org'],
                  style:
                      const TextStyle(color: Colors.red)),
            ]),
          ),
      ],
    ).then((value) async {
      if (value == 'promote') {
        final success =
            await _orgService.promoteMemberToAdmin(
          currentAdminId: myMembership.ownerId,
          memberIdToPromote: member.ownerId,
          orgId: widget.organization.id,
        );
        if (success && mounted) {
          scaffoldMessenger.showSnackBar(SnackBar(
              content:
                  Text(t['member_promoted_success'])));
          setState(() {});
        }
      } else if (value == 'remove') {
        if (!mounted) return;
        final confirm =
            await _showTrackedDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t['member_remove_confirm_title']),
            content: Text(t.textWithParams(
                'member_remove_confirm_body',
                {'name': ownerName})),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, false),
                child: Text(t['cancel']),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, true),
                child: Text(t['delete'],
                    style: const TextStyle(
                        color: Colors.red)),
              ),
            ],
          ),
        );
        if (confirm == true) {
          final success =
              await _orgService.leaveOrganization(
            member.ownerId,
            widget.organization.id,
          );
          if (success && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text(t['member_removed_success'])),
            );
            setState(() {});
          }
        }
      }
    });
  }

  // ========================================
  // DATE FORMATTING
  // ========================================
  String _formatDate(DateTime date) {
    final locale = Localizations.localeOf(context).languageCode;
    final now = DateTime.now();
    final difference = now.difference(date);
    if (locale == 'vi') {
      if (difference.inDays == 0) return 'hôm nay';
      if (difference.inDays == 1) return 'hôm qua';
      if (difference.inDays < 7) {
        return '${difference.inDays} ngày trước';
      }
      if (difference.inDays < 30) {
        return '${(difference.inDays / 7).floor()} tuần trước';
      }
      if (difference.inDays < 365) {
        return '${(difference.inDays / 30).floor()} tháng trước';
      }
      return '${(difference.inDays / 365).floor()} năm trước';
    } else {
      if (difference.inDays == 0) return 'today';
      if (difference.inDays == 1) return 'yesterday';
      if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      }
      if (difference.inDays < 30) {
        return '${(difference.inDays / 7).floor()} weeks ago';
      }
      if (difference.inDays < 365) {
        return '${(difference.inDays / 30).floor()} months ago';
      }
      return '${(difference.inDays / 365).floor()} years ago';
    }
  }
}

// ============================================================
// BUILDING STATS HELPER
// ============================================================
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