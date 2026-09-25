part of 'organization_screen.dart';

// Statistics tab, revenue and occupancy calculations, and chart widgets.
// The main screen owns state, services, and lifecycle.
extension _OrganizationStatistics on _OrganizationScreenState {
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

        // Rented buildings aren't room-managed — exclude them from every
        // room/occupancy-based stat below (KPI grid, occupancy chart, trend).
        final managedBuildings = buildings.where((b) => !b.isRented).toList();
        final managedBuildingIds = managedBuildings.map((b) => b.id).toSet();
        final managedRooms =
            rooms.where((r) => managedBuildingIds.contains(r.buildingId)).toList();

        final buildingOccupancy = _calculateBuildingOccupancy(managedBuildings, managedRooms, tenants);

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
                    // Building-rent payments (income from a whole-building
                    // renter) count toward revenue/payment stats like any
                    // other payment, so no filtering needed here.
                    final payments = _reportPayments(_paymentsNotifier.payments);
                    if (payments == null) return _currencySelector(_paymentsNotifier.payments);

                    final activeTenants = tenants
                        .where((tn) =>
                            tn.status == TenantStatus.active &&
                            managedBuildingIds.contains(tn.buildingId))
                        .length;
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

                    // Building-rent income: derived from the same unfiltered
                    // `payments` list now that Step 4 stopped excluding it.
                    final buildingRentPayments =
                        payments.where((p) => p.isBuildingLevelIncome).toList();
                    final hasRentedBuildings = buildings.any((b) => b.isRented);
                    final totalBuildingRentRevenue =
                        buildingRentPayments.fold<double>(0, (sum, p) {
                      if (p.status == PaymentStatus.paid && p.paidAmount == 0) {
                        return sum + p.totalWithAllFees;
                      }
                      return sum + p.paidAmount;
                    });
                    final monthlyBuildingRentRevenue =
                        _calculateMonthlyRevenue(buildingRentPayments);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _currencySelector(_paymentsNotifier.payments),
                        // Export buttons + KPI grid
                        Padding(
                          padding: const EdgeInsets.only(top: 28, bottom: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 3, height: 14,
                                  decoration: BoxDecoration(color: AppThemePalette.primary, borderRadius: BorderRadius.circular(2))),
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
                          rooms: managedRooms,
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
                        _MonthlyRevenueChart(monthlyRevenue: monthlyRevenue, currency: _reportCurrency),

                        _statsSectionLabel(t['stat_payment_breakdown']),
                        // ✅ Chart widget — only rebuilds if these counts change
                        _PaymentBreakdownChart(
                          paid: paidPayments,
                          pending: pendingPayments,
                          overdue: overduePayments,
                          total: totalPayments,
                        ),

                        // ── Building-rent income: only shown for orgs that ──
                        // actually have at least one rented-out building.
                        if (hasRentedBuildings) ...[
                          _statsSectionLabel(t['stat_building_rent_income']),
                          Row(children: [
                            Expanded(child: _buildRevenueCard(
                              t: t, label: t['stat_building_rent_total'],
                              amount: totalBuildingRentRevenue,
                              count: buildingRentPayments
                                  .where((p) => p.status == PaymentStatus.paid)
                                  .length,
                              color: AppThemePalette.primary,
                              bgColor: AppThemePalette.primaryLight,
                              icon: Icons.real_estate_agent_outlined,
                            )),
                          ]),

                          _statsSectionLabel(t['stat_building_rent_monthly']),
                          _MonthlyRevenueChart(monthlyRevenue: monthlyBuildingRentRevenue, currency: _reportCurrency),
                        ],

                        // ── Revenue by building — ALL buildings, not just rented ones ──────
                        _statsSectionLabel(t['stat_revenue_by_building']),
                        _buildRevenueByBuildingSection(
                          _calculateRevenueByBuilding(payments, buildings),
                          buildings,
                        ),

                        _statsSectionLabel(t['stat_revenue_distribution']),
                        _buildRevenueByBuildingPieChart(_calculateRevenueByBuilding(payments, buildings)),
                      ],
                    );
                  },
                ),

                // ── Static section: NEVER rebuilds on payment notifications ────
                // These only depend on tenants/buildings/rooms from _statsFuture

                _statsSectionLabel(t['stat_occupancy_by_building']),
                _buildBuildingOccupancyChart(buildingOccupancy, managedBuildings),

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
                _buildMonthlyOccupancyTrendChart(managedBuildings, managedRooms, tenants),
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
            color: AppThemePalette.primary,
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
              color: AppThemePalette.primaryLight,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppThemePalette.primary.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(Icons.bar_chart_rounded,
                size: 36, color: AppThemePalette.primary),
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
          iconColor: AppThemePalette.primary,
          iconBg: AppThemePalette.primaryLight,
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
          iconColor: AppThemePalette.primary,
          iconBg: AppThemePalette.primaryLight,
          value: totalPayments.toString(),
          label: t['stat_total_payments'],
        )),
        const SizedBox(width: 10),
        Expanded(child: _kpiCard(
          icon: Icons.pie_chart_rounded,
          iconColor: AppThemePalette.primary,
          iconBg: AppThemePalette.primaryLight,
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
        color: Theme.of(context).colorScheme.surfaceContainerLow,
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
          Icons.people_outline, t['chart_no_tenant_data']);
    }
  
    return Container(
      padding: const EdgeInsets.all(12),
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
            color: Colors.grey.shade600),
        if (suspended > 0) ...[
          const SizedBox(height: 18),
          _tenantStatusRow(
              label: t['tenant_status_suspended'],
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
                  TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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

  Map<String, Map<String, dynamic>> _calculateRevenueByBuilding(
    List<Payment> payments,
    List<Building> buildings,
  ) {
    final Map<String, Map<String, dynamic>> breakdown = {
      for (final b in buildings) b.id: {'name': b.name, 'collected': 0.0, 'pending': 0.0},
    };

    for (final p in payments) {
      if (p.status == PaymentStatus.cancelled) continue;
      if (!breakdown.containsKey(p.buildingId)) continue;

      if (p.status == PaymentStatus.paid) {
        // Same fallback the KPI cards already use — fixes the "0đ despite paid" bug.
        final amount = p.paidAmount > 0 ? p.paidAmount : p.totalWithAllFees;
        breakdown[p.buildingId]!['collected'] =
            (breakdown[p.buildingId]!['collected'] as double) + amount;
      } else {
        breakdown[p.buildingId]!['pending'] =
            (breakdown[p.buildingId]!['pending'] as double) + p.remainingAmount;
      }
    }

    return breakdown;
  }

  Widget _buildRevenueByBuildingSection(
    Map<String, Map<String, dynamic>> breakdown,
    List<Building> buildings,
  ) {
    final t = AppTranslations.of(context);
    if (breakdown.isEmpty) {
      return _buildChartEmptyState(Icons.apartment_outlined, t['stat_no_building_data']);
    }

    final displayBreakdown = _selectedRevenueBuildingId == null
        ? breakdown
        : (breakdown.containsKey(_selectedRevenueBuildingId)
            ? {_selectedRevenueBuildingId!: breakdown[_selectedRevenueBuildingId]!}
            : <String, Map<String, dynamic>>{});

    final maxCollected = breakdown.values
        .map((d) => d['collected'] as double)
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min, // ← hug content, don't stretch
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(t['stat_filter_by_building'],
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
                    value: _selectedRevenueBuildingId,
                    hint: Text(t['stat_all_buildings'], style: const TextStyle(fontSize: 13)),
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: Text(t['stat_all_buildings'])),
                      ...buildings.map((b) => DropdownMenuItem<String?>(value: b.id, child: Text(b.name))),
                    ],
                    onChanged: (value) => _updateOrganizationState(() => _selectedRevenueBuildingId = value),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // ── Hug content, cap at 320, scroll beyond that ──
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: displayBreakdown.entries
                    .map((e) => _revenueBuildingRow(e, maxCollected))
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _revenueBuildingRow(MapEntry<String, Map<String, dynamic>> entry, double maxCollected) {
    final t = AppTranslations.of(context);
    final data = entry.value;
    final buildingName = data['name'] as String? ?? '';
    final collected = data['collected'] as double;
    final pending = data['pending'] as double;
    final ratio = maxCollected > 0 ? collected / maxCollected : 0.0;
    final barColor = AppThemePalette.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(buildingName,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                    color: barColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(_formatCurrency(collected),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: barColor)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
                value: ratio, backgroundColor: barColor.withValues(alpha: 0.1),
                color: barColor, minHeight: 10),
          ),
          if (pending > 0) ...[
            const SizedBox(height: 4),
            Text(t.textWithParams('stat_pending_amount', {'amount': _formatCurrency(pending)}),
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          ],
        ],
      ),
    );
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

  Widget _buildRevenueByBuildingPieChart(Map<String, Map<String, dynamic>> breakdown) {
    final t = AppTranslations.of(context);
    final entries = breakdown.entries
        .where((e) => (e.value['collected'] as double) > 0)
        .toList();
    final total = entries.fold<double>(0, (s, e) => s + (e.value['collected'] as double));

    if (entries.isEmpty || total == 0) {
      return _buildChartEmptyState(Icons.pie_chart_outline_rounded, t['stat_no_revenue_data']);
    }

    final sections = [
      for (var i = 0; i < entries.length; i++)
        _DonutSection(entries[i].value['collected'] as double, _buildingColors[i % _buildingColors.length]),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 90,
            height: 90,
            child: CustomPaint(
              painter: _DonutPainter(sections: sections, centerText: _formatCurrencyShort(total)),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < entries.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(children: [
                      Container(width: 10, height: 10,
                          decoration: BoxDecoration(
                              color: _buildingColors[i % _buildingColors.length],
                              borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 8),
                      Expanded(child: Text(entries[i].value['name'] as String? ?? '',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          overflow: TextOverflow.ellipsis)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                            color: _buildingColors[i % _buildingColors.length].withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(
                            '${((entries[i].value['collected'] as double) / total * 100).toStringAsFixed(0)}%',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                color: _buildingColors[i % _buildingColors.length])),
                      ),
                    ]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
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
      padding: const EdgeInsets.all(12),
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
                    onChanged: (value) => _updateOrganizationState(
                        () => _selectedOccupancyBuildingId = value),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
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
                          color: barColor.withValues(alpha: 0.12),
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
                      backgroundColor: barColor.withValues(alpha: 0.1),
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
      padding: const EdgeInsets.all(12),
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
                        _updateOrganizationState(() => _selectedBuildingId = value),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          if (monthlyOccupancy.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(t['stat_no_building_selected'],
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 13)),
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
                        color: Colors.grey.shade600,
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
                                              barColor.withValues(alpha: 0.7),
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
    return AppMoney.numberFormat(_reportCurrency).format(amount);
  }

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
  final String currency;
  const _MonthlyRevenueChart({required this.monthlyRevenue, required this.currency});

  @override
  State<_MonthlyRevenueChart> createState() => _MonthlyRevenueChartState();
}

class _MonthlyRevenueChartState extends State<_MonthlyRevenueChart> {
  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild theme-dependent custom accents.
    final t = AppTranslations.of(context);
    // move _buildMonthlyRevenueChart body here, replace widget refs
    final monthlyRevenue = widget.monthlyRevenue;
    if (monthlyRevenue.isEmpty || monthlyRevenue.values.every((v) => v == 0)) {
      return _buildChartEmptyState(Icons.bar_chart_rounded, t['chart_no_revenue_data']);
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
                        color: isHighest ? AppThemePalette.primary : Colors.grey.shade400,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: barH,
                      decoration: BoxDecoration(
                        gradient: isHighest
                            ?  LinearGradient(
                                colors: [AppThemePalette.primary, AppThemePalette.primary],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              )
                            : null,
                        color: isHighest ? null : AppThemePalette.primary.withValues(alpha: 0.25),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      entry.key.split('/')[0],
                      style: TextStyle(
                        fontSize: 9,
                        color: isHighest ? AppThemePalette.primary : Colors.grey.shade500,
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
  String _formatCurrencyShort(double amount) {
    if (amount >= 1000000000) return '${(amount / 1000000000).toStringAsFixed(1)}B';
    if (amount >= 1000000) return '${(amount / 1000000).toStringAsFixed(1)}M';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(0)}K';
    return AppMoney.numberFormat(widget.currency).format(amount);
  }

  static BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
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
        Text(message, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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
    Theme.of(context); // Rebuild theme-dependent custom accents.
    final t = AppTranslations.of(context);
    if (widget.total == 0) {
      return Container(
        height: 100,
        decoration: _cardDecoration(),
        child: Center(child: Text(t['chart_no_payment_data'],
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
      );
    }
    final paidPct = (widget.paid / widget.total * 100).toStringAsFixed(0);
    final pendingPct = (widget.pending / widget.total * 100).toStringAsFixed(0);
    final overduePct = (widget.overdue / widget.total * 100).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(12),
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
    color: Theme.of(context).colorScheme.surfaceContainerLow,
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

