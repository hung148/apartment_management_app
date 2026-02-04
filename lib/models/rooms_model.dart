import 'package:cloud_firestore/cloud_firestore.dart';

class Room {
  final String id;
  final String organizationId;
  final String buildingId;
  final String roomNumber;
  final String roomType; 
  final double area; // Trường mới: Diện tích (m2)
  final DateTime createdAt;

  Room({
    required this.id,
    required this.organizationId,
    required this.buildingId,
    required this.roomNumber,
    required this.roomType,
    required this.area, // Thêm vào constructor
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'organizationId': organizationId,
      'buildingId': buildingId,
      'roomNumber': roomNumber,
      'roomType': roomType,
      'area': area, // Lưu diện tích lên Firestore
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory Room.fromMap(String id, Map<String, dynamic> map) {
    return Room(
      id: id,
      organizationId: map['organizationId'] ?? '',
      buildingId: map['buildingId'] ?? '',
      roomNumber: map['roomNumber'] ?? '',
      roomType: map['roomType'] ?? 'Tiêu chuẩn', 
      // Ép kiểu an toàn từ Firestore (có thể là int hoặc double)
      area: (map['area'] as num?)?.toDouble() ?? 0.0, 
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}