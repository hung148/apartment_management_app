import 'package:cloud_firestore/cloud_firestore.dart';

enum PaymentType {
  rent,           // Tiền thuê
  electricity,    // Tiền điện
  water,          // Tiền nước
  internet,       // Tiền internet
  parking,        // Tiền gửi xe
  maintenance,    // Phí bảo trì
  deposit,        // Tiền cọc
  penalty,        // Tiền phạt
  other,          // Khác
}

enum PaymentStatus {
  pending,        // Chờ thanh toán
  paid,           // Đã thanh toán
  overdue,        // Quá hạn
  cancelled,      // Đã hủy
  refunded,       // Đã hoàn tiền
  partial,        // Thanh toán một phần
}

enum PaymentMethod {
  cash,           // Tiền mặt
  bankTransfer,   // Chuyển khoản
  momo,           // Ví MoMo
  zalopay,        // Ví ZaloPay
  creditCard,     // Thẻ tín dụng
  other,          // Khác
}

class Payment {
  final String id;
  final String organizationId;
  final String buildingId;           // NEW: Track which building
  final String roomId;
  final String? tenantId;             // NEW: Who made the payment
  final String? tenantName;           // NEW: Tenant name for easy display
  
  // Payment details
  final PaymentType type;             // NEW: Type of payment
  final PaymentStatus status;         // NEW: Payment status
  final double amount;                // Total amount to pay
  final double paidAmount;            // NEW: Amount actually paid (for partial payments)
  final String currency;              // NEW: Currency (VND, USD, etc.)
  
  // Payment method
  final PaymentMethod? paymentMethod; // NEW: How was it paid
  final String? transactionId;        // NEW: Bank transaction ID or reference
  final String? receiptNumber;        // NEW: Receipt number
  
  // Billing period (for recurring payments like rent)
  final DateTime? billingStartDate;   // NEW: Start of billing period
  final DateTime? billingEndDate;     // NEW: End of billing period
  final DateTime dueDate;             // NEW: When payment is due
  
  // Payment tracking
  final DateTime createdAt;           // When payment record was created
  final DateTime? paidAt;             // NEW: When payment was actually made
  final String? paidBy;               // NEW: User ID who recorded the payment
  
  // Additional info
  final String? description;          // NEW: Additional notes
  final String? notes;                // NEW: Admin notes
  final Map<String, dynamic>? metadata; // NEW: Extra data (meter readings, etc.)
  
  // Late fee tracking
  final double? lateFee;              // NEW: Late payment fee
  final bool isRecurring;             // NEW: Is this a recurring payment
  final String? recurringParentId;    // NEW: Link to parent recurring payment

  Payment({
    required this.id,
    required this.organizationId,
    required this.buildingId,
    required this.roomId,
    this.tenantId,
    this.tenantName,
    required this.type,
    required this.status,
    required this.amount,
    this.paidAmount = 0.0,
    this.currency = 'VND',
    this.paymentMethod,
    this.transactionId,
    this.receiptNumber,
    this.billingStartDate,
    this.billingEndDate,
    required this.dueDate,
    required this.createdAt,
    this.paidAt,
    this.paidBy,
    this.description,
    this.notes,
    this.metadata,
    this.lateFee,
    this.isRecurring = false,
    this.recurringParentId,
  });

  // Helper getters
  bool get isPaid => status == PaymentStatus.paid;
  bool get isPending => status == PaymentStatus.pending;
  bool get isOverdue => status == PaymentStatus.overdue || 
                        (status == PaymentStatus.pending && DateTime.now().isAfter(dueDate));
  bool get isPartiallyPaid => status == PaymentStatus.partial;
  
  double get remainingAmount => amount - paidAmount + (lateFee ?? 0);
  double get totalAmount => amount + (lateFee ?? 0);
  
  int get daysOverdue {
    if (!isOverdue) return 0;
    return DateTime.now().difference(dueDate).inDays;
  }

  Map<String, dynamic> toMap() {
    return {
      'organizationId': organizationId,
      'buildingId': buildingId,
      'roomId': roomId,
      'tenantId': tenantId,
      'tenantName': tenantName,
      'type': type.name,
      'status': status.name,
      'amount': amount,
      'paidAmount': paidAmount,
      'currency': currency,
      'paymentMethod': paymentMethod?.name,
      'transactionId': transactionId,
      'receiptNumber': receiptNumber,
      'billingStartDate': billingStartDate != null 
          ? Timestamp.fromDate(billingStartDate!) 
          : null,
      'billingEndDate': billingEndDate != null 
          ? Timestamp.fromDate(billingEndDate!) 
          : null,
      'dueDate': Timestamp.fromDate(dueDate),
      'createdAt': Timestamp.fromDate(createdAt),
      'paidAt': paidAt != null ? Timestamp.fromDate(paidAt!) : null,
      'paidBy': paidBy,
      'description': description,
      'notes': notes,
      'metadata': metadata,
      'lateFee': lateFee,
      'isRecurring': isRecurring,
      'recurringParentId': recurringParentId,
    };
  }

  factory Payment.fromMap(String id, Map<String, dynamic> map) {
    return Payment(
      id: id,
      organizationId: map['organizationId'] ?? '',
      buildingId: map['buildingId'] ?? '',
      roomId: map['roomId'] ?? '',
      tenantId: map['tenantId'],
      tenantName: map['tenantName'],
      type: PaymentType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => PaymentType.other,
      ),
      status: PaymentStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => PaymentStatus.pending,
      ),
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      paidAmount: (map['paidAmount'] as num?)?.toDouble() ?? 0.0,
      currency: map['currency'] ?? 'VND',
      paymentMethod: map['paymentMethod'] != null
          ? PaymentMethod.values.firstWhere(
              (e) => e.name == map['paymentMethod'],
              orElse: () => PaymentMethod.other,
            )
          : null,
      transactionId: map['transactionId'],
      receiptNumber: map['receiptNumber'],
      billingStartDate: map['billingStartDate'] != null
          ? (map['billingStartDate'] as Timestamp).toDate()
          : null,
      billingEndDate: map['billingEndDate'] != null
          ? (map['billingEndDate'] as Timestamp).toDate()
          : null,
      dueDate: (map['dueDate'] as Timestamp).toDate(),
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      paidAt: map['paidAt'] != null 
          ? (map['paidAt'] as Timestamp).toDate() 
          : null,
      paidBy: map['paidBy'],
      description: map['description'],
      notes: map['notes'],
      metadata: map['metadata'],
      lateFee: (map['lateFee'] as num?)?.toDouble(),
      isRecurring: map['isRecurring'] ?? false,
      recurringParentId: map['recurringParentId'],
    );
  }

  // Copy with method for easy updates
  Payment copyWith({
    String? id,
    String? organizationId,
    String? buildingId,
    String? roomId,
    String? tenantId,
    String? tenantName,
    PaymentType? type,
    PaymentStatus? status,
    double? amount,
    double? paidAmount,
    String? currency,
    PaymentMethod? paymentMethod,
    String? transactionId,
    String? receiptNumber,
    DateTime? billingStartDate,
    DateTime? billingEndDate,
    DateTime? dueDate,
    DateTime? createdAt,
    DateTime? paidAt,
    String? paidBy,
    String? description,
    String? notes,
    Map<String, dynamic>? metadata,
    double? lateFee,
    bool? isRecurring,
    String? recurringParentId,
  }) {
    return Payment(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      buildingId: buildingId ?? this.buildingId,
      roomId: roomId ?? this.roomId,
      tenantId: tenantId ?? this.tenantId,
      tenantName: tenantName ?? this.tenantName,
      type: type ?? this.type,
      status: status ?? this.status,
      amount: amount ?? this.amount,
      paidAmount: paidAmount ?? this.paidAmount,
      currency: currency ?? this.currency,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      transactionId: transactionId ?? this.transactionId,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      billingStartDate: billingStartDate ?? this.billingStartDate,
      billingEndDate: billingEndDate ?? this.billingEndDate,
      dueDate: dueDate ?? this.dueDate,
      createdAt: createdAt ?? this.createdAt,
      paidAt: paidAt ?? this.paidAt,
      paidBy: paidBy ?? this.paidBy,
      description: description ?? this.description,
      notes: notes ?? this.notes,
      metadata: metadata ?? this.metadata,
      lateFee: lateFee ?? this.lateFee,
      isRecurring: isRecurring ?? this.isRecurring,
      recurringParentId: recurringParentId ?? this.recurringParentId,
    );
  }

  // Helper method to get payment type display name in Vietnamese
  String getTypeDisplayName() {
    switch (type) {
      case PaymentType.rent:
        return 'Tiền thuê';
      case PaymentType.electricity:
        return 'Tiền điện';
      case PaymentType.water:
        return 'Tiền nước';
      case PaymentType.internet:
        return 'Tiền internet';
      case PaymentType.parking:
        return 'Tiền gửi xe';
      case PaymentType.maintenance:
        return 'Phí bảo trì';
      case PaymentType.deposit:
        return 'Tiền cọc';
      case PaymentType.penalty:
        return 'Tiền phạt';
      case PaymentType.other:
        return 'Khác';
    }
  }

  // Helper method to get status display name in Vietnamese
  String getStatusDisplayName() {
    switch (status) {
      case PaymentStatus.pending:
        return 'Chờ thanh toán';
      case PaymentStatus.paid:
        return 'Đã thanh toán';
      case PaymentStatus.overdue:
        return 'Quá hạn';
      case PaymentStatus.cancelled:
        return 'Đã hủy';
      case PaymentStatus.refunded:
        return 'Đã hoàn tiền';
      case PaymentStatus.partial:
        return 'Thanh toán một phần';
    }
  }

  // Helper method to get payment method display name in Vietnamese
  String? getPaymentMethodDisplayName() {
    if (paymentMethod == null) return null;
    
    switch (paymentMethod!) {
      case PaymentMethod.cash:
        return 'Tiền mặt';
      case PaymentMethod.bankTransfer:
        return 'Chuyển khoản';
      case PaymentMethod.momo:
        return 'Ví MoMo';
      case PaymentMethod.zalopay:
        return 'Ví ZaloPay';
      case PaymentMethod.creditCard:
        return 'Thẻ tín dụng';
      case PaymentMethod.other:
        return 'Khác';
    }
  }
}