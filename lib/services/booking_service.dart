import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:phan_mem_quan_ly_can_ho/models/booking_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/rooms_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/payment_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/tenants_model.dart';

/// Thrown when a booking write would overlap an existing booking or an
/// active tenant contract on the same room.
class BookingConflictException implements Exception {
  final String message;
  BookingConflictException(this.message);
  @override
  String toString() => message;
}

class BookingService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  dynamic _encode(dynamic value) {
    if (value is Timestamp)
      return {'__timestamp': value.millisecondsSinceEpoch};
    if (value is DateTime) return {'__timestamp': value.millisecondsSinceEpoch};
    if (value is Map)
      return value.map((k, v) => MapEntry(k.toString(), _encode(v)));
    if (value is List) return value.map(_encode).toList();
    return value;
  }

  Future<Map<String, dynamic>> _mutate(Map<String, dynamic> data) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('mutateCalendarBooking')
          .call(_encode(data));
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'already-exists')
        throw BookingConflictException('booking_conflict');
      throw BookingConflictException(
        e.message?.startsWith('booking_') == true
            ? e.message!
            : 'booking_operation_failed',
      );
    }
  }

  static const List<String> _activeStatuses = [
    'pending',
    'confirmed',
    'checkedIn',
  ];

  // ========================================
  // PRICING ENGINE
  // ========================================

  /// Computes price for [room] over [start, end). Chooses hourly / daily /
  /// overnight based on room config and duration. Throws if the room has
  /// no hourly pricing configured at all.
  ({double price, BookingPricingType pricingType}) calculatePrice({
    required Room room,
    required DateTime start,
    required DateTime end,
    bool isOvernightPreset = false,
  }) {
    if (!room.hasHourlyPricing) {
      throw ArgumentError(
        'Room ${room.roomNumber} has no hourly pricing configured',
      );
    }

    if (isOvernightPreset && room.overnightPrice != null) {
      return (
        price: room.overnightPrice!,
        pricingType: BookingPricingType.overnight,
      );
    }

    final hours = end.difference(start).inMinutes / 60.0;

    if (room.dailyPrice != null &&
        room.dailyPriceThresholdHours != null &&
        hours >= room.dailyPriceThresholdHours!) {
      return (price: room.dailyPrice!, pricingType: BookingPricingType.daily);
    }

    final price = hours * room.hourlyPrice!;
    return (price: price, pricingType: BookingPricingType.hourly);
  }

  // ========================================
  // AVAILABILITY / OVERLAP CHECKS
  // ========================================

  /// True if [roomId] is free for the entire [start, end) window.
  /// Checks both existing bookings AND (if the room isn't pure-hourly) any
  /// active tenant contract that would occupy the room during that window.
  Future<bool> isRoomAvailable({
    required String organizationId,
    required String roomId,
    required DateTime start,
    required DateTime end,
    String? excludeBookingId,
    int cleaningBufferMinutes = 0,
  }) async {
    // 1. Overlapping bookings
    final bufferedStart = start.subtract(
      Duration(minutes: cleaningBufferMinutes),
    );
    final bufferedEnd = end.add(Duration(minutes: cleaningBufferMinutes));

    final snapshot = await _firestore
        .collection('bookings')
        .where('organizationId', isEqualTo: organizationId)
        .where('roomId', isEqualTo: roomId)
        .where('startTime', isLessThan: Timestamp.fromDate(bufferedEnd))
        .get(const GetOptions(source: Source.server));

    for (final doc in snapshot.docs) {
      if (doc.id == excludeBookingId) continue;
      final booking = RoomBooking.fromMap(doc.id, doc.data());
      if (!_activeStatuses.contains(booking.status.name)) continue;
      if (booking.endTime.isAfter(bufferedStart)) {
        return false; // overlap found
      }
    }

    // 2. Active tenant contract occupying the room during this window
    final tenantSnapshot = await _firestore
        .collection('tenants')
        .where('organizationId', isEqualTo: organizationId)
        .where('roomId', isEqualTo: roomId)
        .where('status', isEqualTo: 'active')
        .get(const GetOptions(source: Source.server));

    for (final doc in tenantSnapshot.docs) {
      final data = doc.data();
      final moveIn = (data['moveInDate'] as Timestamp?)?.toDate();
      final moveOut = (data['moveOutDate'] as Timestamp?)?.toDate();
      if (moveIn == null) continue;
      final tenantEnd =
          moveOut ??
          DateTime(2999); // no move-out date yet = occupies indefinitely
      if (moveIn.isBefore(end) && tenantEnd.isAfter(start)) {
        return false; // tenant occupies the room during this window
      }
    }

    return true;
  }

  /// Returns the rooms in [buildingId] that are free for the whole
  /// [start, end) window and configured for hourly booking.
  Future<List<Room>> getAvailableRoomsInBuilding({
    required String organizationId,
    required String buildingId,
    required DateTime start,
    required DateTime end,
    required List<Room>
    candidateRooms, // pass in rooms already fetched for the building
  }) async {
    final available = <Room>[];
    for (final room in candidateRooms) {
      if (!room.supportsHourlyBooking || !room.hasHourlyPricing) continue;
      final free = await isRoomAvailable(
        organizationId: organizationId,
        roomId: room.id,
        start: start,
        end: end,
        cleaningBufferMinutes: room.cleaningBufferMinutes ?? 0,
      );
      if (free) available.add(room);
    }
    return available;
  }

  // ========================================
  // CREATE
  // ========================================

  /// The server performs the overlap check and write in one transaction.
  Future<String?> createBooking(RoomBooking booking) async {
    final bookingId = booking.id.isEmpty
        ? _firestore.collection('bookings').doc().id
        : booking.id;
    final result = await _mutate({
      'action': 'create',
      'bookingId': bookingId,
      'booking': booking.toMap(),
    });
    return result['id'] as String;
  }

  // ========================================
  // READ
  // ========================================

  Future<RoomBooking?> getBookingById(String bookingId) async {
    try {
      final doc = await _firestore
          .collection('bookings')
          .doc(bookingId)
          .get(const GetOptions(source: Source.server));
      if (!doc.exists) return null;
      return RoomBooking.fromMap(doc.id, doc.data()!);
    } catch (e) {
      print('Error getting booking: $e');
      rethrow;
    }
  }

  Future<List<RoomBooking>> getRoomBookings(
    String organizationId,
    String roomId, {
    BookingStatus? status,
  }) async {
    try {
      Query query = _firestore
          .collection('bookings')
          .where('organizationId', isEqualTo: organizationId)
          .where('roomId', isEqualTo: roomId);
      if (status != null) {
        query = query.where('status', isEqualTo: status.name);
      }
      final snapshot = await query
          .orderBy('startTime', descending: true)
          .get(const GetOptions(source: Source.server));
      return snapshot.docs
          .map(
            (doc) =>
                RoomBooking.fromMap(doc.id, doc.data() as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      print('Error getting room bookings: $e');
      rethrow;
    }
  }

  /// All bookings for [roomId] that intersect the calendar day of [date].
  Future<List<RoomBooking>> getRoomBookingsForDay(
    String organizationId,
    String roomId,
    DateTime date,
  ) async {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    try {
      final snapshot = await _firestore
          .collection('bookings')
          .where('organizationId', isEqualTo: organizationId)
          .where('roomId', isEqualTo: roomId)
          .where('startTime', isLessThan: Timestamp.fromDate(dayEnd))
          .get(const GetOptions(source: Source.server));

      return snapshot.docs
          .map((doc) => RoomBooking.fromMap(doc.id, doc.data()))
          .where((b) => b.endTime.isAfter(dayStart) && !b.isCancelled)
          .toList();
    } catch (e) {
      print('Error getting room bookings for day: $e');
      rethrow;
    }
  }

  /// All bookings across every room in [buildingId] that intersect [date],
  /// grouped by roomId. Powers the day-view timeline.
  Future<Map<String, List<RoomBooking>>> getBuildingBookingsForDay(
    String organizationId,
    String buildingId,
    DateTime date,
  ) async {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    try {
      final snapshot = await _firestore
          .collection('bookings')
          .where('organizationId', isEqualTo: organizationId)
          .where('buildingId', isEqualTo: buildingId)
          .where('startTime', isLessThan: Timestamp.fromDate(dayEnd))
          .get(const GetOptions(source: Source.server));

      final bookings = snapshot.docs
          .map((doc) => RoomBooking.fromMap(doc.id, doc.data()))
          .where((b) => b.endTime.isAfter(dayStart) && !b.isCancelled)
          .toList();

      final grouped = <String, List<RoomBooking>>{};
      for (final booking in bookings) {
        grouped.putIfAbsent(booking.roomId, () => []).add(booking);
      }
      return grouped;
    } catch (e) {
      print('Error getting building bookings for day: $e');
      rethrow;
    }
  }

  /// Raw bookings for every room in [buildingId] intersecting [month], used
  /// to build the room-by-room month view.
  Future<List<RoomBooking>> getBuildingBookingsForMonth(
    String organizationId,
    String buildingId,
    DateTime month,
  ) async {
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month + 1, 1);
    try {
      final snapshot = await _firestore
          .collection('bookings')
          .where('organizationId', isEqualTo: organizationId)
          .where('buildingId', isEqualTo: buildingId)
          .where('startTime', isLessThan: Timestamp.fromDate(monthEnd))
          .get(const GetOptions(source: Source.server));

      return snapshot.docs
          .map((doc) => RoomBooking.fromMap(doc.id, doc.data()))
          .where((b) => b.endTime.isAfter(monthStart))
          .toList();
    } catch (e) {
      print('Error getting building bookings for month: $e');
      rethrow;
    }
  }

  /// Per-day occupancy summary for a whole month, for the month-view heatmap.
  /// [totalRoomCount] should be the number of hourly/both-mode rooms in the
  /// building (pass in from the already-fetched room list).
  Future<Map<DateTime, double>> getBuildingOccupancySummaryForMonth(
    String organizationId,
    String buildingId,
    DateTime month,
    int totalRoomCount, {
    Map<String, Tenant> activeTenantsByRoomId = const {},
  }) async {
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month + 1, 1);

    try {
      final snapshot = await _firestore
          .collection('bookings')
          .where('organizationId', isEqualTo: organizationId)
          .where('buildingId', isEqualTo: buildingId)
          .where('startTime', isLessThan: Timestamp.fromDate(monthEnd))
          .get(const GetOptions(source: Source.server));

      final bookings = snapshot.docs
          .map((doc) => RoomBooking.fromMap(doc.id, doc.data()))
          .where((b) => b.endTime.isAfter(monthStart) && !b.isCancelled)
          .toList();

      final result = <DateTime, double>{};
      if (totalRoomCount == 0) return result;

      for (int d = 0; d < monthEnd.difference(monthStart).inDays; d++) {
        final day = monthStart.add(Duration(days: d));
        final dayEnd = day.add(const Duration(days: 1));

        final bookedRoomIds = bookings
            .where(
              (b) => b.startTime.isBefore(dayEnd) && b.endTime.isAfter(day),
            )
            .map((b) => b.roomId)
            .toSet();

        final tenantOccupiedRoomIds = activeTenantsByRoomId.entries
            .where((e) {
              final moveOut = e.value.moveOutDate ?? DateTime(2999);
              return e.value.moveInDate.isBefore(dayEnd) &&
                  moveOut.isAfter(day);
            })
            .map((e) => e.key)
            .toSet();

        final occupiedRoomIds = {...bookedRoomIds, ...tenantOccupiedRoomIds};
        result[day] = occupiedRoomIds.length / totalRoomCount;
      }
      return result;
    } catch (e) {
      print('Error getting building occupancy summary: $e');
      rethrow;
    }
  }

  // ========================================
  // STREAMS (real-time for the calendar screen)
  // ========================================

  Stream<List<RoomBooking>> streamRoomBookings(
    String organizationId,
    String roomId,
  ) {
    return _firestore
        .collection('bookings')
        .where('organizationId', isEqualTo: organizationId)
        .where('roomId', isEqualTo: roomId)
        .orderBy('startTime', descending: true)
        .snapshots()
        .map(
          (s) =>
              s.docs.map((d) => RoomBooking.fromMap(d.id, d.data())).toList(),
        );
  }

  Stream<List<RoomBooking>> streamBuildingBookingsForDay(
    String organizationId,
    String buildingId,
    DateTime date,
  ) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return _firestore
        .collection('bookings')
        .where('organizationId', isEqualTo: organizationId)
        .where('buildingId', isEqualTo: buildingId)
        .where('startTime', isLessThan: Timestamp.fromDate(dayEnd))
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => RoomBooking.fromMap(d.id, d.data()))
              .where((b) => b.endTime.isAfter(dayStart) && !b.isCancelled)
              .toList(),
        );
  }

  // ========================================
  // UPDATE / LIFECYCLE
  // ========================================

  Future<bool> updateBooking(
    String bookingId,
    Map<String, dynamic> data,
  ) async {
    await _mutate({'action': 'edit', 'bookingId': bookingId, 'changes': data});
    return true;
  }

  Future<bool> _setStatus(
    String bookingId,
    String status, {
    String? reason,
  }) async {
    await _mutate({
      'action': 'status',
      'bookingId': bookingId,
      'status': status,
      'reason': reason,
    });
    return true;
  }

  Future<bool> confirmBooking(String bookingId) =>
      _setStatus(bookingId, 'confirmed');
  Future<bool> checkIn(String bookingId, {String? staffId}) =>
      _setStatus(bookingId, 'checkedIn');
  Future<bool> checkOut(
    String bookingId, {
    String? staffId,
    required PaymentMethod paymentMethod,
  }) async {
    await _mutate({
      'action': 'checkout',
      'bookingId': bookingId,
      'paymentMethod': paymentMethod.name,
    });
    return true;
  }

  Future<bool> cancelBooking(String bookingId, {String? reason}) =>
      _setStatus(bookingId, 'cancelled', reason: reason);
  Future<bool> markNoShow(String bookingId) => _setStatus(bookingId, 'noShow');
  Future<bool> recordPayment(
    String bookingId,
    double amount,
    PaymentMethod method, {
    required String operationId,
    bool deposit = false,
    bool refund = false,
  }) async {
    await _mutate({
      'action': refund
          ? 'refund'
          : deposit
          ? 'deposit'
          : 'payment',
      'bookingId': bookingId,
      'operationId': operationId,
      'amount': amount,
      'paymentMethod': method.name,
    });
    return true;
  }

  Future<bool> refundDeposit(String bookingId, double amount) => recordPayment(
    bookingId,
    amount,
    PaymentMethod.cash,
    operationId: _firestore.collection('payments').doc().id,
    refund: true,
  );
  Future<bool> deleteBooking(String bookingId) async {
    await _mutate({'action': 'delete', 'bookingId': bookingId});
    return true;
  }
}
