import 'package:apartment_management_project_2/models/tenants_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TenantService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
  }) async {
    return updateTenant(tenantId, {
      'status': TenantStatus.moveOut.name,
      'moveOutDate': Timestamp.fromDate(moveOutDate ?? DateTime.now()),
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
  // UPDATE - Move tenant to different room
  // ========================================
  Future<bool> moveTenantToRoom(
    String tenantId,
    String newBuildingId,
    String newRoomId,
  ) async {
    return updateTenant(tenantId, {
      'buildingId': newBuildingId,
      'roomId': newRoomId,
      'moveInDate': Timestamp.now(), // Reset move-in date
    });
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

      // Filter by name or phone in memory
      final searchLower = searchTerm.toLowerCase();
      return snapshot.docs
          .map((doc) => Tenant.fromMap(doc.id, doc.data()))
          .where((tenant) =>
              tenant.fullName.toLowerCase().contains(searchLower) ||
              tenant.phoneNumber.contains(searchTerm) ||
              (tenant.email?.toLowerCase().contains(searchLower) ?? false) ||
              (tenant.nationalId?.contains(searchTerm) ?? false))
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
}