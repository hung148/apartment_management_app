part of 'room_detail.dart';

// Vehicle management, add/edit forms, parking, and vehicle labels.
// The room detail screen owns state, services, lifecycle, and subscriptions.
extension _RoomDetailVehicleDialogs on _RoomDetailScreenState {
  // ═══════════════════════════════════════════════════════════════
  // VEHICLE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showVehicleManagementDialog(Tenant tenant) async {
    await _showTrackedDialog(
      context: context,
      builder: (context) {
        final t = AppTranslations.of(context);
        return _DialogShell(
          maxWidth: 500,
          child: StatefulBuilder(
            builder: (context, setDialogState) => Column(
              children: [
                _DialogHeader(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3A2FA0), Color(0xFF534AB7)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  leading: const Icon(Icons.directions_car_rounded,
                      size: 22, color: Colors.white),
                  title: t['room_detail_vehicle_title'],
                  subtitle: tenant.fullName,
                  onClose: () => Navigator.pop(context),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded,
                          size: 22, color: Colors.white),
                      tooltip: t['room_detail_vehicle_add_title'],
                      onPressed: () async {
                        try {
                          final result = await _showAddVehicleDialog();
                          if (result != null) {
                            final success = await widget.tenantService
                                .addVehicle(tenant.id, result);
                            if (success) {
                              final updated = await widget.tenantService
                                  .getTenantById(tenant.id);
                              if (updated != null)
                                setDialogState(() => tenant = updated);
                              if (mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(
                                        t['room_detail_vehicle_added'])));
                            }
                          }
                        } catch (e) {
                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(t.textWithParams(
                                        'room_detail_err_generic',
                                        {'error': e})),
                                    backgroundColor: Colors.red));
                        }
                      },
                    ),
                  ],
                ),
                Flexible(
                  child: tenant.vehicles == null || tenant.vehicles!.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.directions_car_outlined,
                                  size: 48, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text(t['room_detail_vehicle_no_vehicles'],
                                  style: TextStyle(
                                      color: Colors.grey.shade500)),
                            ],
                          ),
                        )
                      : FutureBuilder<Tenant?>(
                          future: widget.tenantService.getTenantById(tenant.id),
                          builder: (context, snapshot) {
                            final current = snapshot.data ?? tenant;
                            return ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: current.vehicles?.length ?? 0,
                              itemBuilder: (context, index) {
                                final v = current.vehicles![index];
                                return _VehicleCard(
                                  vehicle: v,
                                  typeIcon: _getVehicleIcon(v.type),
                                  typeLabel: _getVehicleTypeDisplayName(
                                      context, v.type),
                                  parkingLabel: v.isParkingRegistered &&
                                          v.parkingSpot != null
                                      ? t.textWithParams(
                                          'tenant_vehicle_parking_spot',
                                          {'spot': v.parkingSpot!})
                                      : null,
                                  menuItems: [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Row(children: [
                                        const Icon(Icons.edit_rounded, size: 18),
                                        const SizedBox(width: 10),
                                        Text(t['room_detail_vehicle_edit_menu']),
                                      ]),
                                    ),
                                    if (!v.isParkingRegistered)
                                      PopupMenuItem(
                                        value: 'parking',
                                        child: Row(children: [
                                          const Icon(
                                              Icons.local_parking_rounded,
                                              size: 18),
                                          const SizedBox(width: 10),
                                          Text(t['room_detail_vehicle_park_menu']),
                                        ]),
                                      )
                                    else
                                      PopupMenuItem(
                                        value: 'unparking',
                                        child: Row(children: [
                                          const Icon(Icons.cancel_rounded,
                                              size: 18),
                                          const SizedBox(width: 10),
                                          Text(t['room_detail_vehicle_unpark_menu']),
                                        ]),
                                      ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Row(children: [
                                        const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 18,
                                            color: Color(0xFFE74C3C)),
                                        const SizedBox(width: 10),
                                        Text(t['room_detail_vehicle_del_menu'],
                                            style: const TextStyle(
                                                color: Color(0xFFE74C3C))),
                                      ]),
                                    ),
                                  ],
                                  onMenuSelected: (value) async {
                                    if (value == 'edit') {
                                      final result =
                                          await _showEditVehicleDialog(v);
                                      if (result != null) {
                                        final ok = await widget.tenantService
                                            .updateVehicle(
                                                tenant.id, index, result);
                                        if (ok) {
                                          setDialogState(() {});
                                          if (mounted)
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                                    content: Text(t[
                                                        'room_detail_vehicle_updated'])));
                                        }
                                      }
                                    } else if (value == 'parking') {
                                      final spot =
                                          await _showParkingSpotDialog();
                                      if (spot != null) {
                                        final ok = await widget.tenantService
                                            .registerParkingSpot(
                                                tenant.id, index, spot);
                                        if (ok) {
                                          setDialogState(() {});
                                          if (mounted)
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                                    content: Text(t[
                                                        'room_detail_vehicle_parking_reg'])));
                                        }
                                      }
                                    } else if (value == 'unparking') {
                                      final ok = await widget.tenantService
                                          .unregisterParkingSpot(
                                              tenant.id, index);
                                      if (ok) {
                                        setDialogState(() {});
                                        if (mounted)
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                                  content: Text(t[
                                                      'room_detail_vehicle_parking_unreg'])));
                                      }
                                    } else if (value == 'delete') {
                                      final ok = await _showConfirmDialog(
                                        title: t['room_detail_vehicle_del_title'],
                                        message: t.textWithParams(
                                            'room_detail_vehicle_del_msg',
                                            {'plate': v.licensePlate}),
                                        confirmLabel:
                                            t['room_detail_vehicle_del_menu'],
                                        destructive: true,
                                      );
                                      if (ok == true) {
                                        final success = await widget
                                            .tenantService
                                            .removeVehicle(tenant.id, index);
                                        if (success) {
                                          setDialogState(() {});
                                          if (mounted)
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                                    content: Text(t[
                                                        'room_detail_vehicle_deleted'])));
                                        }
                                      }
                                    }
                                  },
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<VehicleInfo?> _showAddVehicleDialog() async {
    final licensePlateController = TextEditingController();
    final brandController = TextEditingController();
    final modelController = TextEditingController();
    final colorController = TextEditingController();
    VehicleType selectedType = VehicleType.motorcycle;

    try {
      return await _showTrackedDialog<VehicleInfo>(
        context: context,
        builder: (context) {
          final t = AppTranslations.of(context);
          return StatefulBuilder(
            builder: (context, setDialogState) => _DialogShell(
              maxWidth: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DialogHeader(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3A2FA0), Color(0xFF534AB7)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    leading: const Icon(Icons.add_rounded,
                        size: 22, color: Colors.white),
                    title: t['room_detail_vehicle_add_title'],
                    onClose: _doNothing,
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionLabel(t['room_detail_vehicle_section_info'],
                              icon: Icons.confirmation_number_rounded,
                              color: const Color(0xFF534AB7)),
                          _inputField(
                              licensePlateController,
                              t['room_detail_vehicle_field_plate'],
                              Icons.confirmation_number_rounded,
                              maxLength: 11),
                          _dropdownField<VehicleType>(
                            label: t['room_detail_vehicle_field_type'],
                            value: selectedType,
                            items: VehicleType.values
                                .map((vt) => DropdownMenuItem(
                                      value: vt,
                                      child: Text(_getVehicleTypeDisplayName(
                                          context, vt)),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              if (v != null)
                                setDialogState(() => selectedType = v);
                            },
                          ),
                          _SectionLabel(
                              t['room_detail_vehicle_section_detail'],
                              icon: Icons.info_outline_rounded,
                              color: const Color(0xFF534AB7)),
                          _inputField(brandController,
                              t['room_detail_vehicle_field_brand'],
                              Icons.branding_watermark_rounded,
                              maxLength: 30),
                          _inputField(modelController,
                              t['room_detail_vehicle_field_model'],
                              Icons.directions_car_rounded,
                              maxLength: 50),
                          _inputField(colorController,
                              t['room_detail_vehicle_field_color'],
                              Icons.palette_rounded,
                              maxLength: 30),
                        ],
                      ),
                    ),
                  ),
                  _DialogActions(children: [
                    _ActionButton(
                        label: t['cancel'],
                        onPressed: () => Navigator.pop(context)),
                    _ActionButton(
                      label: t['room_detail_vehicle_add_btn'],
                      primary: true,
                      icon: Icons.add_rounded,
                      onPressed: () {
                        if (licensePlateController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content:
                                  Text(t['room_detail_vehicle_err_plate'])));
                          return;
                        }
                        Navigator.pop(
                          context,
                          VehicleInfo(
                            licensePlate: licensePlateController.text
                                .trim()
                                .toUpperCase(),
                            type: selectedType,
                            brand: brandController.text.trim().isEmpty
                                ? null
                                : brandController.text.trim(),
                            model: modelController.text.trim().isEmpty
                                ? null
                                : modelController.text.trim(),
                            color: colorController.text.trim().isEmpty
                                ? null
                                : colorController.text.trim(),
                          ),
                        );
                      },
                    ),
                  ]),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      licensePlateController.dispose();
      brandController.dispose();
      modelController.dispose();
      colorController.dispose();
    }
  }

  Future<VehicleInfo?> _showEditVehicleDialog(VehicleInfo vehicle) async {
    final licensePlateController =
        TextEditingController(text: vehicle.licensePlate);
    final brandController = TextEditingController(text: vehicle.brand);
    final modelController = TextEditingController(text: vehicle.model);
    final colorController = TextEditingController(text: vehicle.color);
    VehicleType selectedType = vehicle.type;

    try {
      return await _showTrackedDialog<VehicleInfo>(
        context: context,
        builder: (context) {
          final t = AppTranslations.of(context);
          return StatefulBuilder(
            builder: (context, setDialogState) => _DialogShell(
              maxWidth: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DialogHeader(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3A2FA0), Color(0xFF534AB7)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    leading: const Icon(Icons.edit_rounded,
                        size: 20, color: Colors.white),
                    title: t['room_detail_vehicle_edit_title'],
                    subtitle: vehicle.licensePlate,
                    onClose: () => Navigator.pop(context),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          _inputField(
                              licensePlateController,
                              t['room_detail_vehicle_field_plate'],
                              Icons.confirmation_number_rounded,
                              maxLength: 12),
                          _dropdownField<VehicleType>(
                            label: t['room_detail_vehicle_field_type'],
                            value: selectedType,
                            items: VehicleType.values
                                .map((vt) => DropdownMenuItem(
                                      value: vt,
                                      child: Text(_getVehicleTypeDisplayName(
                                          context, vt)),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              if (v != null)
                                setDialogState(() => selectedType = v);
                            },
                          ),
                          _inputField(brandController,
                              t['room_detail_vehicle_field_brand'],
                              Icons.branding_watermark_rounded,
                              maxLength: 30),
                          _inputField(modelController,
                              t['room_detail_vehicle_field_model'],
                              Icons.directions_car_rounded,
                              maxLength: 50),
                          _inputField(colorController,
                              t['room_detail_vehicle_field_color'],
                              Icons.palette_rounded,
                              maxLength: 30),
                        ],
                      ),
                    ),
                  ),
                  _DialogActions(children: [
                    _ActionButton(
                        label: t['cancel'],
                        onPressed: () => Navigator.pop(context)),
                    _ActionButton(
                      label: t['save'],
                      primary: true,
                      icon: Icons.check_rounded,
                      onPressed: () {
                        if (licensePlateController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content:
                                  Text(t['room_detail_vehicle_err_plate'])));
                          return;
                        }
                        Navigator.pop(
                          context,
                          VehicleInfo(
                            licensePlate: licensePlateController.text
                                .trim()
                                .toUpperCase(),
                            type: selectedType,
                            brand: brandController.text.trim().isEmpty
                                ? null
                                : brandController.text.trim(),
                            model: modelController.text.trim().isEmpty
                                ? null
                                : modelController.text.trim(),
                            color: colorController.text.trim().isEmpty
                                ? null
                                : colorController.text.trim(),
                            isParkingRegistered: vehicle.isParkingRegistered,
                            parkingSpot: vehicle.parkingSpot,
                          ),
                        );
                      },
                    ),
                  ]),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      licensePlateController.dispose();
      brandController.dispose();
      modelController.dispose();
      colorController.dispose();
    }
  }

  Future<String?> _showParkingSpotDialog() async {
    final controller = TextEditingController();
    try {
      return await _showTrackedDialog<String>(
        context: context,
        builder: (context) {
          final t = AppTranslations.of(context);
          return _DialogShell(
            maxWidth: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogHeader(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF085041), Color(0xFF0F6E56)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  leading: const Icon(Icons.local_parking_rounded,
                      size: 22, color: Colors.white),
                  title: t['room_detail_parking_title'],
                  onClose: _doNothing,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: _inputField(controller,
                      t['room_detail_parking_field'],
                      Icons.local_parking_rounded,
                      maxLength: 10),
                ),
                _DialogActions(children: [
                  _ActionButton(
                      label: t['cancel'],
                      onPressed: () => Navigator.pop(context)),
                  _ActionButton(
                    label: t['room_detail_parking_btn'],
                    primary: true,
                    icon: Icons.check_rounded,
                    onPressed: () {
                      if (controller.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(t['room_detail_parking_err'])));
                        return;
                      }
                      Navigator.pop(
                          context, controller.text.trim().toUpperCase());
                    },
                  ),
                ]),
              ],
            ),
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // VEHICLE / TENANT TYPE HELPERS
  // ═══════════════════════════════════════════════════════════════
  IconData _getVehicleIcon(VehicleType type) {
    switch (type) {
      case VehicleType.motorcycle:  return Icons.two_wheeler;
      case VehicleType.car:         return Icons.directions_car;
      case VehicleType.bicycle:     return Icons.pedal_bike;
      case VehicleType.electricBike:return Icons.electric_bike;
      case VehicleType.other:       return Icons.local_shipping;
    }
  }

  String _getVehicleTypeDisplayName(BuildContext context, VehicleType type) {
    final t = AppTranslations.of(context);
    switch (type) {
      case VehicleType.motorcycle:  return t['tenant_vehicle_motorcycle'];
      case VehicleType.car:         return t['tenant_vehicle_car'];
      case VehicleType.bicycle:     return t['tenant_vehicle_bicycle'];
      case VehicleType.electricBike:return t['tenant_vehicle_electric_bike'];
      case VehicleType.other:       return t['tenant_vehicle_other'];
    }
  }

}
