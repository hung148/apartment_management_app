import 'package:cloud_firestore/cloud_firestore.dart';

class Organization {
  final String id;
  final String name;
  final String? address;           // Optional address field
  final String? phone;             // Optional phone field
  final String? email;             // Optional email field
  final String? bankName;          // NEW: Bank name (e.g., "Vietcombank, North Danang Branch")
  final String? bankAccountNumber; // NEW: Bank account number (e.g., "1057631599")
  final String? bankAccountName;   // NEW: Bank account holder name (e.g., "CÔNG TY CỔ PHẦN PPC AN THỊNH ĐÀ NẴNG")
  final String? taxCode;           // NEW: Tax code for organization
  final String createdBy;          // Owner ID who created it
  final DateTime createdAt;
  final DateTime? updatedAt;       // NEW: Track last update

  Organization({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    this.email,
    this.bankName,
    this.bankAccountNumber,
    this.bankAccountName,
    this.taxCode,
    required this.createdBy,
    required this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address,
      'phone': phone,
      'email': email,
      'bankName': bankName,
      'bankAccountNumber': bankAccountNumber,
      'bankAccountName': bankAccountName,
      'taxCode': taxCode,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  factory Organization.fromMap(String id, Map<String, dynamic> map) {
    return Organization(
      id: id,
      name: map['name'] ?? '',
      address: map['address'],
      phone: map['phone'],
      email: map['email'],
      bankName: map['bankName'],
      bankAccountNumber: map['bankAccountNumber'],
      bankAccountName: map['bankAccountName'],
      taxCode: map['taxCode'],
      createdBy: map['createdBy'] ?? '',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      updatedAt: map['updatedAt'] != null 
          ? (map['updatedAt'] as Timestamp).toDate() 
          : null,
    );
  }

  // CopyWith method for easy updates
  Organization copyWith({
    String? id,
    String? name,
    String? address,
    String? phone,
    String? email,
    String? bankName,
    String? bankAccountNumber,
    String? bankAccountName,
    String? taxCode,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Organization(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      bankName: bankName ?? this.bankName,
      bankAccountNumber: bankAccountNumber ?? this.bankAccountNumber,
      bankAccountName: bankAccountName ?? this.bankAccountName,
      taxCode: taxCode ?? this.taxCode,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Helper method to check if bank info is complete
  bool get hasBankInfo {
    return bankName != null && 
           bankAccountNumber != null && 
           bankAccountName != null;
  }

  // Format bank info for display
  String get formattedBankInfo {
    if (!hasBankInfo) return 'Chưa có thông tin ngân hàng';
    return '''
      Account Name: $bankAccountName
      Account Number: $bankAccountNumber
      Bank: $bankName
      ''';
  }
}