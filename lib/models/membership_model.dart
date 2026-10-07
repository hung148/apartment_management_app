import 'package:cloud_firestore/cloud_firestore.dart';

class Membership {
  final String id;
  final String organizationId;
  final String ownerId;
  final String role; // "admin" or "member"
  final String status; // "active" or "pending_removal"
  final DateTime joinedAt;
  final String displayName; 
  final String email;       
  /// Version 2 only, read-only here (server-owned): the organization role's
  /// own name, and whether the membership carries a copy of that role's grants.
  final String? roleName;
  final bool hasRoleGrants;

  Membership({
    required this.id,
    required this.organizationId,
    required this.ownerId,
    required this.role,
    required this.status,
    required this.joinedAt,
    this.displayName = '', 
    this.email = '',       
    this.roleName,
    this.hasRoleGrants = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'organizationId': organizationId,
      'ownerId': ownerId,
      'role': role,
      'status': status,
      'joinedAt': Timestamp.fromDate(joinedAt),
      'displayName': displayName, 
      'email': email,             
    };
  }

  factory Membership.fromMap(String id, Map<String, dynamic> map) {
    return Membership(
      id: id,
      organizationId: map['organizationId'] ?? '',
      ownerId: map['ownerId'] ?? '',
      role: map['role'] ?? 'member',
      status: map['status'] ?? 'active',
      joinedAt: (map['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      displayName: map['displayName'] ?? '', 
      email: map['email'] ?? '',             
      roleName: map['roleName'] is String ? map['roleName'] as String : null,
      hasRoleGrants: map['roleGrants'] is Map,
    );
  }
}
