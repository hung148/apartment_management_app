import 'package:apartment_management_project_2/models/rooms_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RoomService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  // ========================================
  // CREATE - Add a new room
  // ========================================
  Future<String?> addRoom(Room room) async {
    try {
      final docRef = await _firestore.collection('rooms').add(room.toMap());
      print('Room added successfully: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('Error adding room: $e');
      return null;
    }
  }

  // ========================================
  // CREATE - Add multiple rooms at once
  // ========================================
  Future<bool> addMultipleRooms(List<Room> rooms) async {
    try {
      final batch = _firestore.batch();
      
      for (var room in rooms) {
        final docRef = _firestore.collection('rooms').doc();
        batch.set(docRef, room.toMap());
      }
      
      await batch.commit();
      print('${rooms.length} rooms added successfully');
      return true;
    } catch (e) {
      print('Error adding multiple rooms: $e');
      return false;
    }
  }

  // ========================================
  // READ - Get all rooms in a building
  // ========================================
  Future<List<Room>> getBuildingRooms(String organizationId, String buildingId) async {
    try {
      final snapshot = await _firestore
          .collection('rooms')
          .where('organizationId', isEqualTo: organizationId)
          .where('buildingId', isEqualTo: buildingId)
          .orderBy('roomNumber', descending: false)
          .get();

      return snapshot.docs
          .map((doc) => Room.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      print('Error getting building rooms: $e');
      return [];
    }
  }

  // ========================================
  // READ - Get all rooms in an organization
  // ========================================
  Future<List<Room>> getOrganizationRooms(String organizationId) async {
    try {
      final snapshot = await _firestore
          .collection('rooms')
          .where('organizationId', isEqualTo: organizationId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => Room.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      print('Error getting organization rooms: $e');
      return [];
    }
  }

  // ========================================
  // READ - Get a single room by ID
  // ========================================
  Future<Room?> getRoomById(String roomId) async {
    try {
      final doc = await _firestore.collection('rooms').doc(roomId).get();
      
      if (!doc.exists) {
        print('Room not found: $roomId');
        return null;
      }
      
      return Room.fromMap(doc.id, doc.data()!);
    } catch (e) {
      print('Error getting room: $e');
      return null;
    }
  }

  // ========================================
  // READ - Get room by room number in a building
  // ========================================
  Future<Room?> getRoomByNumber(String organizationId, String buildingId, String roomNumber) async {
    try {
      final snapshot = await _firestore
          .collection('rooms')
          .where('organizationId', isEqualTo: organizationId)
          .where('buildingId', isEqualTo: buildingId)
          .where('roomNumber', isEqualTo: roomNumber)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return null;
      }

      return Room.fromMap(snapshot.docs.first.id, snapshot.docs.first.data());
    } catch (e) {
      print('Error getting room by number: $e');
      return null;
    }
  }

  // ========================================
  // READ - Stream rooms (real-time updates)
  // ========================================
  Stream<List<Room>> streamBuildingRooms(String buildingId, String orgId) {
    return _firestore
        .collection('rooms')
        .where('organizationId', isEqualTo: orgId) // Add this line!
        .where('buildingId', isEqualTo: buildingId)
        .orderBy('roomNumber', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Room.fromMap(doc.id, doc.data()))
            .toList());
  }

  Stream<List<Room>> streamOrganizationRooms(String organizationId) {
    return _firestore
        .collection('rooms')
        .where('organizationId', isEqualTo: organizationId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Room.fromMap(doc.id, doc.data()))
            .toList());
  }

  // ========================================
  // UPDATE - Update room information
  // ========================================
  Future<bool> updateRoom(String roomId, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('rooms').doc(roomId).update(data);
      print('Room updated successfully: $roomId');
      return true;
    } catch (e) {
      print('Error updating room: $e');
      return false;
    }
  }

  // ========================================
  // UPDATE - Update room number
  // ========================================
  Future<bool> updateRoomNumber(String roomId, String newRoomNumber) async {
    return updateRoom(roomId, {'roomNumber': newRoomNumber});
  }

  // ========================================
  // UPDATE - Move room to different building
  // ========================================
  Future<bool> moveRoomToBuilding(String roomId, String newBuildingId) async {
    return updateRoom(roomId, {'buildingId': newBuildingId});
  }

  // ========================================
  // DELETE - Delete a room
  // ========================================
  Future<bool> deleteRoom(String roomId) async {
    try {
      await _firestore.collection('rooms').doc(roomId).delete();
      print('Room deleted successfully: $roomId');
      return true;
    } catch (e) {
      print('Error deleting room: $e');
      return false;
    }
  }

  // ========================================
  // DELETE - Delete all rooms in a building
  // ========================================
  Future<bool> deleteAllBuildingRooms(String organizationId, String buildingId) async {
    try {
      final snapshot = await _firestore
          .collection('rooms')
          .where('organizationId', isEqualTo: organizationId)
          .where('buildingId', isEqualTo: buildingId)
          .get();

      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      
      await batch.commit();
      print('Deleted ${snapshot.docs.length} rooms from building');
      return true;
    } catch (e) {
      print('Error deleting building rooms: $e');
      return false;
    }
  }

  // ========================================
  // DELETE - Delete multiple rooms by IDs
  // ========================================
  Future<bool> deleteMultipleRooms(List<String> roomIds) async {
    try {
      final batch = _firestore.batch();
      
      for (var roomId in roomIds) {
        batch.delete(_firestore.collection('rooms').doc(roomId));
      }
      
      await batch.commit();
      print('Deleted ${roomIds.length} rooms');
      return true;
    } catch (e) {
      print('Error deleting multiple rooms: $e');
      return false;
    }
  }

  // ========================================
  // UTILITY - Count rooms in a building
  // ========================================
  Future<int> countBuildingRooms(String organizationId, String buildingId) async {
    try {
      final snapshot = await _firestore
          .collection('rooms')
          .where('organizationId', isEqualTo: organizationId)
          .where('buildingId', isEqualTo: buildingId)
          .count()
          .get();
      
      return snapshot.count ?? 0;
    } catch (e) {
      print('Error counting rooms: $e');
      return 0;
    }
  }

  // ========================================
  // UTILITY - Count rooms in organization
  // ========================================
  Future<int> countOrganizationRooms(String organizationId) async {
    try {
      final snapshot = await _firestore
          .collection('rooms')
          .where('organizationId', isEqualTo: organizationId)
          .count()
          .get();
      
      return snapshot.count ?? 0;
    } catch (e) {
      print('Error counting organization rooms: $e');
      return 0;
    }
  }

  // ========================================
  // UTILITY - Check if room number exists in building
  // ========================================
  Future<bool> isRoomNumberExists(String organizationId, String buildingId, String roomNumber) async {
    try {
      final snapshot = await _firestore
          .collection('rooms')
          .where('organizationId', isEqualTo: organizationId)
          .where('buildingId', isEqualTo: buildingId)
          .where('roomNumber', isEqualTo: roomNumber)
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking room number: $e');
      return false;
    }
  }

  // ========================================
  // UTILITY - Search rooms by room number
  // ========================================
  Future<List<Room>> searchRoomsByNumber(
    String organizationId,
    String buildingId, 
    String searchTerm,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('rooms')
          .where('organizationId', isEqualTo: organizationId)
          .where('buildingId', isEqualTo: buildingId)
          .get();

      // Filter by room number
      return snapshot.docs
          .map((doc) => Room.fromMap(doc.id, doc.data()))
          .where((room) => 
              room.roomNumber.toLowerCase().contains(searchTerm.toLowerCase()))
          .toList();
    } catch (e) {
      print('Error searching rooms: $e');
      return [];
    }
  }

  // ========================================
  // UTILITY - Generate room numbers for a building (LEGACY - kept for compatibility)
  // ========================================
  Future<List<Room>> generateRoomsForBuilding({
    required String organizationId,
    required String buildingId,
    required int numberOfFloors,
    required int roomsPerFloor,
    String prefix = '',
  }) async {
    List<Room> rooms = [];
    
    for (int floor = 1; floor <= numberOfFloors; floor++) {
      for (int roomNum = 1; roomNum <= roomsPerFloor; roomNum++) {
        String roomNumber = '${prefix}${floor}${roomNum.toString().padLeft(2, '0')}';
        
        rooms.add(Room(
          id: '', // Will be generated by Firestore
          organizationId: organizationId,
          buildingId: buildingId,
          roomNumber: roomNumber,
          area: 0.0,
          roomType: 'Tiêu Chuẩn',
          createdAt: DateTime.now(),
        ));
      }
    }
    
    return rooms;
  }

  // ========================================
  // UTILITY - Generate rooms with uniform distribution (same rooms per floor)
  // ========================================
   Future<List<Room>> generateUniformRoomsForBuilding({
    required String organizationId,
    required String buildingId,
    required int numberOfFloors,
    required int roomsPerFloor,
    required String prefix,
    required String roomType,
    required double area,
  }) async {
    final rooms = <Room>[];
    for (int floor = 1; floor <= numberOfFloors; floor++) {
      for (int roomNum = 1; roomNum <= roomsPerFloor; roomNum++) {
        // Format: A101, A102...
        final roomNumber = '$prefix$floor${roomNum.toString().padLeft(2, '0')}';
        rooms.add(Room(
          id: '',
          organizationId: organizationId,
          buildingId: buildingId,
          roomNumber: roomNumber,
          roomType: roomType,
          area: area,
          createdAt: DateTime.now(),
        ));
      }
    }
    return rooms;
  }

  // ========================================
  // UTILITY - Generate rooms with custom distribution (different rooms per floor)
  // ========================================
  Future<List<Room>> generateCustomRoomsForBuilding({
    required String organizationId,
    required String buildingId,
    required List<Map<String, dynamic>> floorDetails,
    required String prefix,
  }) async {
    final rooms = <Room>[];
    
    for (int i = 0; i < floorDetails.length; i++) {
      final floorNum = i + 1;
      final detail = floorDetails[i];
      
      final int count = detail['count'] as int;
      final String type = detail['type'] ?? 'Standard';
      final double area = (detail['area'] as num?)?.toDouble() ?? 0.0;
      
      // ✅ NEW: Get custom names if available
      final List<String> customNames = detail['customNames'] != null 
          ? List<String>.from(detail['customNames'])
          : [];

      for (int roomNum = 1; roomNum <= count; roomNum++) {
        // ✅ NEW: Use custom name if provided, otherwise use auto-generated
        final String roomNumber;
        if (roomNum <= customNames.length && customNames[roomNum - 1].isNotEmpty) {
          roomNumber = customNames[roomNum - 1];
        } else {
          roomNumber = '$prefix$floorNum${roomNum.toString().padLeft(2, '0')}';
        }
        
        rooms.add(Room(
          id: '',
          organizationId: organizationId,
          buildingId: buildingId,
          roomNumber: roomNumber,
          roomType: type,
          area: area,
          createdAt: DateTime.now(),
        ));
      }
    }
    return rooms;
  }

  // ========================================
  // UTILITY - Hàm xử lý cấu hình tổng quát
  // ========================================
  Future<List<Room>> generateRoomsFromConfig({
    required String organizationId,
    required String buildingId,
    required Map<String, dynamic> config,
  }) async {
    final String prefix = config['roomPrefix'] ?? '';

    if (config['uniformRooms'] == true) {
      // Chế độ đồng đều
      return generateUniformRoomsForBuilding(
        organizationId: organizationId,
        buildingId: buildingId,
        numberOfFloors: config['floors'] as int,
        roomsPerFloor: config['roomsPerFloor'] as int,
        prefix: prefix,
        roomType: config['roomType'] ?? 'Tiêu chuẩn',
        area: (config['roomArea'] as num?)?.toDouble() ?? 0.0,
      );
    } else {
      // Chế độ tùy chỉnh
      final List<Map<String, dynamic>> details = 
          List<Map<String, dynamic>>.from(config['floorDetails'] ?? []);
          
      return generateCustomRoomsForBuilding(
        organizationId: organizationId,
        buildingId: buildingId,
        floorDetails: details,
        prefix: prefix,
      );
    }
  }
}