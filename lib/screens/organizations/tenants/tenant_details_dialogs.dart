part of 'tenant_tab.dart';

// Tenant details, options menu, and rental history.
// The tenant tab owns state, services, lifecycle, and refresh callbacks.
extension _TenantDetailsDialogs on _TenantsTabState {
  // ═══════════════════════════════════════════════════════════════
  // TENANT DETAIL DIALOG
  // ═══════════════════════════════════════════════════════════════
  void _showTenantDetailDialog(
      Tenant tenant, String buildingName, String roomNumber) {
    final bool isMovedOut = tenant.status == TenantStatus.moveOut;
    final accentColor =
        isMovedOut ? Colors.grey.shade600 : AppThemePalette.primary;
    final gradient = isMovedOut
        ? LinearGradient(
            colors: [Colors.blueGrey.shade700, Colors.blueGrey.shade500],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          )
        : _defaultHeaderGradient;

    _showTrackedDialog(
      context: context,
      builder: (context) {
        final t = AppTranslations.of(context);
        return _DialogShell(
          maxWidth: 540,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogHeader(
                gradient: gradient,
                onClose: () => Navigator.pop(context),
                leading: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      tenant.fullName.isNotEmpty
                          ? tenant.fullName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                title: tenant.fullName,
                subtitle: tenant.isMainTenant
                    ? t['tenant_main_tenant_badge']
                    : tenant.phoneNumber,
                actions: _membership != null && _membership!.role == 'admin'
                    ? [
                        TextButton.icon(
                          icon: const Icon(Icons.more_horiz_rounded,
                              size: 16),
                          label: Text(t['tenant_options_label']),
                          onPressed: () {
                            Navigator.pop(context);
                            _showTenantOptionsMenu(tenant, isMovedOut);
                          },
                        ),
                      ]
                    : null,
              ),

              // Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Location section
                      _SectionLabel(
                        isMovedOut
                            ? t['tenant_detail_previous_location']
                            : t['tenant_detail_location'],
                        color: accentColor,
                        icon: Icons.location_on_rounded,
                      ),
                      _DetailCard(
                        borderColor: accentColor.withValues(alpha: 0.2),
                        fillColor: accentColor.withValues(alpha: 0.05),
                        rows: [
                          _DetailRow(t['tenant_detail_building'],
                              buildingName),
                          _DetailRow(
                              t['tenant_detail_room'], roomNumber),
                        ],
                      ),

                      const _ContentDivider(),

                      // Contact
                      _SectionLabel(
                        t['tenant_detail_contact_section'],
                        icon: Icons.contact_phone_rounded,
                      ),
                      _DetailCard(
                        rows: [
                          _DetailRow(t['tenant_detail_phone'],
                              tenant.phoneNumber),
                          if (tenant.email != null)
                            _DetailRow(
                                t['tenant_detail_email'], tenant.email!),
                        ],
                      ),

                      const _ContentDivider(),

                      // Personal
                      _SectionLabel(
                        t['tenant_detail_personal_section'],
                        icon: Icons.person_rounded,
                      ),
                      _DetailCard(
                        rows: [
                          if (tenant.gender != null)
                            _DetailRow(t['tenant_detail_gender'],
                                tenant.getGenderDisplayName(t)!),
                          if (tenant.nationalId != null)
                            _DetailRow(t['tenant_detail_national_id'],
                                tenant.nationalId!),
                          if (tenant.occupation != null)
                            _DetailRow(t['tenant_detail_occupation'],
                                tenant.occupation!),
                          if (tenant.workplace != null)
                            _DetailRow(t['tenant_detail_workplace'],
                                tenant.workplace!),
                        ],
                      ),

                      // Rental info
                      if (!isMovedOut) ...[
                        const _ContentDivider(),
                        _SectionLabel(
                          t['tenant_detail_rental_section'],
                          icon: Icons.home_rounded,
                        ),
                        _DetailCard(
                          rows: [
                            _DetailRow(t['tenant_detail_move_in_date'],
                                _formatDate(tenant.moveInDate)),
                            _DetailRow(
                              t['tenant_detail_days_living'],
                              t.textWithParams(
                                  'tenant_detail_days_value',
                                  {'days': tenant.daysLiving}),
                            ),
                            if (tenant.monthlyRent != null)
                              _DetailRow(
                                  t['tenant_detail_monthly_rent'],
                                  _formatCurrency(tenant.monthlyRent!,tenant.currency),
                                  valueColor: const Color(0xFF3B6D11)),
                            if (tenant.deposit != null)
                              _DetailRow(
                                  t['tenant_detail_deposit'],
                                  _formatCurrency(tenant.deposit!,tenant.currency)),
                            if (tenant.apartmentType != null &&
                                tenant.apartmentType!.isNotEmpty)
                              _DetailRow(
                                  t['tenant_detail_apartment_type'],
                                  tenant.apartmentType!),
                            if (tenant.apartmentArea != null &&
                                tenant.apartmentArea! > 0)
                              _DetailRow(
                                t['tenant_detail_area'],
                                t.textWithParams(
                                    'tenant_detail_area_value',
                                    {'area': tenant.apartmentArea}),
                              ),
                          ],
                        ),
                      ],

                      // Move-out info
                      if (isMovedOut && tenant.moveOutDate != null) ...[
                        const _ContentDivider(),
                        _SectionLabel(
                          t['tenant_detail_moveout_section'],
                          icon: Icons.logout_rounded,
                          color: const Color(0xFF854F0B),
                        ),
                        _DetailCard(
                          borderColor: const Color(0xFF854F0B)
                              .withValues(alpha: 0.2),
                          fillColor: const Color(0xFF854F0B)
                              .withValues(alpha: 0.04),
                          rows: [
                            _DetailRow(t['tenant_detail_move_out_date'],
                                _formatDate(tenant.moveOutDate!)),
                            _DetailRow(
                              t['tenant_detail_duration'],
                              t.textWithParams(
                                  'tenant_detail_days_value', {
                                'days': tenant.moveOutDate!
                                    .difference(tenant.moveInDate)
                                    .inDays
                              }),
                            ),
                            if (tenant.contractTerminationReason != null)
                              _DetailRow(t['tenant_detail_reason'],
                                  tenant.contractTerminationReason!),
                            if (tenant.notes != null &&
                                tenant.notes!.isNotEmpty)
                              _DetailRow(t['tenant_detail_notes'],
                                  tenant.notes!),
                          ],
                        ),
                      ],

                      // Contract
                      if (tenant.contractStartDate != null ||
                          tenant.contractEndDate != null) ...[
                        const _ContentDivider(),
                        _SectionLabel(
                          t['tenant_detail_contract_section'],
                          icon: Icons.description_rounded,
                        ),
                        _DetailCard(
                          rows: [
                            if (tenant.contractStartDate != null)
                              _DetailRow(
                                  t['tenant_detail_contract_start'],
                                  _formatDate(
                                      tenant.contractStartDate!)),
                            if (tenant.contractEndDate != null)
                              _DetailRow(
                                isMovedOut
                                    ? t[
                                        'tenant_detail_contract_end_date']
                                    : t['tenant_detail_contract_end'],
                                _formatDate(tenant.contractEndDate!),
                              ),
                            if (isMovedOut) ...[
                              _DetailRow(
                                  t['tenant_detail_contract_status'],
                                  tenant
                                      .getContractStatusDisplayName(t)),
                              if (tenant.moveOutDate != null &&
                                  tenant.contractEndDate != null)
                                _DetailRow(
                                  tenant.moveOutDate!.isBefore(
                                          tenant.contractEndDate!)
                                      ? t[
                                          'tenant_detail_early_termination']
                                      : t['tenant_detail_end_label'],
                                  tenant.moveOutDate!.isBefore(
                                          tenant.contractEndDate!)
                                      ? t.textWithParams(
                                          'tenant_detail_days_early',
                                          {
                                            'days': tenant.contractEndDate!
                                                .difference(
                                                    tenant.moveOutDate!)
                                                .inDays
                                          })
                                      : t['tenant_detail_on_time'],
                                  valueColor: tenant.moveOutDate!.isBefore(
                                          tenant.contractEndDate!)
                                      ? const Color(0xFF854F0B)
                                      : const Color(0xFF3B6D11),
                                ),
                            ] else if (tenant.daysUntilContractEnd !=
                                null)
                              _DetailRow(
                                t['tenant_detail_remaining'],
                                t.textWithParams(
                                    'tenant_detail_days_value', {
                                  'days': tenant.daysUntilContractEnd
                                }),
                              ),
                          ],
                        ),
                      ],

                      // Vehicles
                      if (tenant.vehicles != null &&
                          tenant.vehicles!.isNotEmpty) ...[
                        const _ContentDivider(),
                        _SectionLabel(
                          t.textWithParams(
                              'tenant_detail_vehicles_section',
                              {'count': tenant.vehicles!.length}),
                          icon: Icons.directions_car_rounded,
                          color: AppThemePalette.primary,
                        ),
                        ...tenant.vehicles!.map((vehicle) => _VehicleCard(
                              vehicle: vehicle,
                              typeIcon: _getVehicleIcon(vehicle.type),
                              typeLabel: _getVehicleTypeDisplayName(
                                  vehicle.type),
                              parkingLabel: vehicle.isParkingRegistered &&
                                      vehicle.parkingSpot != null
                                  ? t.textWithParams(
                                      'tenant_vehicle_parking_spot',
                                      {'spot': vehicle.parkingSpot!})
                                  : null,
                              menuItems: const [],
                              onMenuSelected: (_) {},
                            )),
                      ],

                      // Rental history
                      if (tenant.previousRentals != null &&
                          tenant.previousRentals!.isNotEmpty) ...[
                        const _ContentDivider(),
                        _SectionLabel(
                          t.textWithParams(
                              'tenant_detail_history_section',
                              {'count': tenant.previousRentals!.length}),
                          icon: Icons.history_rounded,
                          color: const Color(0xFF854F0B),
                        ),
                        ...tenant.previousRentals!.map((rental) =>
                            _RentalHistoryEntry(
                              locationText: t.textWithParams(
                                  'tenant_location_value', {
                                'building': rental.buildingName,
                                'room': rental.roomNumber,
                              }),
                              dateRangeText: t.textWithParams(
                                  'tenant_detail_history_dates', {
                                'from': _formatDate(rental.moveInDate),
                                'to': _formatDate(rental.moveOutDate),
                              }),
                              durationText: t.textWithParams(
                                  'tenant_detail_days_value',
                                  {'days': rental.duration}),
                            )),
                      ],

                      const _ContentDivider(),
                      _DetailRow(
                        t['tenant_detail_status'],
                        tenant.getStatusDisplayName(t),
                        valueColor: _getTenantStatusColor(tenant.status),
                      ),
                    ],
                  ),
                ),
              ),

              _DialogActions(
                children: [
                  _ActionButton(
                    label: t['close'],
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // TENANT OPTIONS MENU
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showTenantOptionsMenu(
      Tenant tenant, bool isMovedOut) async {
    final t = AppTranslations.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isLargeScreen = screenWidth >= 600;

    Widget menuTile({
      required IconData icon,
      required String title,
      String? subtitle,
      Color? color,
      required VoidCallback onTap,
    }) {
      final c = color ?? Colors.grey.shade800;
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: c),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c)),
                    if (subtitle != null)
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 16, color: Colors.grey.shade300),
            ],
          ),
        ),
      );
    }

    Widget menuDivider() => Divider(
        height: 1,
        indent: 20,
        endIndent: 20,
        color: Colors.grey.shade100);

    List<Widget> menuItems = [
      menuTile(
        icon: Icons.info_outline_rounded,
        title: t['tenant_menu_view_detail'],
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
          _showTenantDetailDialog(
              tenant, building.name, room.roomNumber);
        },
      ),
      menuDivider(),
      menuTile(
        icon: Icons.edit_rounded,
        title: t['tenant_menu_edit'],
        color: AppThemePalette.primary,
        onTap: () {
          Navigator.pop(context);
          _showEditTenantDialog(tenant);
        },
      ),
      menuDivider(),
      menuTile(
        icon: Icons.swap_horiz_rounded,
        title: t['tenant_menu_move_room'],
        color: const Color(0xFF0F6E56),
        onTap: () {
          Navigator.pop(context);
          _showMoveRoomDialog(tenant);
        },
      ),
      if (!isMovedOut) ...[
        menuDivider(),
        menuTile(
          icon: Icons.logout_rounded,
          title: t['tenant_menu_move_out'],
          color: const Color(0xFF854F0B),
          onTap: () {
            Navigator.pop(context);
            _showMoveOutDialog(tenant);
          },
        ),
      ],
      menuDivider(),
      menuTile(
        icon: Icons.directions_car_rounded,
        title: t['tenant_menu_vehicles'],
        subtitle: tenant.vehicles != null && tenant.vehicles!.isNotEmpty
            ? t.textWithParams('tenant_vehicle_count',
                {'count': tenant.vehicles!.length})
            : null,
        color: AppThemePalette.primary,
        onTap: () {
          Navigator.pop(context);
          _showVehicleManagementDialog(tenant);
        },
      ),
      menuDivider(),
      menuTile(
        icon: Icons.history_rounded,
        title: t['tenant_menu_rental_history'],
        onTap: () {
          Navigator.pop(context);
          _showRentalHistoryDialog(tenant);
        },
      ),
      menuDivider(),
      menuTile(
        icon: Icons.delete_outline_rounded,
        title: t['tenant_menu_delete'],
        color: const Color(0xFFE74C3C),
        onTap: () {
          Navigator.pop(context);
          _confirmDeleteTenant(tenant);
        },
      ),
    ];

    // Options sheet header (not using _DialogHeader since it's a sheet)
    Widget sheetHeader = Container(
      decoration: BoxDecoration(gradient: _defaultHeaderGradient),
      padding: const EdgeInsets.fromLTRB(20, 16, 14, 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                tenant.fullName.isNotEmpty
                    ? tenant.fullName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tenant.fullName,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                Text(tenant.phoneNumber,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white70)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );

    final sheetContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isLargeScreen) const _SheetHandle(),
        sheetHeader,
        ...menuItems,
        const SizedBox(height: 8),
      ],
    );

    if (isLargeScreen) {
      await _showTrackedDialog(
        context: context,
        builder: (context) => _DialogShell(
          maxWidth: 380,
          maxHeightFactor: 0.85,
          child: SingleChildScrollView(child: sheetContent),
        ),
      );
    } else {
      await _showTrackedBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => SafeArea(
          child: SingleChildScrollView(child: sheetContent),
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // RENTAL HISTORY DIALOG
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showRentalHistoryDialog(Tenant tenant) async {
    await _showTrackedDialog(
      context: context,
      builder: (context) {
        final t = AppTranslations.of(context);
        return _DialogShell(
          maxWidth: 480,
          child: Column(
            children: [
              _DialogHeader(
                gradient: const LinearGradient(
                  colors: [Color(0xFF633806), Color(0xFF854F0B)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                leading: const Icon(Icons.history_rounded,
                    size: 22, color: Colors.white),
                title: t['tenant_rental_history_title'],
                subtitle: tenant.fullName,
                onClose: () => Navigator.pop(context),
              ),
              Flexible(
                child: tenant.previousRentals == null ||
                        tenant.previousRentals!.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_rounded,
                                size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text(t['tenant_rental_history_empty'],
                                style: TextStyle(
                                    color: Colors.grey.shade500)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: tenant.previousRentals!.length,
                        itemBuilder: (context, i) {
                          final r = tenant.previousRentals![i];
                          return _RentalHistoryEntry(
                            locationText: t.textWithParams(
                                'tenant_location_value', {
                              'building': r.buildingName,
                              'room': r.roomNumber,
                            }),
                            dateRangeText: t.textWithParams(
                                'tenant_detail_history_dates', {
                              'from': DateFormat.yMd()
                                  .format(r.moveInDate),
                              'to':
                                  DateFormat.yMd().format(r.moveOutDate),
                            }),
                            durationText: t.textWithParams(
                                'tenant_detail_days_value',
                                {'days': r.duration}),
                          );
                        },
                      ),
              ),
              _DialogActions(
                children: [
                  _ActionButton(
                      label: t['close'],
                      onPressed: () => Navigator.pop(context)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

}
