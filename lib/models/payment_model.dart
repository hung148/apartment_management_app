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
  buildingRent,
  hourlyRent,
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

// How a Rent line's amount was produced. `direct` = staff typed the total
// themselves (existing behavior). The other three multiply a unit price by
// a quantity of days/months/years — normally derived from billingStartDate/
// billingEndDate, but rentUnitQuantity can override that.
enum RentPriceMode {
  direct,   // Nhập trực tiếp
  daily,    // Theo ngày
  monthly,  // Theo tháng
  yearly,   // Theo năm
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

  // Rent unit-price calculation (theo ngày / theo tháng / theo năm) —
  // only meaningful when type == PaymentType.rent and rentPriceMode != direct.
  final RentPriceMode? rentPriceMode;
  final double? rentUnitPrice;      // Đơn giá / ngày, / tháng, hoặc / năm
  final double? rentUnitQuantity;   // Số ngày/tháng/năm dùng để nhân (có thể override thủ công)

  // Electricity meter readings (chỉ số điện)
  final double? electricityStartReading;  // Chỉ số đầu
  final DateTime? electricityStartDate;   // Từ ngày (chỉ số đầu)
  final double? electricityEndReading;    // Chỉ số cuối
  final DateTime? electricityEndDate;     // Đến ngày (chỉ số cuối)
  final double? electricityPricePerUnit;  // Giá điện/kWh

  // Water meter readings (chỉ số nước)
  final double? waterStartReading;        // Chỉ số đầu
  final DateTime? waterStartDate;         // Từ ngày (chỉ số đầu)
  final double? waterEndReading;          // Chỉ số cuối
  final DateTime? waterEndDate;           // Đến ngày (chỉ số cuối)
  final double? waterPricePerUnit;        // Giá nước/m³

  // NEW: Additional Fees (for combined receipts)
  final double? internetFee;              // NEW: Phí internet
  final double? cableTVFee;               // NEW: Phí truyền hình cáp
  final double? hotWaterFee;               // NEW: Phí nước nóng
  final double? hotWaterPercent;          // NEW: % tính phí nước nóng
  final double? managementFee;            // NEW: Phí quản lý (if different from rent)

  // Tax
  final double? taxAmount;                // Tiền thuế / Tax amount

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
  final String? bookingId;

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
    // Rent unit-price fields
    this.rentPriceMode,
    this.rentUnitPrice,
    this.rentUnitQuantity,
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
    // NEW: Additional fees
    this.internetFee,
    this.cableTVFee,
    this.hotWaterFee,
    this.hotWaterPercent,
    this.managementFee,
    // Tax
    this.taxAmount,
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
    this.bookingId,
  });

  // Helper getters
  bool get isPaid => status == PaymentStatus.paid;
  bool get isPending => status == PaymentStatus.pending;
  bool get isOverdue => status == PaymentStatus.overdue ||
                        (status == PaymentStatus.pending && DateTime.now().isAfter(dueDate));
  bool get isPartiallyPaid => status == PaymentStatus.partial;

  // Building-level rent received FROM a renter leasing the whole building
  // (income), not a per-tenant payment. roomId will be empty and tenantId
  // will be null for this type.
  bool get isBuildingLevelIncome => type == PaymentType.buildingRent;
  bool get isHourlyBookingIncome => type == PaymentType.hourlyRent;

  double get remainingAmount => amount - paidAmount + (lateFee ?? 0) + (taxAmount ?? 0);
  double get totalAmount => amount + (lateFee ?? 0) + (taxAmount ?? 0);

  int get daysOverdue {
    if (!isOverdue) return 0;
    return DateTime.now().difference(dueDate).inDays;
  }

  // Calculate electricity usage (số điện tiêu thụ)
  double? get electricityUsage {
    if (electricityStartReading != null && electricityEndReading != null) {
      return electricityEndReading! - electricityStartReading!;
    }
    return null;
  }

  // Calculate water usage (số nước tiêu thụ)
  double? get waterUsage {
    if (waterStartReading != null && waterEndReading != null) {
      return waterEndReading! - waterStartReading!;
    }
    return null;
  }

  // True when this rent payment's amount was computed as unit price × quantity
  // rather than typed directly.
  bool get hasRentUnitPricing =>
      type == PaymentType.rent &&
      rentPriceMode != null &&
      rentPriceMode != RentPriceMode.direct &&
      rentUnitPrice != null &&
      rentUnitQuantity != null;

  String? getRentPriceModeDisplayName() {
    switch (rentPriceMode) {
      case RentPriceMode.direct:
        return 'Nhập trực tiếp';
      case RentPriceMode.daily:
        return 'Theo ngày';
      case RentPriceMode.monthly:
        return 'Theo tháng';
      case RentPriceMode.yearly:
        return 'Theo năm';
      case null:
        return null;
    }
  }

  // NEW: Calculate total with all fees
  double get totalWithAllFees {
    double total = amount;
    if (internetFee != null) total += internetFee!;
    if (cableTVFee != null) total += cableTVFee!;
    if (hotWaterFee != null) total += hotWaterFee!;
    if (lateFee != null) total += lateFee!;
    if (taxAmount != null) total += taxAmount!;
    return total;
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
      // Rent unit-price fields
      'rentPriceMode': rentPriceMode?.name,
      'rentUnitPrice': rentUnitPrice,
      'rentUnitQuantity': rentUnitQuantity,
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
      // NEW: Additional fees
      'internetFee': internetFee,
      'cableTVFee': cableTVFee,
      'hotWaterFee': hotWaterFee,
      'hotWaterPercent': hotWaterPercent,
      'managementFee': managementFee,
      // Tax
      'taxAmount': taxAmount,
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
      'bookingId': bookingId,
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
      // Rent unit-price fields
      rentPriceMode: map['rentPriceMode'] != null
          ? RentPriceMode.values.firstWhere(
              (e) => e.name == map['rentPriceMode'],
              orElse: () => RentPriceMode.direct,
            )
          : null,
      rentUnitPrice: (map['rentUnitPrice'] as num?)?.toDouble(),
      rentUnitQuantity: (map['rentUnitQuantity'] as num?)?.toDouble(),
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
      // NEW: Additional fees
      internetFee: (map['internetFee'] as num?)?.toDouble(),
      cableTVFee: (map['cableTVFee'] as num?)?.toDouble(),
      hotWaterFee: (map['hotWaterFee'] as num?)?.toDouble(),
      hotWaterPercent: (map['hotWaterPercent'] as num?)?.toDouble(),
      managementFee: (map['managementFee'] as num?)?.toDouble(),
      // Tax
      taxAmount: (map['taxAmount'] as num?)?.toDouble(),
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
      bookingId: map['bookingId'],
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
    RentPriceMode? rentPriceMode,
    double? rentUnitPrice,
    double? rentUnitQuantity,
    bool clearRentPricing = false,
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
    double? internetFee,       // NEW
    double? cableTVFee,        // NEW
    double? hotWaterFee,       // NEW
    double? hotWaterPercent,   // NEW
    double? managementFee,     // NEW
    double? taxAmount,         // NEW
    DateTime? createdAt,
    DateTime? paidAt,
    String? paidBy,
    String? description,
    String? notes,
    Map<String, dynamic>? metadata,
    double? lateFee,
    bool? isRecurring,
    String? recurringParentId,
    String? bookingId,
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
      rentPriceMode: clearRentPricing ? null : (rentPriceMode ?? this.rentPriceMode),
      rentUnitPrice: clearRentPricing ? null : (rentUnitPrice ?? this.rentUnitPrice),
      rentUnitQuantity: clearRentPricing ? null : (rentUnitQuantity ?? this.rentUnitQuantity),
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
      internetFee: internetFee ?? this.internetFee,               // NEW
      cableTVFee: cableTVFee ?? this.cableTVFee,                 // NEW
      hotWaterFee: hotWaterFee ?? this.hotWaterFee,               // NEW
      hotWaterPercent: hotWaterPercent ?? this.hotWaterPercent,   // NEW
      managementFee: managementFee ?? this.managementFee,         // NEW
      taxAmount: taxAmount ?? this.taxAmount,                     // NEW
      createdAt: createdAt ?? this.createdAt,
      paidAt: paidAt ?? this.paidAt,
      paidBy: paidBy ?? this.paidBy,
      description: description ?? this.description,
      notes: notes ?? this.notes,
      metadata: metadata ?? this.metadata,
      lateFee: lateFee ?? this.lateFee,
      isRecurring: isRecurring ?? this.isRecurring,
      recurringParentId: recurringParentId ?? this.recurringParentId,
      bookingId: bookingId ?? this.bookingId,
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
      case PaymentType.buildingRent:
        return 'Tiền thuê tòa nhà';
      case PaymentType.hourlyRent:
        return 'Tiền thuê theo giờ';
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
