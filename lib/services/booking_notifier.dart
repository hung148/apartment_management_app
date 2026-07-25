import 'package:flutter/material.dart';
import 'package:phan_mem_quan_ly_can_ho/models/booking_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/payment_model.dart';
import 'package:phan_mem_quan_ly_can_ho/services/booking_service.dart';

class BookingsNotifier extends ChangeNotifier {
  final BookingService _bookingService;

  // Day-view state: bookings grouped by roomId for the selected building/date
  Map<String, List<RoomBooking>> _dayBookingsByRoom = {};
  // Detail-view state: bookings for a single room
  List<RoomBooking> _roomBookings = [];
  // Month-view state: occupancy fraction (0.0–1.0) per day
  Map<DateTime, double> _monthOccupancy = {};

  bool _isLoading = false;
  String? _error;

  BookingsNotifier(this._bookingService);

  // Getters
  Map<String, List<RoomBooking>> get dayBookingsByRoom => _dayBookingsByRoom;
  List<RoomBooking> get roomBookings => _roomBookings;
  Map<DateTime, double> get monthOccupancy => _monthOccupancy;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Safe notifyListeners — won't crash if called during a build
  void _safeNotify() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) notifyListeners();
    });
  }

  // ========================================
  // DAY VIEW
  // ========================================

  Future<void> loadDayBookings(
    String organizationId,
    String buildingId,
    DateTime date,
  ) async {
    _isLoading = true;
    _error = null;
    _safeNotify();

    try {
      _dayBookingsByRoom = await _bookingService.getBuildingBookingsForDay(
        organizationId,
        buildingId,
        date,
      );
    } catch (e) {
      print('Error loading day bookings: $e');
      _error = e.toString();
      _dayBookingsByRoom = {};
    } finally {
      _isLoading = false;
      _safeNotify();
    }
  }

  /// Subscribe to real-time updates for the day view. Call the returned
  /// function to cancel the subscription (e.g. in dispose or when the
  /// selected building/date changes).
  void Function() streamDayBookings(
    String organizationId,
    String buildingId,
    DateTime date,
  ) {
    final sub = _bookingService
        .streamBuildingBookingsForDay(organizationId, buildingId, date)
        .listen((bookings) {
      final grouped = <String, List<RoomBooking>>{};
      for (final booking in bookings) {
        grouped.putIfAbsent(booking.roomId, () => []).add(booking);
      }
      _dayBookingsByRoom = grouped;
      _safeNotify();
    });
    return sub.cancel;
  }

  // ========================================
  // MONTH VIEW
  // ========================================

  Future<void> loadMonthOccupancy(
    String organizationId,
    String buildingId,
    DateTime month,
    int totalRoomCount,
  ) async {
    _isLoading = true;
    _safeNotify();

    try {
      _monthOccupancy = await _bookingService.getBuildingOccupancySummaryForMonth(
        organizationId,
        buildingId,
        month,
        totalRoomCount,
      );
    } catch (e) {
      print('Error loading month occupancy: $e');
      _monthOccupancy = {};
    } finally {
      _isLoading = false;
      _safeNotify();
    }
  }

  // ========================================
  // ROOM DETAIL
  // ========================================

  Future<void> loadRoomBookings(
    String organizationId,
    String roomId,
  ) async {
    _isLoading = true;
    _safeNotify();

    try {
      _roomBookings = await _bookingService.getRoomBookings(organizationId, roomId);
    } catch (e) {
      print('Error loading room bookings: $e');
      _roomBookings = [];
    } finally {
      _isLoading = false;
      _safeNotify();
    }
  }

  // ========================================
  // MUTATIONS
  // ========================================

  /// Creates a booking. Throws [BookingConflictException] if the room isn't
  /// actually free — callers should catch this and show the conflict to
  /// the user (someone else may have just booked it).
  Future<String?> createBooking(RoomBooking booking) async {
    try {
      final bookingId = await _bookingService.createBooking(booking);
      if (bookingId != null) {
        final newBooking = booking.copyWith(id: bookingId);
        _dayBookingsByRoom
            .putIfAbsent(booking.roomId, () => [])
            .add(newBooking);
        notifyListeners();
      }
      return bookingId;
    } catch (e) {
      print('Error creating booking in notifier: $e');
      rethrow;
    }
  }

  Future<bool> confirmBooking(String bookingId) => _mutate(
        bookingId,
        (status: BookingStatus.confirmed, id: bookingId),
        () => _bookingService.confirmBooking(bookingId),
      );

  Future<bool> checkIn(String bookingId, {String? staffId}) => _mutate(
        bookingId,
        (status: BookingStatus.checkedIn, id: bookingId),
        () => _bookingService.checkIn(bookingId, staffId: staffId),
      );

  Future<bool> checkOut(
    String bookingId, {
    String? staffId,
    required PaymentMethod paymentMethod,
  }) =>
      _mutate(
        bookingId,
        (status: BookingStatus.checkedOut, id: bookingId),
        () => _bookingService.checkOut(
          bookingId,
          staffId: staffId,
          paymentMethod: paymentMethod,
        ),
      );

  Future<bool> cancelBooking(String bookingId, {String? reason}) => _mutate(
        bookingId,
        (status: BookingStatus.cancelled, id: bookingId),
        () => _bookingService.cancelBooking(bookingId, reason: reason),
      );

  /// Runs [action], and on success patches the booking's status in both
  /// local lists so the UI updates without a full reload.
  Future<bool> _mutate(
    String bookingId,
    ({BookingStatus status, String id}) patch,
    Future<bool> Function() action,
  ) async {
    try {
      final success = await action();
      if (success) {
        _patchStatusInList(_roomBookings, bookingId, patch.status);
        for (final list in _dayBookingsByRoom.values) {
          _patchStatusInList(list, bookingId, patch.status);
        }
        notifyListeners();
      }
      return success;
    } catch (e) {
      print('Error mutating booking $bookingId in notifier: $e');
      rethrow;
    }
  }

  void _patchStatusInList(List<RoomBooking> list, String bookingId, BookingStatus status) {
    final index = list.indexWhere((b) => b.id == bookingId);
    if (index >= 0) {
      list[index] = list[index].copyWith(status: status);
    }
  }

  Future<bool> deleteBooking(String bookingId) async {
    try {
      final success = await _bookingService.deleteBooking(bookingId);
      if (success) {
        _roomBookings.removeWhere((b) => b.id == bookingId);
        for (final list in _dayBookingsByRoom.values) {
          list.removeWhere((b) => b.id == bookingId);
        }
        notifyListeners();
      }
      return success;
    } catch (e) {
      print('Error deleting booking in notifier: $e');
      rethrow;
    }
  }

  void clear() {
    _dayBookingsByRoom = {};
    _roomBookings = [];
    _monthOccupancy = {};
    notifyListeners();
  }
}