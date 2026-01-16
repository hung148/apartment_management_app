import 'package:apartment_management_project_2/models/buildings_model.dart';
import 'package:apartment_management_project_2/services/tenants_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BuildingService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  // ========================================
  // CREATE - Add a new building
  // ========================================
  Future<String?> addBuilding(Building building) async {
    try {
      final docRef = await _firestore.collection('buildings').add(building.toMap());
      print('Building added successfully: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('Error adding building: $e');
      return null;
    }
  }

  // ========================================
  // READ - Get all buildings for an organization
  // ========================================
  Future<List<Building>> getOrganizationBuildings(String organizationId) async {
    try {
      final snapshot = await _firestore
          .collection('buildings')
          .where('organizationId', isEqualTo: organizationId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => Building.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      print('Error getting buildings: $e');
      return [];
    }
  }

  // ========================================
  // READ - Get a single building by ID
  // ========================================
  Future<Building?> getBuildingById(String buildingId) async {
    try {
      final doc = await _firestore.collection('buildings').doc(buildingId).get();
      
      if (!doc.exists) {
        print('Building not found: $buildingId');
        return null;
      }
      
      return Building.fromMap(doc.id, doc.data()!);
    } catch (e) {
      print('Error getting building: $e');
      return null;
    }
  }

  // ========================================
  // READ - Stream buildings (real-time updates)
  // ========================================
  Stream<List<Building>> streamOrganizationBuildings(String organizationId) {
    return _firestore
        .collection('buildings')
        .where('organizationId', isEqualTo: organizationId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Building.fromMap(doc.id, doc.data()))
            .toList());
  }

  // ========================================
  // UPDATE - Update building information
  // ========================================
  Future<bool> updateBuilding(String buildingId, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('buildings').doc(buildingId).update(data);
      print('Building updated successfully: $buildingId');
      return true;
    } catch (e) {
      print('Error updating building: $e');
      return false;
    }
  }

  // ========================================
  // UPDATE - Update specific fields
  // ========================================
  Future<bool> updateBuildingName(String buildingId, String newName) async {
    return updateBuilding(buildingId, {'name': newName});
  }

  Future<bool> updateBuildingAddress(String buildingId, String newAddress) async {
    return updateBuilding(buildingId, {'address': newAddress});
  }

  // ========================================
  // DELETE - Delete a building
  // ========================================
  Future<bool> deleteBuilding(String buildingId) async {
    try {
      // Optional: Check if building has rooms before deleting
      final rooms = await _firestore
          .collection('rooms')
          .where('buildingId', isEqualTo: buildingId)
          .limit(1)
          .get();
      
      if (rooms.docs.isNotEmpty) {
        print('Cannot delete building: It contains rooms');
        return false;
      }

      await _firestore.collection('buildings').doc(buildingId).delete();
      print('Building deleted successfully: $buildingId');
      return true;
    } catch (e) {
      print('Error deleting building: $e');
      return false;
    }
  }

  // ========================================
  // DELETE - Force delete building and all its rooms
  // ========================================
  Future<bool> deleteBuildingWithRooms(String buildingId) async {
    try {
      // First, delete all rooms in this building
      final roomsSnapshot = await _firestore
          .collection('rooms')
          .where('buildingId', isEqualTo: buildingId)
          .get();

      // Delete rooms in batch
      final batch = _firestore.batch();
      for (var doc in roomsSnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      // Then delete the building
      await _firestore.collection('buildings').doc(buildingId).delete();
      
      print('Building and ${roomsSnapshot.docs.length} rooms deleted successfully');
      return true;
    } catch (e) {
      print('Error deleting building with rooms: $e');
      return false;
    }
  }

  // ========================================
  // UTILITY - Count buildings in organization
  // ========================================
  Future<int> countOrganizationBuildings(String organizationId) async {
    try {
      final snapshot = await _firestore
          .collection('buildings')
          .where('organizationId', isEqualTo: organizationId)
          .count()
          .get();
      
      return snapshot.count ?? 0;
    } catch (e) {
      print('Error counting buildings: $e');
      return 0;
    }
  }

  // ========================================
  // UTILITY - Search buildings by name
  // ========================================
  Future<List<Building>> searchBuildingsByName(
    String organizationId, 
    String searchTerm,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('buildings')
          .where('organizationId', isEqualTo: organizationId)
          .get();

      // Filter by name (Firestore doesn't support case-insensitive search)
      return snapshot.docs
          .map((doc) => Building.fromMap(doc.id, doc.data()))
          .where((building) => 
              building.name.toLowerCase().contains(searchTerm.toLowerCase()))
          .toList();
    } catch (e) {
      print('Error searching buildings: $e');
      return [];
    }
  }

  // ========================================
  // DELETE - Delete building with rooms and mark tenants as moved out
  // ========================================
  Future<Map<String, int>> deleteBuildingWithRoomsAndTenants(String buildingId) async {
    try {
      final tenantService = TenantService();
      
      // Step 1: Mark all tenants as moved out (preserve data)
      final tenantsAffected = await tenantService.markBuildingTenantsAsMovedOut(buildingId);
      
      // Step 2: Delete all rooms in this building
      final roomsSnapshot = await _firestore
          .collection('rooms')
          .where('buildingId', isEqualTo: buildingId)
          .get();

      final batch = _firestore.batch();
      for (var doc in roomsSnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      // Step 3: Delete the building itself
      await _firestore
          .collection('buildings')
          .doc(buildingId)
          .delete();
      
      print('✅ Building deleted: ${roomsSnapshot.docs.length} rooms, $tenantsAffected tenants marked as moved out');
      
      return {
        'rooms': roomsSnapshot.docs.length,
        'tenants': tenantsAffected,
      };
    } catch (e) {
      print('❌ Error deleting building: $e');
      return {
        'rooms': 0,
        'tenants': 0,
      };
    }
  }
}