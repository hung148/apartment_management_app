import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/payment_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/rooms_model.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/payment/view_edit_payment_dialogs.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/searchable_select_field.dart';
import 'package:phan_mem_quan_ly_can_ho/services/payments_service.dart';
import 'calendar_screen_test.dart' show RoomsFake, BuildingsFake;
import 'tenant_editable_forms_test.dart' show EditableTenantFake;

class PaymentRoomsFake extends RoomsFake {
  @override
  Future<Room?> getRoomById(String id) async =>
      (await getBuildingRooms('o', 'b')).first;
}

class PaymentUpdatesFake implements PaymentService {
  Map<String, dynamic>? saved;
  @override
  Future<bool> updatePayment(String id, Map<String, dynamic> data) async {
    saved = data;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets('Payment edit searches existing tenants and saves their ID', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = PaymentUpdatesFake();
    final org = Organization(
      id: 'o',
      name: 'Test',
      createdBy: 'u',
      createdAt: DateTime(2026),
      inviteCode: '123',
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppTranslationsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => EditPaymentDialog(
                  organization: org,
                  payment: Payment(
                    id: 'p',
                    organizationId: 'o',
                    buildingId: 'b',
                    roomId: 'r',
                    type: PaymentType.rent,
                    amount: 100,
                    paidAmount: 0,
                    status: PaymentStatus.pending,
                    dueDate: DateTime.now().add(const Duration(days: 5)),
                    createdAt: DateTime.now(),
                  ),
                  buildingService: BuildingsFake(),
                  roomService: PaymentRoomsFake(),
                  tenantService: EditableTenantFake(),
                  paymentService: service,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text(AppTranslations(const Locale('en'))['payment_add_item_btn']), findsOneWidget);
    await tester.tap(find.byType(SearchableSelectField<String>));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('record-search')), 'Mai');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nguyễn Thị Mai'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(
        ElevatedButton,
        AppTranslations(const Locale('en'))['payment_btn_save'],
      ),
    );
    await tester.pumpAndSettle();
    expect(service.saved?['tenantId'], 'tenant');
    expect(service.saved?['tenantName'], 'Nguyễn Thị Mai');
    expect(tester.takeException(), isNull);
  });
}
