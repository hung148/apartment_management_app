part of 'organization_screen.dart';

// Payment list, filters, summary widgets, and payment dialog actions.
// The main screen owns state, services, and lifecycle.
extension _OrganizationPayments on _OrganizationScreenState {
  // ========================================
  // PAYMENTS TAB
  // ========================================
  Widget _buildPaymentsTab() {
    final t = AppTranslations.of(context);
    return ListenableBuilder(
      listenable: _paymentsNotifier,
      builder: (context, _) {
        // Building-rent payments (income from a whole-building renter) count
        // as revenue like any other payment, so no filtering needed here.
        final allCurrencies = _paymentsNotifier.payments;
        final allPayments = allCurrencies;
        final reporting = _reportPayments(allCurrencies);

        return FutureBuilder<Membership?>(
          future: _membershipFuture,
          builder: (context, membershipSnapshot) {
            final isAdmin = membershipSnapshot.hasData &&
                membershipSnapshot.data!.role == 'admin';

            return FutureBuilder<List<dynamic>>(
              future: _summaryBarFuture,
              builder: (context, roomsSnap) {
                final rooms = roomsSnap.data?[0] as List<Room>? ?? [];
                final buildings = roomsSnap.data?[2] as List<Building>? ?? [];
                if (allCurrencies.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(t['no_payments'],
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                        const SizedBox(height: 16),
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
                    _currencySelector(allCurrencies),
                    // ── KPI bar ──────────────────────────────────────────────
                    if (reporting != null) ExpansionTile(
                      title: Text(t['stat_revenue_title']),
                      subtitle: Text('${allPayments.length} ${t['payments_tab'].toLowerCase()}'),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                      initiallyExpanded: MediaQuery.sizeOf(context).width >= 1000,
                      children: [_buildPaymentKpis(reporting), _buildPaymentRevenueBar(reporting)],
                    ),

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
                                      color: AppThemePalette.primary,
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
                          return _buildPaymentsList(sorted, value.text, isAdmin, rooms, buildings);
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
      child: LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth < 640 ? 2 : 4;
        final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
        return Wrap(spacing: 16, runSpacing: 16, children: [
          _payKpi(label: t['stat_total_payments'], value: total.toString(),
              color: Theme.of(context).colorScheme.onSurface),
          _payKpi(label: t['stat_collected'], value: _formatCurrency(collected),
              color: const Color(0xFF3B6D11)),
          _payKpi(label: t['stat_pending'], value: pending.toString(),
              color: const Color(0xFF854F0B)),
          _payKpi(label: t['stat_overdue'], value: overdue.toString(),
              color: const Color(0xFFA32D2D)),
        ].map((child) => SizedBox(width: width, child: child)).toList());
      }),
    );
  }

  Widget _payKpi({required String label, required String value, required Color color}) {
    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          ],
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
          color: Theme.of(context).colorScheme.surfaceContainerLow,
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
      child: GestureDetector(
        onHorizontalDragUpdate: (_) {},
        child: Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              final newOffset = (_filterChipsScrollController.offset + event.scrollDelta.dy)
                  .clamp(0.0, _filterChipsScrollController.position.maxScrollExtent);
              _filterChipsScrollController.jumpTo(newOffset);
            }
          },
          onPointerPanZoomUpdate: (event) {
            final delta = event.panDelta.dx.abs() > event.panDelta.dy.abs()
                ? -event.panDelta.dx
                : -event.panDelta.dy;
            final newOffset = (_filterChipsScrollController.offset + delta)
                .clamp(0.0, _filterChipsScrollController.position.maxScrollExtent);
            _filterChipsScrollController.jumpTo(newOffset);
          },
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
              },
            ),
            child: ListView.separated(
              controller: _filterChipsScrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: chips.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final entry = chips[i];
                final isActive = _paymentStatusFilter == entry.key;
                final count = counts[entry.key] ?? 0;
                return _FilterChip(
                  label: entry.value,
                  count: count,
                  isActive: isActive,
                  onTap: () => _updateOrganizationState(() => _paymentStatusFilter = entry.key),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentsListView(List<Payment> payments, bool isAdmin, List<Room> rooms, List<Building> buildings) {
    final t = AppTranslations.of(context);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      itemCount: payments.length,
      itemBuilder: (context, index) {
        return _buildRichPaymentCard(payments[index], isAdmin, t, rooms, buildings);
      },
    );
  }

  Widget _buildRichPaymentCard(Payment payment, bool isAdmin, AppTranslations t, List<Room> rooms, List<Building> buildings) {
    final statusColor = _getPaymentStatusColor(payment.status);
    final initials = _getInitials(payment.tenantName ?? '?');
    final remaining = payment.remainingAmount;
    final isPartial = payment.status == PaymentStatus.partial;

    final roomNumber = rooms
        .where((r) => r.id == payment.roomId)
        .firstOrNull
        ?.roomNumber ?? '';

    final buildingName = buildings
      .where((b) => b.id == payment.buildingId)
      .firstOrNull
      ?.name ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
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
                                payment.getStatusDisplayName(t),
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
                          _formatCurrency(payment.totalAmount,payment.currency),
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
                            if (buildingName.isNotEmpty)
                              _infoChip(
                                icon: Icons.apartment_rounded,
                                text: buildingName,
                                color: Colors.grey.shade600,
                              ),
                            if (roomNumber.isNotEmpty)
                              _infoChip(
                                icon: Icons.meeting_room_outlined,
                                text: 'P.$roomNumber',
                                color: Colors.grey.shade600,
                              ),
                            _infoChip(
                              icon: Icons.calendar_today_outlined,
                              text: DateFormat(t.dateFormatCompact).format(payment.dueDate),
                              color: payment.isOverdue
                                  ? const Color(0xFFA32D2D)
                                  : Colors.grey.shade600,
                            ),
                            if (payment.paidAt != null)
                              _infoChip(
                                icon: Icons.check_circle_outline_rounded,
                                text: DateFormat(t.dateFormatCompact).format(payment.paidAt!),
                                color: const Color(0xFF3B6D11),
                              ),
                            if (isPartial && remaining > 0)
                              _infoChip(
                                icon: Icons.pending_outlined,
                                text: _formatCurrency(remaining, payment.currency),
                                color: AppThemePalette.primary,
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
                            size: 18, color: Colors.grey.shade600),
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
      List<Payment> allPayments, String searchText, bool isAdmin, List<Room> rooms, List<Building> buildings) {
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
          .getTypeDisplayName(t)
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
                  filteredPayments, isAdmin, rooms, buildings)),
        ],
      );
    }

    return _buildPaymentsListView(filteredPayments, isAdmin, rooms, buildings);
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
    return key != null ? t[key] : payment.getTypeDisplayName(t);
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
        if (payment.bookingId == null) PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            const Icon(Icons.edit, size: 20),
            const SizedBox(width: 8),
            Text(t['edit_payment']),
          ]),
        ),
        if (payment.bookingId == null) PopupMenuItem(
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

}

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


class _FilterChip extends StatefulWidget {
  final String label;
  final int count;
  final bool isActive;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild theme-dependent custom accents.
    final scale = _pressed ? 0.94 : (_hovered ? 1.04 : 1.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: widget.isActive
                  ? AppThemePalette.primary
                  : Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: widget.isActive
                    ? AppThemePalette.primary
                    : Colors.grey.shade300,
              ),
              boxShadow: widget.isActive
                  ? [
                      BoxShadow(
                        color: AppThemePalette.primary.withValues(alpha: 0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: widget.isActive ? Colors.white : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: widget.isActive
                        ? Colors.white.withValues(alpha: 0.25)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.count.toString(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: widget.isActive ? Colors.white : Colors.grey.shade500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

