import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phan_mem_quan_ly_can_ho/services/exchange_rate_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/organization_money.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_money.dart';

class PendingRates extends ExchangeRateService {
  final requested = Completer<void>();
  final result = Completer<ExchangeRateSnapshot>();
  @override
  Future<ExchangeRateSnapshot?> cached() async => null;
  @override
  Future<ExchangeRateSnapshot> refresh() {
    requested.complete();
    return result.future;
  }
}

void main() {
  test('organization rates retain the server snapshot identity through selection and offline cache', () async {
    SharedPreferences.setMockInitialValues({});
    final money = OrganizationMoney.shared;
    money.clear();
    addTearDown(money.clear);
    final id = List.filled(64, 'a').join();
    final calls = <String>[];
    await money.load('o', TeamService(transport: (_, data) async {
      calls.add(data['action'] as String);
      return data['action'] == 'readCurrency'
          ? {'currency': 'USD', 'revision': 0, 'canChange': true}
          : {'id': id, 'perUsd': {'USD': '1', 'VND': '25000'}, 'dates': {'VND': '2026-10-08'}};
    }));
    expect(calls, ['readCurrency', 'readRates']);
    final pinned = money.forOrganization('o')!;
    expect(pinned.snapshotId, id);
    expect(pinned.convertMinor(5000000, 'VND', 'USD'), 20000);
    money.select('o', 'VND');
    expect(money.forOrganization('o')?.snapshotId, id);
    expect(pinned.currency, 'USD');
    final provider = ExchangeRateService();
    addTearDown(provider.dispose);
    expect((await provider.cached())?.snapshotId, id);
  });
  test('revoked currency access clears organization display and report preferences', () async {
    final money=OrganizationMoney.shared;
    addTearDown(money.clear);
    money.configure('o','USD',ExchangeRateSnapshot(perUsd:{'USD':1,'VND':25000},dates:{}));
    money.activate('o');
    await expectLater(money.load('o',TeamService(transport:(_,_) async {
      throw FirebaseFunctionsException(code:'permission-denied',message:'Revoked');
    })),throwsA(isA<FirebaseFunctionsException>()));
    expect(money.forOrganization('o'),isNull);
    expect(AppMoney.displayConversion,isNull);
    expect(ReportingMoney.format('o',25000,'VND'),'25,000 VND');
  });
  test('offline rate refresh retains server currency and exposes retry state', () async {
    final money = OrganizationMoney.shared, provider = PendingRates();
    money.clear();
    addTearDown(money.clear);
    addTearDown(provider.dispose);
    final pending = money.load('o', TeamService(transport: (_, _) async => {
      'currency': 'USD', 'revision': 0, 'canChange': true,
    }), exchange: provider);
    final failure = expectLater(pending, throwsStateError);
    await provider.requested.future;
    expect(money.isLoading('o'), isTrue);
    expect(money.forOrganization('o')?.currency, 'USD');
    provider.result.completeError(StateError('offline'));
    await failure;
    expect(money.isLoading('o'), isFalse);
    expect(money.refreshFailed('o'), isTrue);
    expect(money.forOrganization('o')!.canConvert('VND'), isFalse);
  });
  test('selection before rates load retains the selected currency', () {
    final money = OrganizationMoney.shared;
    money.clear();
    addTearDown(money.clear);
    money.activate('o');
    money.select('o', 'USD');
    expect(money.forOrganization('o')?.currency, 'USD');
    expect(AppMoney.displayConversion?.currency, 'USD');
    expect(AppMoney.format(25000, 'VND'), '25,000 VND');
  });
  for (final clear in [false, true]) {
    test('late rate load cannot undo ${clear ? 'sign-out' : 'currency change'}', () async {
      final money = OrganizationMoney.shared;
      final provider = PendingRates();
      addTearDown(money.clear);
      addTearDown(provider.dispose);
      final rates = ExchangeRateSnapshot(perUsd: {'USD': 1, 'VND': 25000}, dates: {});
      money.configure('o', 'USD', rates);
      money.activate('o');
      final pending = money.load('o', TeamService(transport: (_, __) async => {
        'currency': 'USD', 'revision': 0, 'canChange': true,
      }), exchange: provider);
      await provider.requested.future;
      if (clear) {
        money.clear();
      } else {
        money.select('o', 'VND');
      }
      provider.result.complete(rates);
      await pending;
      expect(money.forOrganization('o')?.currency, clear ? isNull : 'VND');
      expect(AppMoney.displayConversion?.currency, clear ? isNull : 'VND');
      expect(ReportingMoney.format('o', 1, 'USD'), clear ? '1.00 USD' : '≈ 25,000 VND');
    });
  }
}
