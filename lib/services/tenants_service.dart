import 'package:apartment_management_project_2/models/tenants_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TenantService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  // ========================================
  // CREATE - Add a new tenant
  // ========================================
  Future<String?> addTenant(Tenant tenant) async {
    try {
      final docRef = await _firestore.collection('tenants').add(tenant.toMap());
      print('Tenant added successfully: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('Error adding tenant: $e');
      return null;
    }
  }

  // ========================================
  // READ - Get tenant by ID
  // ========================================
  Future<Tenant?> getTenantById(String tenantId) async {
    try {
      final doc = await _firestore.collection('tenants').doc(tenantId).get();
      
      if (!doc.exists) {
        print('Tenant not found: $tenantId');
        return null;
      }
      
      return Tenant.fromMap(doc.id, doc.data()!);
    } catch (e) {
      print('Error getting tenant: $e');
      return null;
    }
  }

  // ========================================
  // READ - Get all tenants in a room
  // ========================================
  Future<List<Tenant>> getRoomTenants(String roomId) async {
    try {
      final snapshot = await _firestore
          .collection('tenants')
          .where('roomId', isEqualTo: roomId)
          .orderBy('isMainTenant', descending: true) // Main tenant first
          .orderBy('createdAt', descending: false)
          .get();

      return snapshot.docs
          .map((doc) => Tenant.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      print('Error getting room tenants: $e');
      return [];
    }
  }

  // ========================================
  // READ - Get all active tenants in a room
  // ========================================
  Future<List<Tenant>> getActiveRoomTenants(String roomId) async {
    try {
      final snapshot = await _firestore
          .collection('tenants')
          .where('roomId', isEqualTo: roomId)
          .where('status', isEqualTo: 'active')
          .orderBy('isMainTenant', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => Tenant.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      print('Error getting active room tenants: $e');
      return [];
    }
  }

  // ========================================
  // READ - Get all tenants in a building
  // ========================================
  Future<List<Tenant>> getBuildingTenants(String buildingId) async {
    try {
      final snapshot = await _firestore
          .collection('tenants')
          .where('buildingId', isEqualTo: buildingId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => Tenant.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      print('Error getting building tenants: $e');
      return [];
    }
  }

  // ========================================
  // READ - Get all tenants in an organization
  // ========================================
  Future<List<Tenant>> getOrganizationTenants(String organizationId) async {
    try {
      final snapshot = await _firestore
          .collection('tenants')
          .where('organizationId', isEqualTo: organizationId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => Tenant.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      print('Error getting organization tenants: $e');
      return [];
    }
  }

  // ========================================
  // READ - Get tenants by status
  // ========================================
  Future<List<Tenant>> getTenantsByStatus(
    String organizationId,
    TenantStatus status,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('tenants')
          .where('organizationId', isEqualTo: organizationId)
          .where('status', isEqualTo: status.name)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => Tenant.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      print('Error getting tenants by status: $e');
      return [];
    }
  }

  // ========================================
  // READ - Get tenants with expiring contracts
  // ========================================
  Future<List<Tenant>> getTenantsWithExpiringContracts(
    String organizationId, {
    int daysThreshold = 30,
  }) async {
    try {
      final now = DateTime.now();
      final thresholdDate = now.add(Duration(days: daysThreshold));

      final snapshot = await _firestore
          .collection('tenants')
          .where('organizationId', isEqualTo: organizationId)
          .where('status', isEqualTo: 'active')
          .orderBy('contractEndDate', descending: false)
          .get();

      // Filter in memory for contracts expiring within threshold
      return snapshot.docs
          .map((doc) => Tenant.fromMap(doc.id, doc.data()))
          .where((tenant) {
            if (tenant.contractEndDate == null) return false;
            return tenant.contractEndDate!.isAfter(now) &&
                   tenant.contractEndDate!.isBefore(thresholdDate);
          })
          .toList();
    } catch (e) {
      print('Error getting tenants with expiring contracts: $e');
      return [];
    }
  }

  // ========================================
  // READ - Find tenant by phone number
  // ========================================
  Future<Tenant?> getTenantByPhone(
    String organizationId,
    String phoneNumber,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('tenants')
          .where('organizationId', isEqualTo: organizationId)
          .where('phoneNumber', isEqualTo: phoneNumber)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return null;
      }

      return Tenant.fromMap(snapshot.docs.first.id, snapshot.docs.first.data());
    } catch (e) {
      print('Error finding tenant by phone: $e');
      return null;
    }
  }

  // ========================================
  // READ - Find tenant by national ID
  // ========================================
  Future<Tenant?> getTenantByNationalId(
    String organizationId,
    String nationalId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('tenants')
          .where('organizationId', isEqualTo: organizationId)
          .where('nationalId', isEqualTo: nationalId)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return null;
      }

      return Tenant.fromMap(snapshot.docs.first.id, snapshot.docs.first.data());
    } catch (e) {
      print('Error finding tenant by national ID: $e');
      return null;
    }
  }

  // ========================================
  // READ - Get tenants by occupation
  // ========================================
  Future<List<Tenant>> getTenantsByOccupation(
    String organizationId,
    String occupation,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('tenants')
          .where('organizationId', isEqualTo: organizationId)
          .where('occupation', isEqualTo: occupation)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => Tenant.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      print('Error getting tenants by occupation: $e');
      return [];
    }
  }

  // ========================================
  // READ - Stream tenants (real-time updates)
  // ========================================
  Stream<List<Tenant>> streamRoomTenants(String roomId) {
    return _firestore
        .collection('tenants')
        .where('roomId', isEqualTo: roomId)
        .orderBy('isMainTenant', descending: true)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Tenant.fromMap(doc.id, doc.data()))
            .toList());
  }

  Stream<List<Tenant>> streamBuildingTenants(String buildingId) {
    return _firestore
        .collection('tenants')
        .where('buildingId', isEqualTo: buildingId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Tenant.fromMap(doc.id, doc.data()))
            .toList());
  }

  Stream<List<Tenant>> streamOrganizationTenants(String organizationId) {
    return _firestore
        .collection('tenants')
        .where('organizationId', isEqualTo: organizationId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Tenant.fromMap(doc.id, doc.data()))
            .toList());
  }

  // ========================================
  // UPDATE - Update tenant information
  // ========================================
  Future<bool> updateTenant(String tenantId, Map<String, dynamic> data) async {
    try {
      // Always update the updatedAt timestamp
      data['updatedAt'] = Timestamp.now();
      
      await _firestore.collection('tenants').doc(tenantId).update(data);
      print('Tenant updated successfully: $tenantId');
      return true;
    } catch (e) {
      print('Error updating tenant: $e');
      return false;
    }
  }

  // ========================================
  // UPDATE - Update tenant status
  // ========================================
  Future<bool> updateTenantStatus(
    String tenantId,
    TenantStatus status,
  ) async {
    return updateTenant(tenantId, {
      'status': status.name,
    });
  }

  // ========================================
  // UPDATE - Mark tenant as moved out
  // ========================================
  Future<bool> markTenantAsMovedOut(
    String tenantId, {
    DateTime? moveOutDate,
    String? newBuildingName,
    String? newBuildingAddress,
    String? newRoomNumber,
  }) async {
    try {
      // Get current tenant info
      final tenant = await getTenantById(tenantId);
      if (tenant == null) return false;

      // Get current building and room info
      final building = await _firestore
          .collection('buildings')
          .doc(tenant.buildingId)
          .get();
      
      final room = await _firestore
          .collection('rooms')
          .doc(tenant.roomId)
          .get();

      final currentBuildingName = building.exists && building.data()?['name'] != null
          ? building.data()!['name'] as String
          : 'Không xác định';
      
      final currentBuildingAddress = building.exists && building.data()?['address'] != null
          ? building.data()!['address'] as String
          : null;

      final currentRoomNumber = room.exists && room.data()?['roomNumber'] != null
          ? room.data()!['roomNumber'] as String
          : '?';

      // Create new rental history entry
      final previousRental = PreviousRentalHistory(
        buildingName: currentBuildingName,
        buildingAddress: currentBuildingAddress,
        roomNumber: currentRoomNumber,
        moveInDate: tenant.moveInDate,
        moveOutDate: moveOutDate ?? DateTime.now(),
        monthlyRent: tenant.monthlyRent,
        moveOutReason: 'Chuyển đi',
        notes: tenant.notes,
      );

      // Update previous rentals list
      final previousRentals = tenant.previousRentals ?? [];
      previousRentals.add(previousRental);

      // Prepare update data
      final updateData = {
        'status': TenantStatus.moveOut.name,
        'moveOutDate': Timestamp.fromDate(moveOutDate ?? DateTime.now()),
        'lastBuildingName': currentBuildingName,
        'lastRoomNumber': currentRoomNumber,
        'previousRentals': previousRentals.map((r) => r.toMap()).toList(),
      };

      // If moving to a new location, add that info to notes
      if (newBuildingName != null) {
        final newLocationNote = 'Chuyển đến: $newBuildingName${newRoomNumber != null ? ' - Phòng $newRoomNumber' : ''}';
        updateData['notes'] = tenant.notes != null 
            ? '${tenant.notes}\n$newLocationNote'
            : newLocationNote;
      }

      return updateTenant(tenantId, updateData);
    } catch (e) {
      print('Error marking tenant as moved out: $e');
      return false;
    }
  }

  // ========================================
  // UPDATE - Move tenant to different room and record history
  // FIXED: Prevents duplicate history when moving after "moved out"
  // ========================================
  Future<bool> moveTenantToRoom(
    String tenantId,
    String newBuildingId,
    String newRoomId, {
    String? moveOutReason,
  }) async {
    try {
      // Get current tenant info
      final tenant = await getTenantById(tenantId);
      if (tenant == null) return false;

      // Start with existing rental history
      final previousRentals = tenant.previousRentals ?? [];

      // ⚠️ KEY FIX: Only add a new history entry if the tenant is NOT already marked as "moved out"
      // If they're already moved out, that status change already created a history entry
      if (tenant.status != TenantStatus.moveOut) {
        // Get current building and room info
        final oldBuilding = await _firestore
            .collection('buildings')
            .doc(tenant.buildingId)
            .get();
        
        final oldRoom = await _firestore
            .collection('rooms')
            .doc(tenant.roomId)
            .get();

        final oldBuildingName = oldBuilding.exists && oldBuilding.data()?['name'] != null
            ? oldBuilding.data()!['name'] as String
            : 'Không xác định';
        
        final oldBuildingAddress = oldBuilding.exists && oldBuilding.data()?['address'] != null
            ? oldBuilding.data()!['address'] as String
            : null;

        final oldRoomNumber = oldRoom.exists && oldRoom.data()?['roomNumber'] != null
            ? oldRoom.data()!['roomNumber'] as String
            : '?';

        // Create rental history entry for old location
        final previousRental = PreviousRentalHistory(
          buildingName: oldBuildingName,
          buildingAddress: oldBuildingAddress,
          roomNumber: oldRoomNumber,
          moveInDate: tenant.moveInDate,
          moveOutDate: DateTime.now(),
          monthlyRent: tenant.monthlyRent,
          moveOutReason: moveOutReason ?? 'Chuyển phòng',
        );

        // Add to history
        previousRentals.add(previousRental);
      }
      // If status IS moveOut, we skip adding a new history entry
      // because markTenantAsMovedOut() already added one

      // Update tenant with new room and history
      return updateTenant(tenantId, {
        'buildingId': newBuildingId,
        'roomId': newRoomId,
        'moveInDate': Timestamp.now(),
        'previousRentals': previousRentals.map((r) => r.toMap()).toList(),
        // Reactivate tenant
        'status': TenantStatus.active.name,
        'moveOutDate': null,
        'lastBuildingName': null, // Clear moved-out metadata
        'lastRoomNumber': null,
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      print('Error moving tenant to room: $e');
      return false;
    }
  }

  // ========================================
  // UPDATE - Add previous rental history
  // ========================================
  Future<bool> addPreviousRentalHistory(
    String tenantId,
    PreviousRentalHistory rentalHistory,
  ) async {
    try {
      final tenant = await getTenantById(tenantId);
      if (tenant == null) return false;

      final previousRentals = tenant.previousRentals ?? [];
      previousRentals.add(rentalHistory);

      return updateTenant(tenantId, {
        'previousRentals': previousRentals.map((r) => r.toMap()).toList(),
      });
    } catch (e) {
      print('Error adding previous rental history: $e');
      return false;
    }
  }

  // ========================================
  // UPDATE - Update previous rental history
  // ========================================
  Future<bool> updatePreviousRentalHistory(
    String tenantId,
    int historyIndex,
    PreviousRentalHistory rentalHistory,
  ) async {
    try {
      final tenant = await getTenantById(tenantId);
      if (tenant == null) return false;

      final previousRentals = tenant.previousRentals ?? [];
      if (historyIndex < 0 || historyIndex >= previousRentals.length) {
        print('Invalid history index');
        return false;
      }

      previousRentals[historyIndex] = rentalHistory;

      return updateTenant(tenantId, {
        'previousRentals': previousRentals.map((r) => r.toMap()).toList(),
      });
    } catch (e) {
      print('Error updating previous rental history: $e');
      return false;
    }
  }

  // ========================================
  // UPDATE - Remove previous rental history
  // ========================================
  Future<bool> removePreviousRentalHistory(
    String tenantId,
    int historyIndex,
  ) async {
    try {
      final tenant = await getTenantById(tenantId);
      if (tenant == null) return false;

      final previousRentals = tenant.previousRentals ?? [];
      if (historyIndex < 0 || historyIndex >= previousRentals.length) {
        print('Invalid history index');
        return false;
      }

      previousRentals.removeAt(historyIndex);

      return updateTenant(tenantId, {
        'previousRentals': previousRentals.map((r) => r.toMap()).toList(),
      });
    } catch (e) {
      print('Error removing previous rental history: $e');
      return false;
    }
  }

  // ========================================
  // UPDATE - Update occupation
  // ========================================
  Future<bool> updateOccupation(
    String tenantId,
    String? occupation,
    String? workplace,
  ) async {
    return updateTenant(tenantId, {
      'occupation': occupation,
      'workplace': workplace,
    });
  }

  // ========================================
  // UPDATE - Extend contract
  // ========================================
  Future<bool> extendContract(
    String tenantId,
    DateTime newEndDate,
  ) async {
    return updateTenant(tenantId, {
      'contractEndDate': Timestamp.fromDate(newEndDate),
    });
  }

  // ========================================
  // UPDATE - Update monthly rent
  // ========================================
  Future<bool> updateMonthlyRent(
    String tenantId,
    double newRent,
  ) async {
    return updateTenant(tenantId, {
      'monthlyRent': newRent,
    });
  }

  // ========================================
  // UPDATE - Update apartment details (type and area)
  // ========================================
  Future<bool> updateApartmentDetails(
    String tenantId, {
    String? apartmentType,
    double? apartmentArea,
  }) async {
    final Map<String, dynamic> updateData = {};
    
    if (apartmentType != null) {
      updateData['apartmentType'] = apartmentType;
    }
    if (apartmentArea != null) {
      updateData['apartmentArea'] = apartmentArea;
    }

    if (updateData.isEmpty) return true;
    
    return updateTenant(tenantId, updateData);
  }

  // ========================================
  // DELETE - Delete a tenant
  // ========================================
  Future<bool> deleteTenant(String tenantId) async {
    try {
      await _firestore.collection('tenants').doc(tenantId).delete();
      print('Tenant deleted successfully: $tenantId');
      return true;
    } catch (e) {
      print('Error deleting tenant: $e');
      return false;
    }
  }

  // ========================================
  // DELETE - Delete all tenants in a room
  // ========================================
  Future<bool> deleteAllRoomTenants(String roomId) async {
    try {
      final snapshot = await _firestore
          .collection('tenants')
          .where('roomId', isEqualTo: roomId)
          .get();

      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      
      await batch.commit();
      print('Deleted ${snapshot.docs.length} tenants from room');
      return true;
    } catch (e) {
      print('Error deleting room tenants: $e');
      return false;
    }
  }

  // ========================================
  // UTILITY - Count tenants
  // ========================================
  Future<int> countRoomTenants(String roomId) async {
    try {
      final snapshot = await _firestore
          .collection('tenants')
          .where('roomId', isEqualTo: roomId)
          .count()
          .get();
      
      return snapshot.count ?? 0;
    } catch (e) {
      print('Error counting room tenants: $e');
      return 0;
    }
  }

  Future<int> countActiveTenants(String organizationId) async {
    try {
      final snapshot = await _firestore
          .collection('tenants')
          .where('organizationId', isEqualTo: organizationId)
          .where('status', isEqualTo: 'active')
          .count()
          .get();
      
      return snapshot.count ?? 0;
    } catch (e) {
      print('Error counting active tenants: $e');
      return 0;
    }
  }

  // ========================================
  // UTILITY - Check if room has active tenants
  // ========================================
  Future<bool> hasActiveTenants(String roomId) async {
    try {
      final snapshot = await _firestore
          .collection('tenants')
          .where('roomId', isEqualTo: roomId)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking active tenants: $e');
      return false;
    }
  }

  // ========================================
  // UTILITY - Get main tenant of a room
  // ========================================
  Future<Tenant?> getMainTenant(String roomId) async {
    try {
      final snapshot = await _firestore
          .collection('tenants')
          .where('roomId', isEqualTo: roomId)
          .where('isMainTenant', isEqualTo: true)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return null;
      }

      return Tenant.fromMap(snapshot.docs.first.id, snapshot.docs.first.data());
    } catch (e) {
      print('Error getting main tenant: $e');
      return null;
    }
  }

  // ========================================
  // UTILITY - Search tenants
  // ========================================
  Future<List<Tenant>> searchTenants(
    String organizationId,
    String searchTerm,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('tenants')
          .where('organizationId', isEqualTo: organizationId)
          .get();

      // Filter by name, phone, occupation, or workplace in memory
      final searchLower = searchTerm.toLowerCase();
      return snapshot.docs
          .map((doc) => Tenant.fromMap(doc.id, doc.data()))
          .where((tenant) =>
              tenant.fullName.toLowerCase().contains(searchLower) ||
              tenant.phoneNumber.contains(searchTerm) ||
              (tenant.email?.toLowerCase().contains(searchLower) ?? false) ||
              (tenant.nationalId?.contains(searchTerm) ?? false) ||
              (tenant.occupation?.toLowerCase().contains(searchLower) ?? false) ||
              (tenant.workplace?.toLowerCase().contains(searchLower) ?? false))
          .toList();
    } catch (e) {
      print('Error searching tenants: $e');
      return [];
    }
  }

  // ========================================
  // UTILITY - Get tenant statistics
  // ========================================
  Future<Map<String, int>> getTenantStatistics(String organizationId) async {
    try {
      final snapshot = await _firestore
          .collection('tenants')
          .where('organizationId', isEqualTo: organizationId)
          .get();

      final tenants = snapshot.docs
          .map((doc) => Tenant.fromMap(doc.id, doc.data()))
          .toList();

      return {
        'total': tenants.length,
        'active': tenants.where((t) => t.status == TenantStatus.active).length,
        'inactive': tenants.where((t) => t.status == TenantStatus.inactive).length,
        'movedOut': tenants.where((t) => t.status == TenantStatus.moveOut).length,
        'contractExpiring': tenants.where((t) => t.isContractExpiring).length,
        'contractExpired': tenants.where((t) => t.isContractExpired).length,
      };
    } catch (e) {
      print('Error getting tenant statistics: $e');
      return {};
    }
  }

  // ========================================
  // UTILITY - Get rental history statistics
  // ========================================
  Future<Map<String, dynamic>> getRentalHistoryStatistics(String tenantId) async {
    try {
      final tenant = await getTenantById(tenantId);
      if (tenant == null) return {};

      final previousRentals = tenant.previousRentals ?? [];
      
      return {
        'totalLocations': previousRentals.length + 1, // +1 for current location
        'totalDaysLiving': tenant.totalDaysLiving,
        'currentLocationDays': tenant.daysLiving,
        'averageDaysPerLocation': previousRentals.isEmpty 
            ? tenant.daysLiving 
            : tenant.totalDaysLiving ~/ (previousRentals.length + 1),
        'previousLocations': previousRentals.length,
      };
    } catch (e) {
      print('Error getting rental history statistics: $e');
      return {};
    }
  }

  // ========================================
  // UPDATE - Mark all building tenants as moved out
  // ========================================
  Future<int> markBuildingTenantsAsMovedOut(String buildingId) async {
    try {
      final snapshot = await _firestore
          .collection('tenants')
          .where('buildingId', isEqualTo: buildingId)
          .where('status', whereIn: ['active', 'inactive', 'suspended'])
          .get();

      if (snapshot.docs.isEmpty) {
        print('No active tenants found in building');
        return 0;
      }

      final batch = _firestore.batch();
      final now = DateTime.now();
      
      for (var doc in snapshot.docs) {
        final tenant = Tenant.fromMap(doc.id, doc.data());
        
        // Get building and room info before they're deleted
        final building = await _firestore
            .collection('buildings')
            .doc(tenant.buildingId)
            .get();
        
        final room = await _firestore
            .collection('rooms')
            .doc(tenant.roomId)
            .get();
        
        final buildingName = (() {
          if (building.exists != true) return 'Không xác định';

          final data = building.data();
          if (data == null) return 'Không xác định';

          final name = data['name'];
          if (name is String && name.isNotEmpty) return name;

          return 'Không xác định';
        })();

        final buildingAddress = building.exists && building.data()?['address'] != null
            ? building.data()!['address'] as String
            : null;

        final roomNumber = (() {
          if (room.exists != true) return '?';

          final data = room.data();
          if (data == null) return '?';

          final number = data['roomNumber'];
          if (number is String && number.isNotEmpty) return number;

          return '?';
        })();

        // Create rental history entry
        final previousRental = PreviousRentalHistory(
          buildingName: buildingName,
          buildingAddress: buildingAddress,
          roomNumber: roomNumber,
          moveInDate: tenant.moveInDate,
          moveOutDate: now,
          monthlyRent: tenant.monthlyRent,
          moveOutReason: 'Toà nhà bị xoá',
          notes: 'Tự động chuyển trạng thái do xóa toà nhà',
        );

        // Update previous rentals list
        final previousRentals = tenant.previousRentals ?? [];
        previousRentals.add(previousRental);
        
        batch.update(doc.reference, {
          'status': TenantStatus.moveOut.name,
          'moveOutDate': Timestamp.fromDate(now),
          'updatedAt': Timestamp.fromDate(now),
          'lastBuildingName': buildingName,
          'lastRoomNumber': roomNumber,
          'previousRentals': previousRentals.map((r) => r.toMap()).toList(),
          'notes': 'Tự động chuyển trạng thái do xóa toà nhà',
        });
      }
      
      await batch.commit();
      print('✅ Marked ${snapshot.docs.length} tenants as moved out from building: $buildingId');
      return snapshot.docs.length;
    } catch (e) {
      print('❌ Error marking building tenants as moved out: $e');
      return 0;
    }
  }

  // ========================================
  // DELETE - Delete all tenants in a building (hard delete)
  // ========================================
  Future<bool> deleteAllBuildingTenants(String buildingId) async {
    try {
      final snapshot = await _firestore
          .collection('tenants')
          .where('buildingId', isEqualTo: buildingId)
          .get();

      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      
      await batch.commit();
      print('Deleted ${snapshot.docs.length} tenants from building');
      return true;
    } catch (e) {
      print('Error deleting building tenants: $e');
      return false;
    }
  }
    // ========================================
  // VEHICLE - Add vehicle to tenant (simpler approach without transaction)
  // ========================================
  Future<bool> addVehicle(String tenantId, VehicleInfo vehicle) async {
    try {
      print('=== Starting addVehicle ===');
      print('Tenant ID: $tenantId');
      print('Vehicle: ${vehicle.licensePlate}');
      
      final tenantRef = _firestore.collection('tenants').doc(tenantId);
      print('Got tenant reference');

      // First, get the current tenant document
      print('Fetching current tenant...');
      final snapshot = await tenantRef.get();
      
      if (!snapshot.exists) {
        print('Error: Tenant not found with ID: $tenantId');
        return false;
      }

      final data = snapshot.data() as Map<String, dynamic>;
      print('Got tenant data');
      
      // Get existing vehicles
      List<Map<String, dynamic>> vehiclesList = [];
      
      if (data.containsKey('vehicles') && data['vehicles'] != null) {
        print('Vehicles field exists');
        if (data['vehicles'] is List) {
          print('Converting vehicles list...');
          try {
            vehiclesList = (data['vehicles'] as List)
                .map((item) {
                  if (item is Map<String, dynamic>) {
                    return item;
                  }
                  return Map<String, dynamic>.from(item as Map);
                })
                .toList();
            print('Converted ${vehiclesList.length} existing vehicles');
          } catch (e) {
            print('Error converting vehicles: $e');
            vehiclesList = [];
          }
        }
      } else {
        print('No existing vehicles');
      }

      // Create the vehicle map
      final vehicleMap = {
        'type': vehicle.type.name,
        'licensePlate': vehicle.licensePlate,
        'brand': vehicle.brand,
        'model': vehicle.model,
        'color': vehicle.color,
        'isParkingRegistered': vehicle.isParkingRegistered,
        'parkingSpot': vehicle.parkingSpot,
      };
      print('Vehicle map: $vehicleMap');
      
      vehiclesList.add(vehicleMap);
      print('Vehicle added, new count: ${vehiclesList.length}');

      // Update the tenant with new vehicles list
      print('Updating tenant...');
      await tenantRef.update({
        'vehicles': vehiclesList,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      print('Vehicle added successfully');
      return true;
    } catch (e, stackTrace) {
      print('=== Error adding vehicle ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      return false;
    }
  }

  // ========================================
  // VEHICLE - Update vehicle by index (simplified approach without transaction)
  // ========================================
  Future<bool> updateVehicle(String tenantId, int index, VehicleInfo vehicle) async {
    try {
      final tenantRef = _firestore.collection('tenants').doc(tenantId);

      // Get current tenant
      final snapshot = await tenantRef.get();
      if (!snapshot.exists) return false;

      final data = snapshot.data() as Map<String, dynamic>;
      
      // Get vehicles list
      List<Map<String, dynamic>> vehiclesList = [];
      if (data.containsKey('vehicles') && data['vehicles'] != null && data['vehicles'] is List) {
        vehiclesList = (data['vehicles'] as List)
            .map((item) => item is Map<String, dynamic> ? item : Map<String, dynamic>.from(item as Map))
            .toList();
      }

      if (index < 0 || index >= vehiclesList.length) {
        return false;
      }

      vehiclesList[index] = {
        'type': vehicle.type.name,
        'licensePlate': vehicle.licensePlate,
        'brand': vehicle.brand,
        'model': vehicle.model,
        'color': vehicle.color,
        'isParkingRegistered': vehicle.isParkingRegistered,
        'parkingSpot': vehicle.parkingSpot,
      };

      await tenantRef.update({
        'vehicles': vehiclesList,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      print('Error updating vehicle: $e');
      return false;
    }
  }

  // ========================================
  // VEHICLE - Remove vehicle by index (simplified approach without transaction)
  // ========================================
  Future<bool> removeVehicle(String tenantId, int index) async {
    try {
      final tenantRef = _firestore.collection('tenants').doc(tenantId);

      // Get current tenant
      final snapshot = await tenantRef.get();
      if (!snapshot.exists) return false;

      final data = snapshot.data() as Map<String, dynamic>;
      
      // Get vehicles list
      List<Map<String, dynamic>> vehiclesList = [];
      if (data.containsKey('vehicles') && data['vehicles'] != null && data['vehicles'] is List) {
        vehiclesList = (data['vehicles'] as List)
            .map((item) => item is Map<String, dynamic> ? item : Map<String, dynamic>.from(item as Map))
            .toList();
      }

      if (index < 0 || index >= vehiclesList.length) {
        return false;
      }

      vehiclesList.removeAt(index);

      await tenantRef.update({
        'vehicles': vehiclesList,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      print('Error removing vehicle: $e');
      return false;
    }
  }

  // ========================================
  // VEHICLE - Get tenant vehicles
  // ========================================
  Future<List<VehicleInfo>> getTenantVehicles(String tenantId) async {
    try {
      final tenant = await getTenantById(tenantId);
      return tenant?.vehicles ?? [];
    } catch (e) {
      print('Error getting tenant vehicles: $e');
      return [];
    }
  }

  // ========================================
  // VEHICLE - Find tenant by license plate (scans organization)
  // Note: expensive for large orgs; consider an index collection for production.
  // ========================================
  Future<Tenant?> findTenantByLicensePlate(
    String organizationId,
    String licensePlate,
  ) async {
    try {
      final normalized = licensePlate.replaceAll(' ', '').toLowerCase();

      final snapshot = await _firestore
          .collection('tenants')
          .where('organizationId', isEqualTo: organizationId)
          .get();

      for (var doc in snapshot.docs) {
        final tenant = Tenant.fromMap(doc.id, doc.data());
        if (tenant.vehicles != null) {
          for (var v in tenant.vehicles!) {
            final vPlate = v.licensePlate.replaceAll(' ', '').toLowerCase();
            if (vPlate == normalized) return tenant;
          }
        }
      }

      return null;
    } catch (e) {
      print('Error finding tenant by license plate: $e');
      return null;
    }
  }

  // ========================================
  // VEHICLE - Register parking spot for a vehicle (simplified approach without transaction)
  // ========================================
  Future<bool> registerParkingSpot(
    String tenantId,
    int vehicleIndex,
    String parkingSpot,
  ) async {
    try {
      final tenantRef = _firestore.collection('tenants').doc(tenantId);

      // Get current tenant
      final snapshot = await tenantRef.get();
      if (!snapshot.exists) return false;

      final data = snapshot.data() as Map<String, dynamic>;
      
      // Get vehicles list
      List<Map<String, dynamic>> vehiclesList = [];
      if (data.containsKey('vehicles') && data['vehicles'] != null && data['vehicles'] is List) {
        vehiclesList = (data['vehicles'] as List)
            .map((item) => item is Map<String, dynamic> ? item : Map<String, dynamic>.from(item as Map))
            .toList();
      }

      if (vehicleIndex < 0 || vehicleIndex >= vehiclesList.length) {
        return false;
      }

      // Update the vehicle
      vehiclesList[vehicleIndex]['isParkingRegistered'] = true;
      vehiclesList[vehicleIndex]['parkingSpot'] = parkingSpot;

      await tenantRef.update({
        'vehicles': vehiclesList,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      print('Error registering parking spot: $e');
      return false;
    }
  }

  // ========================================
  // VEHICLE - Unregister parking spot for a vehicle (simplified approach without transaction)
  // ========================================
  Future<bool> unregisterParkingSpot(
    String tenantId,
    int vehicleIndex,
  ) async {
    try {
      final tenantRef = _firestore.collection('tenants').doc(tenantId);

      // Get current tenant
      final snapshot = await tenantRef.get();
      if (!snapshot.exists) return false;

      final data = snapshot.data() as Map<String, dynamic>;
      
      // Get vehicles list
      List<Map<String, dynamic>> vehiclesList = [];
      if (data.containsKey('vehicles') && data['vehicles'] != null && data['vehicles'] is List) {
        vehiclesList = (data['vehicles'] as List)
            .map((item) => item is Map<String, dynamic> ? item : Map<String, dynamic>.from(item as Map))
            .toList();
      }

      if (vehicleIndex < 0 || vehicleIndex >= vehiclesList.length) {
        return false;
      }

      // Update the vehicle
      vehiclesList[vehicleIndex]['isParkingRegistered'] = false;
      vehiclesList[vehicleIndex]['parkingSpot'] = null;

      await tenantRef.update({
        'vehicles': vehiclesList,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      print('Error unregistering parking spot: $e');
      return false;
    }
  }
}