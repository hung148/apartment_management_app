import 'package:cloud_firestore/cloud_firestore.dart';

enum TenantStatus {
  active,       // Đang thuê
  inactive,     // Không hoạt động
  moveOut,      // Đã chuyển đi
  suspended,    // Tạm dừng
}

enum Gender {
  male,         // Nam
  female,       // Nữ
  other,        // Khác
}

enum ContractStatus {
  active,       // Đang hiệu lực
  terminated,   // Đã chấm dứt
  expired,      // Đã hết hạn
}

class Tenant {
  final String id;
  final String organizationId;
  final String buildingId;
  final String roomId;
  
  // Personal Information
  final String fullName;
  final String? nickname;
  final Gender? gender;
  final DateTime? dateOfBirth;
  final String? nationalId;              // CMND/CCCD
  final DateTime? nationalIdIssueDate;
  final String? nationalIdIssuePlace;
  
  // Contact Information
  final String phoneNumber;
  final String? email;
  final String? emergencyContact;        // Số điện thoại liên hệ khẩn cấp
  final String? emergencyContactName;
  final String? emergencyContactRelation;
  
  // Address
  final String? permanentAddress;        // Địa chỉ thường trú
  final String? currentAddress;          // Địa chỉ tạm trú (before moving in)
  
  // Rental Information
  final TenantStatus status;
  final DateTime moveInDate;
  final DateTime? moveOutDate;
  final DateTime? contractStartDate;
  final DateTime? contractEndDate;
  final double? monthlyRent;
  final double? deposit;                 // Tiền cọc
  final bool isMainTenant;               // Người thuê chính hay người ở cùng
  final String? mainTenantId;            // Nếu không phải người thuê chính
  
  // Contract Status (NEW)
  final ContractStatus? contractStatus;
  final DateTime? contractTerminationDate;
  final String? contractTerminationReason;
  
  // NEW: Room/Apartment Details (for PDF generation)
  final String? apartmentType;           // NEW: Loại căn hộ (1PN, 2PN, 3PN, Studio, etc.)
  final double? apartmentArea;           // NEW: Diện tích căn hộ (m²)
  
  // Last Known Location (for moved-out tenants)
  final String? lastBuildingName;        // Tên toà nhà trước khi chuyển đi
  final String? lastRoomNumber;          // Số phòng trước khi chuyển đi
  
  // Documents & Files
  final List<String>? documentUrls;      // URLs of uploaded documents (ID card, contract, etc.)
  final String? contractUrl;             // Contract file URL
  final String? profileImageUrl;         // Profile photo
  
  // Vehicle Information
  final List<VehicleInfo>? vehicles;
  
  // Additional Information
  final String? occupation;              // Nghề nghiệp
  final String? workplace;               // Nơi làm việc
  final List<PreviousRentalHistory>? previousRentals;  // Lịch sử thuê trước đây
  final String? notes;                   // Ghi chú
  final Map<String, dynamic>? metadata;  // Extra data
  
  // System fields
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? createdBy;               // User ID who created
  final String? updatedBy;               // User ID who last updated

  Tenant({
    required this.id,
    required this.organizationId,
    required this.buildingId,
    required this.roomId,
    required this.fullName,
    this.nickname,
    this.gender,
    this.dateOfBirth,
    this.nationalId,
    this.nationalIdIssueDate,
    this.nationalIdIssuePlace,
    required this.phoneNumber,
    this.email,
    this.emergencyContact,
    this.emergencyContactName,
    this.emergencyContactRelation,
    this.permanentAddress,
    this.currentAddress,
    required this.status,
    required this.moveInDate,
    this.moveOutDate,
    this.contractStartDate,
    this.contractEndDate,
    this.monthlyRent,
    this.deposit,
    this.isMainTenant = true,
    this.mainTenantId,
    this.contractStatus,              // NEW
    this.contractTerminationDate,     // NEW
    this.contractTerminationReason,   // NEW
    this.apartmentType,
    this.apartmentArea,
    this.lastBuildingName,
    this.lastRoomNumber,
    this.documentUrls,
    this.contractUrl,
    this.profileImageUrl,
    this.vehicles,
    this.occupation,
    this.workplace,
    this.previousRentals,
    this.notes,
    this.metadata,
    required this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  // Helper getters
  bool get isActive => status == TenantStatus.active;
  bool get hasMovedOut => status == TenantStatus.moveOut;
  
  int get daysLiving {
    final endDate = moveOutDate ?? DateTime.now();
    return endDate.difference(moveInDate).inDays;
  }
  
  int? get daysUntilContractEnd {
    if (contractEndDate == null) return null;
    final now = DateTime.now();
    if (contractEndDate!.isBefore(now)) return 0;
    return contractEndDate!.difference(now).inDays;
  }
  
  bool get isContractExpiring {
    final days = daysUntilContractEnd;
    return days != null && days > 0 && days <= 30; // Expiring in 30 days
  }
  
  bool get isContractExpired {
    if (contractEndDate == null) return false;
    return DateTime.now().isAfter(contractEndDate!);
  }
  
  bool get isContractActive => contractStatus == ContractStatus.active || contractStatus == null;
  bool get isContractTerminated => contractStatus == ContractStatus.terminated;
  
  int? get age {
    if (dateOfBirth == null) return null;
    final now = DateTime.now();
    int age = now.year - dateOfBirth!.year;
    if (now.month < dateOfBirth!.month || 
        (now.month == dateOfBirth!.month && now.day < dateOfBirth!.day)) {
      age--;
    }
    return age;
  }
  
  // Get total time lived across all rentals
  int get totalDaysLiving {
    int total = daysLiving;
    if (previousRentals != null) {
      for (var rental in previousRentals!) {
        total += rental.duration;
      }
    }
    return total;
  }

  Map<String, dynamic> toMap() {
    return {
      'organizationId': organizationId,
      'buildingId': buildingId,
      'roomId': roomId,
      'fullName': fullName,
      'nickname': nickname,
      'gender': gender?.name,
      'dateOfBirth': dateOfBirth != null 
          ? Timestamp.fromDate(dateOfBirth!) 
          : null,
      'nationalId': nationalId,
      'nationalIdIssueDate': nationalIdIssueDate != null
          ? Timestamp.fromDate(nationalIdIssueDate!)
          : null,
      'nationalIdIssuePlace': nationalIdIssuePlace,
      'phoneNumber': phoneNumber,
      'email': email,
      'emergencyContact': emergencyContact,
      'emergencyContactName': emergencyContactName,
      'emergencyContactRelation': emergencyContactRelation,
      'permanentAddress': permanentAddress,
      'currentAddress': currentAddress,
      'status': status.name,
      'moveInDate': Timestamp.fromDate(moveInDate),
      'moveOutDate': moveOutDate != null 
          ? Timestamp.fromDate(moveOutDate!) 
          : null,
      'contractStartDate': contractStartDate != null
          ? Timestamp.fromDate(contractStartDate!)
          : null,
      'contractEndDate': contractEndDate != null
          ? Timestamp.fromDate(contractEndDate!)
          : null,
      'monthlyRent': monthlyRent,
      'deposit': deposit,
      'isMainTenant': isMainTenant,
      'mainTenantId': mainTenantId,
      'contractStatus': contractStatus?.name,                          // NEW
      'contractTerminationDate': contractTerminationDate != null       // NEW
          ? Timestamp.fromDate(contractTerminationDate!)
          : null,
      'contractTerminationReason': contractTerminationReason,          // NEW
      'apartmentType': apartmentType,
      'apartmentArea': apartmentArea,
      'lastBuildingName': lastBuildingName,
      'lastRoomNumber': lastRoomNumber,
      'documentUrls': documentUrls,
      'contractUrl': contractUrl,
      'profileImageUrl': profileImageUrl,
      'vehicles': vehicles?.map((v) => v.toMap()).toList(),
      'occupation': occupation,
      'workplace': workplace,
      'previousRentals': previousRentals?.map((r) => r.toMap()).toList(),
      'notes': notes,
      'metadata': metadata,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null 
          ? Timestamp.fromDate(updatedAt!) 
          : null,
      'createdBy': createdBy,
      'updatedBy': updatedBy,
    };
  }

  factory Tenant.fromMap(String id, Map<String, dynamic> map) {
    return Tenant(
      id: id,
      organizationId: map['organizationId'] ?? '',
      buildingId: map['buildingId'] ?? '',
      roomId: map['roomId'] ?? '',
      fullName: map['fullName'] ?? '',
      nickname: map['nickname'],
      gender: map['gender'] != null
          ? Gender.values.firstWhere(
              (e) => e.name == map['gender'],
              orElse: () => Gender.other,
            )
          : null,
      dateOfBirth: map['dateOfBirth'] != null
          ? (map['dateOfBirth'] as Timestamp).toDate()
          : null,
      nationalId: map['nationalId'],
      nationalIdIssueDate: map['nationalIdIssueDate'] != null
          ? (map['nationalIdIssueDate'] as Timestamp).toDate()
          : null,
      nationalIdIssuePlace: map['nationalIdIssuePlace'],
      phoneNumber: map['phoneNumber'] ?? '',
      email: map['email'],
      emergencyContact: map['emergencyContact'],
      emergencyContactName: map['emergencyContactName'],
      emergencyContactRelation: map['emergencyContactRelation'],
      permanentAddress: map['permanentAddress'],
      currentAddress: map['currentAddress'],
      status: TenantStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => TenantStatus.active,
      ),
      moveInDate: (map['moveInDate'] as Timestamp).toDate(),
      moveOutDate: map['moveOutDate'] != null
          ? (map['moveOutDate'] as Timestamp).toDate()
          : null,
      contractStartDate: map['contractStartDate'] != null
          ? (map['contractStartDate'] as Timestamp).toDate()
          : null,
      contractEndDate: map['contractEndDate'] != null
          ? (map['contractEndDate'] as Timestamp).toDate()
          : null,
      monthlyRent: (map['monthlyRent'] as num?)?.toDouble(),
      deposit: (map['deposit'] as num?)?.toDouble(),
      isMainTenant: map['isMainTenant'] ?? true,
      mainTenantId: map['mainTenantId'],
      contractStatus: map['contractStatus'] != null                    // NEW
          ? ContractStatus.values.firstWhere(
              (e) => e.name == map['contractStatus'],
              orElse: () => ContractStatus.active,
            )
          : null,
      contractTerminationDate: map['contractTerminationDate'] != null  // NEW
          ? (map['contractTerminationDate'] as Timestamp).toDate()
          : null,
      contractTerminationReason: map['contractTerminationReason'],     // NEW
      apartmentType: map['apartmentType'],
      apartmentArea: (map['apartmentArea'] as num?)?.toDouble(),
      lastBuildingName: map['lastBuildingName'],
      lastRoomNumber: map['lastRoomNumber'],
      documentUrls: map['documentUrls'] != null
          ? List<String>.from(map['documentUrls'])
          : null,
      contractUrl: map['contractUrl'],
      profileImageUrl: map['profileImageUrl'],
      vehicles: map['vehicles'] != null
          ? (map['vehicles'] as List)
              .map((v) => VehicleInfo.fromMap(v))
              .toList()
          : null,
      occupation: map['occupation'],
      workplace: map['workplace'],
      previousRentals: map['previousRentals'] != null
          ? (map['previousRentals'] as List)
              .map((r) => PreviousRentalHistory.fromMap(r))
              .toList()
          : null,
      notes: map['notes'],
      metadata: map['metadata'],
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      updatedAt: map['updatedAt'] != null
          ? (map['updatedAt'] as Timestamp).toDate()
          : null,
      createdBy: map['createdBy'],
      updatedBy: map['updatedBy'],
    );
  }

  // CopyWith method
  Tenant copyWith({
    String? id,
    String? organizationId,
    String? buildingId,
    String? roomId,
    String? fullName,
    String? nickname,
    Gender? gender,
    DateTime? dateOfBirth,
    String? nationalId,
    DateTime? nationalIdIssueDate,
    String? nationalIdIssuePlace,
    String? phoneNumber,
    String? email,
    String? emergencyContact,
    String? emergencyContactName,
    String? emergencyContactRelation,
    String? permanentAddress,
    String? currentAddress,
    TenantStatus? status,
    DateTime? moveInDate,
    DateTime? moveOutDate,
    DateTime? contractStartDate,
    DateTime? contractEndDate,
    double? monthlyRent,
    double? deposit,
    bool? isMainTenant,
    String? mainTenantId,
    ContractStatus? contractStatus,
    DateTime? contractTerminationDate,
    String? contractTerminationReason,
    String? apartmentType,
    double? apartmentArea,
    String? lastBuildingName,
    String? lastRoomNumber,
    List<String>? documentUrls,
    String? contractUrl,
    String? profileImageUrl,
    List<VehicleInfo>? vehicles,
    String? occupation,
    String? workplace,
    List<PreviousRentalHistory>? previousRentals,
    String? notes,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
    String? updatedBy,
  }) {
    return Tenant(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      buildingId: buildingId ?? this.buildingId,
      roomId: roomId ?? this.roomId,
      fullName: fullName ?? this.fullName,
      nickname: nickname ?? this.nickname,
      gender: gender ?? this.gender,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      nationalId: nationalId ?? this.nationalId,
      nationalIdIssueDate: nationalIdIssueDate ?? this.nationalIdIssueDate,
      nationalIdIssuePlace: nationalIdIssuePlace ?? this.nationalIdIssuePlace,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      emergencyContactName: emergencyContactName ?? this.emergencyContactName,
      emergencyContactRelation: emergencyContactRelation ?? this.emergencyContactRelation,
      permanentAddress: permanentAddress ?? this.permanentAddress,
      currentAddress: currentAddress ?? this.currentAddress,
      status: status ?? this.status,
      moveInDate: moveInDate ?? this.moveInDate,
      moveOutDate: moveOutDate ?? this.moveOutDate,
      contractStartDate: contractStartDate ?? this.contractStartDate,
      contractEndDate: contractEndDate ?? this.contractEndDate,
      monthlyRent: monthlyRent ?? this.monthlyRent,
      deposit: deposit ?? this.deposit,
      isMainTenant: isMainTenant ?? this.isMainTenant,
      mainTenantId: mainTenantId ?? this.mainTenantId,
      contractStatus: contractStatus ?? this.contractStatus,
      contractTerminationDate: contractTerminationDate ?? this.contractTerminationDate,
      contractTerminationReason: contractTerminationReason ?? this.contractTerminationReason,
      apartmentType: apartmentType ?? this.apartmentType,
      apartmentArea: apartmentArea ?? this.apartmentArea,
      lastBuildingName: lastBuildingName ?? this.lastBuildingName,
      lastRoomNumber: lastRoomNumber ?? this.lastRoomNumber,
      documentUrls: documentUrls ?? this.documentUrls,
      contractUrl: contractUrl ?? this.contractUrl,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      vehicles: vehicles ?? this.vehicles,
      occupation: occupation ?? this.occupation,
      workplace: workplace ?? this.workplace,
      previousRentals: previousRentals ?? this.previousRentals,
      notes: notes ?? this.notes,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
    );
  }

  // Helper methods for display names
  String getStatusDisplayName() {
    switch (status) {
      case TenantStatus.active:
        return 'Đang thuê';
      case TenantStatus.inactive:
        return 'Không hoạt động';
      case TenantStatus.moveOut:
        return 'Đã chuyển đi';
      case TenantStatus.suspended:
        return 'Tạm dừng';
    }
  }

  String? getGenderDisplayName() {
    if (gender == null) return null;
    switch (gender!) {
      case Gender.male:
        return 'Nam';
      case Gender.female:
        return 'Nữ';
      case Gender.other:
        return 'Khác';
    }
  }

  String getContractStatusDisplayName() {
    if (contractStatus == null) return 'Không xác định';
    switch (contractStatus!) {
      case ContractStatus.active:
        return 'Đang hiệu lực';
      case ContractStatus.terminated:
        return 'Đã chấm dứt';
      case ContractStatus.expired:
        return 'Đã hết hạn';
    }
  }
}

// ============================================
// PREVIOUS RENTAL HISTORY MODEL
// ============================================
class PreviousRentalHistory {
  final String buildingName;           // Tên toà nhà
  final String? buildingAddress;       // Địa chỉ toà nhà
  final String roomNumber;             // Số phòng
  final DateTime moveInDate;           // Ngày chuyển vào
  final DateTime moveOutDate;          // Ngày chuyển đi
  final double? monthlyRent;           // Tiền thuê hàng tháng
  final String? moveOutReason;         // Lý do chuyển đi
  final String? landlordName;          // Tên chủ nhà
  final String? landlordPhone;         // Số điện thoại chủ nhà
  final String? notes;                 // Ghi chú

  PreviousRentalHistory({
    required this.buildingName,
    this.buildingAddress,
    required this.roomNumber,
    required this.moveInDate,
    required this.moveOutDate,
    this.monthlyRent,
    this.moveOutReason,
    this.landlordName,
    this.landlordPhone,
    this.notes,
  });

  int get duration {
    return moveOutDate.difference(moveInDate).inDays;
  }

  Map<String, dynamic> toMap() {
    return {
      'buildingName': buildingName,
      'buildingAddress': buildingAddress,
      'roomNumber': roomNumber,
      'moveInDate': Timestamp.fromDate(moveInDate),
      'moveOutDate': Timestamp.fromDate(moveOutDate),
      'monthlyRent': monthlyRent,
      'moveOutReason': moveOutReason,
      'landlordName': landlordName,
      'landlordPhone': landlordPhone,
      'notes': notes,
    };
  }

  factory PreviousRentalHistory.fromMap(Map<String, dynamic> map) {
    return PreviousRentalHistory(
      buildingName: map['buildingName'] ?? '',
      buildingAddress: map['buildingAddress'],
      roomNumber: map['roomNumber'] ?? '',
      moveInDate: (map['moveInDate'] as Timestamp).toDate(),
      moveOutDate: (map['moveOutDate'] as Timestamp).toDate(),
      monthlyRent: (map['monthlyRent'] as num?)?.toDouble(),
      moveOutReason: map['moveOutReason'],
      landlordName: map['landlordName'],
      landlordPhone: map['landlordPhone'],
      notes: map['notes'],
    );
  }
}

// ============================================
// VEHICLE INFO MODEL
// ============================================
enum VehicleType {
  motorcycle,   // Xe máy
  car,          // Ô tô
  bicycle,      // Xe đạp
  electricBike, // Xe đạp điện
  other,        // Khác
}

class VehicleInfo {
  final VehicleType type;
  final String licensePlate;      // Biển số xe
  final String? brand;            // Hãng xe
  final String? model;            // Model
  final String? color;            // Màu xe
  final bool isParkingRegistered; // Đã đăng ký gửi xe chưa
  final String? parkingSpot;      // Vị trí gửi xe

  VehicleInfo({
    required this.type,
    required this.licensePlate,
    this.brand,
    this.model,
    this.color,
    this.isParkingRegistered = false,
    this.parkingSpot,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'licensePlate': licensePlate,
      'brand': brand,
      'model': model,
      'color': color,
      'isParkingRegistered': isParkingRegistered,
      'parkingSpot': parkingSpot,
    };
  }

  factory VehicleInfo.fromMap(Map<String, dynamic> map) {
    return VehicleInfo(
      type: VehicleType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => VehicleType.other,
      ),
      licensePlate: map['licensePlate'] ?? '',
      brand: map['brand'],
      model: map['model'],
      color: map['color'],
      isParkingRegistered: map['isParkingRegistered'] ?? false,
      parkingSpot: map['parkingSpot'],
    );
  }

  String getTypeDisplayName() {
    switch (type) {
      case VehicleType.motorcycle:
        return 'Xe máy';
      case VehicleType.car:
        return 'Ô tô';
      case VehicleType.bicycle:
        return 'Xe đạp';
      case VehicleType.electricBike:
        return 'Xe đạp điện';
      case VehicleType.other:
        return 'Khác';
    }
  }
}