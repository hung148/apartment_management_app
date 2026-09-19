import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/app_localizations.dart';

enum RoomRentalMode {
  monthly,  // Cho thuê dài hạn (mặc định, như hiện tại)
  hourly,   // Cho thuê theo giờ (kiểu khách sạn)
  both,     // Linh hoạt: vừa dài hạn vừa theo giờ khi trống
}

class Room {
  final String currency;
  final String id;
  final String organizationId;
  final String buildingId;
  final String roomNumber;
  final String roomType;
  final double area; // Diện tích (m2)
  final DateTime createdAt;
  final double? roomPrice; // Giá thuê mặc định của phòng (VND/tháng)

  // ---- Hourly rental config (all optional — backward compatible) ----
  final RoomRentalMode rentalMode;
  final double? hourlyPrice;              // Giá theo giờ (VND/giờ)
  final double? dailyPrice;               // Giá trọn ngày (áp dụng khi vượt ngưỡng giờ)
  final double? overnightPrice;           // Giá qua đêm (gói cố định)
  final double? dailyPriceThresholdHours; // Vượt ngưỡng này thì tính theo dailyPrice thay vì hourlyPrice
  final int? minBookingHours;             // Số giờ đặt tối thiểu
  final int? cleaningBufferMinutes;       // Thời gian dọn phòng bắt buộc giữa 2 lượt đặt
  final int? operatingHoursStartMin;      // Phút tính từ nửa đêm, null = mở 24h
  final int? operatingHoursEndMin;        // Phút tính từ nửa đêm, null = mở 24h

  Room({
    this.currency = 'VND',
    required this.id,
    required this.organizationId,
    required this.buildingId,
    required this.roomNumber,
    required this.roomType,
    required this.area,
    required this.createdAt,
    this.roomPrice,
    this.rentalMode = RoomRentalMode.monthly,
    this.hourlyPrice,
    this.dailyPrice,
    this.overnightPrice,
    this.dailyPriceThresholdHours,
    this.minBookingHours,
    this.cleaningBufferMinutes,
    this.operatingHoursStartMin,
    this.operatingHoursEndMin,
  });

  bool get supportsHourlyBooking =>
      rentalMode == RoomRentalMode.hourly || rentalMode == RoomRentalMode.both;
  bool get supportsMonthlyTenant =>
      rentalMode == RoomRentalMode.monthly || rentalMode == RoomRentalMode.both;
  bool get hasHourlyPricing => hourlyPrice != null && hourlyPrice! > 0;

  Map<String, dynamic> toMap() {
    return {
      'currency': currency,
      'organizationId': organizationId,
      'buildingId': buildingId,
      'roomNumber': roomNumber,
      'roomType': roomType,
      'area': area,
      'createdAt': Timestamp.fromDate(createdAt),
      'roomPrice': roomPrice,
      'rentalMode': rentalMode.name,
      'hourlyPrice': hourlyPrice,
      'dailyPrice': dailyPrice,
      'overnightPrice': overnightPrice,
      'dailyPriceThresholdHours': dailyPriceThresholdHours,
      'minBookingHours': minBookingHours,
      'cleaningBufferMinutes': cleaningBufferMinutes,
      'operatingHoursStartMin': operatingHoursStartMin,
      'operatingHoursEndMin': operatingHoursEndMin,
    };
  }

  factory Room.fromMap(String id, Map<String, dynamic> map) {
    return Room(
      currency: map['currency'] as String? ?? 'VND',
      id: id,
      organizationId: map['organizationId'] ?? '',
      buildingId: map['buildingId'] ?? '',
      roomNumber: map['roomNumber'] ?? '',
      roomType: map['roomType'] ?? 'Tiêu chuẩn',
      area: (map['area'] as num?)?.toDouble() ?? 0.0,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      roomPrice: (map['roomPrice'] as num?)?.toDouble(),
      rentalMode: RoomRentalMode.values.firstWhere(
        (e) => e.name == map['rentalMode'],
        orElse: () => RoomRentalMode.monthly,
      ),
      hourlyPrice: (map['hourlyPrice'] as num?)?.toDouble(),
      dailyPrice: (map['dailyPrice'] as num?)?.toDouble(),
      overnightPrice: (map['overnightPrice'] as num?)?.toDouble(),
      dailyPriceThresholdHours: (map['dailyPriceThresholdHours'] as num?)?.toDouble(),
      minBookingHours: map['minBookingHours'] as int?,
      cleaningBufferMinutes: map['cleaningBufferMinutes'] as int?,
      operatingHoursStartMin: map['operatingHoursStartMin'] as int?,
      operatingHoursEndMin: map['operatingHoursEndMin'] as int?,
    );
  }

  Room copyWith({
    String? id,
    String? organizationId,
    String? buildingId,
    String? roomNumber,
    String? roomType,
    double? area,
    DateTime? createdAt,
    double? roomPrice,
    RoomRentalMode? rentalMode,
    double? hourlyPrice,
    double? dailyPrice,
    double? overnightPrice,
    double? dailyPriceThresholdHours,
    int? minBookingHours,
    int? cleaningBufferMinutes,
    int? operatingHoursStartMin,
    int? operatingHoursEndMin,
  }) {
    return Room(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      buildingId: buildingId ?? this.buildingId,
      roomNumber: roomNumber ?? this.roomNumber,
      roomType: roomType ?? this.roomType,
      area: area ?? this.area,
      createdAt: createdAt ?? this.createdAt,
      roomPrice: roomPrice ?? this.roomPrice,
      rentalMode: rentalMode ?? this.rentalMode,
      hourlyPrice: hourlyPrice ?? this.hourlyPrice,
      dailyPrice: dailyPrice ?? this.dailyPrice,
      overnightPrice: overnightPrice ?? this.overnightPrice,
      dailyPriceThresholdHours: dailyPriceThresholdHours ?? this.dailyPriceThresholdHours,
      minBookingHours: minBookingHours ?? this.minBookingHours,
      cleaningBufferMinutes: cleaningBufferMinutes ?? this.cleaningBufferMinutes,
      operatingHoursStartMin: operatingHoursStartMin ?? this.operatingHoursStartMin,
      operatingHoursEndMin: operatingHoursEndMin ?? this.operatingHoursEndMin,
    );
  }

  String getRentalModeDisplayName(AppTranslations t) {
    switch (rentalMode) {
      case RoomRentalMode.monthly:
        return t['room_rental_mode_monthly'];
      case RoomRentalMode.hourly:
        return t['room_rental_mode_hourly'];
      case RoomRentalMode.both:
        return t['room_rental_mode_both'];
    }
  }
}
