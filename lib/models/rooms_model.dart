import 'package:cloud_firestore/cloud_firestore.dart';

class Room {
  final String id;
  final String organizationId;
  final String buildingId;
  final String roomNumber;
  final DateTime createdAt;

  Room({
    required this.id,
    required this.organizationId,
    required this.buildingId,
    required this.roomNumber,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'organizationId': organizationId,
      'buildingId': buildingId,
      'roomNumber': roomNumber,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory Room.fromMap(String id, Map<String, dynamic> map) {
    return Room(
      id: id,
      organizationId: map['organizationId'] ?? '',
      buildingId: map['buildingId'] ?? '',
      roomNumber: map['roomNumber'] ?? '',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
    );
  }
}