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
import 'package:intl/intl.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

final Color kPrimaryColor = const Color(0xFF4F46E5); // Modern Indigo
final Color kBgColor = const Color(0xFFF8FAFC);      // Soft Slate background
final Color kSurfaceColor = Colors.white;

const List<Color> _buildingColors = [
  Color(0xFF185FA5), // blue
  Color(0xFF0F6E56), // teal
  Color(0xFF854F0B), // amber
  Color(0xFF534AB7), // purple
  Color(0xFF993556), // pink
];

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

class _StableTab extends StatefulWidget {
  final Widget Function(BuildContext context) builder;
  const _StableTab({required this.builder, required super.key});
  @override
  State<_StableTab> createState() => _StableTabState();
}

class _StableTabState extends State<_StableTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // ← keeps state alive when tab is not visible

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    return widget.builder(context);
  }
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

  int _tenantTabRefreshKey = 0;

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
  // Cache per-building futures to avoid recreation on rebuild
  final Map<String, Future<List<dynamic>>> _buildingCardFutures = {};
  Future<List<dynamic>>? _summaryBarFuture;
  Future<List<Building>>? _buildingsFuture;
  Future<Membership?>? _membershipFuture;
  Future<List<dynamic>>? _membersTabFuture;
  PaymentStatus? _paymentStatusFilter;

  void _refreshAll() {
    if (!mounted) return;
    setState(() {
      _buildingsFuture = _getBuildings();
      _membershipFuture = _getMyMembership();
      _summaryBarFuture = Future.wait([_getAllRooms(), _getAllTenants()]);
      _buildingCardFutures.clear();
      _statsFuture = Future.wait([
        _getAllTenants(),
        _getAllPayments(),
        _getBuildings(),
        _getAllRooms(),
      ]);
      _membersTabFuture = Future.wait([
        _getMembers(),
        _getMyMembership(),
      ]);
    });
  }

  // Replace _refreshStats calls with _refreshAll
  void _refreshStats() => _refreshAll();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _paymentsNotifier.loadPayments(widget.organization.id);
    _refreshAll();
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
            _buildingCardFutures.clear();
            setState(() {
               _buildingsFuture = _getBuildings();
               _tenantTabRefreshKey++;
            });
          }
        } else {
          if (mounted) Navigator.of(context).pop();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(t['add_building_success']),
              backgroundColor: Colors.green,
            ));
            _buildingCardFutures.clear();
            setState(() {
               _buildingsFuture = _getBuildings();
               _tenantTabRefreshKey++;
            });
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
            _buildingCardFutures.remove(building.id);
            setState(() {
              _buildingsFuture = _getBuildings();
              _tenantTabRefreshKey++; 
            });
          }
        } else {
          if (mounted) Navigator.of(context).pop();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(t['update_building_success']),
              backgroundColor: Colors.green,
            ));
            _buildingCardFutures.remove(building.id);
            setState(() {
              _buildingsFuture = _getBuildings();
              _tenantTabRefreshKey++; 
            });
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
        organization.id, building.id);
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
        _buildingCardFutures.remove(building.id);
        setState(() {
          _tenantTabRefreshKey++;
        });
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
    return DefaultTabController(
      length: 5,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < minWidth ||
              constraints.maxHeight < minHeight) {
            return Scaffold(
              body: _buildMinimumSizeWarning(context, constraints),
            );
          }
          return Scaffold(
            backgroundColor: kBgColor,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 6,
              shadowColor: Colors.black.withValues(alpha: 0.4),
              automaticallyImplyLeading: false,
              titleSpacing: 0,
              flexibleSpace: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Gradient background (bottom layer)
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1565C0), Color(0xFF185FA5), Color(0xFF0D47A1)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),

                  // ── Right-side circles ───────────────────────────────────
                  Positioned(
                    right: -15,
                    top: -20,
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 55,
                    top: -28,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                  ),

                  // ── Center circle ────────────────────────────────────────
                  Positioned(
                    left: 280,
                    top: -18,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.09),
                      ),
                    ),
                  ),

                  // ── Left-side circles ────────────────────────────────────
                  Positioned(
                    left: -18,
                    bottom: -12,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 42,
                    top: -12,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                ],
              ),
              title: Stack(
                clipBehavior: Clip.none,
                children: [
                  Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 12),  
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  'Back',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(Icons.apartment_rounded, size: 18, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.organization.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Quản lý chung cư',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.7),
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: TabBar(
                  isScrollable: false,
                  labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                  unselectedLabelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w400),
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorWeight: 3,
                  labelPadding: EdgeInsets.zero,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white.withValues(alpha: 0.55),
                  indicatorColor: Colors.white,
                  tabs: [
                    _CompactTab(icon: Icons.apartment_rounded,   label: t['buildings_tab']),
                    _CompactTab(icon: Icons.people_alt_rounded,   label: t['tenants_tab']),
                    _CompactTab(icon: Icons.receipt_long_rounded, label: t['payments_tab']),
                    _CompactTab(icon: Icons.bar_chart_rounded,    label: t['statistics_tab']),
                    _CompactTab(icon: Icons.group_rounded,        label: t['members_tab']),
                  ],
                ),
              ),
            ),
            body: TabBarView(
              children: [
                _StableTab(
                  key: const ValueKey('buildings'),
                  builder: (_) => _buildBuildingsTab(),
                ),
                TenantsTab(
                  key: ValueKey('tenants_$_tenantTabRefreshKey'),
                  organization: widget.organization,
                  tenantService: _tenantService,
                  buildingService: _buildingService,
                  roomService: _roomService,
                  organizationService: _orgService,
                  authService: _authService,
                  onChanged: () {
                    _refreshStats();
                    setState(() => _tenantTabRefreshKey++);
                  },
                ),
                _StableTab(
                  key: const ValueKey('payments'),
                  builder: (_) => _buildPaymentsTab(),
                ),
                _StableTab(
                  key: const ValueKey('statistics'),
                  builder: (_) => _buildStatisticsTab(),
                ),
                _StableTab(
                  key: const ValueKey('members'),
                  builder: (_) => _buildMembersTab(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ========================================
  // BUILDINGS TAB
  // ========================================
  Widget _buildBuildingsTab() {
    final t = AppTranslations.of(context);
    return FutureBuilder<Membership?>(
      future: _membershipFuture,
      builder: (context, membershipSnapshot) {
        final isAdmin = membershipSnapshot.hasData &&
            membershipSnapshot.data!.role == 'admin';
        return FutureBuilder<List<Building>>(
          future: _buildingsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final buildings = snapshot.data ?? [];

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Column(
                      children: [
                        // ── Summary bar ──────────────────────────────
                        _buildBuildingSummaryBar(t, buildings),
                        const SizedBox(height: 16),

                        // ── Add button ───────────────────────────────
                        if (isAdmin)
                          _buildAddBuildingButton(t),

                        // ── Section header ───────────────────────────
                        if (buildings.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                Text(
                                  t['buildings_tab'].toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${buildings.length} ${t['buildings_tab'].toLowerCase()}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                if (buildings.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.apartment, size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text(t['no_buildings'],
                              style: TextStyle(color: Colors.grey.shade400)),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final building = buildings[index];
                          final color = _buildingColors[index % _buildingColors.length];
                          return _buildBuildingCard(
                            t: t,
                            building: building,
                            color: color,
                            isAdmin: isAdmin,
                            allRooms: snapshot.data != null ? null : [],
                          );
                        },
                        childCount: buildings.length,
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBuildingSummaryBar(AppTranslations t, List<Building> buildings) {
    return FutureBuilder<List<dynamic>>(
      future: _summaryBarFuture,
      builder: (context, snap) {
        final rooms = snap.data?[0] as List<Room>? ?? [];
        final tenants = snap.data?[1] as List<Tenant>? ?? [];
        final activeTenants = tenants.where((t) => t.status == TenantStatus.active).length;
        final occupancyPct = rooms.isNotEmpty
            ? (activeTenants / rooms.length * 100).round()
            : 0;

        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              _summaryBarItem(
                value: buildings.length.toString(),
                label: t['stat_buildings'], 
                color: const Color(0xFF185FA5),
                isFirst: true,
              ),
              _summaryBarDivider(),
              _summaryBarItem(
                value: rooms.length.toString(),
                label: t['stat_rooms'],
                color: const Color(0xFF0F6E56),
              ),
              _summaryBarDivider(),
              _summaryBarItem(
                value: '$occupancyPct%',
                label: t['stat_occupancy'],
                color: occupancyPct >= 80
                    ? const Color(0xFF3B6D11)
                    : occupancyPct >= 50
                        ? const Color(0xFF854F0B)
                        : const Color(0xFFA32D2D),
                isLast: true,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _summaryBarItem({
    required String value,
    required String label,
    required Color color,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryBarDivider() => Container(
        width: 0.5,
        height: 40,
        color: Colors.grey.shade200,
      );

  Widget _buildAddBuildingButton(AppTranslations t) {
    return Material(
      color: const Color(0xFFE6F1FB),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _showAddBuildingDialog,
        borderRadius: BorderRadius.circular(14),
        hoverColor: const Color(0xFFD0E8F8),
        splashColor: const Color(0xFF378ADD).withValues(alpha: 0.2),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF378ADD),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_rounded, color: Color(0xFF185FA5), size: 20),
              const SizedBox(width: 6),
              Text(
                t['add_building'],
                style: const TextStyle(
                  color: Color(0xFF185FA5),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBuildingCard({
    required AppTranslations t,
    required Building building,
    required Color color,
    required bool isAdmin,
    List<Room>? allRooms,
  }) {
    // Cache the future so resize doesn't recreate it
    final future = _buildingCardFutures.putIfAbsent(
      building.id,
      () => Future.wait([
        _roomService.getBuildingRooms(widget.organization.id, building.id),
        _tenantService.getBuildingTenants(widget.organization.id, building.id),
      ]),
    );
    return FutureBuilder<List<dynamic>>(
      future: future,
      builder: (context, snap) {
        final rooms = snap.data?[0] as List<Room>? ?? [];
        final tenants = snap.data?[1] as List<Tenant>? ?? [];
        final occupied = tenants.where((t) => t.status == TenantStatus.active).length;
        final vacant = (rooms.length - occupied).clamp(0, rooms.length);
        final pct = rooms.isNotEmpty ? (occupied / rooms.length) : 0.0;

        Color barColor = pct >= 0.8
            ? const Color(0xFF1D9E75)
            : pct >= 0.5
                ? const Color(0xFFEF9F27)
                : const Color(0xFFE24B4A);

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // ── Colored top accent ───────────────────────────────
              Container(height: 5, color: color),

              // ── Card body ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.apartment_rounded, color: color, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                building.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                building.address,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Status badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: pct >= 1.0
                                ? const Color(0xFFFCEBEB)
                                : const Color(0xFFEAF3DE),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            pct >= 1.0 ? t['building_status_full'] : t['building_status_active'],
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: pct >= 1.0
                                  ? const Color(0xFFA32D2D)
                                  : const Color(0xFF3B6D11),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Stats row
                    Row(
                      children: [
                        _buildingStatChip(
                          value: rooms.length.toString(),
                          label: t['building_stat_total_rooms'],
                          color: color,
                        ),
                        const SizedBox(width: 8),
                        _buildingStatChip(
                          value: occupied.toString(),
                          label: t['building_stat_rented'],
                          color: const Color(0xFF3B6D11),
                        ),
                        const SizedBox(width: 8),
                        _buildingStatChip(
                          value: vacant.toString(),
                          label: t['building_stat_vacant'],
                          color: vacant == 0
                              ? Colors.grey
                              : const Color(0xFF854F0B),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Occupancy bar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          t['building_occupancy_label'],
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        Text(
                          '${(pct * 100).round()}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: barColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        backgroundColor: barColor.withValues(alpha: 0.12),
                        color: barColor,
                        minHeight: 7,
                      ),
                    ),

                    // Created at
                    const SizedBox(height: 10),
                    Text(
                      '${t['created_at']} ${_formatDate(building.createdAt)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),

              // ── Footer actions ───────────────────────────────────
              if (isAdmin) ...[
                Divider(height: 1, color: Colors.grey.shade100),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      _footerActionBtn(
                        icon: Icons.meeting_room_rounded,
                        label: t['manage_rooms'],
                        color: color,
                        bgColor: color.withValues(alpha: 0.08),
                        onTap: () => _navigateToBuildingRooms(building),
                      ),
                      const SizedBox(width: 8),
                      _footerActionBtn(
                        icon: Icons.edit_rounded,
                        label: t['edit'],
                        color: Colors.grey.shade600,
                        bgColor: Colors.grey.shade100,
                        onTap: () => _showEditBuildingDialog(building),
                      ),
                      const SizedBox(width: 8),
                      _footerActionBtn(
                        icon: Icons.delete_outline_rounded,
                        label: t['delete'],
                        color: const Color(0xFFA32D2D),
                        bgColor: const Color(0xFFFCEBEB),
                        onTap: () => _deleteBuilding(building, widget.organization),
                      ),
                    ],
                  ),
                ),
              ] else
                InkWell(
                  onTap: () => _navigateToBuildingRooms(building),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.meeting_room_rounded, size: 16, color: color),
                        const SizedBox(width: 6),
                        Text(
                          t['building_action_view_rooms'],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios_rounded,
                            size: 12, color: color),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildingStatChip({
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _footerActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: color.withValues(alpha: 0.15),
          splashColor: color.withValues(alpha: 0.2),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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

        return FutureBuilder<Membership?>(
          future: _membershipFuture,
          builder: (context, membershipSnapshot) {
            final isAdmin = membershipSnapshot.hasData &&
                membershipSnapshot.data!.role == 'admin';

            return FutureBuilder<List<dynamic>>(
              future: _summaryBarFuture,
              builder: (context, roomsSnap) {
                final rooms = roomsSnap.data?[0] as List<Room>? ?? [];
                if (allPayments.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(t['no_payments'],
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
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
                }

                final sorted = List<Payment>.from(allPayments)
                  ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

                return Column(
                  children: [
                    // ── KPI bar ──────────────────────────────────────────────
                    _buildPaymentKpis(sorted),

                    // ── Revenue bar ──────────────────────────────────────────
                    _buildPaymentRevenueBar(sorted),

                    // ── Toolbar (search + filter chips + add button) ─────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: Column(
                        children: [
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _searchController,
                            builder: (context, value, _) {
                              return Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _searchController,
                                      maxLength: 100,
                                      decoration: InputDecoration(
                                        counterText: '',
                                        hintText: t['search_payments_hint'],
                                        prefixIcon: const Icon(Icons.search, size: 18),
                                        suffixIcon: value.text.isNotEmpty
                                            ? IconButton(
                                                icon: const Icon(Icons.clear, size: 16),
                                                onPressed: () => _searchController.clear())
                                            : null,
                                        border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(10)),
                                        contentPadding:
                                            const EdgeInsets.symmetric(vertical: 10),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  if (isAdmin) ...[
                                    const SizedBox(width: 10),
                                    Material(
                                      color: const Color(0xFF185FA5),
                                      borderRadius: BorderRadius.circular(10),
                                      child: InkWell(
                                        onTap: _showAddPaymentDialog,
                                        borderRadius: BorderRadius.circular(10),
                                        hoverColor: Colors.white.withValues(alpha: 0.12),
                                        splashColor: Colors.white.withValues(alpha: 0.2),
                                        highlightColor: Colors.white.withValues(alpha: 0.08),
                                        child: Container(
                                          height: 42,
                                          padding: const EdgeInsets.symmetric(horizontal: 14),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: 24,
                                                height: 24,
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withValues(alpha: 0.18),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.add, size: 15, color: Colors.white),
                                              ),
                                              const SizedBox(width: 10),
                                              Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    t['add_payment'],
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                      color: Colors.white,
                                                      height: 1.2,
                                                    ),
                                                  ),
                                                  Text(
                                                    t['create_invoice'],
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.white.withValues(alpha: 0.65),
                                                      height: 1.2,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          _buildStatusFilterChips(sorted),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // ── Payment list ─────────────────────────────────────────
                    Expanded(
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _searchController,
                        builder: (context, value, _) {
                          return _buildPaymentsList(sorted, value.text, isAdmin, rooms);
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // ── KPI summary row ────────────────────────────────────────────────────────────
  Widget _buildPaymentKpis(List<Payment> payments) {
    final t = AppTranslations.of(context);
    final total = payments.length;
    final pending = payments.where((p) => p.status == PaymentStatus.pending).length;
    final overdue = payments.where((p) => p.isOverdue).length;
    final collected = payments.fold<double>(0, (s, p) {
      if (p.status == PaymentStatus.paid) {
        return s + (p.paidAmount > 0 ? p.paidAmount : p.totalWithAllFees);
      }
      return s + p.paidAmount;
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          _payKpi(label: t['stat_total_payments'], value: total.toString(),
              color: Theme.of(context).colorScheme.onSurface),
          const SizedBox(width: 8),
          _payKpi(label: t['stat_collected'], value: _formatCurrencyShort(collected),
              color: const Color(0xFF3B6D11)),
          const SizedBox(width: 8),
          _payKpi(label: t['stat_pending'], value: pending.toString(),
              color: const Color(0xFF854F0B)),
          const SizedBox(width: 8),
          _payKpi(label: t['stat_overdue'], value: overdue.toString(),
              color: const Color(0xFFA32D2D)),
        ],
      ),
    );
  }

  Widget _payKpi({required String label, required String value, required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  // ── Revenue bar ────────────────────────────────────────────────────────────────
  Widget _buildPaymentRevenueBar(List<Payment> payments) {
    final t = AppTranslations.of(context);
    final totalBilled = payments.fold<double>(0, (s, p) => s + p.totalAmount);
    final collected = payments.fold<double>(0, (s, p) {
      if (p.status == PaymentStatus.paid) {
        return s + (p.paidAmount > 0 ? p.paidAmount : p.totalWithAllFees);
      }
      if (p.status == PaymentStatus.partial) {
        return s + p.paidAmount;
      }
      return s;
    });
    final pct = totalBilled > 0 ? (collected / totalBilled).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(t['stat_revenue_title'],
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600)),
                Text('${(pct * 100).round()}% ${t['stat_collected'].toLowerCase()}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF3B6D11))),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
                backgroundColor: Colors.grey.shade100,
                color: const Color(0xFF639922),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _revLegendDot(const Color(0xFF639922)),
                const SizedBox(width: 5),
                Text(
                  '${t['stat_collected']}  ${_formatCurrencyShort(collected)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const SizedBox(width: 16),
                _revLegendDot(Colors.grey.shade300),
                const SizedBox(width: 5),
                Text(
                  '${t['stat_uncollected']}  ${_formatCurrencyShort(totalBilled - collected)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _revLegendDot(Color color) => Container(
        width: 8, height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle));

  // ── Filter chips ────────────────────────────────────────────────────────────────
  // Add to state: PaymentStatus? _paymentStatusFilter;

  Widget _buildStatusFilterChips(List<Payment> payments) {
    final t = AppTranslations.of(context);
    final counts = <PaymentStatus?, int>{null: payments.length};
    for (final s in PaymentStatus.values) {
      counts[s] = payments.where((p) => p.status == s).length;
    }

    final chips = <MapEntry<PaymentStatus?, String>>[
      MapEntry(null, t['stat_total_payments']),
      MapEntry(PaymentStatus.paid, t['stat_paid']),
      MapEntry(PaymentStatus.pending, t['stat_pending']),
      MapEntry(PaymentStatus.overdue, t['stat_overdue']),
      MapEntry(PaymentStatus.partial, t['status_partial']),
      MapEntry(PaymentStatus.cancelled, t['status_cancelled']),
    ];

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final entry = chips[i];
          final isActive = _paymentStatusFilter == entry.key;
          final count = counts[entry.key] ?? 0;
          return Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: () => setState(() => _paymentStatusFilter = entry.key),
              borderRadius: BorderRadius.circular(20),
              hoverColor: isActive
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.grey.withValues(alpha: 0.08),
              splashColor: isActive
                  ? Colors.white.withValues(alpha: 0.2)
                  : const Color(0xFF185FA5).withValues(alpha: 0.12),
              highlightColor: isActive
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFF185FA5).withValues(alpha: 0.06),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF185FA5)
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isActive
                        ? const Color(0xFF185FA5)
                        : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.value,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isActive ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.white.withValues(alpha: 0.25)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        count.toString(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isActive ? Colors.white : Colors.grey.shade500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Rich payment card ───────────────────────────────────────────────────────────
  Widget _buildPaymentsListView(List<Payment> payments, bool isAdmin, List<Room> rooms) {
    final t = AppTranslations.of(context);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      itemCount: payments.length,
      itemBuilder: (context, index) {
        return _buildRichPaymentCard(payments[index], isAdmin, t, rooms);
      },
    );
  }

  Widget _buildRichPaymentCard(Payment payment, bool isAdmin, AppTranslations t, List<Room> rooms) {
    final statusColor = _getPaymentStatusColor(payment.status);
    final initials = _getInitials(payment.tenantName ?? '?');
    final remaining = payment.remainingAmount;
    final isPartial = payment.status == PaymentStatus.partial;

    final roomNumber = rooms
        .where((r) => r.id == payment.roomId)
        .firstOrNull
        ?.roomNumber ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showPaymentDetailsDialog(payment, isAdmin),
        child: Column(
          children: [
            // ── Colored top accent ───────────────────────────────────
            Container(height: 4, color: statusColor),

            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Avatar ──────────────────────────────────────────
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // ── Main info ────────────────────────────────────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name + status badge
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                payment.tenantName ?? '—',
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                payment.getStatusDisplayName(),
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: statusColor),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),

                        // Amount
                        Text(
                          _formatCurrency(payment.totalAmount),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Meta chips row
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _infoChip(
                              icon: Icons.label_outline_rounded,
                              text: _getPaymentTitle(payment),
                              color: Colors.grey.shade600,
                            ),
                            if (roomNumber.isNotEmpty)
                              _infoChip(
                                icon: Icons.meeting_room_outlined,
                                text: 'Room $roomNumber',
                                color: Colors.grey.shade600,
                              ),
                            _infoChip(
                              icon: Icons.calendar_today_outlined,
                              text: DateFormat('dd/MM/yy').format(payment.dueDate),
                              color: payment.isOverdue
                                  ? const Color(0xFFA32D2D)
                                  : Colors.grey.shade600,
                            ),
                            if (payment.paidAt != null)
                              _infoChip(
                                icon: Icons.check_circle_outline_rounded,
                                text: DateFormat('dd/MM/yy').format(payment.paidAt!),
                                color: const Color(0xFF3B6D11),
                              ),
                            if (isPartial && remaining > 0)
                              _infoChip(
                                icon: Icons.pending_outlined,
                                text: _formatCurrencyShort(remaining),
                                color: const Color(0xFF185FA5),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // ── Menu button ──────────────────────────────────────
                  if (isAdmin)
                    Builder(
                      builder: (ctx) => IconButton(
                        icon: Icon(Icons.more_vert,
                            size: 18, color: Colors.grey.shade400),
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        onPressed: () => _showPaymentMenu(ctx, payment, isAdmin),
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

  Widget _infoChip({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(fontSize: 11, color: color),
        ),
      ],
    );
  }

  String _getInitials(String name) {
    final words = name.trim().split(' ');
    if (words.isEmpty) return '?';
    if (words.length == 1) return words[0][0].toUpperCase();
    return (words.first[0] + words.last[0]).toUpperCase();
  }

  Widget _buildPaymentsList(
      List<Payment> allPayments, String searchText, bool isAdmin, List<Room> rooms) {
    final t = AppTranslations.of(context);
    final searchTerm = searchText.toLowerCase();
    final filteredPayments = allPayments.where((payment) {
      if (_paymentStatusFilter != null && payment.status != _paymentStatusFilter) {
      return false;
    }
      if (searchTerm.isEmpty) return true;
      if ((payment.tenantName?.toLowerCase() ?? '')
          .contains(searchTerm)) {return true;}
      if (payment.totalAmount.toString().contains(searchTerm))
        {return true;}
      if (payment
          .getTypeDisplayName()
          .toLowerCase()
          .contains(searchTerm)) {return true;}
      final description = payment.description;
      if (description != null && description.contains('\n')) {
        if (description.toLowerCase().contains(searchTerm))
          {return true;}
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
                  filteredPayments, isAdmin, rooms)),
        ],
      );
    }

    return _buildPaymentsListView(filteredPayments, isAdmin, rooms);
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

    // ✅ FutureBuilder resolves tenants/buildings/rooms ONCE
    return FutureBuilder<List<dynamic>>(
      future: _statsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && snapshot.data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData) return _buildStatsEmptyState(t);

        final tenants = snapshot.data![0] as List<Tenant>;
        final buildings = snapshot.data![2] as List<Building>;
        final rooms = snapshot.data![3] as List<Room>;

        final buildingOccupancy = _calculateBuildingOccupancy(buildings, rooms, tenants);

        // ✅ ListenableBuilder ONLY wraps the payment-derived section
        // Tenant/building/room charts are completely outside it
        return RefreshIndicator(
          onRefresh: () async => _refreshStats(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Payment-driven section: rebuilds on notifier changes ───────
                ListenableBuilder(
                  listenable: _paymentsNotifier,
                  builder: (context, _) {
                    final payments = _paymentsNotifier.payments;

                    final activeTenants = tenants.where((tn) => tn.status == TenantStatus.active).length;
                    final paidPayments = payments.where((p) => p.status == PaymentStatus.paid).length;
                    final pendingPayments = payments.where((p) => p.status == PaymentStatus.pending).length;
                    final overduePayments = payments.where((p) => p.isOverdue).length;
                    final totalPayments = payments.length;

                    final totalRevenue = payments.fold<double>(0, (sum, p) {
                      if (p.status == PaymentStatus.paid && p.paidAmount == 0) return sum + p.totalWithAllFees;
                      return sum + p.paidAmount;
                    });
                    final pendingRevenue = payments.fold<double>(0, (sum, p) {
                      if (p.status == PaymentStatus.paid || p.status == PaymentStatus.cancelled) return sum;
                      return sum + p.remainingAmount;
                    });

                    final monthlyRevenue = _calculateMonthlyRevenue(payments);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Export buttons + KPI grid
                        Padding(
                          padding: const EdgeInsets.only(top: 28, bottom: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 3, height: 14,
                                  decoration: BoxDecoration(color: Colors.blue.shade400, borderRadius: BorderRadius.circular(2))),
                              const SizedBox(width: 16),
                              Text(t['stat_overview_title'].toUpperCase(),
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2, color: Colors.grey.shade500)),
                              const SizedBox(width: 10),
                              Tooltip(
                                message: t['export_excel'],
                                child: Material(
                                  color: const Color(0xFF1D6F42),
                                  borderRadius: BorderRadius.circular(6),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: () => _exportStatisticsToExcel(
                                      buildings: buildings, tenants: tenants,
                                      rooms: rooms, payments: payments,
                                      organizationName: widget.organization.name,
                                    ),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                      child: Icon(Icons.table_chart_outlined, size: 16, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Tooltip(
                                message: t['export_pdf'],
                                child: Material(
                                  color: const Color(0xFFB71C1C),
                                  borderRadius: BorderRadius.circular(6),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: () => _exportStatisticsToPdf(
                                      buildings: buildings, tenants: tenants,
                                      rooms: rooms, payments: payments,
                                      organizationName: widget.organization.name,
                                    ),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                      child: Icon(Icons.picture_as_pdf_outlined, size: 16, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        _buildKpiGrid(
                          t: t,
                          buildings: buildings,
                          activeTenants: activeTenants,
                          rooms: rooms,
                          paidPayments: paidPayments,
                          pendingPayments: pendingPayments,
                          overduePayments: overduePayments,
                          totalPayments: totalPayments,
                        ),

                        _statsSectionLabel(t['stat_revenue_title']),
                        Row(children: [
                          Expanded(child: _buildRevenueCard(
                            t: t, label: t['stat_collected'], amount: totalRevenue,
                            count: paidPayments, color: const Color(0xFF3B6D11),
                            bgColor: const Color(0xFFEAF3DE), icon: Icons.check_circle_outline_rounded,
                          )),
                          const SizedBox(width: 10),
                          Expanded(child: _buildRevenueCard(
                            t: t, label: t['stat_uncollected'], amount: pendingRevenue,
                            count: pendingPayments + overduePayments, color: const Color(0xFF854F0B),
                            bgColor: const Color(0xFFFAEEDA), icon: Icons.schedule_rounded,
                          )),
                        ]),

                        _statsSectionLabel(t['stat_monthly_revenue']),
                        // ✅ Chart widget — only rebuilds if monthlyRevenue actually changes
                        _MonthlyRevenueChart(monthlyRevenue: monthlyRevenue),

                        _statsSectionLabel(t['stat_payment_breakdown']),
                        // ✅ Chart widget — only rebuilds if these counts change
                        _PaymentBreakdownChart(
                          paid: paidPayments,
                          pending: pendingPayments,
                          overdue: overduePayments,
                          total: totalPayments,
                        ),
                      ],
                    );
                  },
                ),

                // ── Static section: NEVER rebuilds on payment notifications ────
                // These only depend on tenants/buildings/rooms from _statsFuture

                _statsSectionLabel(t['stat_occupancy_by_building']),
                _buildBuildingOccupancyChart(buildingOccupancy, buildings),

                _statsSectionLabel(t['stat_tenant_status']),
                _buildTenantStatusCard(
                  active: tenants.where((tn) => tn.status == TenantStatus.active).length,
                  inactive: tenants.where((tn) => tn.status == TenantStatus.inactive).length,
                  movedOut: tenants.where((tn) => tn.status == TenantStatus.moveOut).length,
                  suspended: tenants.where((tn) => tn.status == TenantStatus.suspended).length,
                  total: tenants.length,
                  t: t,
                ),

                _statsSectionLabel(t['stat_occupancy_trend']),
                _buildMonthlyOccupancyTrendChart(buildings, rooms, tenants),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Section label ────────────────────────────────────────────────────────────
  Widget _statsSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 12),
      child: Row(children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: Colors.blue.shade400,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: Colors.grey.shade500,
          ),
        ),
      ]),
    );
  }

  // ── Empty state ──────────────────────────────────────────────────────────────
  Widget _buildStatsEmptyState(AppTranslations t) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(Icons.bar_chart_rounded,
                size: 36, color: Colors.blue.shade400),
          ),
          const SizedBox(height: 18),
          Text(t['stat_no_data'],
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(t['stat_empty_hint'],
              style:
                  TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  // ── KPI grid ─────────────────────────────────────────────────────────────────
  Widget _buildKpiGrid({
    required AppTranslations t,
    required List<Building> buildings,
    required int activeTenants,
    required List<Room> rooms,
    required int paidPayments,
    required int pendingPayments,
    required int overduePayments,
    required int totalPayments,
  }) {
    final occupancyPct = rooms.isNotEmpty
        ? (activeTenants / rooms.length * 100).toStringAsFixed(0)
        : '0';

    return Column(children: [
      Row(children: [
        Expanded(child: _kpiCard(
          icon: Icons.apartment_rounded,
          iconColor: const Color(0xFF185FA5),
          iconBg: const Color(0xFFE6F1FB),
          value: buildings.length.toString(),
          label: t['stat_buildings'],
        )),
        const SizedBox(width: 10),
        Expanded(child: _kpiCard(
          icon: Icons.people_alt_rounded,
          iconColor: const Color(0xFF3B6D11),
          iconBg: const Color(0xFFEAF3DE),
          value: activeTenants.toString(),
          label: t['stat_tenants'],
        )),
        const SizedBox(width: 10),
        Expanded(child: _kpiCard(
          icon: Icons.meeting_room_rounded,
          iconColor: const Color(0xFF0F6E56),
          iconBg: const Color(0xFFE1F5EE),
          value: rooms.length.toString(),
          label: t['stat_rooms'],
        )),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _kpiCard(
          icon: Icons.check_circle_rounded,
          iconColor: const Color(0xFF3B6D11),
          iconBg: const Color(0xFFEAF3DE),
          value: paidPayments.toString(),
          label: t['stat_paid'],
          valueColor: const Color(0xFF3B6D11),
        )),
        const SizedBox(width: 10),
        Expanded(child: _kpiCard(
          icon: Icons.pending_rounded,
          iconColor: const Color(0xFF854F0B),
          iconBg: const Color(0xFFFAEEDA),
          value: pendingPayments.toString(),
          label: t['stat_pending'],
          valueColor: const Color(0xFF854F0B),
        )),
        const SizedBox(width: 10),
        Expanded(child: _kpiCard(
          icon: Icons.warning_rounded,
          iconColor: const Color(0xFFA32D2D),
          iconBg: const Color(0xFFFCEBEB),
          value: overduePayments.toString(),
          label: t['stat_overdue'],
          valueColor: const Color(0xFFA32D2D),
        )),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _kpiCard(
          icon: Icons.receipt_long_rounded,
          iconColor: const Color(0xFF534AB7),
          iconBg: const Color(0xFFEEEDFE),
          value: totalPayments.toString(),
          label: t['stat_total_payments'],
        )),
        const SizedBox(width: 10),
        Expanded(child: _kpiCard(
          icon: Icons.pie_chart_rounded,
          iconColor: const Color(0xFF185FA5),
          iconBg: const Color(0xFFE6F1FB),
          value: '$occupancyPct%',
          label: t['stat_occupancy'],
        )),
      ]),
    ]);
  }

  Widget _kpiCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String value,
    required String label,
    Color? valueColor,
  }) {
    final effectiveColor = valueColor ?? iconColor;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: effectiveColor.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Colored top accent bar
            Container(height: 3, color: effectiveColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 19, color: iconColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: effectiveColor,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // ── Revenue cards ─────────────────────────────────────────────────────────────
  Widget _buildRevenueCard({
    required AppTranslations t,
    required String label,
    required double amount,
    required int count,
    required Color color,
    required Color bgColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha:0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha:0.18), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha:0.10),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha:0.15),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 9),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color.withValues(alpha:0.8))),
        ]),
        const SizedBox(height: 14),
        Text(
          _formatCurrency(amount),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: color,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          t.textWithParams('invoices', {'count': count}),
          style: TextStyle(fontSize: 11, color: color.withValues(alpha:0.6)),
        ),
      ]),
    );
  }

  // ── Tenant status breakdown ───────────────────────────────────────────────────
  Widget _buildTenantStatusCard({
    required int active,
    required int inactive,
    required int movedOut,
    required int suspended,
    required int total,
    required AppTranslations t,
  }) {
    if (total == 0) {
      return _buildChartEmptyState(
          Icons.people_outline, 'No tenant data yet');
    }
  
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(children: [
        _tenantStatusRow(
            label: t['tenant_status_active'],
            count: active,
            total: total,
            color: const Color(0xFF639922)),
        const SizedBox(height: 18),
        _tenantStatusRow(
            label: t['tenant_status_inactive'],
            count: inactive,
            total: total,
            color: const Color(0xFFEF9F27)),
        const SizedBox(height: 18),
        _tenantStatusRow(
            label: t['tenant_status_moved_out'],
            count: movedOut,
            total: total,
            color: Colors.grey.shade400),
        if (suspended > 0) ...[
          const SizedBox(height: 18),
          _tenantStatusRow(
              label: 'Suspended',
              count: suspended,
              total: total,
              color: const Color(0xFFE24B4A)),
        ],
      ]),
    );
  }

  Widget _tenantStatusRow({
    required String label,
    required int count,
    required int total,
    required Color color,
  }) {
    final pct = total > 0 ? count / total : 0.0;
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count  ·  ${(pct * 100).toStringAsFixed(0)}%',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: pct,
          backgroundColor: color.withValues(alpha:0.1),
          color: color,
          minHeight: 8,
        ),
      ),
    ]);
  }

  // ── Chart empty state ─────────────────────────────────────────────────────────
  Widget _buildChartEmptyState(IconData icon, String message) {
    return Container(
      height: 100,
      decoration: _cardDecoration(),
      child: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 28, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text(message,
              style:
                  TextStyle(fontSize: 12, color: Colors.grey.shade400)),
        ]),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.07),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ],
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

  Widget _buildBuildingOccupancyChart(
    Map<String, Map<String, dynamic>> occupancy,
    List<Building> buildings,
  ) {
    final t = AppTranslations.of(context);
    if (occupancy.isEmpty) {
      return _buildChartEmptyState(
          Icons.apartment_outlined, t['stat_no_building_data']);
    }
  
    Map<String, Map<String, dynamic>> displayOccupancy;
    if (_selectedOccupancyBuildingId == null) {
      displayOccupancy = occupancy;
    } else {
      displayOccupancy =
          occupancy.containsKey(_selectedOccupancyBuildingId)
              ? {
                  _selectedOccupancyBuildingId!:
                      occupancy[_selectedOccupancyBuildingId]!
                }
              : {};
    }
  
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(t['stat_filter_by_building'],
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border.all(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    value: _selectedOccupancyBuildingId,
                    hint: Text(t['stat_all_buildings'],
                        style: const TextStyle(fontSize: 13)),
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(t['stat_all_buildings']),
                      ),
                      ...buildings.map((b) => DropdownMenuItem<String?>(
                            value: b.id,
                            child: Text(b.name),
                          )),
                    ],
                    onChanged: (value) => setState(
                        () => _selectedOccupancyBuildingId = value),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          ...displayOccupancy.entries.map((entry) {
            final data = entry.value;
            final String buildingName = data['name'] ?? '';
            final pct = (data['percentage'] as num).toDouble();
            final occupied = data['occupied'] as int;
            final total = data['total'] as int;
            final Color barColor = pct >= 80
                ? const Color(0xFF639922)
                : pct >= 50
                    ? const Color(0xFFEF9F27)
                    : const Color(0xFFE24B4A);
  
            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(buildingName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: barColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$occupied/$total  ·  ${pct.toStringAsFixed(0)}%',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: barColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: pct / 100,
                      backgroundColor: barColor.withOpacity(0.1),
                      color: barColor,
                      minHeight: 10,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
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
      return _buildChartEmptyState(
          Icons.trending_up_rounded, t['stat_no_building_data']);
    }
  
    // Safe — no setState inside build
    final effectiveBuildingId =
        (_selectedBuildingId != null &&
                buildings.any((b) => b.id == _selectedBuildingId))
            ? _selectedBuildingId!
            : buildings.first.id;
  
    final selectedBuilding = buildings.firstWhere(
      (b) => b.id == effectiveBuildingId,
      orElse: () => buildings.first,
    );
  
    final monthlyOccupancy = _calculateMonthlyOccupancyTrend(
        selectedBuilding.id, rooms, tenants);
  
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(t['stat_select_building'],
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border.all(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: effectiveBuildingId,
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface),
                    items: buildings
                        .map((b) => DropdownMenuItem<String>(
                              value: b.id,
                              child: Text(b.name),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _selectedBuildingId = value),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          if (monthlyOccupancy.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(t['stat_no_building_selected'],
                    style: TextStyle(
                        color: Colors.grey.shade400, fontSize: 13)),
              ),
            )
          else
            SizedBox(
              height: 210,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t['stat_occupancy_rate'],
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade400,
                        letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: monthlyOccupancy.entries.map((entry) {
                        final rate = entry.value;
                        final barH =
                            (rate / 100 * 145).clamp(3.0, 145.0);
                        final Color barColor = rate >= 80
                            ? const Color(0xFF639922)
                            : rate >= 50
                                ? const Color(0xFFEF9F27)
                                : const Color(0xFFE24B4A);
                        final bool hasData = rate > 0;
  
                        return Expanded(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 2),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (hasData)
                                  Text(
                                    '${rate.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w700,
                                      color: barColor,
                                    ),
                                  )
                                else
                                  const SizedBox(height: 11),
                                const SizedBox(height: 3),
                                Container(
                                  height: barH,
                                  decoration: BoxDecoration(
                                    gradient: hasData
                                        ? LinearGradient(
                                            colors: [
                                              barColor.withOpacity(0.7),
                                              barColor,
                                            ],
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                          )
                                        : null,
                                    color: hasData
                                        ? null
                                        : Colors.grey.shade200,
                                    borderRadius:
                                        const BorderRadius.vertical(
                                            top: Radius.circular(4)),
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  entry.key.split('/')[0],
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: hasData
                                        ? Colors.grey.shade600
                                        : Colors.grey.shade400,
                                    fontWeight: hasData
                                        ? FontWeight.w600
                                        : FontWeight.w400,
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
            future: _membershipFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();
              final membership = snapshot.data!;
              if (membership.role != 'admin') return const SizedBox();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: loadingInvite ? null : _loadInviteCode,
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
                                  final confirm = await _showTrackedDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Text(t['refresh_invite_code_title']),
                                      content: Text(t['refresh_invite_code_body']),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: Text(t['cancel']),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.orange,
                                            foregroundColor: Colors.white,
                                          ),
                                          onPressed: () => Navigator.pop(ctx, true),
                                          child: Text(t['refresh_action']),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm != true || !mounted) return;

                                  setState(() => _refreshingCode = true);
                                  try {
                                    final success = await _orgService.refreshInviteCode(
                                      membership.ownerId,
                                      widget.organization.id,
                                    );
                                    if (success && mounted) {
                                      await _loadInviteCode();
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                        content: Text(t['code_refreshed']),
                                        backgroundColor: Colors.green,
                                      ));
                                    } else if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                        content: Text(t['cannot_refresh_code']),
                                        backgroundColor: Colors.red,
                                      ));
                                    }
                                  } finally {
                                    if (mounted) setState(() => _refreshingCode = false);
                                  }
                                },
                          icon: _refreshingCode
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.refresh, size: 18),
                          label: Text(t['refresh_code']),
                        ),
                      ],
                    ],
                  ),
                  if (inviteCode != null) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      '${t['invite_code_label']}: $inviteCode',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                  const Divider(height: 32),
                ],
              );
            },
          ),
          Text(
            t['members_title'],
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Expanded(
            // ✅ Wrap BOTH futures together so membership is resolved once
            // before the list is built — no per-tile fetching at all
            child: FutureBuilder<List<dynamic>>(
              future: _membersTabFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final members = (snapshot.data?[0] as List<Membership>?) ?? [];
                final myMembership = snapshot.data?[1] as Membership?;
                final isAdmin = myMembership?.role == 'admin';

                if (members.isEmpty) {
                  return Center(child: Text(t['no_members']));
                }

                return ListView.builder(
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    // ✅ Pass resolved values down — no async work here at all
                    return _buildMemberTile(member, myMembership, isAdmin);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ✅ Pure sync widget — receives membership as plain parameters
  Widget _buildMemberTile(
    Membership member,
    Membership? myMembership,
    bool isAdmin,
  ) {
    final t = AppTranslations.of(context);
    final ownerName = member.displayName.isNotEmpty
        ? member.displayName
        : member.email.isNotEmpty
            ? member.email
            : member.ownerId;
    final roleText = member.role == 'admin'
        ? t['member_role_admin']
        : t['member_role_member'];

    // ✅ Resolved synchronously — no FutureBuilder needed
    final Widget trailing;
    if (!isAdmin || myMembership == null) {
      trailing = member.status == 'active'
          ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
          : const Icon(Icons.pending, color: Colors.orange, size: 20);
    } else if (member.ownerId == myMembership.ownerId) {
      trailing = const Icon(Icons.check_circle, color: Colors.green, size: 20);
    } else {
      trailing = Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () => _showMemberMenu(ctx, member, myMembership, ownerName),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: member.role == 'admin' ? Colors.orange : Colors.blue,
          child: Icon(
            member.role == 'admin' ? Icons.admin_panel_settings : Icons.person,
            color: Colors.white,
          ),
        ),
        title: Text(ownerName,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              roleText,
              style: TextStyle(
                color: member.role == 'admin' ? Colors.orange : Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            if (member.email.isNotEmpty)
              Text(member.email,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        trailing: trailing,
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

// ── Donut chart painter ───────────────────────────────────────────────────────
class _DonutSection {
  final double value;
  final Color color;
  const _DonutSection(this.value, this.color);
}

class _DonutPainter extends CustomPainter {
  final List<_DonutSection> sections;
  final String centerText;
  const _DonutPainter({required this.sections, required this.centerText});

  @override
  void paint(Canvas canvas, Size size) {
    final total = sections.fold(0.0, (s, e) => s + e.value);
    if (total == 0) return;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.butt;

    double startAngle = -1.5708; // -90 degrees in radians
    for (final section in sections) {
      final sweep = (section.value / total) * 2 * 3.14159;
      paint.color = section.color;
      canvas.drawArc(
        rect.deflate(7),
        startAngle,
        sweep,
        false,
        paint,
      );
      startAngle += sweep;
    }

    // Center text
    final tp = TextPainter(
      text: TextSpan(
        text: centerText,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(size.width / 2 - tp.width / 2, size.height / 2 - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(_DonutPainter old) => true;
}

// ── Monthly Revenue Chart ─────────────────────────────────────────────────────
class _MonthlyRevenueChart extends StatefulWidget {
  final Map<String, double> monthlyRevenue;
  const _MonthlyRevenueChart({required this.monthlyRevenue});

  @override
  State<_MonthlyRevenueChart> createState() => _MonthlyRevenueChartState();
}

class _MonthlyRevenueChartState extends State<_MonthlyRevenueChart> {
  @override
  Widget build(BuildContext context) {
    // move _buildMonthlyRevenueChart body here, replace widget refs
    final monthlyRevenue = widget.monthlyRevenue;
    if (monthlyRevenue.isEmpty || monthlyRevenue.values.every((v) => v == 0)) {
      return _buildChartEmptyState(Icons.bar_chart_rounded, 'No revenue data');
    }
    final maxVal = monthlyRevenue.values.reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: _cardDecoration(context),
      child: SizedBox(
        height: 175,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: monthlyRevenue.entries.map((entry) {
            final isHighest = entry.value == maxVal && maxVal > 0;
            final ratio = maxVal > 0 ? (entry.value / maxVal) : 0.0;
            final barH = (ratio * 115).clamp(3.0, 115.0);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      _formatCurrencyShort(entry.value),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: isHighest ? const Color(0xFF1A6FBF) : Colors.grey.shade400,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: barH,
                      decoration: BoxDecoration(
                        gradient: isHighest
                            ? const LinearGradient(
                                colors: [Color(0xFF378ADD), Color(0xFF1A6FBF)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              )
                            : null,
                        color: isHighest ? null : const Color(0xFF378ADD).withOpacity(0.25),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      entry.key.split('/')[0],
                      style: TextStyle(
                        fontSize: 9,
                        color: isHighest ? const Color(0xFF1A6FBF) : Colors.grey.shade500,
                        fontWeight: isHighest ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // Helpers needed — move these to top-level functions so all chart widgets can share them
  static String _formatCurrencyShort(double amount) {
    if (amount >= 1000000000) return '${(amount / 1000000000).toStringAsFixed(1)}B';
    if (amount >= 1000000) return '${(amount / 1000000).toStringAsFixed(1)}M';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(0)}K';
    return amount.toStringAsFixed(0);
  }

  static BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 16, offset: const Offset(0, 4)),
      BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 1)),
    ],
  );

  static Widget _buildChartEmptyState(IconData icon, String message) => SizedBox(
    height: 100,
    child: Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 28, color: Colors.grey.shade300),
        const SizedBox(height: 8),
        Text(message, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
      ]),
    ),
  );
}

// ── Payment Breakdown Chart ───────────────────────────────────────────────────
class _PaymentBreakdownChart extends StatefulWidget {
  final int paid;
  final int pending;
  final int overdue;
  final int total;

  const _PaymentBreakdownChart({
    required this.paid,
    required this.pending,
    required this.overdue,
    required this.total,
  });

  @override
  State<_PaymentBreakdownChart> createState() => _PaymentBreakdownChartState();
}

class _PaymentBreakdownChartState extends State<_PaymentBreakdownChart> {
  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    if (widget.total == 0) {
      return Container(
        height: 100,
        decoration: _cardDecoration(),
        child: Center(child: Text('No payment data yet',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400))),
      );
    }
    final paidPct = (widget.paid / widget.total * 100).toStringAsFixed(0);
    final pendingPct = (widget.pending / widget.total * 100).toStringAsFixed(0);
    final overduePct = (widget.overdue / widget.total * 100).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 90,
            height: 90,
            child: CustomPaint(
              painter: _DonutPainter(
                sections: [
                  _DonutSection(widget.paid.toDouble(), const Color(0xFF639922)),
                  _DonutSection(widget.pending.toDouble(), const Color(0xFFEF9F27)),
                  _DonutSection(widget.overdue.toDouble(), const Color(0xFFE24B4A)),
                ],
                centerText: widget.total.toString(),
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _legendRow(context, const Color(0xFF639922), t['stat_paid'], '${widget.paid} ($paidPct%)'),
                const SizedBox(height: 14),
                _legendRow(context, const Color(0xFFEF9F27), t['stat_pending'], '${widget.pending} ($pendingPct%)'),
                const SizedBox(height: 14),
                _legendRow(context, const Color(0xFFE24B4A), t['stat_overdue'], '${widget.overdue} ($overduePct%)'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 16, offset: const Offset(0, 4)),
      BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 1)),
    ],
  );

  Widget _legendRow(BuildContext context, Color color, String label, String value) {
    return Row(children: [
      Container(width: 10, height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
        child: Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      ),
    ]);
  }
}

class _CompactTab extends StatelessWidget {
  final IconData icon;
  final String label;
  const _CompactTab({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Tab(
      height: 52,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18),
          const SizedBox(height: 3),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}