import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:phan_mem_quan_ly_can_ho/models/booking_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/rooms_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/payment_model.dart';
import 'package:phan_mem_quan_ly_can_ho/services/payments_service.dart';
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
  final PaymentService _paymentService = PaymentService();

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
      throw ArgumentError('Room ${room.roomNumber} has no hourly pricing configured');
    }

    if (isOvernightPreset && room.overnightPrice != null) {
      return (price: room.overnightPrice!, pricingType: BookingPricingType.overnight);
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
    final bufferedStart = start.subtract(Duration(minutes: cleaningBufferMinutes));
    final bufferedEnd = end.add(Duration(minutes: cleaningBufferMinutes));

    final snapshot = await _firestore
        .collection('bookings')
        .where('organizationId', isEqualTo: organizationId)
        .where('roomId', isEqualTo: roomId)
        .where('startTime', isLessThan: Timestamp.fromDate(bufferedEnd))
        .get();

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
        .get();

    for (final doc in tenantSnapshot.docs) {
      final data = doc.data();
      final moveIn = (data['moveInDate'] as Timestamp?)?.toDate();
      final moveOut = (data['moveOutDate'] as Timestamp?)?.toDate();
      if (moveIn == null) continue;
      final tenantEnd = moveOut ?? DateTime(2999); // no move-out date yet = occupies indefinitely
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
    required List<Room> candidateRooms, // pass in rooms already fetched for the building
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

  /// Creates a booking after re-validating availability.
  ///
  /// NOTE ON RACE CONDITIONS: this re-checks availability immediately
  /// before writing, but cloud_firestore transactions don't reliably
  /// support arbitrary queries across SDK versions, so this is a
  /// best-effort check, not a hard atomic guarantee. Acceptable for
  /// low-concurrency internal staff usage; if two staff members create
  /// overlapping bookings within the same instant, add a Cloud Function
  /// safety net later (see plan doc).
  Future<String?> createBooking(RoomBooking booking) async {
    final available = await isRoomAvailable(
      organizationId: booking.organizationId,
      roomId: booking.roomId,
      start: booking.startTime,
      end: booking.endTime,
    );

    if (!available) {
      throw BookingConflictException(
        'Phòng đã được đặt hoặc đang có khách thuê dài hạn trong khoảng thời gian này',
      );
    }

    try {
      final docRef = await _firestore.collection('bookings').add(booking.toMap());
      print('Booking created successfully: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('Error creating booking: $e');
      return null;
    }
  }

  // ========================================
  // READ
  // ========================================

  Future<RoomBooking?> getBookingById(String bookingId) async {
    try {
      final doc = await _firestore.collection('bookings').doc(bookingId).get();
      if (!doc.exists) return null;
      return RoomBooking.fromMap(doc.id, doc.data()!);
    } catch (e) {
      print('Error getting booking: $e');
      return null;
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
      final snapshot = await query.orderBy('startTime', descending: true).get();
      return snapshot.docs
          .map((doc) => RoomBooking.fromMap(doc.id, doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error getting room bookings: $e');
      return [];
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
          .get();

      return snapshot.docs
          .map((doc) => RoomBooking.fromMap(doc.id, doc.data()))
          .where((b) => b.endTime.isAfter(dayStart) && !b.isCancelled)
          .toList();
    } catch (e) {
      print('Error getting room bookings for day: $e');
      return [];
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
          .get();

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
      return {};
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
          .get();

      return snapshot.docs
          .map((doc) => RoomBooking.fromMap(doc.id, doc.data()))
          .where((b) => b.endTime.isAfter(monthStart) && !b.isCancelled)
          .toList();
    } catch (e) {
      print('Error getting building bookings for month: $e');
      return [];
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
          .get();

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
            .where((b) => b.startTime.isBefore(dayEnd) && b.endTime.isAfter(day))
            .map((b) => b.roomId)
            .toSet();

        final tenantOccupiedRoomIds = activeTenantsByRoomId.entries
            .where((e) {
              final moveOut = e.value.moveOutDate ?? DateTime(2999);
              return e.value.moveInDate.isBefore(dayEnd) && moveOut.isAfter(day);
            })
            .map((e) => e.key)
            .toSet();

        final occupiedRoomIds = {...bookedRoomIds, ...tenantOccupiedRoomIds};
        result[day] = occupiedRoomIds.length / totalRoomCount;
      }
      return result;
    } catch (e) {
      print('Error getting building occupancy summary: $e');
      return {};
    }
  }

  // ========================================
  // STREAMS (real-time for the calendar screen)
  // ========================================

  Stream<List<RoomBooking>> streamRoomBookings(String organizationId, String roomId) {
    return _firestore
        .collection('bookings')
        .where('organizationId', isEqualTo: organizationId)
        .where('roomId', isEqualTo: roomId)
        .orderBy('startTime', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => RoomBooking.fromMap(d.id, d.data())).toList());
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
        .map((s) => s.docs
            .map((d) => RoomBooking.fromMap(d.id, d.data()))
            .where((b) => b.endTime.isAfter(dayStart) && !b.isCancelled)
            .toList());
  }

  // ========================================
  // UPDATE / LIFECYCLE
  // ========================================

  Future<bool> updateBooking(String bookingId, Map<String, dynamic> data) async {
    try {
      data['updatedAt'] = Timestamp.now();
      await _firestore.collection('bookings').doc(bookingId).update(data);
      return true;
    } catch (e) {
      print('Error updating booking: $e');
      return false;
    }
  }

  Future<bool> confirmBooking(String bookingId) async {
    return updateBooking(bookingId, {'status': BookingStatus.confirmed.name});
  }

  Future<bool> checkIn(String bookingId, {String? staffId}) async {
    return updateBooking(bookingId, {
      'status': BookingStatus.checkedIn.name,
      'checkedInAt': Timestamp.now(),
      'checkedInBy': staffId,
    });
  }

  /// Checks a booking out and creates the matching Payment record so it
  /// flows into existing revenue reporting automatically.
  Future<bool> checkOut(
    String bookingId, {
    String? staffId,
    required PaymentMethod paymentMethod,
  }) async {
    try {
      final booking = await getBookingById(bookingId);
      if (booking == null) return false;

      final paymentId = await _paymentService.addPayment(Payment(
        id: '',
        organizationId: booking.organizationId,
        buildingId: booking.buildingId,
        roomId: booking.roomId,
        tenantId: null,
        tenantName: booking.guestName,
        type: PaymentType.hourlyRent,
        status: PaymentStatus.paid,
        amount: booking.totalPrice,
        paidAmount: booking.totalPrice,
        paymentMethod: paymentMethod,
        dueDate: booking.endTime,
        billingStartDate: booking.startTime,
        billingEndDate: booking.endTime,
        description:
            'Thuê phòng theo giờ - ${booking.guestName} (${booking.durationHours.toStringAsFixed(1)}h)',
        createdAt: DateTime.now(),
        paidAt: DateTime.now(),
      ));

      return updateBooking(bookingId, {
        'status': BookingStatus.checkedOut.name,
        'checkedOutAt': Timestamp.now(),
        'checkedOutBy': staffId,
        'paidAmount': booking.totalPrice,
        if (paymentId != null) 'paymentId': paymentId,
      });
    } catch (e) {
      print('Error checking out booking: $e');
      return false;
    }
  }

  Future<bool> cancelBooking(String bookingId, {String? reason}) async {
    return updateBooking(bookingId, {
      'status': BookingStatus.cancelled.name,
      'cancelReason': reason,
    });
  }

  Future<bool> markNoShow(String bookingId) async {
    return updateBooking(bookingId, {'status': BookingStatus.noShow.name});
  }

  Future<bool> refundDeposit(String bookingId, double amount) async {
    return updateBooking(bookingId, {
      'depositRefunded': true,
      'depositRefundedAmount': amount,
    });
  }

  // ========================================
  // DELETE
  // ========================================

  Future<bool> deleteBooking(String bookingId) async {
    try {
      await _firestore.collection('bookings').doc(bookingId).delete();
      return true;
    } catch (e) {
      print('Error deleting booking: $e');
      return false;
    }
  }
}