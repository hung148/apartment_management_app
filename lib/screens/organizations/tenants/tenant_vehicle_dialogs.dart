part of 'tenant_tab.dart';

// Vehicle management, add/edit vehicle forms, parking, and vehicle labels.
// The tenant tab owns state, services, lifecycle, and refresh callbacks.
extension _TenantVehicleDialogs on _TenantsTabState {
  // ═══════════════════════════════════════════════════════════════
  // VEHICLE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════
  Future<void> _showVehicleManagementDialog(Tenant tenant) async {
    await _showTrackedDialog(
      context: context,
      builder: (context) => _DialogShell(
        maxWidth: 500,
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            final t = AppTranslations.of(context);
            return Column(
              children: [
                _DialogHeader(
                  gradient:  LinearGradient(
                    colors: [AppThemePalette.primaryDeep, AppThemePalette.primary],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  leading: const Icon(Icons.directions_car_rounded,
                      size: 22, color: Colors.white),
                  title: t['tenant_vehicle_manage_title'],
                  subtitle: tenant.fullName,
                  onClose: () => Navigator.pop(context),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded,
                          size: 22, color: Colors.white),
                      tooltip: t['tenant_vehicle_add_tooltip'],
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context); // capture before await
                        try {
                          final result = await _showAddVehicleDialog();
                          if (result != null) {
                            final success = await widget.tenantService
                                .addVehicle(tenant.id, result);
                            if (success) {
                              await _refreshAll();
                              final updatedTenant = await widget
                                  .tenantService
                                  .getTenantById(tenant.id);
                              if (updatedTenant != null) {
                                setDialogState(() => tenant = updatedTenant);
                              }
                              messenger.showSnackBar(SnackBar(
                                  content: Text(t['tenant_vehicle_added'])));
                            } else {
                              messenger.showSnackBar(SnackBar(
                                  content: Text(t['tenant_vehicle_add_error']),
                                  backgroundColor: Colors.red));
                            }
                          }
                        } catch (e) {
                          messenger.showSnackBar(SnackBar(
                            content: Text(t.textWithParams('tenant_error', {'error': e})),
                            backgroundColor: Colors.red,
                          ));
                        }
                      },
                    ),
                  ],
                ),
                Flexible(
                  child:
                      tenant.vehicles == null || tenant.vehicles!.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(40),
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.directions_car_outlined,
                                      size: 48,
                                      color: Colors.grey.shade300),
                                  const SizedBox(height: 12),
                                  Text(t['tenant_vehicle_empty'],
                                      style: TextStyle(
                                          color: Colors.grey.shade500)),
                                ],
                              ),
                            )
                          : FutureBuilder<Tenant?>(
                              future: widget.tenantService
                                  .getTenantById(tenant.id),
                              builder: (context, snapshot) {
                                final currentTenant =
                                    snapshot.data ?? tenant;
                                return ListView.separated(
                                  padding: const EdgeInsets.all(16),
                                  itemCount:
                                      currentTenant.vehicles?.length ?? 0,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 0),
                                  itemBuilder: (context, index) {
                                    final vehicle =
                                        currentTenant.vehicles![index];
                                    return _VehicleCard(
                                      vehicle: vehicle,
                                      typeIcon:
                                          _getVehicleIcon(vehicle.type),
                                      typeLabel:
                                          _getVehicleTypeDisplayName(
                                              vehicle.type),
                                      parkingLabel: vehicle
                                                  .isParkingRegistered &&
                                              vehicle.parkingSpot != null
                                          ? t.textWithParams(
                                              'tenant_vehicle_parking_spot',
                                              {
                                                'spot':
                                                    vehicle.parkingSpot!
                                              })
                                          : null,
                                      menuItems: [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Row(children: [
                                            const Icon(Icons.edit_rounded,
                                                size: 18),
                                            const SizedBox(width: 10),
                                            Text(t[
                                                'tenant_vehicle_menu_edit']),
                                          ]),
                                        ),
                                        if (!vehicle.isParkingRegistered)
                                          PopupMenuItem(
                                            value: 'parking',
                                            child: Row(children: [
                                              const Icon(
                                                  Icons
                                                      .local_parking_rounded,
                                                  size: 18),
                                              const SizedBox(width: 10),
                                              Text(t[
                                                  'tenant_vehicle_menu_register_parking']),
                                            ]),
                                          )
                                        else
                                          PopupMenuItem(
                                            value: 'unparking',
                                            child: Row(children: [
                                              const Icon(
                                                  Icons.cancel_rounded,
                                                  size: 18),
                                              const SizedBox(width: 10),
                                              Text(t[
                                                  'tenant_vehicle_menu_unregister_parking']),
                                            ]),
                                          ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Row(children: [
                                            Icon(
                                                Icons
                                                    .delete_outline_rounded,
                                                size: 18,
                                                color: const Color(
                                                    0xFFE74C3C)),
                                            const SizedBox(width: 10),
                                            Text(
                                                t['tenant_vehicle_menu_delete'],
                                                style: const TextStyle(
                                                    color: Color(
                                                        0xFFE74C3C))),
                                          ]),
                                        ),
                                      ],
                                      onMenuSelected: (value) async {
                                        final messenger = ScaffoldMessenger.of(context); // capture once
                                        if (value == 'edit') {
                                          final result = await _showEditVehicleDialog(vehicle);
                                          if (result != null) {
                                            final success = await widget.tenantService
                                                .updateVehicle(tenant.id, index, result);
                                            if (success) {
                                              await _refreshAll();
                                              setDialogState(() {});
                                              messenger.showSnackBar(SnackBar(
                                                  content: Text(t['tenant_vehicle_updated'])));
                                            }
                                          }
                                        } else if (value == 'parking') {
                                          final spot = await _showParkingSpotDialog();
                                          if (spot != null) {
                                            final success = await widget.tenantService
                                                .registerParkingSpot(tenant.id, index, spot);
                                            if (success) {
                                              await _refreshAll();
                                              setDialogState(() {});
                                              messenger.showSnackBar(SnackBar(
                                                  content: Text(t['tenant_vehicle_parking_registered'])));
                                            }
                                          }
                                        } else if (value == 'unparking') {
                                          final success = await widget.tenantService
                                              .unregisterParkingSpot(tenant.id, index);
                                          if (success) {
                                            await _refreshAll();
                                            setDialogState(() {});
                                            messenger.showSnackBar(SnackBar(
                                                content: Text(t['tenant_vehicle_parking_unregistered'])));
                                          }
                                        } else if (value == 'delete') {
                                          final ok = await _showConfirmDialog(
                                            title: t['tenant_vehicle_delete_title'],
                                            message: t.textWithParams('tenant_vehicle_delete_confirm',
                                                {'plate': vehicle.licensePlate}),
                                            confirmLabel: t['delete'],
                                            destructive: true,
                                          );
                                          if (ok == true) {
                                            final success = await widget.tenantService
                                                .removeVehicle(tenant.id, index);
                                            if (success) {
                                              await _refreshAll();
                                              setDialogState(() {});
                                              messenger.showSnackBar(SnackBar(
                                                  content: Text(t['tenant_vehicle_deleted'])));
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
            );
          },
        ),
      ),
    );
    await _refreshAll();
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
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            final t = AppTranslations.of(context);
            return _DialogShell(
              maxWidth: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DialogHeader(
                    gradient:  LinearGradient(
                      colors: [AppThemePalette.primaryDeep, AppThemePalette.primary],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    leading: const Icon(Icons.add_rounded,
                        size: 22, color: Colors.white),
                    title: t['tenant_vehicle_add_title'],
                    onClose: () => Navigator.pop(context),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionLabel(
                            t['tenant_vehicle_plate_label'],
                            icon: Icons.confirmation_number_rounded,
                            color: AppThemePalette.primary,
                          ),
                          _inputField(
                              licensePlateController,
                              t['tenant_vehicle_plate_label'],
                              Icons.confirmation_number_rounded,
                              maxLength: 11),
                          _dropdownField<VehicleType>(
                            label: t['tenant_vehicle_type_label'],
                            value: selectedType,
                            items: VehicleType.values
                                .map((type) => DropdownMenuItem(
                                      value: type,
                                      child: Text(
                                          _getVehicleTypeDisplayName(
                                              type)),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() => selectedType = value);
                              }
                            },
                          ),
                          _SectionLabel(
                            t['tenant_detail_personal_section'],
                            icon: Icons.info_outline_rounded,
                            color: AppThemePalette.primary,
                          ),
                          _inputField(
                              brandController,
                              t['tenant_vehicle_brand_label'],
                              Icons.branding_watermark_rounded,
                              maxLength: 30),
                          _inputField(
                              modelController,
                              t['tenant_vehicle_model_label'],
                              Icons.directions_car_rounded,
                              maxLength: 50),
                          _inputField(
                              colorController,
                              t['tenant_vehicle_color_label'],
                              Icons.palette_rounded,
                              maxLength: 30),
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
                        label: t['tenant_vehicle_add_action'],
                        primary: true,
                        icon: Icons.add_rounded,
                        onPressed: () {
                          if (licensePlateController.text
                              .trim()
                              .isEmpty) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(
                                    content: Text(t[
                                        'tenant_vehicle_plate_required'])));
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
                    ],
                  ),
                ],
              ),
            );
          },
        ),
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
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            final t = AppTranslations.of(context);
            return _DialogShell(
              maxWidth: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DialogHeader(
                    gradient:  LinearGradient(
                      colors: [AppThemePalette.primaryDeep, AppThemePalette.primary],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    leading: const Icon(Icons.edit_rounded,
                        size: 20, color: Colors.white),
                    title: t['tenant_vehicle_edit_title'],
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
                            t['tenant_vehicle_plate_label'],
                            Icons.confirmation_number_rounded,
                            maxLength: 12,
                          ),
                          _dropdownField<VehicleType>(
                            label: t['tenant_vehicle_type_label'],
                            value: selectedType,
                            items: VehicleType.values
                                .map((type) => DropdownMenuItem(
                                      value: type,
                                      child: Text(
                                          _getVehicleTypeDisplayName(
                                              type)),
                                    ))
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() => selectedType = value);
                              }
                            },
                          ),
                          _inputField(
                              brandController,
                              t['tenant_vehicle_brand_label'],
                              Icons.branding_watermark_rounded,
                              maxLength: 30),
                          _inputField(
                              modelController,
                              t['tenant_vehicle_model_label'],
                              Icons.directions_car_rounded,
                              maxLength: 50),
                          _inputField(
                              colorController,
                              t['tenant_vehicle_color_label'],
                              Icons.palette_rounded,
                              maxLength: 30),
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
                        label: t['tenant_vehicle_save_action'],
                        primary: true,
                        icon: Icons.check_rounded,
                        onPressed: () {
                          if (licensePlateController.text
                              .trim()
                              .isEmpty) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(
                                    content: Text(t[
                                        'tenant_vehicle_plate_required'])));
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
                              isParkingRegistered:
                                  vehicle.isParkingRegistered,
                              parkingSpot: vehicle.parkingSpot,
                            ),
                          );
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
                  title: t['tenant_parking_register_title'],
                  onClose: () => Navigator.pop(context),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: _inputField(
                    controller,
                    t['tenant_parking_spot_label'],
                    Icons.local_parking_rounded,
                    maxLength: 10,
                  ),
                ),
                _DialogActions(
                  children: [
                    _ActionButton(
                        label: t['cancel'],
                        onPressed: () => Navigator.pop(context)),
                    _ActionButton(
                      label: t['tenant_parking_register_action'],
                      primary: true,
                      icon: Icons.check_rounded,
                      onPressed: () {
                        if (controller.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(
                                  content: Text(t[
                                      'tenant_parking_spot_required'])));
                          return;
                        }
                        Navigator.pop(context,
                            controller.text.trim().toUpperCase());
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  IconData _getVehicleIcon(VehicleType type) {
    switch (type) {
      case VehicleType.motorcycle:
        return Icons.two_wheeler;
      case VehicleType.car:
        return Icons.directions_car;
      case VehicleType.bicycle:
        return Icons.pedal_bike;
      case VehicleType.electricBike:
        return Icons.electric_bike;
      case VehicleType.other:
        return Icons.local_shipping;
    }
  }

  String _getVehicleTypeDisplayName(VehicleType type) {
    final t = AppTranslations.of(context);
    switch (type) {
      case VehicleType.motorcycle:
        return t['tenant_vehicle_motorcycle'];
      case VehicleType.car:
        return t['tenant_vehicle_car'];
      case VehicleType.bicycle:
        return t['tenant_vehicle_bicycle'];
      case VehicleType.electricBike:
        return t['tenant_vehicle_electric_bike'];
      case VehicleType.other:
        return t['tenant_vehicle_other'];
    }
  }

}
