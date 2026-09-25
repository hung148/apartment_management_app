part of 'room_detail.dart';

// Tenant details, options, add/edit forms, move-out, deletion, and rental history.
// The room detail screen owns state, services, lifecycle, and subscriptions.
extension _RoomDetailTenantDialogs on _RoomDetailScreenState {
  // ═══════════════════════════════════════════════════════════════
  // ADD / EDIT TENANT DIALOG
  // ═══════════════════════════════════════════════════════════════
  void _showAddEditTenantDialog({Tenant? tenant}) {
    final isEditing = tenant != null;
    final nameController = TextEditingController(text: tenant?.fullName ?? '');
    final phoneController = TextEditingController(text: tenant?.phoneNumber ?? '');
    final emailController = TextEditingController(text: tenant?.email ?? '');
    final nationalIdController = TextEditingController(text: tenant?.nationalId ?? '');
    final occupationController = TextEditingController(text: tenant?.occupation ?? '');
    final workplaceController = TextEditingController(text: tenant?.workplace ?? '');
    final rentController = TextEditingController(
      text: (tenant?.monthlyRent == null ? null : CurrencyParser.format(tenant!.monthlyRent!)) ??
          (widget.room.roomPrice != null && widget.room.roomPrice! > 0
              ? CurrencyParser.format(widget.room.roomPrice!)
              : ''),
    );
    final depositController = TextEditingController(text: tenant?.deposit == null ? '' : CurrencyParser.format(tenant!.deposit!));
    final areaController = TextEditingController(text: tenant?.apartmentArea?.toString() ?? '');
    final typeController = TextEditingController(text: tenant?.apartmentType ?? '');

    Gender? selectedGender = tenant?.gender;
    bool isMainTenant = tenant?.isMainTenant ?? (_tenants?.isEmpty ?? true);
    DateTime moveInDate = tenant?.moveInDate ?? DateTime.now();
    DateTime? contractStartDate = tenant?.contractStartDate;
    DateTime? contractEndDate = tenant?.contractEndDate;
    bool isSaving = false;

    _showTrackedDialog(
      context: context,
      builder: (dialogContext) {
        final t = AppTranslations.of(dialogContext);
        return _DialogShell(
          maxWidth: 520,
          child: StatefulBuilder(
            builder: (context, setDialogState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogHeader(
                  gradient: isEditing
                      ? const LinearGradient(
                          colors: [Color(0xFF633806), Color(0xFFBA7517)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        )
                      : _kDefaultHeaderGradient,
                  leading: Icon(
                    isEditing ? Icons.edit_rounded : Icons.person_add_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                  title: isEditing
                      ? t['room_detail_edit_tenant_title']
                      : t['room_detail_add_tenant_title'],
                  subtitle: isEditing ? tenant!.fullName : null,
                  onClose: isSaving ? () {} : () => Navigator.pop(dialogContext),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(t['room_detail_section_contact'],
                            icon: Icons.contact_phone_rounded),
                        _inputField(nameController, t['room_detail_field_fullname'],
                            Icons.person_rounded, maxLength: 100),
                        _inputField(phoneController, t['room_detail_field_phone'],
                            Icons.phone_rounded,
                            keyboardType: TextInputType.phone, maxLength: 20),
                        _inputField(rentController, t['room_detail_field_rent'],
                            Icons.payments_rounded,
                            suffix: tenant?.currency ?? widget.room.currency,
                            keyboardType: TextInputType.number,
                            maxLength: 20),
                        const SizedBox(height: 4),
                        LocalizedDatePicker(
                          labelText: t['room_detail_field_movein'],
                          initialDate: moveInDate,
                          required: true,
                          prefixIcon: Icons.calendar_today_rounded,
                          onDateChanged: (date) {
                            if (date != null)
                              setDialogState(() => moveInDate = date);
                          },
                        ),
                        const _ContentDivider(),
                        _SectionLabel(t['room_detail_section_apartment'],
                            icon: Icons.apartment_rounded),
                        ResponsiveFormRow(children: [
                          Expanded(
                              child: _inputField(typeController,
                                  t['room_detail_field_apt_type'],
                                  Icons.category_rounded,
                                  maxLength: 50)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _inputField(areaController,
                                  t['room_detail_field_area'],
                                  Icons.square_foot_rounded,
                                  suffix: 'm²',
                                  keyboardType: TextInputType.number,
                                  maxLength: 10)),
                        ]),
                        const _ContentDivider(),
                        _SectionLabel(t['room_detail_section_personal'],
                            icon: Icons.person_rounded),
                        _inputField(emailController, t['room_detail_field_email'],
                            Icons.email_rounded,
                            keyboardType: TextInputType.emailAddress,
                            maxLength: 254),
                        _inputField(nationalIdController,
                            t['room_detail_field_national_id'],
                            Icons.badge_rounded, maxLength: 20),
                        _inputField(occupationController,
                            t['room_detail_field_occupation'],
                            Icons.work_rounded, maxLength: 100),
                        _inputField(workplaceController,
                            t['room_detail_field_workplace'],
                            Icons.location_city_rounded, maxLength: 150),
                        _dropdownField<Gender>(
                          label: t['room_detail_field_gender'],
                          value: selectedGender,
                          items: Gender.values
                              .map((g) => DropdownMenuItem(
                                  value: g,
                                  child: Text(_getGenderDisplayName(context, g))))
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => selectedGender = v),
                        ),
                        const _ContentDivider(),
                        _SectionLabel(t['room_detail_section_contract'],
                            icon: Icons.description_rounded),
                        _inputField(depositController,
                            t['room_detail_field_deposit'],
                            Icons.account_balance_wallet_rounded,
                            suffix: tenant?.currency ?? widget.room.currency,
                            keyboardType: TextInputType.number,
                            maxLength: 20),
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: CheckboxListTile(
                            title: Text(t['room_detail_field_main_tenant'],
                                style: const TextStyle(fontSize: 14)),
                            value: isMainTenant,
                            activeColor: AppThemePalette.primary,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            onChanged: (v) =>
                                setDialogState(() => isMainTenant = v ?? true),
                          ),
                        ),
                        _ContractDateTile(
                          label: t['room_detail_field_contract_start'],
                          noDateLabel: t['room_detail_contract_no_date'],
                          icon: Icons.description_rounded,
                          date: contractStartDate,
                          formatDate: _formatDate,
                          onPick: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: contractStartDate ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (d != null)
                              setDialogState(() => contractStartDate = d);
                          },
                          onClear: () =>
                              setDialogState(() => contractStartDate = null),
                        ),
                        const SizedBox(height: 8),
                        _ContractDateTile(
                          label: t['room_detail_field_contract_end'],
                          noDateLabel: t['room_detail_contract_no_date'],
                          icon: Icons.event_busy_rounded,
                          date: contractEndDate,
                          formatDate: _formatDate,
                          onPick: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: contractEndDate ??
                                  DateTime.now().add(const Duration(days: 365)),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (d != null)
                              setDialogState(() => contractEndDate = d);
                          },
                          onClear: () =>
                              setDialogState(() => contractEndDate = null),
                        ),
                      ],
                    ),
                  ),
                ),
                _DialogActions(children: [
                  _ActionButton(
                      label: t['cancel'],
                      onPressed: isSaving
                          ? null
                          : () => Navigator.pop(dialogContext)),
                  _ActionButton(
                    label: isEditing
                        ? t['room_detail_save_changes']
                        : t['room_detail_add_action'],
                    primary: true,
                    icon: isEditing
                        ? Icons.check_rounded
                        : Icons.person_add_rounded,
                    onPressed: isSaving
                        ? null
                        : () async {
                            if (nameController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(t['room_detail_err_name'])));
                              return;
                            }
                            if (phoneController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(t['room_detail_err_phone'])));
                              return;
                            }
                            setDialogState(() => isSaving = true);
                            // Capture translated strings before async gap
                            final msgUpdate = t['room_detail_update_success'];
                            final msgAdd    = t['room_detail_add_success'];
                            final msgErrTpl = t['room_detail_err_generic'];
                            try {
                              final newTenant = Tenant(
                                currency: tenant?.currency ?? widget.room.currency,
                                id: tenant?.id ?? '',
                                organizationId: widget.room.organizationId,
                                buildingId: widget.room.buildingId,
                                roomId: widget.room.id,
                                fullName: nameController.text.trim(),
                                phoneNumber: phoneController.text.trim(),
                                email: emailController.text.trim().isEmpty
                                    ? null
                                    : emailController.text.trim(),
                                nationalId: nationalIdController.text.trim().isEmpty
                                    ? null
                                    : nationalIdController.text.trim(),
                                occupation: occupationController.text.trim().isEmpty
                                    ? null
                                    : occupationController.text.trim(),
                                workplace: workplaceController.text.trim().isEmpty
                                    ? null
                                    : workplaceController.text.trim(),
                                gender: selectedGender,
                                isMainTenant: isMainTenant,
                                monthlyRent: rentController.text.isNotEmpty
                                    ? CurrencyParser.tryParse(rentController.text)
                                    : null,
                                deposit: depositController.text.isNotEmpty
                                    ? CurrencyParser.tryParse(depositController.text)
                                    : null,
                                apartmentArea: areaController.text.isNotEmpty
                                    ? double.tryParse(areaController.text)
                                    : null,
                                apartmentType: typeController.text.trim().isEmpty
                                    ? null
                                    : typeController.text.trim(),
                                moveInDate: moveInDate,
                                contractStartDate: contractStartDate,
                                contractEndDate: contractEndDate,
                                status: TenantStatus.active,
                                createdAt: tenant?.createdAt ?? DateTime.now(),
                              );

                              if (isEditing) {
                                await widget.tenantService.updateTenant(
                                    tenant!.id, {
                                  'currency': newTenant.currency,
                                  'fullName': newTenant.fullName,
                                  'phoneNumber': newTenant.phoneNumber,
                                  'email': newTenant.email,
                                  'nationalId': newTenant.nationalId,
                                  'occupation': newTenant.occupation,
                                  'workplace': newTenant.workplace,
                                  'gender': newTenant.gender?.name,
                                  'isMainTenant': newTenant.isMainTenant,
                                  'monthlyRent': newTenant.monthlyRent,
                                  'deposit': newTenant.deposit,
                                  'apartmentArea': newTenant.apartmentArea,
                                  'apartmentType': newTenant.apartmentType,
                                  'moveInDate': newTenant.moveInDate,
                                  'contractStartDate': newTenant.contractStartDate,
                                  'contractEndDate': newTenant.contractEndDate,
                                });
                                if (mounted) {
                                  Navigator.pop(dialogContext);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(msgUpdate)));
                                }
                              } else {
                                await widget.tenantService.addTenant(newTenant);
                                if (mounted) {
                                  Navigator.pop(dialogContext);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(msgAdd)));
                                }
                              }
                            } catch (e) {
                              setDialogState(() => isSaving = false);
                              if (mounted) {
                                final errMsg = msgErrTpl.replaceAll('{{error}}', e.toString());
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(errMsg),
                                    backgroundColor: Colors.red));
                              }
                            }
                          },
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getGenderDisplayName(BuildContext context, Gender g) {
    final t = AppTranslations.of(context);
    switch (g) {
      case Gender.male:   return t['gender_male'];
      case Gender.female: return t['gender_female'];
      case Gender.other:  return t['gender_other'];
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // TENANT DETAIL DIALOG
  // ═══════════════════════════════════════════════════════════════
  void _showTenantDetailDialog(Tenant tenant) async {
    final bool isMovedOut = tenant.status == TenantStatus.moveOut;
    final accentColor =
        isMovedOut ? Colors.grey.shade600 : const Color(0xFF185FA5);
    final gradient = isMovedOut
        ? LinearGradient(
            colors: [Colors.blueGrey.shade700, Colors.blueGrey.shade500],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          )
        : _kDefaultHeaderGradient;

    final building =
        await widget.buildingService.getBuildingById(tenant.buildingId);
    final buildingName = building?.name ?? '—';
    if (!mounted) return;

    final membership = await _getMyMembership();
    if (!mounted) return;

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
                          color: Colors.white),
                    ),
                  ),
                ),
                title: tenant.fullName,
                subtitle: tenant.isMainTenant
                    ? t['room_detail_main_tenant_badge']
                    : tenant.phoneNumber,
                actions: membership?.role == 'admin'
                    ? [
                        TextButton.icon(
                          icon: const Icon(Icons.more_horiz_rounded, size: 16),
                          label: Text(t['room_detail_options_btn']),
                          onPressed: () {
                            Navigator.pop(context);
                            _showTenantOptionsMenu(tenant);
                          },
                        ),
                      ]
                    : null,
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionLabel(
                          isMovedOut
                              ? t['tenant_detail_previous_location']
                              : t['tenant_detail_location'],
                          color: accentColor,
                          icon: Icons.location_on_rounded),
                      _DetailCard(
                        borderColor: accentColor.withValues(alpha: 0.2),
                        fillColor: accentColor.withValues(alpha: 0.05),
                        rows: [
                          _DetailRow(t['tenant_detail_building'], buildingName),
                          _DetailRow(t['tenant_detail_room'], widget.room.roomNumber),
                        ],
                      ),
                      const _ContentDivider(),
                      _SectionLabel(t['tenant_detail_contact_section'],
                          icon: Icons.contact_phone_rounded),
                      _DetailCard(rows: [
                        _DetailRow(t['tenant_detail_phone'], tenant.phoneNumber),
                        if (tenant.email != null)
                          _DetailRow(t['tenant_detail_email'], tenant.email!),
                      ]),
                      const _ContentDivider(),
                      _SectionLabel(t['tenant_detail_personal_section'],
                          icon: Icons.person_rounded),
                      _DetailCard(rows: [
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
                      ]),
                      if (!isMovedOut) ...[
                        const _ContentDivider(),
                        _SectionLabel(t['tenant_detail_rental_section'],
                            icon: Icons.home_rounded),
                        _DetailCard(rows: [
                          _DetailRow(t['tenant_detail_move_in_date'],
                              _formatDate(tenant.moveInDate)),
                          _DetailRow(t['tenant_detail_days_living'],
                              t.textWithParams('tenant_detail_days_value',
                                  {'days': tenant.daysLiving})),
                          if (tenant.monthlyRent != null)
                            _DetailRow(t['tenant_detail_monthly_rent'],
                                _formatCurrency(tenant.monthlyRent!,tenant.currency),
                                valueColor: const Color(0xFF3B6D11)),
                          if (tenant.deposit != null)
                            _DetailRow(t['tenant_detail_deposit'],
                                _formatCurrency(tenant.deposit!,tenant.currency)),
                          if (tenant.apartmentType != null &&
                              tenant.apartmentType!.isNotEmpty)
                            _DetailRow(t['tenant_detail_apartment_type'],
                                tenant.apartmentType!),
                          if (tenant.apartmentArea != null &&
                              tenant.apartmentArea! > 0)
                            _DetailRow(t['tenant_detail_area'],
                                t.textWithParams('tenant_detail_area_value',
                                    {'area': tenant.apartmentArea})),
                        ]),
                      ],
                      if (isMovedOut && tenant.moveOutDate != null) ...[
                        const _ContentDivider(),
                        _SectionLabel(t['tenant_detail_moveout_section'],
                            icon: Icons.logout_rounded,
                            color: const Color(0xFF854F0B)),
                        _DetailCard(
                          borderColor:
                              const Color(0xFF854F0B).withValues(alpha: 0.2),
                          fillColor:
                              const Color(0xFF854F0B).withValues(alpha: 0.04),
                          rows: [
                            _DetailRow(t['tenant_detail_move_out_date'],
                                _formatDate(tenant.moveOutDate!)),
                            _DetailRow(t['tenant_detail_duration'],
                                t.textWithParams('tenant_detail_days_value', {
                                  'days': tenant.moveOutDate!
                                      .difference(tenant.moveInDate)
                                      .inDays
                                })),
                            if (tenant.contractTerminationReason != null)
                              _DetailRow(t['tenant_detail_reason'],
                                  tenant.contractTerminationReason!),
                            if (tenant.notes != null && tenant.notes!.isNotEmpty)
                              _DetailRow(t['tenant_detail_notes'], tenant.notes!),
                          ],
                        ),
                      ],
                      if (tenant.contractStartDate != null ||
                          tenant.contractEndDate != null) ...[
                        const _ContentDivider(),
                        _SectionLabel(t['tenant_detail_contract_section'],
                            icon: Icons.description_rounded),
                        _DetailCard(rows: [
                          if (tenant.contractStartDate != null)
                            _DetailRow(t['tenant_detail_contract_start'],
                                _formatDate(tenant.contractStartDate!)),
                          if (tenant.contractEndDate != null)
                            _DetailRow(
                                isMovedOut
                                    ? t['tenant_detail_contract_end_date']
                                    : t['tenant_detail_contract_end'],
                                _formatDate(tenant.contractEndDate!)),
                          if (isMovedOut) ...[
                            _DetailRow(t['tenant_detail_contract_status'],
                                tenant.getContractStatusDisplayName(t)),
                            if (tenant.moveOutDate != null &&
                                tenant.contractEndDate != null)
                              _DetailRow(
                                tenant.moveOutDate!
                                        .isBefore(tenant.contractEndDate!)
                                    ? t['tenant_detail_early_termination']
                                    : t['tenant_detail_end_label'],
                                tenant.moveOutDate!
                                        .isBefore(tenant.contractEndDate!)
                                    ? t.textWithParams(
                                        'tenant_detail_days_early', {
                                        'days': tenant.contractEndDate!
                                            .difference(tenant.moveOutDate!)
                                            .inDays
                                      })
                                    : t['tenant_detail_on_time'],
                                valueColor: tenant.moveOutDate!
                                        .isBefore(tenant.contractEndDate!)
                                    ? const Color(0xFF854F0B)
                                    : const Color(0xFF3B6D11),
                              ),
                          ] else if (tenant.daysUntilContractEnd != null)
                            _DetailRow(
                                t['tenant_detail_remaining'],
                                t.textWithParams('tenant_detail_days_value', {
                                  'days': tenant.daysUntilContractEnd
                                })),
                        ]),
                      ],
                      if (tenant.vehicles != null &&
                          tenant.vehicles!.isNotEmpty) ...[
                        const _ContentDivider(),
                        _SectionLabel(
                            t.textWithParams('tenant_detail_vehicles_section',
                                {'count': tenant.vehicles!.length}),
                            icon: Icons.directions_car_rounded,
                            color: const Color(0xFF534AB7)),
                        ...tenant.vehicles!.map((v) => _VehicleCard(
                              vehicle: v,
                              typeIcon: _getVehicleIcon(v.type),
                              typeLabel: _getVehicleTypeDisplayName(context, v.type),
                              parkingLabel: v.isParkingRegistered &&
                                      v.parkingSpot != null
                                  ? t.textWithParams(
                                      'tenant_vehicle_parking_spot',
                                      {'spot': v.parkingSpot!})
                                  : null,
                              menuItems: const [],
                              onMenuSelected: (_) {},
                            )),
                      ],
                      if (tenant.previousRentals != null &&
                          tenant.previousRentals!.isNotEmpty) ...[
                        const _ContentDivider(),
                        _SectionLabel(
                            t.textWithParams('tenant_detail_history_section',
                                {'count': tenant.previousRentals!.length}),
                            icon: Icons.history_rounded,
                            color: const Color(0xFF854F0B)),
                        ...tenant.previousRentals!.map((r) =>
                            _RentalHistoryEntry(
                              locationText:
                                  '${r.buildingName} - ${t['tenant_detail_room']} ${r.roomNumber}',
                              dateRangeText: t.textWithParams(
                                  'tenant_detail_history_dates', {
                                'from': _formatDate(r.moveInDate),
                                'to': _formatDate(r.moveOutDate),
                              }),
                              durationText: t.textWithParams(
                                  'tenant_detail_days_value',
                                  {'days': r.duration}),
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
              _DialogActions(children: [
                _ActionButton(
                    label: t['room_detail_close_btn'],
                    onPressed: () => Navigator.pop(context)),
              ]),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // TENANT OPTIONS MENU
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showTenantOptionsMenu(Tenant tenant) async {
    final isMovedOut = tenant.status == TenantStatus.moveOut;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isLargeScreen = screenWidth >= 600;
    final t = AppTranslations.of(context);

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
        height: 1, indent: 20, endIndent: 20, color: Colors.grey.shade100);

    final menuItems = [
      menuTile(
          icon: Icons.info_outline_rounded,
          title: t['room_detail_menu_view'],
          onTap: () {
            Navigator.pop(context);
            _showTenantDetailDialog(tenant);
          }),
      menuDivider(),
      menuTile(
          icon: Icons.edit_rounded,
          title: t['room_detail_menu_edit'],
          color: AppThemePalette.primary,
          onTap: () {
            Navigator.pop(context);
            _showAddEditTenantDialog(tenant: tenant);
          }),
      menuDivider(),
      if (!isMovedOut) ...[
        menuTile(
            icon: Icons.logout_rounded,
            title: t['room_detail_menu_moveout'],
            color: const Color(0xFF854F0B),
            onTap: () {
              Navigator.pop(context);
              _confirmMoveOut(tenant);
            }),
        menuDivider(),
      ],
      menuTile(
          icon: Icons.directions_car_rounded,
          title: t['room_detail_menu_vehicles'],
          subtitle: tenant.vehicles != null && tenant.vehicles!.isNotEmpty
              ? t.textWithParams('room_detail_vehicle_count',
                  {'count': tenant.vehicles!.length})
              : null,
          color: const Color(0xFF534AB7),
          onTap: () {
            Navigator.pop(context);
            _showVehicleManagementDialog(tenant);
          }),
      menuDivider(),
      menuTile(
          icon: Icons.history_rounded,
          title: t['room_detail_menu_history'],
          onTap: () {
            Navigator.pop(context);
            _showRentalHistoryDialog(tenant);
          }),
      menuDivider(),
      menuTile(
          icon: Icons.delete_outline_rounded,
          title: t['room_detail_menu_delete'],
          color: const Color(0xFFE74C3C),
          onTap: () {
            Navigator.pop(context);
            _confirmDeleteTenant(tenant);
          }),
    ];

    Widget sheetHeader = Container(
      decoration: BoxDecoration(gradient: _kDefaultHeaderGradient),
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
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) =>
            SafeArea(child: SingleChildScrollView(child: sheetContent)),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // MOVE OUT DIALOG
  // ═══════════════════════════════════════════════════════════════
  Future<void> _confirmMoveOut(Tenant tenant) async {
    // Capture translations before async gap
    final t = AppTranslations.of(context);
    final reasonOptions = [
      t['room_detail_moveout_reason_1'],
      t['room_detail_moveout_reason_2'],
      t['room_detail_moveout_reason_3'],
      t['room_detail_moveout_reason_4'],
      t['room_detail_moveout_reason_5'],
    ];
    final msgSuccess = t['room_detail_moveout_success'];
    final msgFailed  = t['room_detail_moveout_failed'];

    DateTime selectedDate = DateTime.now();
    String? selectedReason = reasonOptions.first;

    final result = await _showTrackedDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final td = AppTranslations.of(context);
          final bool isEarly = tenant.contractEndDate != null &&
              selectedDate.isBefore(tenant.contractEndDate!);
          return _DialogShell(
            maxWidth: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogHeader(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF633806), Color(0xFF854F0B)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  leading: const Icon(Icons.logout_rounded,
                      size: 20, color: Colors.white),
                  title: td['room_detail_moveout_title'],
                  onClose: _doNothing,
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(td['confirm'],
                            icon: Icons.info_outline_rounded,
                            color: const Color(0xFF854F0B)),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF854F0B).withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: const Color(0xFF854F0B)
                                    .withValues(alpha: 0.2)),
                          ),
                          child: Text(
                            td.textWithParams('room_detail_moveout_confirm',
                                {'name': tenant.fullName}),
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey.shade700),
                          ),
                        ),
                        const SizedBox(height: 16),
                        LocalizedDatePicker(
                          labelText: td['room_detail_moveout_date'],
                          initialDate: selectedDate,
                          required: true,
                          prefixIcon: Icons.calendar_today_rounded,
                          onDateChanged: (date) {
                            if (date != null)
                              setDialogState(() => selectedDate = date);
                          },
                        ),
                        const SizedBox(height: 12),
                        _dropdownField<String>(
                          label: td['room_detail_moveout_reason'],
                          value: selectedReason,
                          items: reasonOptions
                              .map((r) => DropdownMenuItem(
                                  value: r, child: Text(r)))
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => selectedReason = v),
                        ),
                        if (isEarly) ...[
                          const SizedBox(height: 4),
                          _InfoBanner(
                            icon: Icons.warning_amber_rounded,
                            color: const Color(0xFF854F0B),
                            text: td.textWithParams(
                                'room_detail_moveout_early_warn', {
                              'days': tenant.contractEndDate!
                                  .difference(selectedDate)
                                  .inDays
                            }),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                _DialogActions(children: [
                  _ActionButton(
                      label: td['cancel'],
                      onPressed: () => Navigator.pop(context)),
                  _ActionButton(
                    label: td['room_detail_moveout_confirm_btn'],
                    primary: true,
                    icon: Icons.logout_rounded,
                    onPressed: () => Navigator.pop(context, {
                      'date': selectedDate,
                      'reason': selectedReason,
                    }),
                  ),
                ]),
              ],
            ),
          );
        },
      ),
    );

    if (result != null) {
      final success = await widget.tenantService.markTenantAsMovedOut(
        tenant.id,
        moveOutDate: result['date'],
        moveOutReason: result['reason'],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success ? msgSuccess : msgFailed),
          backgroundColor: success ? const Color(0xFF3B6D11) : Colors.red,
        ));
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // DELETE TENANT
  // ═══════════════════════════════════════════════════════════════
  Future<void> _confirmDeleteTenant(Tenant tenant) async {
    final t = AppTranslations.of(context);
    final ok = await _showConfirmDialog(
      title: t['room_detail_del_tenant_title'],
      message: t.textWithParams(
          'room_detail_del_tenant_msg', {'name': tenant.fullName}),
      confirmLabel: t['room_detail_del_tenant_action'],
      destructive: true,
    );
    if (ok == true) {
      // Capture before async
      final msgSuccess = t['room_detail_del_tenant_success'];
      final msgFailed  = t['room_detail_del_tenant_failed'];
      final success = await widget.tenantService.deleteTenant(tenant.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success ? msgSuccess : msgFailed),
          backgroundColor: success ? const Color(0xFF3B6D11) : Colors.red,
        ));
      }
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
                title: t['room_detail_history_title'],
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
                            Text(t['room_detail_history_empty'],
                                style:
                                    TextStyle(color: Colors.grey.shade500)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: tenant.previousRentals!.length,
                        itemBuilder: (context, i) {
                          final r = tenant.previousRentals![i];
                          return _RentalHistoryEntry(
                            locationText:
                                '${r.buildingName} - ${t['tenant_detail_room']} ${r.roomNumber}',
                            dateRangeText: t.textWithParams(
                                'room_detail_history_from_to', {
                              'from': DateFormat.yMd().format(r.moveInDate),
                              'to': DateFormat.yMd().format(r.moveOutDate),
                            }),
                            durationText: t.textWithParams(
                                'room_detail_history_duration',
                                {'days': r.duration}),
                          );
                        },
                      ),
              ),
              _DialogActions(children: [
                _ActionButton(
                    label: t['room_detail_close_btn'],
                    onPressed: () => Navigator.pop(context)),
              ]),
            ],
          ),
        );
      },
    );
  }

}

// ─── Contract date tile ───────────────────────────────────────────────────────
class _ContractDateTile extends StatelessWidget {
  final String label;
  final String noDateLabel;
  final IconData icon;
  final DateTime? date;
  final String Function(DateTime) formatDate;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _ContractDateTile({
    required this.label,
    required this.noDateLabel,
    required this.icon,
    required this.date,
    required this.formatDate,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Icon(icon, size: 18, color: Colors.grey.shade600),
        title: Text(label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        subtitle: Text(
          date != null ? formatDate(date!) : noDateLabel,
          style: TextStyle(
            fontSize: 14,
            fontWeight: date != null ? FontWeight.w600 : FontWeight.normal,
            color: date != null ? Colors.grey.shade800 : Colors.grey.shade400,
          ),
        ),
        onTap: onPick,
        trailing: date != null
            ? IconButton(
                icon: Icon(Icons.clear_rounded,
                    size: 16, color: Colors.grey.shade600),
                onPressed: onClear,
              )
            : Icon(Icons.calendar_today_rounded,
                size: 16, color: Colors.grey.shade600),
      ),
    );
  }
}

