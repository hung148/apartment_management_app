import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/services/payment_command_service.dart';

void main() {
  test(
    'uncertain collection retry keeps its ID and payload, without local time',
    () async {
      final calls = <Map<String, dynamic>>[];
      final service = PaymentCommandService(
        transport: (name, data) async {
          expect(name, 'mutateStandalonePayment');
          calls.add(Map.of(data));
          data['amountMinor'] =
              999; // A transport cannot mutate the saved command.
          if (calls.length == 1) {
            throw StateError('connection lost after commit');
          }
          return {
            'status': 'partial',
            'paidMinor': 40,
            'recordedAt': '2026-09-26T12:34:56.000Z',
          };
        },
      );
      final operation = service.collect(
        organizationId: 'org',
        paymentId: 'invoice',
        amountMinor: 40,
        paymentMethod: 'cash',
      );
      operation.payload['paidAt'] = '1900-01-01';
      await expectLater(service.execute(operation), throwsStateError);
      final result = await service.execute(operation);
      expect(result['paidMinor'], 40);
      expect(calls[0], calls[1]);
      expect(calls[0], {
        'organizationId': 'org',
        'paymentId': 'invoice',
        'amountMinor': 40,
        'action': 'collect',
        'paymentMethod': 'cash',
        'operationId': operation.id,
      });
    },
  );

  test(
    'refund retains reason and minor units; distinct intents have distinct IDs',
    () async {
      final service = PaymentCommandService(transport: (_, data) async => data);
      PaymentOperation refund() => service.refund(
        organizationId: 'org',
        paymentId: 'invoice',
        amountMinor: 29,
        reason: 'Duplicate charge',
      );
      final first = refund();
      expect(refund().id, isNot(first.id));
      expect(await service.execute(first), {
        'organizationId': 'org',
        'paymentId': 'invoice',
        'amountMinor': 29,
        'action': 'refund',
        'reason': 'Duplicate charge',
        'operationId': first.id,
      });
    },
  );

  test(
    'denied and unavailable responses propagate without reporting local success',
    () async {
      for (final message in ['permission-denied', 'unavailable']) {
        var attempts = 0;
        final service = PaymentCommandService(
          transport: (_, data) async {
            attempts++;
            throw StateError(message);
          },
        );
        final operation = service.collect(
          organizationId: 'org',
          paymentId: 'invoice',
          amountMinor: 1,
          paymentMethod: 'cash',
        );
        await expectLater(service.execute(operation), throwsStateError);
        expect(attempts, 1);
      }
    },
  );
}
