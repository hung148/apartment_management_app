import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/services/account_deletion_service.dart';

void main() {
  test('preview orders decisions first and reads candidates', () async {
    final service = AccountDeletionService(
      transport: (name, data) async {
        expect(name, 'deleteMyAccount');
        expect(data, {'action': 'preview'});
        return {
          'recentLogin': false,
          'organizations': [
            {'organizationId': 'w', 'name': 'Work', 'plan': 'leave', 'accessVersion': 2},
            {'organizationId': 's', 'name': 'Solo', 'plan': 'close', 'otherMembers': 2},
            {
              'organizationId': 't', 'name': 'Team', 'plan': 'decide', 'accessVersion': 2,
              'candidates': [
                {'userId': 'a', 'name': 'An'},
              ],
            },
            {'organizationId': 'x', 'name': 'Odd', 'plan': 'unknown'},
          ],
        };
      },
    );
    final p = await service.preview();
    expect(p.recentLogin, isFalse);
    expect(p.organizations.map((o) => o.organizationId), ['t', 's', 'x', 'w']);
    expect(p.organizations.first.candidates.single.name, 'An');
    expect(p.organizations[1].otherMembers, 2);
    expect(p.organizations[2].plan, 'leave', reason: 'unknown plans are treated as leave');
  });

  test('delete sends close or transfer decisions with one operation', () async {
    Map<String, dynamic>? sent;
    final service = AccountDeletionService(
      transport: (_, data) async {
        sent = data;
        return {'status': 'dataDeleted'};
      },
      newOperationId: () => 'op',
    );
    await service.delete({'t': 'a', 's': null});
    expect(sent, {
      'action': 'delete',
      'operationId': 'op',
      'decisions': {
        't': {'action': 'transfer', 'to': 'a'},
        's': {'action': 'close'},
      },
    });
  });
}
