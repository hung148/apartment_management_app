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
  final String buildingId;
  final String roomId;
  final String? tenantId;
  final String? tenantName;
  
  // Payment details
  final PaymentType type;
  final PaymentStatus status;
  final double amount;
  final double paidAmount;
  final String currency;
  
  // Payment method
  final PaymentMethod? paymentMethod;
  final String? transactionId;
  final String? receiptNumber;
  
  // Billing period (for recurring payments like rent)
  final DateTime? billingStartDate;   // Từ ngày (for rent, water)
  final DateTime? billingEndDate;     // Đến ngày (for rent, water)
  final DateTime dueDate;
  
  // Electricity meter readings (chỉ số điện)
  final double? electricityStartReading;  // NEW: Chỉ số đầu
  final DateTime? electricityStartDate;   // NEW: Từ ngày (chỉ số đầu)
  final double? electricityEndReading;    // NEW: Chỉ số cuối
  final DateTime? electricityEndDate;     // NEW: Đến ngày (chỉ số cuối)
  final double? electricityPricePerUnit;  // NEW: Giá điện/kWh
  
  // Water meter readings (chỉ số nước)
  final double? waterStartReading;        // NEW: Chỉ số đầu
  final DateTime? waterStartDate;         // NEW: Từ ngày (chỉ số đầu)
  final double? waterEndReading;          // NEW: Chỉ số cuối
  final DateTime? waterEndDate;           // NEW: Đến ngày (chỉ số cuối)
  final double? waterPricePerUnit;        // NEW: Giá nước/m³
  
  // Payment tracking
  final DateTime createdAt;
  final DateTime? paidAt;
  final String? paidBy;
  
  // Additional info
  final String? description;
  final String? notes;
  final Map<String, dynamic>? metadata;
  
  // Late fee tracking
  final double? lateFee;
  final bool isRecurring;
  final String? recurringParentId;

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
    // Electricity fields
    this.electricityStartReading,
    this.electricityStartDate,
    this.electricityEndReading,
    this.electricityEndDate,
    this.electricityPricePerUnit,
    // Water fields
    this.waterStartReading,
    this.waterStartDate,
    this.waterEndReading,
    this.waterEndDate,
    this.waterPricePerUnit,
    // Payment tracking
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
  
  // NEW: Calculate electricity usage (số điện tiêu thụ)
  double? get electricityUsage {
    if (electricityStartReading != null && electricityEndReading != null) {
      return electricityEndReading! - electricityStartReading!;
    }
    return null;
  }
  
  // NEW: Calculate water usage (số nước tiêu thụ)
  double? get waterUsage {
    if (waterStartReading != null && waterEndReading != null) {
      return waterEndReading! - waterStartReading!;
    }
    return null;
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
      // Electricity fields
      'electricityStartReading': electricityStartReading,
      'electricityStartDate': electricityStartDate != null
          ? Timestamp.fromDate(electricityStartDate!)
          : null,
      'electricityEndReading': electricityEndReading,
      'electricityEndDate': electricityEndDate != null
          ? Timestamp.fromDate(electricityEndDate!)
          : null,
      'electricityPricePerUnit': electricityPricePerUnit,
      // Water fields
      'waterStartReading': waterStartReading,
      'waterStartDate': waterStartDate != null
          ? Timestamp.fromDate(waterStartDate!)
          : null,
      'waterEndReading': waterEndReading,
      'waterEndDate': waterEndDate != null
          ? Timestamp.fromDate(waterEndDate!)
          : null,
      'waterPricePerUnit': waterPricePerUnit,
      // Payment tracking
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
      // Electricity fields
      electricityStartReading: (map['electricityStartReading'] as num?)?.toDouble(),
      electricityStartDate: map['electricityStartDate'] != null
          ? (map['electricityStartDate'] as Timestamp).toDate()
          : null,
      electricityEndReading: (map['electricityEndReading'] as num?)?.toDouble(),
      electricityEndDate: map['electricityEndDate'] != null
          ? (map['electricityEndDate'] as Timestamp).toDate()
          : null,
      electricityPricePerUnit: (map['electricityPricePerUnit'] as num?)?.toDouble(),
      // Water fields
      waterStartReading: (map['waterStartReading'] as num?)?.toDouble(),
      waterStartDate: map['waterStartDate'] != null
          ? (map['waterStartDate'] as Timestamp).toDate()
          : null,
      waterEndReading: (map['waterEndReading'] as num?)?.toDouble(),
      waterEndDate: map['waterEndDate'] != null
          ? (map['waterEndDate'] as Timestamp).toDate()
          : null,
      waterPricePerUnit: (map['waterPricePerUnit'] as num?)?.toDouble(),
      // Payment tracking
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
    double? electricityStartReading,
    DateTime? electricityStartDate,
    double? electricityEndReading,
    DateTime? electricityEndDate,
    double? electricityPricePerUnit,
    double? waterStartReading,
    DateTime? waterStartDate,
    double? waterEndReading,
    DateTime? waterEndDate,
    double? waterPricePerUnit,
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
      electricityStartReading: electricityStartReading ?? this.electricityStartReading,
      electricityStartDate: electricityStartDate ?? this.electricityStartDate,
      electricityEndReading: electricityEndReading ?? this.electricityEndReading,
      electricityEndDate: electricityEndDate ?? this.electricityEndDate,
      electricityPricePerUnit: electricityPricePerUnit ?? this.electricityPricePerUnit,
      waterStartReading: waterStartReading ?? this.waterStartReading,
      waterStartDate: waterStartDate ?? this.waterStartDate,
      waterEndReading: waterEndReading ?? this.waterEndReading,
      waterEndDate: waterEndDate ?? this.waterEndDate,
      waterPricePerUnit: waterPricePerUnit ?? this.waterPricePerUnit,
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