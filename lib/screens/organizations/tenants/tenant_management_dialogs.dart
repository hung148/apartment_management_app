part of 'tenant_tab.dart';

// Add and edit tenants, move rooms, move out, and delete tenants.
// The tenant tab owns state, services, lifecycle, and refresh callbacks.
extension _TenantManagementDialogs on _TenantsTabState {
  // ═══════════════════════════════════════════════════════════════
  // ADD TENANT DIALOG
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showAddTenantDialog(
      List<Building> buildings, List<Room> allRooms) async {
    final Set<String> occupiedRoomIds = _allTenants
        .where((t) => t.status == TenantStatus.active && t.isMainTenant)
        .map((t) => t.roomId)
        .toSet();

    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final nationalIdController = TextEditingController();
    final occupationController = TextEditingController();
    final workplaceController = TextEditingController();
    final monthlyRentController = TextEditingController();
    final areaController = TextEditingController();
    String selectedAptType = normalizeAptType(null);

    String? selectedBuildingId =
        buildings.isNotEmpty ? buildings.first.id : null;
    String? selectedRoomId;
    String selectedCurrency = AppTranslations.of(context).defaultCurrency;
    TenantStatus selectedStatus = TenantStatus.active;
    bool isMainTenant = true;
    DateTime moveInDate = DateTime.now();

    final result = await _showTrackedDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final t = AppTranslations.of(context);
          final availableRooms = allRooms
              .where((r) => r.buildingId == selectedBuildingId)
              .toList();

          final aptTypeOptions = kApartmentTypes.contains(selectedAptType)
            ? kApartmentTypes
            : [selectedAptType, ...kApartmentTypes];

          return _DialogShell(
            maxWidth: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogHeader(
                  leading: const Icon(Icons.person_add_rounded,
                      size: 20, color: Colors.white),
                  title: t['tenant_add_title'],
                  onClose: () => Navigator.pop(context),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(
                          t['tenant_detail_contact_section'],
                          icon: Icons.contact_phone_rounded,
                        ),
                        _inputField(
                            nameController,
                            t['tenant_field_name_required'],
                            Icons.person_rounded,
                            maxLength: 100),
                        _inputField(
                          phoneController,
                          t['tenant_field_phone_required'],
                          Icons.phone_rounded,
                          keyboardType: TextInputType.phone,
                          maxLength: 15,
                        ),
                        const _ContentDivider(),

                        _SectionLabel(
                          t['tenant_detail_location'],
                          icon: Icons.location_on_rounded,
                        ),
                        ComboBoxField<Building>(
                          options: buildings,
                          labelOf: (b) => b.name,
                          selected: buildings
                              .where((b) => b.id == selectedBuildingId)
                              .firstOrNull,
                          icon: Icons.apartment_rounded,
                          label: t['tenant_field_building'],
                          onSelected: (building) {
                            setDialogState(() {
                              selectedBuildingId = building?.id;
                              selectedRoomId = null;
                            });
                          },
                        ),
                        ComboBoxField<Room>(
                          options: availableRooms,
                          labelOf: (r) => t.textWithParams(
                            occupiedRoomIds.contains(r.id)
                                ? 'tenant_room_occupied'
                                : 'tenant_room_vacant',
                            {'number': r.roomNumber},
                          ),
                          colorOf: (r) => occupiedRoomIds.contains(r.id)
                              ? const Color(0xFFDC2626) // red — occupied
                              : const Color(0xFF3B6D11), // green — vacant
                          isSelectable: (r) => !occupiedRoomIds.contains(r.id),
                          selected: availableRooms
                              .where((r) => r.id == selectedRoomId)
                              .firstOrNull,
                          enabled: selectedBuildingId != null,
                          icon: Icons.door_front_door_rounded,
                          label: t['tenant_field_room'],
                          onSelected: (room) {
                            if (room == null) return;
                            setDialogState(() {
                              selectedRoomId = room.id;
                              selectedCurrency = room.currency;
                              areaController.text = room.area.toString();
                              selectedAptType = normalizeAptType(room.roomType);
                              // Prefill monthly rent from the room's default
                              // price, but don't clobber a value the admin
                              // already typed in.
                              if (monthlyRentController.text.isEmpty &&
                                  room.roomPrice != null &&
                                  room.roomPrice! > 0) {
                                monthlyRentController.text =
                                    CurrencyParser.format(room.roomPrice!);
                              }
                            });
                          },
                        ),

                        Row(
                          children: [
                            Expanded(
                              child: ComboBoxField<TenantStatus>(
                                options: TenantStatus.values,
                                labelOf: (s) {
                                  switch (s) {
                                    case TenantStatus.active:
                                      return t['tenant_status_active'];
                                    case TenantStatus.inactive:
                                      return t['tenant_status_inactive'];
                                    case TenantStatus.moveOut:
                                      return t['tenant_status_moved_out'];
                                    case TenantStatus.suspended:
                                      return t['tenant_status_suspended'];
                                  }
                                },
                                selected: selectedStatus,
                                icon: Icons.toggle_on_rounded,
                                label: t['tenant_field_status'],
                                onSelected: (val) {
                                  if (val != null) {
                                    setDialogState(() => selectedStatus = val);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: isMainTenant,
                                    activeColor: AppThemePalette.primary,
                                    onChanged: (val) => setDialogState(
                                        () => isMainTenant = val ?? true),
                                  ),
                                  Flexible(
                                    child: Text(
                                        t['tenant_field_main_tenant'],
                                        style: const TextStyle(
                                            fontSize: 13)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const _ContentDivider(),
                        _SectionLabel(
                          t['tenant_detail_rental_section'],
                          icon: Icons.payments_rounded,
                        ),
                        _inputField(
                            monthlyRentController,
                            t['tenant_field_rent_required'],
                            Icons.payments_rounded,
                            suffix: selectedCurrency,
                            keyboardType: TextInputType.number,
                            maxLength: 24),
                        const SizedBox(height: 4),
                        LocalizedDatePicker(
                          labelText: t['tenant_field_move_in_date'],
                          initialDate: moveInDate,
                          required: true,
                          prefixIcon: Icons.calendar_today_rounded,
                          onDateChanged: (date) {
                            if (date != null)
                              {setDialogState(() => moveInDate = date);}
                          },
                        ),
                        const _ContentDivider(),
                        _SectionLabel(
                          t['tenant_section_invoice_apt'],
                          icon: Icons.apartment_rounded,
                        ),
                        Row(
                          children: [
                            Expanded(
                                child: ComboBoxField<String>(
                                options: aptTypeOptions,
                                labelOf: (v) => aptTypeLabel(t, v),
                                selected: selectedAptType,
                                icon: Icons.category_rounded,
                                label: t['tenant_field_apt_type'],
                                onSelected: (v) {
                                  if (v != null) setDialogState(() => selectedAptType = v);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                                child: _inputField(
                                    areaController,
                                    t['tenant_field_area'],
                                    Icons.square_foot_rounded,
                                    suffix: 'm²',
                                    keyboardType: TextInputType.number,
                                    maxLength: 6)),
                          ],
                        ),
                        const _ContentDivider(),
                        _SectionLabel(
                          t['tenant_detail_personal_section'],
                          icon: Icons.person_rounded,
                        ),
                        _inputField(
                            emailController,
                            t['tenant_field_email'],
                            Icons.email_rounded,
                            keyboardType: TextInputType.emailAddress,
                            maxLength: 100),
                        _inputField(
                            nationalIdController,
                            t['tenant_field_national_id'],
                            Icons.badge_rounded,
                            maxLength: 24),
                        _inputField(
                            occupationController,
                            t['tenant_field_occupation'],
                            Icons.work_rounded,
                            maxLength: 100),
                        _inputField(
                            workplaceController,
                            t['tenant_field_workplace'],
                            Icons.location_city_rounded,
                            maxLength: 150),
                      ],
                    ),
                  ),
                ),
                _DialogActions(
                  children: [
                    _ActionButton(
                        label: t['cancel'],
                        onPressed: () => Navigator.pop(context)),
                    _ActionButton(
                      label: t['tenant_add_action'],
                      primary: true,
                      icon: Icons.person_add_rounded,
                      onPressed: () {
                        if (nameController.text.isEmpty ||
                            selectedRoomId == null) {return;}
                        Navigator.pop(context, {
                          'fullName': nameController.text.trim(),
                          'phoneNumber': phoneController.text.trim(),
                          'email': emailController.text.trim(),
                          'nationalId': nationalIdController.text.trim(),
                          'occupation':
                              occupationController.text.trim(),
                          'workplace': workplaceController.text.trim(),
                          'buildingId': selectedBuildingId,
                          'roomId': selectedRoomId,
                          'currency': selectedCurrency,
                          'monthlyRent':
                              CurrencyParser.tryParse(monthlyRentController.text) ??
                              0,
                          'apartmentArea':
                              double.tryParse(areaController.text) ?? 0,
                          'apartmentType': selectedAptType,
                          'isMainTenant': isMainTenant,
                          'status': selectedStatus,
                          'moveInDate': moveInDate,
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    nationalIdController.dispose();
    occupationController.dispose();
    workplaceController.dispose();
    monthlyRentController.dispose();
    areaController.dispose();

    if (result != null) {
      final tenant = Tenant(
        id: '',
        organizationId: widget.organization.id,
        buildingId: result['buildingId'],
        roomId: result['roomId'],
        fullName: result['fullName'],
        phoneNumber: result['phoneNumber'],
        email: result['email'],
        nationalId: result['nationalId'],
        occupation: result['occupation'],
        workplace: result['workplace'],
        isMainTenant: result['isMainTenant'],
        monthlyRent: result['monthlyRent'],
        currency: result['currency'] as String? ?? 'VND',
        apartmentArea: result['apartmentArea'],
        apartmentType: result['apartmentType'],
        status: result['status'],
        moveInDate: result['moveInDate'],
        createdAt: DateTime.now(),
      );
      await widget.tenantService.addTenant(tenant);
      _refreshAll();
      widget.onChanged?.call();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // EDIT TENANT DIALOG
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showEditTenantDialog(Tenant tenant) async {
    await _getBuildings();
    await _getAllRooms();
    if (!mounted) return;

    final nameController = TextEditingController(text: tenant.fullName);
    final phoneController =
        TextEditingController(text: tenant.phoneNumber);
    final emailController = TextEditingController(text: tenant.email);
    final nationalIdController =
        TextEditingController(text: tenant.nationalId);
    final occupationController =
        TextEditingController(text: tenant.occupation);
    final workplaceController =
        TextEditingController(text: tenant.workplace);
    final monthlyRentController = TextEditingController(
        text: tenant.monthlyRent == null ? '' : CurrencyParser.format(tenant.monthlyRent!));
    final areaController =
        TextEditingController(text: tenant.apartmentArea?.toString() ?? '');
    // Normalize once, up front — keys only from here on out.
    String selectedAptType = normalizeAptType(tenant.apartmentType);

    DateTime editedMoveInDate = tenant.moveInDate;

    // Rooms occupied by OTHER active main tenants (exclude this tenant's own room)
    final Set<String> occupiedRoomIds = _allTenants
        .where((t) =>
            t.id != tenant.id &&
            t.status == TenantStatus.active &&
            t.isMainTenant)
        .map((t) => t.roomId)
        .toSet();

    String? selectedBuildingId =
        tenant.buildingId.isNotEmpty ? tenant.buildingId : null;
    String? selectedRoomId =
        tenant.roomId.isNotEmpty ? tenant.roomId : null;

    final result = await _showTrackedDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final t = AppTranslations.of(context);
          final availableRooms = _rooms
              .where((r) => r.buildingId == selectedBuildingId)
              .toList();

          // Keys, not labels. Inject the current key if it's not one of
          // the canonical four (legacy/custom values still get shown).
          final aptTypeOptions = kApartmentTypes.contains(selectedAptType)
              ? kApartmentTypes
              : [selectedAptType, ...kApartmentTypes];

          return _DialogShell(
            maxWidth: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogHeader(
                  leading: const Icon(Icons.edit_rounded,
                      size: 20, color: Colors.white),
                  title: t['tenant_edit_title'],
                  subtitle: tenant.fullName,
                  onClose: () => Navigator.pop(context),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(
                          t['tenant_detail_contact_section'],
                          icon: Icons.contact_phone_rounded,
                        ),
                        _inputField(
                            nameController,
                            t['tenant_field_name'],
                            Icons.person_rounded,
                            maxLength: 100),
                        _inputField(
                          phoneController,
                          t['tenant_field_phone'],
                          Icons.phone_rounded,
                          keyboardType: TextInputType.phone,
                          maxLength: 15,
                        ),
                        _inputField(
                            monthlyRentController,
                            t['tenant_field_rent'],
                            Icons.payments_rounded,
                            suffix: tenant.currency,
                            keyboardType: TextInputType.number,
                            maxLength: 24),
                        const SizedBox(height: 4),
                        LocalizedDatePicker(
                          labelText: t['tenant_field_move_in_date'],
                          initialDate: editedMoveInDate,
                          required: true,
                          prefixIcon: Icons.calendar_today_rounded,
                          onDateChanged: (date) {
                            if (date != null) {
                              setDialogState(
                                  () => editedMoveInDate = date);
                            }
                          },
                        ),
                        const _ContentDivider(),
                        _SectionLabel(
                          t['tenant_section_invoice_apt'],
                          icon: Icons.apartment_rounded,
                        ),
                        ComboBoxField<Building>(
                          options: _buildings,
                          labelOf: (b) => b.name,
                          selected: _buildings
                              .where((b) => b.id == selectedBuildingId)
                              .firstOrNull,
                          icon: Icons.apartment_rounded,
                          label: t['tenant_field_building'],
                          onSelected: (building) {
                            setDialogState(() {
                              selectedBuildingId = building?.id;
                              selectedRoomId = null;
                            });
                          },
                        ),
                        ComboBoxField<Room>(
                          options: availableRooms,
                          labelOf: (r) => t.textWithParams(
                            occupiedRoomIds.contains(r.id)
                                ? 'tenant_room_occupied'
                                : 'tenant_room_vacant',
                            {'number': r.roomNumber},
                          ),
                          colorOf: (r) => occupiedRoomIds.contains(r.id)
                              ? const Color(0xFFDC2626) // red — occupied
                              : const Color(0xFF3B6D11), // green — vacant
                          isSelectable: (r) =>
                              !occupiedRoomIds.contains(r.id) ||
                              r.id == tenant.roomId,
                          selected: availableRooms
                              .where((r) => r.id == selectedRoomId)
                              .firstOrNull,
                          enabled: selectedBuildingId != null,
                          icon: Icons.door_front_door_rounded,
                          label: t['tenant_field_room'],
                          onSelected: (room) {
                            if (room == null) return;
                            setDialogState(() {
                              selectedRoomId = room.id;

                              areaController.text = room.area.toString();
                              // Normalize here too — room.roomType may
                              // also be legacy free text.
                              selectedAptType =
                                  normalizeAptType(room.roomType);
                            });
                          },
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: ComboBoxField<String>(
                                options: aptTypeOptions,
                                labelOf: (v) => aptTypeLabel(t, v),
                                selected: selectedAptType,
                                icon: Icons.category_rounded,
                                label: t['tenant_field_apt_type'],
                                onSelected: (v) {
                                  if (v != null) setDialogState(() => selectedAptType = v);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                                child: _inputField(
                                    areaController,
                                    t['tenant_field_area'],
                                    Icons.square_foot_rounded,
                                    suffix: 'm²',
                                    keyboardType: TextInputType.number,
                                    maxLength: 6)),
                          ],
                        ),
                        const _ContentDivider(),
                        _SectionLabel(
                          t['tenant_detail_personal_section'],
                          icon: Icons.person_rounded,
                        ),
                        _inputField(
                            emailController,
                            t['tenant_field_email'],
                            Icons.email_rounded,
                            maxLength: 100),
                        _inputField(
                            nationalIdController,
                            t['tenant_field_national_id'],
                            Icons.badge_rounded,
                            maxLength: 24),
                        _inputField(
                            occupationController,
                            t['tenant_field_occupation'],
                            Icons.work_rounded,
                            maxLength: 100),
                        _inputField(
                            workplaceController,
                            t['tenant_field_workplace'],
                            Icons.location_city_rounded,
                            maxLength: 150),
                      ],
                    ),
                  ),
                ),
                _DialogActions(
                  children: [
                    _ActionButton(
                        label: t['cancel'],
                        onPressed: () => Navigator.pop(context)),
                    _ActionButton(
                      label: t['tenant_edit_save'],
                      primary: true,
                      icon: Icons.check_rounded,
                      onPressed: (selectedBuildingId == null ||
                              selectedRoomId == null)
                          ? null
                          : () {
                              Navigator.pop(context, {
                                'fullName': nameController.text.trim(),
                                'phoneNumber': phoneController.text.trim(),
                                'email': emailController.text.trim().isEmpty
                                    ? null
                                    : emailController.text.trim(),
                                'nationalId': nationalIdController.text
                                        .trim()
                                        .isEmpty
                                    ? null
                                    : nationalIdController.text.trim(),
                                'occupation': occupationController.text
                                        .trim()
                                        .isEmpty
                                    ? null
                                    : occupationController.text.trim(),
                                'workplace':
                                    workplaceController.text.trim().isEmpty
                                        ? null
                                        : workplaceController.text.trim(),
                                'monthlyRent': CurrencyParser.tryParse(monthlyRentController.text),
                                'apartmentArea': double.tryParse(
                                    areaController.text.trim()),
                                'apartmentType': selectedAptType,
                                'moveInDate': editedMoveInDate,
                                'buildingId': selectedBuildingId,
                                'roomId': selectedRoomId,
                          'currency': tenant.currency,
                              });
                            },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    nationalIdController.dispose();
    occupationController.dispose();
    workplaceController.dispose();
    monthlyRentController.dispose();
    areaController.dispose();
    if (result != null) {
      final newBuildingId = result['buildingId'] as String?;
      final newRoomId = result['roomId'] as String?;
      final roomChanged = newBuildingId != null &&
          newRoomId != null &&
          (newBuildingId != tenant.buildingId || newRoomId != tenant.roomId);

      if (roomChanged) {
        // Handles history tracking, moveInDate reset, status/contract reset
        final moveSuccess = await widget.tenantService.moveTenantToRoom(
          tenant.id,
          newBuildingId,
          newRoomId,
        );

        if (!mounted) return;

        if (!moveSuccess) {
          final t = AppTranslations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(t['tenant_move_room_error']),
              backgroundColor: Colors.red,
            ),
          );
          return; // Block: don't apply any other field edits, let user retry
        }

        // Apply the rest of the edited fields (name, phone, personal info, rent, etc.)
        // and let the user's explicitly-chosen moveInDate override the
        // auto-stamped "now" that moveTenantToRoom just set.
        final fieldUpdates = Map<String, dynamic>.from(result)
          ..remove('buildingId')
          ..remove('roomId');
        final updateSuccess =
            await widget.tenantService.updateTenant(tenant.id, fieldUpdates);

        if (!mounted) return;

        if (!updateSuccess) {
          final t = AppTranslations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(t['tenant_edit_save_error']),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        final t = AppTranslations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t['tenant_edit_save_success']),
            backgroundColor: const Color(0xFF3B6D11),
          ),
        );
      } else {
        final updateSuccess =
            await widget.tenantService.updateTenant(tenant.id, result);

        if (!mounted) return;

        if (!updateSuccess) {
          final t = AppTranslations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(t['tenant_edit_save_error']),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        final t = AppTranslations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t['tenant_edit_save_success']),
            backgroundColor: const Color(0xFF3B6D11),
          ),
        );
      }

      _refreshAll();
      widget.onChanged?.call();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // MOVE ROOM DIALOG
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showMoveRoomDialog(Tenant tenant) async {
    String? selectedBuildingId =
        tenant.buildingId.isNotEmpty ? tenant.buildingId : null;
    String? selectedRoomId =
        tenant.roomId.isNotEmpty ? tenant.roomId : null;

    final t = AppTranslations.of(context);         // capture before await
    final messenger = ScaffoldMessenger.of(context); // capture before await

    final result = await _showTrackedDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final t = AppTranslations.of(context);
          final availableRooms = _rooms
              .where((r) => r.buildingId == selectedBuildingId)
              .toList();

          return _DialogShell(
            maxWidth: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogHeader(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF085041), Color(0xFF0F6E56)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  leading: const Icon(Icons.swap_horiz_rounded,
                      size: 22, color: Colors.white),
                  title: t['tenant_move_room_title'],
                  subtitle: tenant.fullName,
                  onClose: () => Navigator.pop(context, false),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionLabel(
                        t['tenant_detail_location'],
                        icon: Icons.location_on_rounded,
                        color: const Color(0xFF0F6E56),
                      ),
                      _dropdownField<String>(
                        label: t['tenant_move_room_building'],
                        value: selectedBuildingId,
                        items: _buildings
                            .map((b) => DropdownMenuItem(
                                value: b.id, child: Text(b.name)))
                            .toList(),
                        onChanged: (val) => setDialogState(() {
                          selectedBuildingId = val;
                          selectedRoomId = null;
                        }),
                      ),
                      _dropdownField<String>(
                        label: t['tenant_move_room_room'],
                        value: selectedRoomId,
                        items: availableRooms
                            .map((r) => DropdownMenuItem(
                                value: r.id,
                                child: Text(
                                    '${r.roomNumber} (${r.roomType})')))
                            .toList(),
                        onChanged: (val) =>
                            setDialogState(() => selectedRoomId = val),
                      ),
                    ],
                  ),
                ),
                _DialogActions(
                  children: [
                    _ActionButton(
                        label: t['cancel'],
                        onPressed: () => Navigator.pop(context, false)),
                    _ActionButton(
                      label: t['tenant_move_room_confirm'],
                      primary: true,
                      icon: Icons.swap_horiz_rounded,
                      onPressed: (selectedBuildingId == null ||
                              selectedRoomId == null)
                          ? null
                          : () => Navigator.pop(context, true),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    if (result == true &&
        selectedBuildingId != null &&
        selectedRoomId != null) {
      if (selectedRoomId == tenant.roomId) return;
      final success = await widget.tenantService.moveTenantToRoom(
          tenant.id, selectedBuildingId!, selectedRoomId!);
      messenger.showSnackBar(SnackBar(
        content: Text(success
            ? t['tenant_move_room_success']
            : t['tenant_move_room_error']),
        backgroundColor: success ? const Color(0xFF3B6D11) : Colors.red,
      ));
      _refreshAll();
      widget.onChanged?.call();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // MOVE OUT DIALOG
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showMoveOutDialog(Tenant tenant) async {
    DateTime selectedDate = DateTime.now();
    String? selectedReason;

    final t = AppTranslations.of(context);           // capture here
    final messenger = ScaffoldMessenger.of(context); // capture here

    final result = await _showTrackedDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final t = AppTranslations.of(context);
          final reasonOptions = [
            t['tenant_moveout_reason_1'],
            t['tenant_moveout_reason_2'],
            t['tenant_moveout_reason_3'],
            t['tenant_moveout_reason_4'],
            t['tenant_moveout_reason_5'],
          ];
          selectedReason ??= reasonOptions.first;

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
                  title: t['tenant_moveout_title'],
                  subtitle: tenant.fullName,
                  onClose: () => Navigator.pop(context),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel(
                          t['tenant_moveout_date_label'],
                          icon: Icons.info_outline_rounded,
                          color: const Color(0xFF854F0B),
                        ),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF854F0B)
                                .withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: const Color(0xFF854F0B)
                                    .withValues(alpha: 0.2)),
                          ),
                          child: Text(
                            t.textWithParams('tenant_moveout_confirm',
                                {'name': tenant.fullName}),
                            style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _SectionLabel(
                          t['tenant_detail_rental_section'],
                          icon: Icons.calendar_today_rounded,
                          color: const Color(0xFF854F0B),
                        ),
                        LocalizedDatePicker(
                          labelText: t['tenant_moveout_date_label'],
                          initialDate: selectedDate,
                          required: true,
                          prefixIcon: Icons.calendar_today_rounded,
                          onDateChanged: (date) {
                            if (date != null) {
                              setDialogState(() => selectedDate = date);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        _dropdownField<String>(
                          label: t['tenant_moveout_reason_label'],
                          value: selectedReason,
                          items: reasonOptions
                              .map((reason) => DropdownMenuItem(
                                  value: reason, child: Text(reason)))
                              .toList(),
                          onChanged: (value) =>
                              setDialogState(() => selectedReason = value),
                        ),
                        if (isEarly) ...[
                          const SizedBox(height: 4),
                          _InfoBanner(
                            icon: Icons.warning_amber_rounded,
                            color: const Color(0xFF854F0B),
                            text: t.textWithParams(
                                'tenant_moveout_early_warning', {
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
                _DialogActions(
                  children: [
                    _ActionButton(
                        label: t['cancel'],
                        onPressed: () => Navigator.pop(context)),
                    _ActionButton(
                      label: t['tenant_moveout_confirm_action'],
                      primary: true,
                      icon: Icons.logout_rounded,
                      onPressed: () => Navigator.pop(context, {
                        'date': selectedDate,
                        'reason': selectedReason,
                      }),
                    ),
                  ],
                ),
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
      messenger.showSnackBar(SnackBar(
        content: Text(success
            ? t['tenant_moveout_success']
            : t['tenant_moveout_failed']),
        backgroundColor: success ? const Color(0xFF3B6D11) : Colors.red,
      ));
      await _refreshAll();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // DELETE TENANT
  // ═══════════════════════════════════════════════════════════════
  Future<void> _confirmDeleteTenant(Tenant tenant) async {
    final t = AppTranslations.of(context);
    final ok = await _showConfirmDialog(
      title: t['tenant_delete_title'],
      message: t.textWithParams(
          'tenant_delete_confirm', {'name': tenant.fullName}),
      confirmLabel: t['delete'],
      destructive: true,
    );

    if (ok == true) {
      final success =
          await widget.tenantService.deleteTenant(tenant.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success
            ? t['tenant_delete_success']
            : t['tenant_delete_failed']),
        backgroundColor: success ? const Color(0xFF3B6D11) : Colors.red,
      ));
      await _refreshAll();
    }
  }

}
