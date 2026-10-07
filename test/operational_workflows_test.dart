import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/operational_widgets.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/lease_lifecycle_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/invoice_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/property_layout_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/booking_workspace_screen.dart';
import 'tenant_lease_test.dart' show store;
import 'team_review_test.dart' show mountReview;
import 'room_rates_test.dart' show press;
import 'room_booking_settings_test.dart' show enter;

void main() {
  test(
    'operational money accepts zero fees and exact cents but rejects excess precision',
    () {
      expect(operationalMoney('0', 'VND'), 0);
      expect(operationalMoney('12.34', 'USD'), 1234);
      expect(operationalMoney('12.345', 'USD'), isNull);
      expect(operationalMoney('-1', 'VND'), isNull);
      expect(operationalMoney('1.2', 'VND'), isNull);
    },
  );
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('lease contract end is amended without freeing occupied room', (
    tester,
  ) async {
    final s = store();
    await mountReview(
      tester,
      LeaseLifecycleScreen(
        organizationId: 'preview',
        buildingId: 'riverside',
        tenantId: 'tenant-anh',
        service: s.service,
        onBack: () {},
      ),
    );
    await enter(tester, 'lease-ops-date', '2026-12-31');
    await enter(tester, 'lease-ops-reason', 'Signed extension');
    await press(tester, 'Review change');
    await press(tester, 'Confirm lease change');
    expect(s.tenants.first['contractEndLocalDate'], '2026-12-31');
    expect(s.tenants.first['status'], 'active');
    expect(s.leaseHistory['tenant-anh']!.length, 1);
  });
  testWidgets('invoice review creates rent once and fee edit preserves rent', (
    tester,
  ) async {
    final s = store();
    await mountReview(
      tester,
      InvoiceScreen(
        organizationId: 'preview',
        buildingId: 'riverside',
        accountId: 'owner',
        service: s.service,
        onBack: () {},
      ),
    );
    await press(tester, 'Create new');
    await enter(tester, 'ops-start', '2026-10-01');
    await enter(tester, 'ops-end', '2026-11-01');
    await enter(tester, 'ops-due', '2026-10-05');
    await enter(tester, 'ops-reason', 'October agreement');
    await press(tester, 'Review calculation');
    await press(tester, 'Confirm and save');
    expect(s.operationalInvoices.length, 1);
    expect(s.operationalInvoices.single['amountMinor'], 1500000);
    await enter(tester, 'ops-taxAmount', '100');
    await enter(tester, 'ops-reason', 'Tax adjustment');
    await press(tester, 'Save');
    expect(s.operationalInvoices.single['totalMinor'], 1500100);
    expect(s.operationalInvoices.single['amountMinor'], 1500000);
    await press(tester,'Financial history');
    expect(find.text('Tax adjustment'),findsOneWidget);
    expect(find.text('October agreement'),findsOneWidget);
  });
  testWidgets('property defaults save without altering existing rooms', (
    tester,
  ) async {
    final s = store(), before = Map.of(store().rooms.first);
    await mountReview(
      tester,
      PropertyLayoutScreen(
        organizationId: 'preview',
        buildingId: 'riverside',
        service: s.service,
        onBack: () {},
      ),
    );
    await enter(tester, 'ops-floors', '2');
    await enter(tester, 'ops-roomPrefix', 'R');
    await enter(tester, 'ops-roomType', 'Studio');
    await enter(tester, 'ops-roomArea', '35.5');
    await enter(tester, 'ops-floorRoomCounts', '2,3');
    await press(tester, 'Save');
    expect(s.buildings.first['floorRoomCounts'], [2, 3]);
    expect(s.rooms.first, before);
  });
  testWidgets(
    'booking quote creates and collects without duplicating booking',
    (tester) async {
      final s = store();
      s.rooms.last.addAll({
        'rentalMode': 'hourly',
        'hourlyPrice': 100000,
        'currency': 'VND',
      });
      await mountReview(
        tester,
        BookingWorkspaceScreen(
          organizationId: 'preview',
          buildingId: 'riverside',
          accountId: 'owner',
          service: s.service,
          onBack: () {},
        ),
      );
      await press(tester, 'New booking');
      await enter(tester, 'ops-guest', 'Guest family');
      await enter(tester, 'ops-startLocal', '2026-10-01 09:00');
      await enter(tester, 'ops-endLocal', '2026-10-01 11:00');
      await press(tester, 'Review calculation');
      await press(tester, 'Confirm and save');
      expect(s.operationalBookings.single['totalPrice'], 200000);
      // 2026-10-04: "Collect" sits in the money section.
      await press(tester, 'Collect');
      await enter(tester, 'ops-reason', 'Receipt');
      await enter(tester, 'ops-amount', '50000');
      await press(tester, 'Confirm and save');
      expect(s.operationalBookings.single['paidAmount'], 50000);
    },
  );
}
