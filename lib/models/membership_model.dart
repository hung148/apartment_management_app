import 'package:cloud_firestore/cloud_firestore.dart';

class Membership {
  final String id;
  final String organizationId;
  final String ownerId;
  final String role; // "admin" or "member"
  final String inviteCode; // Unique per organization
  final String status; // "active" or "pending_removal"
  final DateTime joinedAt;

  Membership({
    required this.id,
    required this.organizationId,
    required this.ownerId,
    required this.role,
    required this.inviteCode,
    required this.status,
    required this.joinedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'organizationId': organizationId,
      'ownerId': ownerId,
      'role': role,
      'inviteCode': inviteCode,
      'status': status,
      'joinedAt': Timestamp.fromDate(joinedAt),
    };
  }

  factory Membership.fromMap(String id, Map<String, dynamic> map) {
    return Membership(
      id: id,
      organizationId: map['organizationId'] ?? '',
      ownerId: map['ownerId'] ?? '',
      role: map['role'] ?? 'member',
      inviteCode: map['inviteCode'] ?? '',
      status: map['status'] ?? 'active',
      joinedAt: (map['joinedAt'] as Timestamp).toDate(),
    );
  }
}