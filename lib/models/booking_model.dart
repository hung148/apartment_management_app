import 'package:cloud_firestore/cloud_firestore.dart';

enum BookingStatus {
  pending,      // Chờ xác nhận
  confirmed,    // Đã xác nhận
  checkedIn,    // Đã nhận phòng
  checkedOut,   // Đã trả phòng
  cancelled,    // Đã hủy
  noShow,       // Không đến
}

enum BookingSource {
  walkIn,       // Khách vãng lai
  phone,        // Điện thoại
  app,          // Ứng dụng
  online,       // Đặt online
  other,        // Khác
}

// How the price for this booking was computed — kept so past bookings stay
// auditable even if the room's pricing config changes later.
enum BookingPricingType {
  hourly,       // Tính theo giờ
  overnight,    // Qua đêm (giá cố định)
  daily,        // Trọn ngày (giá cố định, vượt ngưỡng giờ)
}

class RoomBooking {
  final String id;
  final String organizationId;
  final String buildingId;
  final String roomId;

  // Lightweight guest info — intentionally NOT a full Tenant record
  final String guestName;
  final String guestPhone;
  final String? guestIdNumber;
  final int? numberOfGuests;

  final DateTime startTime;
  final DateTime endTime;
  final BookingStatus status;
  final BookingSource source;
  final BookingPricingType pricingType;

  final double totalPrice;
  final double paidAmount;
  final double? depositAmount;
  final bool depositRefunded;
  final double? depositRefundedAmount;

  final String? paymentId;       // linked Payment doc once settled/checked out
  final String? notes;
  final String? cancelReason;

  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? checkedInBy;
  final String? checkedOutBy;
  final DateTime? checkedInAt;
  final DateTime? checkedOutAt;

  RoomBooking({
    required this.id,
    required this.organizationId,
    required this.buildingId,
    required this.roomId,
    required this.guestName,
    required this.guestPhone,
    this.guestIdNumber,
    this.numberOfGuests,
    required this.startTime,
    required this.endTime,
    this.status = BookingStatus.pending,
    this.source = BookingSource.walkIn,
    this.pricingType = BookingPricingType.hourly,
    required this.totalPrice,
    this.paidAmount = 0.0,
    this.depositAmount,
    this.depositRefunded = false,
    this.depositRefundedAmount,
    this.paymentId,
    this.notes,
    this.cancelReason,
    required this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.checkedInBy,
    this.checkedOutBy,
    this.checkedInAt,
    this.checkedOutAt,
  });

  // ---- Helpers ----

  bool get isActive =>
      status == BookingStatus.pending ||
      status == BookingStatus.confirmed ||
      status == BookingStatus.checkedIn;

  bool get isCancelled =>
      status == BookingStatus.cancelled || status == BookingStatus.noShow;

  bool get isCheckedIn => status == BookingStatus.checkedIn;
  bool get isCheckedOut => status == BookingStatus.checkedOut;

  Duration get duration => endTime.difference(startTime);
  double get durationHours => duration.inMinutes / 60.0;

  double get remainingAmount => totalPrice - paidAmount;
  bool get isFullyPaid => paidAmount >= totalPrice;

  double get remainingDeposit {
    if (depositAmount == null) return 0.0;
    if (depositRefunded) return 0.0;
    return depositAmount!;
  }

  /// True if [other]'s [startTime, endTime) window overlaps this booking's,
  /// ignoring cancelled/no-show bookings on either side.
  bool overlaps(DateTime otherStart, DateTime otherEnd) {
    if (isCancelled) return false;
    return startTime.isBefore(otherEnd) && endTime.isAfter(otherStart);
  }

  Map<String, dynamic> toMap() {
    return {
      'organizationId': organizationId,
      'buildingId': buildingId,
      'roomId': roomId,
      'guestName': guestName,
      'guestPhone': guestPhone,
      'guestIdNumber': guestIdNumber,
      'numberOfGuests': numberOfGuests,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'status': status.name,
      'source': source.name,
      'pricingType': pricingType.name,
      'totalPrice': totalPrice,
      'paidAmount': paidAmount,
      'depositAmount': depositAmount,
      'depositRefunded': depositRefunded,
      'depositRefundedAmount': depositRefundedAmount,
      'paymentId': paymentId,
      'notes': notes,
      'cancelReason': cancelReason,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'createdBy': createdBy,
      'checkedInBy': checkedInBy,
      'checkedOutBy': checkedOutBy,
      'checkedInAt': checkedInAt != null ? Timestamp.fromDate(checkedInAt!) : null,
      'checkedOutAt': checkedOutAt != null ? Timestamp.fromDate(checkedOutAt!) : null,
    };
  }

  factory RoomBooking.fromMap(String id, Map<String, dynamic> map) {
    return RoomBooking(
      id: id,
      organizationId: map['organizationId'] ?? '',
      buildingId: map['buildingId'] ?? '',
      roomId: map['roomId'] ?? '',
      guestName: map['guestName'] ?? '',
      guestPhone: map['guestPhone'] ?? '',
      guestIdNumber: map['guestIdNumber'],
      numberOfGuests: map['numberOfGuests'] as int?,
      startTime: (map['startTime'] as Timestamp).toDate(),
      endTime: (map['endTime'] as Timestamp).toDate(),
      status: BookingStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => BookingStatus.pending,
      ),
      source: BookingSource.values.firstWhere(
        (e) => e.name == map['source'],
        orElse: () => BookingSource.walkIn,
      ),
      pricingType: BookingPricingType.values.firstWhere(
        (e) => e.name == map['pricingType'],
        orElse: () => BookingPricingType.hourly,
      ),
      totalPrice: (map['totalPrice'] as num?)?.toDouble() ?? 0.0,
      paidAmount: (map['paidAmount'] as num?)?.toDouble() ?? 0.0,
      depositAmount: (map['depositAmount'] as num?)?.toDouble(),
      depositRefunded: map['depositRefunded'] ?? false,
      depositRefundedAmount: (map['depositRefundedAmount'] as num?)?.toDouble(),
      paymentId: map['paymentId'],
      notes: map['notes'],
      cancelReason: map['cancelReason'],
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: map['updatedAt'] != null ? (map['updatedAt'] as Timestamp).toDate() : null,
      createdBy: map['createdBy'],
      checkedInBy: map['checkedInBy'],
      checkedOutBy: map['checkedOutBy'],
      checkedInAt: map['checkedInAt'] != null ? (map['checkedInAt'] as Timestamp).toDate() : null,
      checkedOutAt: map['checkedOutAt'] != null ? (map['checkedOutAt'] as Timestamp).toDate() : null,
    );
  }

  RoomBooking copyWith({
    String? id,
    String? organizationId,
    String? buildingId,
    String? roomId,
    String? guestName,
    String? guestPhone,
    String? guestIdNumber,
    int? numberOfGuests,
    DateTime? startTime,
    DateTime? endTime,
    BookingStatus? status,
    BookingSource? source,
    BookingPricingType? pricingType,
    double? totalPrice,
    double? paidAmount,
    double? depositAmount,
    bool? depositRefunded,
    double? depositRefundedAmount,
    String? paymentId,
    String? notes,
    String? cancelReason,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
    String? checkedInBy,
    String? checkedOutBy,
    DateTime? checkedInAt,
    DateTime? checkedOutAt,
  }) {
    return RoomBooking(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      buildingId: buildingId ?? this.buildingId,
      roomId: roomId ?? this.roomId,
      guestName: guestName ?? this.guestName,
      guestPhone: guestPhone ?? this.guestPhone,
      guestIdNumber: guestIdNumber ?? this.guestIdNumber,
      numberOfGuests: numberOfGuests ?? this.numberOfGuests,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      status: status ?? this.status,
      source: source ?? this.source,
      pricingType: pricingType ?? this.pricingType,
      totalPrice: totalPrice ?? this.totalPrice,
      paidAmount: paidAmount ?? this.paidAmount,
      depositAmount: depositAmount ?? this.depositAmount,
      depositRefunded: depositRefunded ?? this.depositRefunded,
      depositRefundedAmount: depositRefundedAmount ?? this.depositRefundedAmount,
      paymentId: paymentId ?? this.paymentId,
      notes: notes ?? this.notes,
      cancelReason: cancelReason ?? this.cancelReason,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      checkedInBy: checkedInBy ?? this.checkedInBy,
      checkedOutBy: checkedOutBy ?? this.checkedOutBy,
      checkedInAt: checkedInAt ?? this.checkedInAt,
      checkedOutAt: checkedOutAt ?? this.checkedOutAt,
    );
  }

  String getStatusDisplayName() {
    switch (status) {
      case BookingStatus.pending:
        return 'Chờ xác nhận';
      case BookingStatus.confirmed:
        return 'Đã xác nhận';
      case BookingStatus.checkedIn:
        return 'Đã nhận phòng';
      case BookingStatus.checkedOut:
        return 'Đã trả phòng';
      case BookingStatus.cancelled:
        return 'Đã hủy';
      case BookingStatus.noShow:
        return 'Không đến';
    }
  }

  String getSourceDisplayName() {
    switch (source) {
      case BookingSource.walkIn:
        return 'Khách vãng lai';
      case BookingSource.phone:
        return 'Điện thoại';
      case BookingSource.app:
        return 'Ứng dụng';
      case BookingSource.online:
        return 'Đặt online';
      case BookingSource.other:
        return 'Khác';
    }
  }
}