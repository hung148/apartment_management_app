import 'package:cloud_firestore/cloud_firestore.dart';

class Building {
  final String id;
  final String organizationId;
  final String name;
  final String address;
  final DateTime createdAt;
  
  // Room configuration fields (optional - only present if rooms were auto-generated)
  final int? floors;
  final String? roomPrefix;
  final bool? uniformRooms;
  final int? roomsPerFloor;
  final List<int>? floorRoomCounts;

  Building({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.address,
    required this.createdAt,
    this.floors,
    this.roomPrefix,
    this.uniformRooms,
    this.roomsPerFloor,
    this.floorRoomCounts,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'organizationId': organizationId,
      'name': name,
      'address': address,
      'createdAt': Timestamp.fromDate(createdAt),
    };

    // Add optional room configuration fields if they exist
    if (floors != null) map['floors'] = floors!;
    if (roomPrefix != null) map['roomPrefix'] = roomPrefix!;
    if (uniformRooms != null) map['uniformRooms'] = uniformRooms!;
    if (roomsPerFloor != null) map['roomsPerFloor'] = roomsPerFloor!;
    if (floorRoomCounts != null) map['floorRoomCounts'] = floorRoomCounts!;

    return map;
  }

  factory Building.fromMap(String id, Map<String, dynamic> map) {
    return Building(
      id: id,
      organizationId: map['organizationId'] ?? '',
      name: map['name'] ?? '',
      address: map['address'] ?? '',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      floors: map['floors'] as int?,
      roomPrefix: map['roomPrefix'] as String?,
      uniformRooms: map['uniformRooms'] as bool?,
      roomsPerFloor: map['roomsPerFloor'] as int?,
      floorRoomCounts: map['floorRoomCounts'] != null 
          ? List<int>.from(map['floorRoomCounts']) 
          : null,
    );
  }

  // Helper method to create a copy with updated fields
  Building copyWith({
    String? name,
    String? address,
    int? floors,
    String? roomPrefix,
    bool? uniformRooms,
    int? roomsPerFloor,
    List<int>? floorRoomCounts,
  }) {
    return Building(
      id: id,
      organizationId: organizationId,
      name: name ?? this.name,
      address: address ?? this.address,
      createdAt: createdAt,
      floors: floors ?? this.floors,
      roomPrefix: roomPrefix ?? this.roomPrefix,
      uniformRooms: uniformRooms ?? this.uniformRooms,
      roomsPerFloor: roomsPerFloor ?? this.roomsPerFloor,
      floorRoomCounts: floorRoomCounts ?? this.floorRoomCounts,
    );
  }
}