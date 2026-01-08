import 'package:cloud_firestore/cloud_firestore.dart';

class Owner {
  final String id; // Unique ID from Firestore
  final String email; // Owner's email
  final String name; // Owner's full name
  final DateTime createdAt; // When they joined
  // If owner was invited by someone, store their ID
  final String? invitedBy; // Optional

  Owner({
    required this.id,
    required this.email,
    required this.name,
    required this.createdAt,
    this.invitedBy,
  });

  // convert Owner to Map for saving to Firestore
  Map<String, dynamic> toMap() {
    // Create the base map with required fields
    Map<String, dynamic> map = {
      'email': email,
      'name': name,
      'createdAt': Timestamp.fromDate(createdAt), // Convert DateTime to Timestamp
    };

    // Add invitedBy only if it exists (not null)
    if (invitedBy != null) {
      map['invitedBy'] = invitedBy;
    }

    return map;
  }

  // Create Owner from map which is from Firestore data
  factory Owner.fromMap(String id, Map<String, dynamic> map) {
    return Owner(
      id: id,
      email: map['email'] ?? '', // use empty string if null
      name: map['name'] ?? '',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      invitedBy: map['invitedBy'], // Can be null
    );
  }

  // copyWith - create a copy with some fields changed useful for updating specific fields
  Owner copyWith({
    String? id,
    String? email,
    String? name,
    DateTime? createdAt,
    String? invitedBy,
  }) {
    return Owner(
      id: id ?? this.id, // Use new value if provided, otherwise keep current
      email: email ?? this.email,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      invitedBy: invitedBy ?? this.invitedBy,
    );
  }
}