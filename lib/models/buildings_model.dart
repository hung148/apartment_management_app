import 'package:cloud_firestore/cloud_firestore.dart';

class Building {
  final String id;
  final String organizationId;
  final String name;
  final String address;
  final DateTime createdAt;
  final int? floors;
  final String? roomPrefix;
  final bool? uniformRooms;
  final int? roomsPerFloor;

  // THÊM ĐẦY ĐỦ 2 DÒNG NÀY VÀO CLASS
  final List<int>? floorRoomCounts; // Dữ liệu cũ (Chỉ chứa số lượng)
  final List<Map<String, dynamic>>? floorDetails; // Dữ liệu mới (Số lượng, Loại, Diện tích)
  
  final String? roomType; 
  final double? roomArea; 

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
    this.floorDetails,    
    this.roomType,
    this.roomArea,
  });

  // Đừng quên cập nhật toMap và fromMap để lưu/đọc 2 trường này từ Firestore
  Map<String, dynamic> toMap() {
    return {
      'organizationId': organizationId,
      'name': name,
      'address': address,
      'createdAt': Timestamp.fromDate(createdAt),
      'floors': floors,
      'roomPrefix': roomPrefix,
      'uniformRooms': uniformRooms,
      'roomsPerFloor': roomsPerFloor,
      'floorRoomCounts': floorRoomCounts,
      'floorDetails': floorDetails,
      'roomType': roomType,
      'roomArea': roomArea,
    };
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
      floorRoomCounts: map['floorRoomCounts'] != null ? List<int>.from(map['floorRoomCounts']) : null,
      floorDetails: map['floorDetails'] != null ? List<Map<String, dynamic>>.from(map['floorDetails']) : null,
      roomType: map['roomType'] as String?,
      roomArea: (map['roomArea'] as num?)?.toDouble(),
    );
  }
}