part of 'organization_screen.dart';

// Building list, cards, navigation, and add/edit/delete dialogs.
// The main screen owns state, services, and lifecycle.
extension _OrganizationBuildings on _OrganizationScreenState {
  // ========================================
  // BUILDINGS TAB
  // ========================================
  Widget _buildBuildingsTab() {
    final t = AppTranslations.of(context);
    return FutureBuilder<Membership?>(
      future: _membershipFuture,
      builder: (context, membershipSnapshot) {
        final isAdmin = membershipSnapshot.hasData &&
            membershipSnapshot.data!.role == 'admin';
        return FutureBuilder<List<Building>>(
          future: _buildingsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final buildings = snapshot.data ?? [];

            return ValueListenableBuilder<TextEditingValue>(
              valueListenable: _buildingSearchController,
              builder: (context, search, _) {
                final query = search.text.trim().toLowerCase();
                final visibleBuildings = buildings.where((building) =>
                    building.name.toLowerCase().contains(query) ||
                    building.address.toLowerCase().contains(query)).toList();
                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _buildBuildingSummaryBar(t, buildings, isAdmin),
                    )),

                    if (visibleBuildings.isEmpty)
                      SliverFillRemaining(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.apartment, size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text(query.isEmpty ? t['no_buildings'] : t['building_search_empty'],
                                  style: TextStyle(color: Colors.grey.shade600)),
                            ],
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final building = visibleBuildings[index];
                              final color = _buildingColors[buildings.indexOf(building) % _buildingColors.length];
                              return _buildBuildingCard(
                                t: t,
                                building: building,
                                color: color,
                                isAdmin: isAdmin,
                                allRooms: snapshot.data != null ? null : [],
                              );
                            },
                            childCount: visibleBuildings.length,
                          ),
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

  Widget _buildBuildingSummaryBar(AppTranslations t, List<Building> buildings, bool isAdmin) {
    return FutureBuilder<List<dynamic>>(
      future: _summaryBarFuture,
      builder: (context, snap) {
        final allRooms = snap.data?[0] as List<Room>? ?? [];
        final allTenants = snap.data?[1] as List<Tenant>? ?? [];

        // Rented buildings aren't room-managed, so exclude their rooms/tenants
        // from the room-count and occupancy stats (still counted in "buildings").
        final managedBuildingIds =
            buildings.where((b) => !b.isRented).map((b) => b.id).toSet();
        final rooms =
            allRooms.where((r) => managedBuildingIds.contains(r.buildingId)).toList();
        final tenants = allTenants
            .where((tn) => managedBuildingIds.contains(tn.buildingId))
            .toList();

        final activeTenants = tenants.where((t) => t.status == TenantStatus.active).length;
        final occupancyPct = rooms.isNotEmpty
            ? (activeTenants / rooms.length * 100).round()
            : 0;

        return CompactSummaryToolbar(
          values: ['${buildings.length}', '${rooms.length}', '$occupancyPct%'],
          labels: [t['stat_buildings'], t['stat_rooms'], t['stat_occupancy']],
          icons: const [Icons.apartment_rounded, Icons.meeting_room_outlined, Icons.pie_chart_outline],
          searchController: _buildingSearchController,
          searchTitle: t['building_search_title'],
          searchHint: t['building_search_hint'],
          addLabel: t['add_building'],
          addIcon: Icons.add_business_rounded,
          actionKeyPrefix: 'building',
          onAdd: isAdmin ? _showAddBuildingDialog : null,
        );
      },
    );
  }

  Widget _buildBuildingCard({
    required AppTranslations t,
    required Building building,
    required Color color,
    required bool isAdmin,
    List<Room>? allRooms,
  }) {
    final future = _buildingCardFutures.putIfAbsent(
      building.id,
      () => building.isRented
          ? Future.value(<dynamic>[<Room>[], <Tenant>[]])
          : Future.wait([
              _roomService.getBuildingRooms(widget.organization.id, building.id,
                  requireServer: true),
              _tenantService.getBuildingTenants(widget.organization.id, building.id,
                  requireServer: true),
            ]),
    );
    return FutureBuilder<List<dynamic>>(
      future: future,
      builder: (context, snap) => BuildingSummaryCard(
        building: building,
        translations: t,
        color: color,
        rooms: snap.data?[0] as List<Room>? ?? [],
        tenants: snap.data?[1] as List<Tenant>? ?? [],
        loading: snap.connectionState != ConnectionState.done,
        hasError: snap.hasError,
        onRetry: () => _updateOrganizationState(() => _buildingCardFutures.remove(building.id)),
        onManage: building.isRented
            ? (isAdmin ? () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => BuildingRentScreen(
                  organization: widget.organization, building: building),
              )) : null)
            : () => _navigateToBuildingRooms(building),
        onEdit: isAdmin ? () => _showEditBuildingDialog(building) : null,
        onDelete: isAdmin ? () => _deleteBuilding(building, widget.organization) : null,
      ),
    );
  }

  void _navigateToBuildingRooms(Building building) {
    Navigator.pushNamed(
      context,
      '/building-rooms',
      arguments: {
        'building': building,
        'organization': widget.organization,
      },
    );
  }

  // ========================================
  // BUILDING DIALOGS
  // ========================================
  Future<void> _showAddBuildingDialog() async {
    final t = AppTranslations.of(context);
    final result = await _showTrackedDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const BuildingDialog(isEditMode: false),
    );

    if (result != null && mounted) {
      _showTrackedDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            const Center(child: CircularProgressIndicator()),
      );

      try {
        final buildingId =
            await _buildingService.addBuildingFromDialogResult(
          organizationId: widget.organization.id,
          dialogResult: result,
        );

        if (buildingId == null) throw Exception('Failed to create building');

        if (result['autoGenerateRooms'] == true) {
          final rooms = await _roomService.generateRoomsFromConfig(
            organizationId: widget.organization.id,
            buildingId: buildingId,
            config: result,
          );
          await _roomService.addMultipleRooms(rooms);
          final totalRooms = rooms.length;
          if (mounted) Navigator.of(context).pop();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(t.textWithParams(
                  'add_building_rooms_success', {'count': totalRooms})),
              backgroundColor: Colors.green,
            ));
            _buildingCardFutures.clear();
            _updateOrganizationState(() {
               _buildingsFuture = _getBuildings();
               _tenantTabRefreshKey++;
            });
          }
        } else {
          if (mounted) Navigator.of(context).pop();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(t['add_building_success']),
              backgroundColor: Colors.green,
            ));
            _buildingCardFutures.clear();
            _updateOrganizationState(() {
               _buildingsFuture = _getBuildings();
               _tenantTabRefreshKey++;
            });
            _refreshStats();
          }
        }
      } catch (e) {
        if (mounted) Navigator.of(context).pop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t.textWithParams('delete_building_error', {'error': e})),
            backgroundColor: Colors.red,
          ));
        }
      }
    }
  }

  Future<void> _showEditBuildingDialog(Building building) async {
    final t = AppTranslations.of(context);
    final result = await _showTrackedDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => BuildingDialog(
        isEditMode: true,
        initialName: building.name,
        initialAddress: building.address,
        initialFloors: building.floors,
        initialRoomPrefix: building.roomPrefix,
        initialUniformRooms: building.uniformRooms,
        initialRoomsPerFloor: building.roomsPerFloor,
        initialRoomType: building.roomType,
        initialRoomArea: building.roomArea,
        initialFloorDetails: building.floorDetails,
        initialFloorRoomCounts: building.floorRoomCounts,

        initialManagementType: building.managementType,
        initialRenterName: building.renterName,
        initialRenterPhone: building.renterPhone,
        initialRentAmount: building.rentAmount,
          initialCurrency: building.currency,
        initialRentDueDay: building.rentDueDay,
        initialRentContractStart: building.rentContractStart,
        initialRentContractEnd: building.rentContractEnd,
        initialRenterNotes: building.renterNotes,
      ),
    );

    if (result != null && mounted) {
      _showTrackedDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            const Center(child: CircularProgressIndicator()),
      );

      try {
        final success =
            await _buildingService.updateBuildingFromDialogResult(
          buildingId: building.id,
          dialogResult: result,
        );
        if (!success) throw Exception('Failed to update building');
        
        final existingRooms = await _roomService.getBuildingRooms(
          widget.organization.id, building.id);

        if (result['autoGenerateRooms'] == true && existingRooms.isEmpty) {
          final rooms = await _roomService.generateRoomsFromConfig(
            organizationId: widget.organization.id,
            buildingId: building.id,
            config: result,
          );
          final addSuccess = await _roomService.addMultipleRooms(rooms);
          if (!addSuccess) throw Exception('Failed to add rooms');
          final totalRooms = rooms.length;
          if (mounted) Navigator.of(context).pop();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(t.textWithParams(
                  'update_building_rooms_success', {'count': totalRooms})),
              backgroundColor: Colors.green,
            ));
            _buildingCardFutures.remove(building.id);
            _updateOrganizationState(() {
              _buildingsFuture = _getBuildings();
              _tenantTabRefreshKey++; 
            });
          }
        } else {
          // Building metadata updated; existing rooms are left alone.
          // Room-count/floor changes should be made via "Quản lý phòng".
          if (mounted) Navigator.of(context).pop();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(t['update_building_success']),
              backgroundColor: Colors.green,
            ));
            _buildingCardFutures.remove(building.id);
            _updateOrganizationState(() {
              _buildingsFuture = _getBuildings();
              _tenantTabRefreshKey++;
            });
          }
        }
      } catch (e) {
        if (mounted) Navigator.of(context).pop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t.textWithParams('delete_building_error', {'error': e})),
            backgroundColor: Colors.red,
          ));
        }
      }
    }
  }

  Future<void> _deleteBuilding(
      Building building, Organization organization) async {
    final t = AppTranslations.of(context);
    final contentPadding = _getResponsivePadding(context);

    final tenants = await _tenantService.getBuildingTenants(
        organization.id, building.id);
    final activeTenants = tenants
        .where((tn) =>
            tn.status == TenantStatus.active ||
            tn.status == TenantStatus.inactive ||
            tn.status == TenantStatus.suspended)
        .toList();

    if (!mounted) return;

    final confirm = await _showTrackedDialog<bool>(
      context: context,
      builder: (context) {
        final dialogBg = Theme.of(context).dialogTheme.backgroundColor ??
            Theme.of(context).colorScheme.surface;
        return AppDialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          constraints:
              const BoxConstraints(maxWidth: 400, minWidth: 320),
          child: Material(
            color: dialogBg,
            elevation: 24,
            shadowColor: Colors.black.withValues(alpha: 0.3),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              child: Padding(
                padding: contentPadding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppTranslations.of(context)['delete_building_title'],
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(
                        height: _isSmallScreen(context) ? 12 : 16),
                    ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: 800),
                      child: Text(
                        AppTranslations.of(context).textWithParams(
                            'delete_building_confirm',
                            {'name': building.name}),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                        softWrap: true,
                      ),
                    ),
                    SizedBox(
                        height: _isSmallScreen(context) ? 12 : 16),
                    Text(
                      AppTranslations.of(context)['delete_action_will'],
                      style:
                          const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(
                        height: _isSmallScreen(context) ? 8 : 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.delete_outline,
                            size: 20, color: Colors.red),
                        const SizedBox(width: 8),
                        Flexible(
                          fit: FlexFit.loose,
                          child: Text(
                            AppTranslations.of(context)[
                                'delete_all_rooms'],
                            style: TextStyle(
                                fontSize: _isSmallScreen(context)
                                    ? 13
                                    : 14),
                            softWrap: true,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                        height: _isSmallScreen(context) ? 8 : 12),
                    if (activeTenants.isNotEmpty) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person_off_outlined,
                              size: 20, color: Colors.orange),
                          const SizedBox(width: 8),
                          Flexible(
                            fit: FlexFit.loose,
                            child: Text(
                              AppTranslations.of(context)
                                  .textWithParams('mark_tenants_moved',
                                      {'count': activeTenants.length}),
                              style: TextStyle(
                                  fontSize: _isSmallScreen(context)
                                      ? 13
                                      : 14),
                              softWrap: true,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                          height: _isSmallScreen(context) ? 10 : 12),
                      Container(
                        padding: EdgeInsets.all(
                            _isSmallScreen(context) ? 10 : 12),
                        decoration: BoxDecoration(
                          color: AppThemePalette.primaryLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.info_outline,
                                size: 20, color: AppThemePalette.primary),
                            const SizedBox(width: 8),
                            Flexible(
                              fit: FlexFit.loose,
                              child: Text(
                                AppTranslations.of(context)[
                                    'tenant_data_preserved'],
                                style: TextStyle(
                                    fontSize: _isSmallScreen(context)
                                        ? 12
                                        : 13),
                                softWrap: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(
                        height: _isSmallScreen(context) ? 12 : 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OverflowBar(
                        alignment: MainAxisAlignment.end,
                        spacing: 8,
                        overflowSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(context).pop(false),
                            child: Text(AppTranslations.of(context)[
                                'cancel']),
                          ),
                          ElevatedButton(
                            onPressed: () =>
                                Navigator.of(context).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            child: Text(AppTranslations.of(context)[
                                'delete']),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (confirm != true || !mounted) return;

    _showTrackedDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator()),
    );

    try {
      final result =
          await _buildingService.deleteBuildingWithRoomsAndTenants(
              building.id, widget.organization.id);
      if (!mounted) return;
      Navigator.of(context).pop();

      if (result['rooms']! > 0 || result['tenants']! > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.textWithParams('building_deleted_summary', {
              'rooms': result['rooms'],
              'tenants': result['tenants'],
            })),
            duration: const Duration(seconds: 4),
          ),
        );
        _buildingCardFutures.remove(building.id);
        _updateOrganizationState(() {
          _tenantTabRefreshKey++;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t['cannot_delete_building'])),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              t.textWithParams('delete_building_error', {'error': e})),
        ));
      }
    }
  }

}
