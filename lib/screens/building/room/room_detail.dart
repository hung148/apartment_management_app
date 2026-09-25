import 'package:phan_mem_quan_ly_can_ho/widgets/app_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/services/exchange_rate_service.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/responsive_form_row.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/currency_formatter.dart';
import 'package:phan_mem_quan_ly_can_ho/main.dart';
import 'package:phan_mem_quan_ly_can_ho/models/membership_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/rooms_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/tenants_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/payment_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/payment/delete_payment_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/payment/payment_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/payment/payment_pdf_export.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/payment/view_edit_payment_dialogs.dart';
import 'package:phan_mem_quan_ly_can_ho/services/auth_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/building_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/room_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/tenants_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/payments_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/payments_notifier.dart';
import 'package:phan_mem_quan_ly_can_ho/services/organization_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_theme.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/date_picker.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';

// This file owns room state, lifecycle, tenant list, header, and tab layout.
// Dialogs and payment content are grouped in the companion files below.
part 'room_detail_dialog_components.dart';
part 'room_detail_tenant_dialogs.dart';
part 'room_detail_vehicle_dialogs.dart';
part 'room_detail_payments.dart';

// ─── Constants ────────────────────────────────────────────────────────────────
const double minWidth  = 360.0;
const double minHeight = 600.0;

// ═════════════════════════════════════════════════════════════════════════════
// ROOM DETAIL SCREEN
// ═════════════════════════════════════════════════════════════════════════════
class RoomDetailScreen extends StatefulWidget {
  final Room room;
  final Organization organization;
  final TenantService tenantService = getIt<TenantService>();
  final BuildingService buildingService = getIt<BuildingService>();
  final RoomService roomService = getIt<RoomService>();
  final OrganizationService organizationService = getIt<OrganizationService>();
  final AuthService authService = getIt<AuthService>();
  final PaymentService paymentService = getIt<PaymentService>();
  final PaymentsNotifier paymentsNotifier = getIt<PaymentsNotifier>();

  RoomDetailScreen({Key? key, required this.room, required this.organization})
      : super(key: key);

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _overlayCount = 0;

  bool _isSmallScreen(BuildContext context) =>
      MediaQuery.of(context).size.width < 600;

  double _getDialogWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 600) return w * 0.95;
    if (w < 1200) return 600;
    return 800;
  }

  Widget _buildMinimumSizeWarning(BuildContext context, BoxConstraints c) {
    final t = AppTranslations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, size: 64, color: Colors.orange[700]),
            const SizedBox(height: 16),
            Text(
              t['room_detail_window_too_small'],
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              t['room_detail_window_min_size'],
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              t.textWithParams('room_detail_window_current_size', {
                'width': c.maxWidth.toInt(),
                'height': c.maxHeight.toInt(),
              }),
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  late TabController _tabController;
  StreamSubscription<List<Tenant>>? _tenantSubscription;
  List<Tenant>? _tenants;
  bool _isLoadingTenants = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _initializeStreams();
    widget.paymentsNotifier
        .loadRoomPayments(widget.room.id, widget.organization.id);
  }

  void _initializeStreams() {
    _tenantSubscription = widget.tenantService
        .streamRoomTenants(widget.room.id, widget.organization.id)
        .listen(
      (tenants) {
        if (mounted) setState(() { _tenants = tenants; _isLoadingTenants = false; });
      },
      onError: (error) {
        debugPrint('❌ Firestore Error: $error');
        if (mounted) {
          setState(() { _isLoadingTenants = false; _tenants = []; });
          final msg = AppTranslations.of(context).textWithParams(
              'room_detail_loading_error', {'error': error});
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg)));
        }
      },
    );
  }

  String? get _userId => widget.authService.currentUser?.uid;

  Future<Membership?> _getMyMembership() {
    if (_userId == null) return Future.value(null);
    return widget.organizationService.getUserMembership(
        _userId!, widget.organization.id);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _tenantSubscription?.cancel();
    _resizeDebounceTimer?.cancel();
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
    _overlayCount++;
    try {
      return await showDialog<T>(
          context: context,
          barrierDismissible: barrierDismissible,
          builder: builder);
    } finally {
      if (mounted) _overlayCount--;
    }
  }

  Future<T?> _showTrackedBottomSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    ShapeBorder? shape,
  }) async {
    _overlayCount++;
    try {
      return await showModalBottomSheet<T>(
          context: context,
          isScrollControlled: isScrollControlled,
          shape: shape,
          builder: builder);
    } finally {
      if (mounted) _overlayCount--;
    }
  }

  // ─── Format helpers ───────────────────────────────────────────────────────
  String _formatDate(DateTime date) =>
      DateFormat(AppTranslations.of(context).dateFormat).format(date);

  String _formatCurrency(double amount, [String currency = 'VND']) => ReportingMoney.format(widget.organization.id, amount, currency);

  Color _getTenantStatusColor(TenantStatus status) {
    switch (status) {
      case TenantStatus.active:    return Colors.green;
      case TenantStatus.inactive:  return Colors.orange;
      case TenantStatus.moveOut:   return Colors.red;
      case TenantStatus.suspended: return Colors.grey;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD TENANTS TAB
  // ═══════════════════════════════════════════════════════════════
  Widget _buildTenantsTab() {
    final t = AppTranslations.of(context);

    if (_isLoadingTenants) {
      return Center(
          child: CircularProgressIndicator(color: AppThemePalette.primary));
    }

    if (_tenants == null || _tenants!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: AppThemePalette.primaryLight, shape: BoxShape.circle),
              child: Icon(Icons.people_outline_rounded,
                  size: 48, color: AppThemePalette.primaryMid),
            ),
            const SizedBox(height: 12),
            Text(t['room_detail_no_tenants'],
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700)),
            const SizedBox(height: 6),
            Text(t['room_detail_no_tenants_hint'],
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _showAddEditTenantDialog(),
              style: FilledButton.styleFrom(
                backgroundColor: AppThemePalette.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.person_add_rounded, color: Colors.white),
              label: Text(t['room_detail_add_tenant_title'],
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    final activeTenants =
        _tenants!.where((t) => t.status != TenantStatus.moveOut).toList();
    final movedOutTenants =
        _tenants!.where((t) => t.status == TenantStatus.moveOut).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
      children: [
        if (activeTenants.isNotEmpty) ...[
          _sectionLabel(t['room_detail_section_active'], activeTenants.length),
          const SizedBox(height: 8),
          ...activeTenants.map((tenant) => _buildRichTenantCard(tenant)),
        ],
        if (movedOutTenants.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionLabel(
              t['room_detail_section_moved_out'], movedOutTenants.length),
          const SizedBox(height: 8),
          ...movedOutTenants.map((tenant) => _buildRichTenantCard(tenant)),
        ],
      ],
    );
  }

  Widget _sectionLabel(String label, int count) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
              color: AppThemePalette.primaryMid,
              borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
                color: Colors.grey.shade500)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10)),
          child: Text(count.toString(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600)),
        ),
      ],
    );
  }

  Widget _buildRichTenantCard(Tenant tenant) {
    final t = AppTranslations.of(context);
    final isMovedOut = tenant.status == TenantStatus.moveOut;
    final Color accentColor =
        isMovedOut ? Colors.grey.shade400 : AppThemePalette.primary;
    final Color accentBg =
        isMovedOut ? Colors.grey.shade50 : AppThemePalette.primaryLight;
    final statusColor = _getTenantStatusColor(tenant.status);
    final words = tenant.fullName.trim().split(' ');
    final initials = words.length >= 2
        ? '${words.first[0]}${words.last[0]}'.toUpperCase()
        : tenant.fullName.isNotEmpty
            ? tenant.fullName[0].toUpperCase()
            : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: accentColor.withOpacity(0.07),
              blurRadius: 14,
              offset: const Offset(0, 4))
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showTenantDetailDialog(tenant),
        onLongPress: () => _showTenantOptionsMenu(tenant),
        child: Column(
          children: [
            Container(height: 4, color: accentColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                        color: accentBg,
                        borderRadius: BorderRadius.circular(13)),
                    child: Center(
                      child: Text(initials,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: accentColor)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(tenant.fullName,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (tenant.isMainTenant) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppThemePalette.primaryLight,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(t['room_detail_main_tenant_badge'],
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: AppThemePalette.primary)),
                            ),
                          ],
                        ]),
                        const SizedBox(height: 4),
                        Row(children: [
                          Icon(Icons.phone_rounded,
                              size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(tenant.phoneNumber,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600)),
                          if (tenant.occupation != null) ...[
                            Text('  ·  ',
                                style:
                                    TextStyle(color: Colors.grey.shade600)),
                            Icon(Icons.work_outline_rounded,
                                size: 12, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(tenant.occupation!,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ]),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(tenant.getStatusDisplayName(t),
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: statusColor)),
                            ),
                            _tenantInfoChip(
                                Icons.calendar_today_rounded,
                                _formatDate(tenant.moveInDate),
                                Colors.grey.shade600),
                            if (tenant.monthlyRent != null)
                              _tenantInfoChip(
                                  Icons.payments_rounded,
                                  _formatCurrency(tenant.monthlyRent!,tenant.currency),
                                  Colors.green.shade700),
                            if (tenant.vehicles != null &&
                                tenant.vehicles!.isNotEmpty)
                              _tenantInfoChip(
                                  Icons.directions_car_rounded,
                                  t.textWithParams('room_detail_vehicle_count',
                                      {'count': tenant.vehicles!.length}),
                                  Colors.purple.shade700),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.more_vert_rounded,
                        size: 18, color: Colors.grey.shade600),
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    onPressed: () => _showTenantOptionsMenu(tenant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tenantInfoChip(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // SLIVER APP BAR
  // ═══════════════════════════════════════════════════════════════
  Widget _buildSliverAppBar(bool innerBoxIsScrolled) {
    final t = AppTranslations.of(context);
    final tabs = [t['room_detail_tab_tenants'], t['room_detail_tab_payments']];
    return SliverAppBar(
      pinned: true,
      toolbarHeight: 56,
      backgroundColor: AppThemePalette.primaryDeep,
      foregroundColor: Colors.white,
      leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      title: LayoutBuilder(builder: (context, constraints) {
        final inline = constraints.maxWidth > 560 && MediaQuery.textScalerOf(context).scale(13) < 18;
        return Row(children: [
          Expanded(child: Tooltip(
            message: '${widget.room.roomNumber} / ${widget.room.roomType} / ${widget.room.area} m²',
            child: Text('${t['manage_rooms']} ${widget.room.roomNumber}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          )),
          const SizedBox(width: 8),
          if (inline) TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppThemePalette.primaryDeep,
            unselectedLabelColor: Colors.white,
            indicator: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding: const EdgeInsets.symmetric(vertical: 5),
            dividerColor: Colors.transparent,
            tabs: tabs.map((label) => Tab(height: 48, text: label)).toList(),
          ) else AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) => PopupMenuButton<int>(
              tooltip: tabs[_tabController.index],
              icon: const Icon(Icons.more_horiz),
              onSelected: _tabController.animateTo,
              itemBuilder: (_) => List.generate(2, (index) => CheckedPopupMenuItem<int>(
                value: index, checked: index == _tabController.index,
                child: Text(tabs[index]),
              )),
            ),
          ),
        ]);
      }),
    );
  }

  Widget _headerChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.28), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < minWidth ||
            constraints.maxHeight < minHeight) {
          return Scaffold(
              body: _buildMinimumSizeWarning(context, constraints));
        }
        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              _buildSliverAppBar(innerBoxIsScrolled),
            ],
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildTenantsTab(),
                _buildPaymentsTab(),
              ],
            ),
          ),
          floatingActionButton: FutureBuilder<Membership?>(
            future: _getMyMembership(),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.role == 'admin') {
                return FloatingActionButton(
                  onPressed: () {
                    if (_tabController.index == 0)
                      _showAddEditTenantDialog();
                    else
                      _showAddPaymentDialog();
                  },
                  backgroundColor: AppThemePalette.primary,
                  child: const Icon(Icons.add, color: Colors.white),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        );
      },
    );
  }
}

