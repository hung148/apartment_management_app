import 'package:phan_mem_quan_ly_can_ho/models/payment_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_money.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';

void main() {
  test('Building room labels preserve the room-number placeholder', () {
    expect(
      AppTranslations(
        const Locale('en'),
      ).textWithParams('building_room_label', {'n': '101'}),
      'Room 101',
    );
    expect(
      AppTranslations(
        const Locale('vi'),
      ).textWithParams('building_room_label', {'n': '101'}),
      'Phòng 101',
    );
  });
  test('USD retains cents and VND displays grouped whole units', () {
    expect(AppMoney.format(1234.56, 'USD'), '1,234.56 USD');
    expect(AppMoney.format(1234567, 'VND'), '1,234,567 VND');
    expect(AppMoney.excelFormat('USD'), '#,##0.00 "USD"');
  });
  test('Mixed currency totals remain separate', () {
    Payment invoice(String currency, double amount) => Payment(
      id: currency,
      organizationId: 'o',
      buildingId: 'b',
      roomId: 'r',
      type: PaymentType.rent,
      status: PaymentStatus.paid,
      amount: amount,
      paidAmount: amount,
      currency: currency,
      dueDate: DateTime(2026),
      createdAt: DateTime(2026),
    );
    final payments = [
      invoice('USD', 25.50),
      invoice('VND', 1000000),
      invoice('USD', 1.25),
    ];
    expect(AppMoney.totals(payments, (p) => p.paidAmount), {
      'USD': 26.75,
      'VND': 1000000,
    });
    expect(AppMoney.only(payments, 'USD').length, 2);
  });
  test('English and Vietnamese expose the same translation keys', () {
    final en = AppTranslations(const Locale('en')).translationKeys;
    final vi = AppTranslations(const Locale('vi')).translationKeys;
    expect(en.difference(vi), isEmpty, reason: 'Missing Vietnamese');
    expect(vi.difference(en), isEmpty, reason: 'Missing English');
  });
}
