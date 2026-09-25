part of 'organization_screen.dart';

// PDF and Excel statistics reports and their export-only data helper.
// The main screen owns state, services, and lifecycle.
extension _OrganizationReportExports on _OrganizationScreenState {
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
          locale: 'en_US', symbol: _reportCurrency, decimalDigits: _reportCurrency == 'VND' ? 0 : 2);
      final dateFormatter =
          DateFormat('${t.dateFormat} – HH:mm');

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
            p.status == PaymentStatus.cancelled) {return sum;}
        return sum + p.remainingAmount;
      });
      final overdueRevenue =
          payments.fold<double>(0, (sum, p) {
        if (p.status == PaymentStatus.paid ||
            p.status == PaymentStatus.cancelled) {return sum;}
        if (p.status == PaymentStatus.overdue) {
          return sum + p.remainingAmount;
        }
        return sum;
      });

      final monthlyRevenue = _calculateMonthlyRevenue(payments);

      final Map<String, _BuildingStats> statsByBuilding = {};
      // Rented buildings aren't room-managed — exclude them from the
      // per-building room/occupancy breakdown table (same as on-screen stats).
      for (final b in buildings.where((b) => !b.isRented)) {
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
                pw.SizedBox(height: 16),
                pw.Divider(thickness: 2),
                pw.SizedBox(height: 16),
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
                pw.SizedBox(height: 16),
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
                pw.SizedBox(height: 16),
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
                pw.SizedBox(height: 12),
                if (buildingTableRows.isEmpty)
                  pw.Center(
                    child: pw.Text(t['pdf_no_building_data'],
                        style: pw.TextStyle(
                            fontSize: 12,
                            color: PdfColors.grey600)),
                  )
                else ...[
                  pw.TableHelper.fromTextArray(
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
                    pw.SizedBox(height: 12),
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
                    pw.SizedBox(height: 16),
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
      final currencyFormat = AppMoney.excelFormat(_reportCurrency);
      final dateFormatter =
          DateFormat('${t.dateFormat} – HH:mm');

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
            p.status == PaymentStatus.cancelled) {return sum;}
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

      // Rented buildings aren't room-managed — exclude them from the
      // per-building room/occupancy breakdown sheet (same as on-screen stats).
      for (var b in buildings.where((b) => !b.isRented)) {
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
            .setText(pm.getStatusDisplayName(t));
        pSheet.getRangeByIndex(pRow, 5).setText(pm.paidAt != null
            ? DateFormat(t.dateFormat).format(pm.paidAt!)
            : '-');
        pSheet.getRangeByIndex(pRow, 6).setText(
            DateFormat(t.dateFormat).format(pm.dueDate));
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

