import 'package:cloud_firestore/cloud_firestore.dart';

class Building {
  final String id;
  final String organizationId;
  final String name;
  final String address;
  final DateTime createdAt;

  Building({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.address,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'organizationId': organizationId,
      'name': name,
      'address': address,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory Building.fromMap(String id, Map<String, dynamic> map) {
    return Building(
      id: id,
      organizationId: map['organizationId'] ?? '',
      name: map['name'] ?? '',
      address: map['address'] ?? '',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
    );
  }
}