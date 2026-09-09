import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/models/rooms_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/booking_model.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_localizations.dart';

void main() {
  test('Language selects the default currency for new records', () {
    expect(AppTranslations(const Locale('en', 'US')).defaultCurrency, 'USD');
    expect(AppTranslations(const Locale('vi', 'VN')).defaultCurrency, 'VND');
  });
  test('Room currency round-trips; legacy data retains VND', () {
    final room = Room(
      id: 'room',
      organizationId: 'org',
      buildingId: 'building',
      roomNumber: '101',
      roomType: 'Standard',
      area: 20,
      createdAt: DateTime(2026),
      currency: 'USD',
      hourlyPrice: 12.50,
    );
    expect(Room.fromMap(room.id, room.toMap()).currency, 'USD');
    final legacy = room.toMap()..remove('currency');
    expect(Room.fromMap(room.id, legacy).currency, 'VND');
  });
  test('Booking currency survives persistence and status updates', () {
    final booking = RoomBooking(
      id: 'booking',
      organizationId: 'org',
      buildingId: 'building',
      roomId: 'room',
      guestName: 'Guest',
      guestPhone: '',
      startTime: DateTime(2026, 9, 8),
      endTime: DateTime(2026, 9, 9),
      totalPrice: 123.45,
      currency: 'USD',
      createdAt: DateTime(2026),
    );
    final restored = RoomBooking.fromMap(booking.id, booking.toMap());
    expect(restored.currency, 'USD');
    expect(restored.totalPrice, 123.45);
    expect(restored.copyWith(status: BookingStatus.confirmed).currency, 'USD');
    expect(
      RoomBooking.fromMap(
        booking.id,
        booking.toMap()..remove('currency'),
      ).currency,
      'VND',
    );
  });
}
