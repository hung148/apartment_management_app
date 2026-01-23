import 'package:cloud_firestore/cloud_firestore.dart';

class Organization {
  final String id;
  final String name;
  final String? address;  // NEW: Optional address field
  final String? phone;    // NEW: Optional phone field
  final String? email;    // NEW: Optional email field
  final String createdBy; // Owner ID who created it
  final DateTime createdAt;

  Organization({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    this.email,
    required this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address,
      'phone': phone,
      'email': email,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory Organization.fromMap(String id, Map<String, dynamic> map) {
    return Organization(
      id: id,
      name: map['name'] ?? '',
      address: map['address'],
      phone: map['phone'],
      email: map['email'],
      createdBy: map['createdBy'] ?? '',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
    );
  }
}