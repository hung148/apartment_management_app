import 'package:phan_mem_quan_ly_can_ho/widgets/compact_summary_toolbar.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/app_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/building_summary_card.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_money.dart';
import 'package:phan_mem_quan_ly_can_ho/services/exchange_rate_service.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

import 'package:phan_mem_quan_ly_can_ho/main.dart';
import 'package:phan_mem_quan_ly_can_ho/models/buildings_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/membership_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/tenants_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/payment_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/rooms_model.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/calendar/availability_calendar_screen.dart'
    show AvailabilityCalendarScreen;
import 'package:phan_mem_quan_ly_can_ho/screens/building/building_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/building/building_rent_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/payment/delete_payment_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/payment/payment_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/payment/view_edit_payment_dialogs.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/organizations/tenants/tenant_tab.dart';
import 'package:phan_mem_quan_ly_can_ho/services/auth_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/building_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/organization_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/tenants_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/payments_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/payments_notifier.dart';
import 'package:phan_mem_quan_ly_can_ho/services/room_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_theme.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/shared.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

// This file owns screen state, lifecycle, tab navigation, and shared helpers.
// Tab content and report exports live in the companion files below.
part 'organization_buildings.dart';
part 'organization_payments.dart';
part 'organization_statistics.dart';
part 'organization_report_exports.dart';
part 'organization_members.dart';

Color get kPrimaryColor => AppThemePalette.primary;
Color get kBgColor => const Color(0xFFF6F7F4);      // Soft neutral background
final Color kSurfaceColor = Colors.white;

List<Color> get _buildingColors => AppThemePalette.identityColors;

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
    Theme.of(context); // Rebuild theme-dependent custom accents.
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
  
  bool _codeCopied = false;
  bool _codeHovered = false;
  bool _codePressed = false;

  bool _isResizing = false;

  int _tenantTabRefreshKey = 0;

  /// When true, the gradient header and the tab row are hidden so the tab
  /// content gets the full screen. Persisted across launches.
  bool _chromeHidden = false;
  static const String _kChromeHiddenKey = 'org_screen_chrome_hidden';

  Future<void> _loadChromePref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hidden = prefs.getBool(_kChromeHiddenKey) ?? false;
      if (mounted && hidden != _chromeHidden) {
        setState(() => _chromeHidden = hidden);
      }
    } catch (_) {
      // Preferences unavailable — fall back to showing the header.
    }
  }

  Future<void> _toggleChrome() async {
    final next = !_chromeHidden;
    // Nothing is visible on screen while hidden, so say how to get back.
    if (next) {
      final t = AppTranslations.of(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(t['swipe_down_to_show_header']),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ));
    }
    setState(() => _chromeHidden = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kChromeHiddenKey, next);
    } catch (_) {
      // Non-fatal: the toggle still works for this session.
    }
  }

  bool _isSmallScreen(BuildContext context) =>
      MediaQuery.of(context).size.width < 600;

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
  String? _selectedRevenueBuildingId;

  final TextEditingController _buildingSearchController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _filterChipsScrollController = ScrollController();

  Future<List<dynamic>>? _statsFuture;
  // Cache per-building futures to avoid recreation on rebuild
  final Map<String, Future<List<dynamic>>> _buildingCardFutures = {};
  Future<List<dynamic>>? _summaryBarFuture;
  Future<List<Building>>? _buildingsFuture;
  Future<Membership?>? _membershipFuture;
  Future<List<dynamic>>? _membersTabFuture;
  PaymentStatus? _paymentStatusFilter;

  // Companion sections request rebuilds through the owning State.
  void _updateOrganizationState(VoidCallback update) => setState(update);

  void _refreshAll() {
    if (!mounted) return;
    setState(() {
      _buildingsFuture = _getBuildings();
      _membershipFuture = _getMyMembership();
      _summaryBarFuture = Future.wait([_getAllRooms(), _getAllTenants(), _getBuildings()]);
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
    _loadChromePref();
    _loadReportingCurrency();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _buildingSearchController.dispose();
    _searchController.dispose();
    _resizeDebounceTimer?.cancel();
    _filterChipsScrollController.dispose();
    _exchangeRates.dispose();
    super.dispose();
  }

  Timer? _resizeDebounceTimer;

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    
    if (!_isResizing) {
      setState(() => _isResizing = true);
    }
    
    _resizeDebounceTimer?.cancel();
    _resizeDebounceTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() => _isResizing = false);
      

    });
  }



  Future<T?> _showTrackedDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) async {
    try {
      return await showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: builder,
      );
    } finally {
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

  // ========================================
  // FORMAT HELPERS
  // ========================================
  String _reportCurrency = 'VND';
  final _exchangeRates = ExchangeRateService();
  ExchangeRateSnapshot? _rateSnapshot;
  bool _ratesLoading = false;
  bool _ratesFailed = false;

  Future<void> _loadReportingCurrency() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = await _exchangeRates.cached();
    if (!mounted) return;
    setState(() {
      _reportCurrency = prefs.getString('report_currency_${widget.organization.id}') ?? 'VND';
      _rateSnapshot = cached;
      ReportingMoney.configure(widget.organization.id, _reportCurrency, _rateSnapshot);
    });
  }

  Future<void> _refreshRates() async {
    if (_ratesLoading) return;
    setState(() { _ratesLoading = true; _ratesFailed = false; });
    try {
      final snapshot = await _exchangeRates.refresh();
      if (mounted) setState(() {
        _rateSnapshot = snapshot;
        ReportingMoney.configure(widget.organization.id, _reportCurrency, snapshot);
      });
    } catch (_) {
      if (mounted) setState(() => _ratesFailed = true);
    } finally {
      if (mounted) setState(() => _ratesLoading = false);
    }
  }

  List<Payment>? _reportPayments(List<Payment> payments) {
    try {
      return payments.map((p) => AppMoney.code(p.currency) == _reportCurrency
          ? p : _rateSnapshot!.project(p, _reportCurrency)).toList();
    } catch (_) {
      // A partial total would be misleading. Keep transactions visible, but
      // require a complete rate snapshot before displaying combined reports.
      return null;
    }
  }

  String _formatCurrency(double amount, [String? currency]) {
    final source = currency ?? _reportCurrency;
    if (source == _reportCurrency) return AppMoney.format(amount, source);
    try {
      return '≈ ${AppMoney.format(_rateSnapshot!.convert(amount, source, _reportCurrency), _reportCurrency)}';
    } catch (_) {
      return AppMoney.format(amount, source);
    }
  }

  Widget _currencySelector(List<Payment> payments) {
    final t=AppTranslations.of(context);
    final currencies={_reportCurrency,'VND','USD','EUR','GBP','AUD','CAD','JPY','SGD',...AppMoney.currencies(payments)}.toList()..sort();
    final usedCurrencies = {...AppMoney.currencies(payments), _reportCurrency};
    final dates = usedCurrencies.map((code) => _rateSnapshot?.dates[code])
        .whereType<String>().toSet().toList();
    dates.sort();
    return Padding(padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),child:Column(
      crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(
            key: ValueKey(_reportCurrency),
            initialValue: _reportCurrency,
            decoration: InputDecoration(labelText: t['report_currency_label']),
            items: currencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (value) async {
              if (value == null) return;
              setState(() {
                _reportCurrency = value;
                ReportingMoney.configure(widget.organization.id, value, _rateSnapshot);
              });
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('report_currency_${widget.organization.id}', value);
              if (mounted && _reportPayments(payments) == null) await _refreshRates();
            },
          )),
          const SizedBox(width: 12),
          IconButton(onPressed: _ratesLoading ? null : _refreshRates,
            tooltip: t['refresh_rates'],
            icon: _ratesLoading ? const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.currency_exchange)),
        ]),
        const SizedBox(height:8),
        Text(_ratesFailed ? t['rates_offline'] : dates.isEmpty
            ? t['report_currency_hint']
            : '${t['reference_rates']} ${dates.first}${dates.last == dates.first ? '' : ' – ${dates.last}'} · Frankfurter',
          style:Theme.of(context).textTheme.bodySmall),
        if (_reportPayments(payments) == null)
          Padding(padding: const EdgeInsets.only(top:8), child: Text(t['rates_required'],
            style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]));
  }

  // ========================================
  // BUILD
  // ========================================
  PreferredSizeWidget _buildWorkspaceAppBar(BuildContext context, AppTranslations t) {
    final gradient = AppThemePalette.identityGradient(widget.organization.id);
    final tabs = <(IconData, String)>[
      (Icons.calendar_month_outlined, t['calendar_tab']),
      (Icons.apartment_outlined, t['buildings_tab']),
      (Icons.people_outline, t['tenants_tab']),
      (Icons.receipt_long_outlined, t['payments_tab']),
      (Icons.bar_chart_outlined, t['statistics_tab']),
      (Icons.group_outlined, t['members_tab']),
    ];
    final controller = DefaultTabController.of(context);
    return AppBar(
      backgroundColor: gradient.last,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 56,
      leadingWidth: 48,
      leading: IconButton(
        tooltip: t['back'],
        icon: const Icon(Icons.arrow_back_rounded, size: 20),
        onPressed: () => Navigator.of(context).pop(),
      ),
      titleSpacing: 4,
      title: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
          // Reserve room for the property name and every translated tab label.
          final tabWidth = tabs.fold<double>(0, (width, tab) {
            final painter = TextPainter(
              text: TextSpan(text: tab.$2, style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
              )),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final widthNeeded = painter.width + 56;
            painter.dispose();
            return width + widthNeeded;
          });
          final inline = constraints.maxWidth >= tabWidth + 220 && scale <= 1.3;
          return Row(
            children: [
              if (constraints.maxWidth >= 360) ...[
                const Icon(Icons.apartment_outlined, size: 21),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Tooltip(
                  message: widget.organization.name,
                  child: Text(
                    widget.organization.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (inline)
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  padding: EdgeInsets.zero,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                  labelColor: gradient.last,
                  unselectedLabelColor: Colors.white,
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding: const EdgeInsets.symmetric(vertical: 5),
                  dividerColor: Colors.transparent,
                  labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  tabs: tabs.map((tab) => Tab(
                    height: 48,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(tab.$1, size: 18),
                      const SizedBox(width: 8),
                      Text(tab.$2, maxLines: 1),
                    ]),
                  )).toList(),
                )
              else
                AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) => PopupMenuButton<int>(
                    tooltip: tabs[controller.index].$2,
                    initialValue: controller.index,
                    onSelected: controller.animateTo,
                    itemBuilder: (context) => List.generate(tabs.length, (index) =>
                      CheckedPopupMenuItem<int>(
                        value: index,
                        checked: controller.index == index,
                        child: Text(tabs[index].$2),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(
                        height: 48,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(tabs[controller.index].$1, size: 20),
                          if (constraints.maxWidth >= 440 && scale <= 1.3) ...[
                            const SizedBox(width: 8),
                            Text(tabs[controller.index].$2,
                              style: const TextStyle(fontSize: 13)),
                          ],
                          const SizedBox(width: 4),
                          const Icon(Icons.expand_more_rounded, size: 18),
                        ]),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      actions: [
        IconButton(
          onPressed: _toggleChrome,
          tooltip: t['hide_header'],
          icon: const Icon(Icons.unfold_less_rounded, size: 20),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild theme-dependent custom accents.
    final t = AppTranslations.of(context);
    return DefaultTabController(
      length: 6,
      initialIndex: 0, // Calendar is the landing tab

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
            appBar: _chromeHidden ? null : _buildWorkspaceAppBar(context, t),
           body: SafeArea(
            // The AppBar normally handles the status bar / notch. When it is
            // hidden we have to keep the content clear of it ourselves.
            top: _chromeHidden,
            bottom: false,
            child: Stack(
              children: [
                // Tab content owns its own readable insets. Keeping this
                // shell edge-to-edge lets the calendar timeline use the full
                // viewport instead of leaving decorative gutters on either
                // side of the resource grid.
                Positioned.fill(child: _buildTabContent()),
                if (_chromeHidden) ...[
                  // Touch: swipe down from the top edge to bring the header back.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _TopEdgeSwipeZone(onRevealed: _toggleChrome),
                  ),
                  // Mouse: the button fades in when the pointer enters this
                  // corner — the same corner the collapse button was in, so the
                  // pointer is already there. The calendar tab reserves room
                  // for it via _kRestoreCornerInset.
                  Positioned(
                    top: 0,
                    right: 0,
                    child: _HoverRestoreButton(
                      onTap: _toggleChrome,
                      tooltip: t['show_header'],
                    ),
                  ),
                ],
              ],
            ),
          ),
          );
        },
      ),
    );
  }

  Widget _buildTabContent() {
    return _isResizing
        ? const SizedBox.expand() // or a lightweight placeholder
        : TabBarView(
              children: [
                _StableTab(
                  key: const ValueKey('calendar'),
                  builder: (_) => AvailabilityCalendarScreen(
                    organization: widget.organization,
                    embedded: true,
                    // Keep the Ngày/Tháng switch out from under the restore
                    // button's hot zone while the header is hidden.
                    trailingInset: _chromeHidden ? _kRestoreCornerInset : 0,
                  ),
                ),
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
            );
  }

  // Shared summary and action widgets used by the tab sections.
  Widget _summaryBarItem({
    required String value,
    required String label,
    required Color color,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
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
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
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

  Widget _footerActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: color.withValues(alpha: 0.15),
        splashColor: color.withValues(alpha: 0.2),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

/// Width the restore button's hot zone occupies in the top-right corner. Tab
/// content that puts controls up there should inset itself by this much while
/// the header is hidden.
const double _kRestoreCornerInset = 48;

/// Invisible until the mouse enters its corner, then fades in. While hidden it
/// ignores pointers entirely so taps fall through to the tab content — which is
/// what makes it harmless on touch devices, where it never appears at all.
class _HoverRestoreButton extends StatefulWidget {
  final VoidCallback onTap;
  final String tooltip;
  const _HoverRestoreButton({required this.onTap, required this.tooltip});

  @override
  State<_HoverRestoreButton> createState() => _HoverRestoreButtonState();
}

class _HoverRestoreButtonState extends State<_HoverRestoreButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild theme-dependent custom accents.
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      // Hot zone is larger than the button so it is easy to find, but the
      // button itself hugs the corner so the reserved inset stays small.
      child: SizedBox(
        width: 72,
        height: 72,
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: IgnorePointer(
              ignoring: !_hovered,
              child: AnimatedOpacity(
                opacity: _hovered ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: Tooltip(
                  message: widget.tooltip,
                  child: Material(
                    color: AppThemePalette.primary,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: widget.onTap,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.unfold_more_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin strip along the top edge. A deliberate downward drag here restores the
/// header — the touch equivalent of hovering the corner button.
class _TopEdgeSwipeZone extends StatefulWidget {
  final VoidCallback onRevealed;
  const _TopEdgeSwipeZone({required this.onRevealed});

  @override
  State<_TopEdgeSwipeZone> createState() => _TopEdgeSwipeZoneState();
}

class _TopEdgeSwipeZoneState extends State<_TopEdgeSwipeZone> {
  static const double _triggerDistance = 56;
  double _accumulated = 0;
  bool _fired = false;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild theme-dependent custom accents.
    return GestureDetector(
      // Translucent so ordinary taps still reach whatever is underneath.
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (_) {
        _accumulated = 0;
        _fired = false;
      },
      onVerticalDragUpdate: (details) {
        if (_fired) return;
        _accumulated += details.delta.dy;
        if (_accumulated >= _triggerDistance) {
          _fired = true;
          widget.onRevealed();
        }
      },
      child: const SizedBox(width: double.infinity, height: 24),
    );
  }
}

