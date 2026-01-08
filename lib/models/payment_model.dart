import 'package:cloud_firestore/cloud_firestore.dart';

class Payment {
  final String id;
  final String organizationId;
  final String roomId;
  final double amount;
  final DateTime createdAt;

  Payment({
    required this.id,
    required this.organizationId,
    required this.roomId,
    required this.amount,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'organizationId': organizationId,
      'roomId': roomId,
      'amount': amount,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory Payment.fromMap(String id, Map<String, dynamic> map) {
    return Payment(
      id: id,
      organizationId: map['organizationId'] ?? '',
      roomId: map['roomId'] ?? '',
      amount: (map['amount'] as num).toDouble(),
      createdAt: (map['createdAt'] as Timestamp).toDate(),
    );
  }
}