import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/services/exchange_rate_service.dart';
import 'package:phan_mem_quan_ly_can_ho/models/payment_model.dart';

void main() {
  final rates = ExchangeRateSnapshot.fromRows([
    {'base':'USD','quote':'VND','rate':25000,'date':'2026-09-08'},
    {'base':'USD','quote':'EUR','rate':0.9,'date':'2026-09-08'},
  ]);
  test('cross currency conversion and identity preserve value', () {
    expect(rates.convert(25000, 'VND', 'USD'), 1);
    expect(rates.convert(25000, 'VND', 'EUR'), closeTo(0.9, 1e-10));
    expect(rates.convert(12, 'XYZ', 'XYZ'), 12);
    expect(() => rates.convert(12, 'XYZ', 'USD'), throwsStateError);
  });
  test('report projection converts all monetary fields and preserves units and original', () {
    final original = Payment(id:'p',organizationId:'o',buildingId:'b',roomId:'r',
      type:PaymentType.rent,status:PaymentStatus.partial,amount:2500000,
      paidAmount:1250000,currency:'VND',createdAt:DateTime(2026),dueDate:DateTime(2026),
      rentUnitPrice:250000,rentUnitQuantity:10,
      electricityStartReading:100,electricityEndReading:120,electricityPricePerUnit:2500,
      waterStartReading:10,waterEndReading:15,waterPricePerUnit:5000,
      internetFee:100000,cableTVFee:25000,hotWaterFee:50000,hotWaterPercent:10,
      managementFee:75000,taxAmount:25000,lateFee:50000);
    final converted = rates.project(original, 'USD');
    expect(converted.amount, 100);
    expect(converted.paidAmount, 50);
    expect(converted.rentUnitPrice, 10);
    expect(converted.rentUnitQuantity, 10);
    expect(converted.electricityStartReading, 100);
    expect(converted.electricityPricePerUnit, 0.1);
    expect(converted.waterPricePerUnit, 0.2);
    expect(converted.internetFee, 4);
    expect(converted.cableTVFee, 1);
    expect(converted.hotWaterFee, 2);
    expect(converted.hotWaterPercent, 10);
    expect(converted.managementFee, 3);
    expect(converted.taxAmount, 1);
    expect(converted.lateFee, 2);
    expect(converted.totalWithAllFees, closeTo(original.totalWithAllFees / 25000, 1e-8));
    expect(converted.remainingAmount, closeTo(original.remainingAmount / 25000, 1e-8));
    expect(original.currency, 'VND');
    expect(original.amount, 2500000);
  });
  test('invalid reference rates cannot enter cache', () {
    expect(() => ExchangeRateSnapshot.fromRows([
      {'base':'USD','quote':'VND','rate':0,'date':'2026-09-08'},
    ]), throwsFormatException);
  });
}
