import 'package:apartment_management_project_2/models/buildings_model.dart';
import 'package:apartment_management_project_2/services/tenants_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:apartment_management_project_2/widgets/app_logger.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BuildingService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  // ========================================
  // CREATE - Add a new building
  // ========================================
  Future<String?> addBuilding(Building building) async {

    if (FirebaseAuth.instance.currentUser == null) return null;
    
    try {
      final docRef = await _firestore.collection('buildings').add(building.toMap());
      logger.i('Building added successfully: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      logger.e('Error adding building', error: e);
      return null;
    }
  }

  // ========================================
  // CREATE - Add building with room configuration from dialog
  // ========================================
  Future<String?> addBuildingFromDialogResult({
    required String organizationId,
    required Map<String, dynamic> dialogResult,
  }) async {

    if (FirebaseAuth.instance.currentUser == null) return null;
    
    try {
      final building = Building(
        id: '', 
        organizationId: organizationId,
        name: dialogResult['name'],
        address: dialogResult['address'],
        createdAt: DateTime.now(),
        floors: dialogResult['autoGenerateRooms'] == true ? dialogResult['floors'] : null,
        roomPrefix: dialogResult['autoGenerateRooms'] == true ? dialogResult['roomPrefix'] : null,
        uniformRooms: dialogResult['autoGenerateRooms'] == true ? dialogResult['uniformRooms'] : null,
        
        // Handle Uniform specific data
        roomsPerFloor: dialogResult['uniformRooms'] == true ? dialogResult['roomsPerFloor'] : null,
        roomType: dialogResult['uniformRooms'] == true ? dialogResult['roomType'] : null,
        roomArea: dialogResult['uniformRooms'] == true ? dialogResult['roomArea'] : null,
        
        // Handle Custom specific data
        floorDetails: dialogResult['uniformRooms'] == false ? dialogResult['floorDetails'] : null,
      );

      final docRef = await _firestore.collection('buildings').add(building.toMap());
      return docRef.id;
    } catch (e) {
      logger.e('Error adding building', error: e);
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
      logger.e('Error getting buildings', error: e);
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
        logger.w('Building not found: $buildingId');
        return null;
      }
      
      return Building.fromMap(doc.id, doc.data()!);
    } catch (e) {
      logger.e('Error getting building', error: e);
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
    
    if (FirebaseAuth.instance.currentUser == null) return false;
    
    try {
      await _firestore.collection('buildings').doc(buildingId).update(data);
      logger.i('Building updated successfully: $buildingId');
      return true;
    } catch (e) {
      logger.e('Error updating building', error: e);
      return false;
    }
  }

  // ========================================
  // UPDATE - Update building from dialog result
  // ========================================
  Future<bool> updateBuildingFromDialogResult({
    required String buildingId,
    required Map<String, dynamic> dialogResult,
  }) async {
    
    if (FirebaseAuth.instance.currentUser == null) return false;
    
    try {
      final updateData = <String, dynamic>{
        'name': dialogResult['name'],
        'address': dialogResult['address'],
      };

      if (dialogResult['autoGenerateRooms'] == true) {
        updateData['floors'] = dialogResult['floors'];
        updateData['roomPrefix'] = dialogResult['roomPrefix'];
        updateData['uniformRooms'] = dialogResult['uniformRooms'];
        
        if (dialogResult['uniformRooms'] == true) {
          updateData['roomsPerFloor'] = dialogResult['roomsPerFloor'];
          updateData['roomType'] = dialogResult['roomType'];
          updateData['roomArea'] = dialogResult['roomArea'];
          // Clear custom details if switching to uniform
          updateData['floorDetails'] = FieldValue.delete();
        } else {
          updateData['floorDetails'] = dialogResult['floorDetails'];
          // Clear uniform fields if switching to custom
          updateData['roomsPerFloor'] = FieldValue.delete();
          updateData['roomType'] = FieldValue.delete();
          updateData['roomArea'] = FieldValue.delete();
        }
      }

      await _firestore.collection('buildings').doc(buildingId).update(updateData);
      return true;
    } catch (e) {
      logger.e('Error updating building', error: e);
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
  Future<bool> deleteBuilding(String buildingId, String organizationId) async {
    
    if (FirebaseAuth.instance.currentUser == null) return false;
    
    try {
      // Optional: Check if building has rooms before deleting
      final rooms = await _firestore
          .collection('rooms')
          .where('organizationId', isEqualTo: organizationId)
          .where('buildingId', isEqualTo: buildingId)
          .limit(1)
          .get();
      
      if (rooms.docs.isNotEmpty) {
        logger.w('Cannot delete building: It contains rooms');
        return false;
      }

      await _firestore.collection('buildings').doc(buildingId).delete();
      logger.i('Building deleted successfully: $buildingId');
      return true;
    } catch (e) {
      logger.e('Error deleting building', error: e);
      return false;
    }
  }

  // ========================================
  // DELETE - Force delete building and all its rooms
  // ========================================
  Future<bool> deleteBuildingWithRooms(String buildingId, String organizationId) async {
    
    if (FirebaseAuth.instance.currentUser == null) return false;
    
    try {
      // First, delete all rooms in this building
      final roomsSnapshot = await _firestore
          .collection('rooms')
          .where('organizationId', isEqualTo: organizationId)
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
      
      logger.i('Building and ${roomsSnapshot.docs.length} rooms deleted successfully');
      return true;
    } catch (e) {
      logger.e('Error deleting building with rooms', error: e);
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
      logger.e('Error counting buildings', error: e);
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
      logger.e('Error searching buildings', error: e);
      return [];
    }
  }

  // ========================================
  // DELETE - Delete building with rooms and mark tenants as moved out
  // ========================================
  Future<Map<String, int>> deleteBuildingWithRoomsAndTenants(String buildingId, String organizationId) async {
    
    if (FirebaseAuth.instance.currentUser == null) {
      return {
        'rooms': 0,
        'tenants': 0,
      };
    }
    
    try {
      final tenantService = TenantService();
      
      // Step 1: Mark all tenants as moved out (preserve data)
      final tenantsAffected = await tenantService.markBuildingTenantsAsMovedOut(buildingId, organizationId);
      
      // Step 2: Delete all rooms in this building
      final roomsSnapshot = await _firestore
          .collection('rooms')
          .where('organizationId', isEqualTo: organizationId)
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
      
      logger.i('Building deleted: ${roomsSnapshot.docs.length} rooms, $tenantsAffected tenants marked as moved out');
      
      return {
        'rooms': roomsSnapshot.docs.length,
        'tenants': tenantsAffected,
      };
    } catch (e) {
      logger.e('Error deleting building', error: e);
      return {
        'rooms': 0,
        'tenants': 0,
      };
    }
  }
}