import 'package:cloud_firestore/cloud_firestore.dart';

enum BuildingManagementType {
  selfManaged, // Tự quản lý (chủ sở hữu hoặc quản lý trực tiếp)
  rented,      // Đi thuê (thuê nguyên tòa nhà từ chủ nhà khác)
}

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

  final List<int>? floorRoomCounts; // Dữ liệu cũ (Chỉ chứa số lượng)
  final List<Map<String, dynamic>>? floorDetails; // Dữ liệu mới (Số lượng, Loại, Diện tích)
  
  final String? roomType; 
  final double? roomArea; 

  // Building management type: self-managed (default) vs rented from a renter
  final BuildingManagementType managementType;

  // Renter info — the party leasing the *whole building* from you (only relevant when managementType == rented)
  final String? renterName;
  final String? renterPhone;
  final double? rentAmount;        // Số tiền người thuê trả cho bạn mỗi kỳ
  final int? rentDueDay;           // Ngày đến hạn thanh toán trong tháng (1-31)
  final DateTime? rentContractStart;
  final DateTime? rentContractEnd;
  final String? renterNotes;

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
    this.managementType = BuildingManagementType.selfManaged,
    this.renterName,
    this.renterPhone,
    this.rentAmount,
    this.rentDueDay,
    this.rentContractStart,
    this.rentContractEnd,
    this.renterNotes,
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
      'managementType': managementType.name,
      'renterName': renterName,
      'renterPhone': renterPhone,
      'rentAmount': rentAmount,
      'rentDueDay': rentDueDay,
      'rentContractStart': rentContractStart != null
          ? Timestamp.fromDate(rentContractStart!)
          : null,
      'rentContractEnd': rentContractEnd != null
          ? Timestamp.fromDate(rentContractEnd!)
          : null,
      'renterNotes': renterNotes,
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
      managementType: BuildingManagementType.values.firstWhere(
        (e) => e.name == map['managementType'],
        orElse: () => BuildingManagementType.selfManaged,
      ),
      renterName: map['renterName'] as String?,
      renterPhone: map['renterPhone'] as String?,
      rentAmount: (map['rentAmount'] as num?)?.toDouble(),
      rentDueDay: map['rentDueDay'] as int?,
      rentContractStart: map['rentContractStart'] != null
          ? (map['rentContractStart'] as Timestamp).toDate()
          : null,
      rentContractEnd: map['rentContractEnd'] != null
          ? (map['rentContractEnd'] as Timestamp).toDate()
          : null,
      renterNotes: map['renterNotes'] as String?,
    );
  }

  // Convenience getter
  bool get isRented => managementType == BuildingManagementType.rented;

  // copyWith - needed since we now mutate management/renter fields independently
  Building copyWith({
    String? id,
    String? organizationId,
    String? name,
    String? address,
    DateTime? createdAt,
    int? floors,
    String? roomPrefix,
    bool? uniformRooms,
    int? roomsPerFloor,
    List<int>? floorRoomCounts,
    List<Map<String, dynamic>>? floorDetails,
    String? roomType,
    double? roomArea,
    BuildingManagementType? managementType,
    String? renterName,
    String? renterPhone,
    double? rentAmount,
    int? rentDueDay,
    DateTime? rentContractStart,
    DateTime? rentContractEnd,
    String? renterNotes,
  }) {
    return Building(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      name: name ?? this.name,
      address: address ?? this.address,
      createdAt: createdAt ?? this.createdAt,
      floors: floors ?? this.floors,
      roomPrefix: roomPrefix ?? this.roomPrefix,
      uniformRooms: uniformRooms ?? this.uniformRooms,
      roomsPerFloor: roomsPerFloor ?? this.roomsPerFloor,
      floorRoomCounts: floorRoomCounts ?? this.floorRoomCounts,
      floorDetails: floorDetails ?? this.floorDetails,
      roomType: roomType ?? this.roomType,
      roomArea: roomArea ?? this.roomArea,
      managementType: managementType ?? this.managementType,
      renterName: renterName ?? this.renterName,
      renterPhone: renterPhone ?? this.renterPhone,
      rentAmount: rentAmount ?? this.rentAmount,
      rentDueDay: rentDueDay ?? this.rentDueDay,
      rentContractStart: rentContractStart ?? this.rentContractStart,
      rentContractEnd: rentContractEnd ?? this.rentContractEnd,
      renterNotes: renterNotes ?? this.renterNotes,
    );
  }
}