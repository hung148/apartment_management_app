import 'package:cloud_firestore/cloud_firestore.dart';

/// Employment identity survives account unlinking and access revocation.
class StaffProfile {
  final String id, organizationId, code, displayName, employmentStatus;
  final String? accountId, email, phone, color;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const StaffProfile({required this.id, required this.organizationId,
    required this.code, required this.displayName, required this.createdAt,
    this.employmentStatus = 'active', this.accountId, this.email, this.phone,
    this.color, this.updatedAt});

  Map<String, dynamic> toMap() => {
    'organizationId': organizationId, 'code': code, 'displayName': displayName,
    'employmentStatus': employmentStatus, 'accountId': accountId,
    'email': email, 'phone': phone, 'color': color,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
  };

  factory StaffProfile.fromMap(String id, Map<String, dynamic> map) => StaffProfile(
    id: id, organizationId: map['organizationId'] as String,
    code: map['code'] as String, displayName: map['displayName'] as String,
    employmentStatus: map['employmentStatus'] as String? ?? 'inactive',
    accountId: map['accountId'] as String?, email: map['email'] as String?,
    phone: map['phone'] as String?, color: map['color'] as String?,
    createdAt: (map['createdAt'] as Timestamp).toDate(),
    updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
  );
}
