import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/services/organization_settings_service.dart';

void main() {
  test('read maps private details, role and allowed actions', () async {
    final service = OrganizationSettingsService(
      transport: (name, data) async {
        expect(name, 'organizationSettings');
        expect(data, {'action': 'read', 'organizationId': 'org'});
        return {
          'id': 'org', 'accessVersion': 2, 'name': 'Sunrise',
          'createdBy': 'owner', 'createdAt': '2026-09-01T00:00:00.000Z',
          'bankAccountNumber': '123', 'role': 'administrator',
          'canManage': true, 'canClose': false, 'canLeave': true,
        };
      },
    );
    final s = await service.read('org');
    expect(s.organization.name, 'Sunrise');
    expect(s.organization.accessVersion, 2);
    expect(s.organization.bankAccountNumber, '123');
    expect(s.organization.createdAt, DateTime.utc(2026, 9, 1));
    expect(s.organization.inviteCode, isEmpty);
    expect([s.role, s.canManage, s.canClose, s.canLeave],
        ['administrator', true, false, true]);
  });

  test('read tolerates a missing creation date instead of failing', () async {
    final service = OrganizationSettingsService(
      transport: (_, _) async => {'name': 'Migrated', 'role': 'receptionist'},
    );
    final s = await service.read('org');
    expect(s.organization.createdAt.millisecondsSinceEpoch, 0);
    expect([s.canManage, s.canClose, s.canLeave], [false, false, false]);
  });

  test('update always sends all eight fields, trimmed, with a new operation',
      () async {
    final calls = <Map<String, dynamic>>[];
    var n = 0;
    final service = OrganizationSettingsService(
      transport: (_, data) async {
        calls.add(data);
        return {};
      },
      newOperationId: () => 'op${n++}',
    );
    await service.update('org', {'name': ' Sunrise ', 'bankName': null});
    await service.update('org', {'name': 'Sunrise'});
    final fields = calls.first['fields'] as Map;
    expect(fields.keys.toSet(), OrganizationSettingsService.fieldNames.toSet());
    expect(fields['name'], 'Sunrise');
    expect(fields['bankName'], '');
    expect(fields['address'], '');
    expect([calls[0]['operationId'], calls[1]['operationId']], ['op0', 'op1']);
    expect(() => service.update('org', {'createdBy': 'me'}), throwsArgumentError);
  });

  test('leave and close send exact commands and surface server errors',
      () async {
    final calls = <Map<String, dynamic>>[];
    final service = OrganizationSettingsService(
      transport: (_, data) async {
        calls.add(data);
        if (data['action'] == 'leave') throw Exception('org_owner_cannot_leave');
        return {'status': 'closed'};
      },
      newOperationId: () => 'op',
    );
    await expectLater(service.leave('org'), throwsException);
    await service.close('org', 'Sunrise');
    expect(calls.last, {
      'action': 'close', 'organizationId': 'org',
      'operationId': 'op', 'confirmName': 'Sunrise',
    });
  });

  test('copy preview keeps counts; copy reuses the caller\'s operation ID',
      () async {
    final calls = <Map<String, dynamic>>[];
    final service = OrganizationSettingsService(
      transport: (_, data) async {
        calls.add(data);
        return data['action'] == 'copyPreview'
            ? {'buildings': 2, 'rooms': 10, 'tenants': 7, 'payments': 30}
            : {'status': 'copied'};
      },
      newOperationId: () => 'fixed',
    );
    final preview = await service.copyPreview('src', 'dst');
    expect(preview, {'buildings': 2, 'rooms': 10, 'tenants': 7, 'payments': 30});
    final op = service.newOperation();
    await service.copy('src', 'dst', operationId: op);
    await service.copy('src', 'dst', operationId: op);
    expect(calls[1], {
      'action': 'copy', 'organizationId': 'src',
      'operationId': 'fixed', 'targetOrganizationId': 'dst',
    });
    expect(calls[2]['operationId'], calls[1]['operationId']);
  });

  test('closed list is sorted by removal date and restore sends its command',
      () async {
    final calls = <Map<String, dynamic>>[];
    final service = OrganizationSettingsService(
      transport: (_, data) async {
        calls.add(data);
        return data['action'] == 'closedList'
            ? {
                'records': [
                  {'id': 'b', 'name': 'Later', 'closedAt': '2026-09-20T00:00:00.000Z', 'purgeAfter': '2026-10-20T00:00:00.000Z'},
                  {'id': 'a', 'name': 'Sooner', 'closedAt': '2026-09-10T00:00:00.000Z', 'purgeAfter': '2026-10-10T00:00:00.000Z'},
                ],
              }
            : {'status': 'restored'};
      },
      newOperationId: () => 'op',
    );
    final list = await service.closedList();
    expect(list.map((o) => o.name), ['Sooner', 'Later']);
    expect(list.first.daysLeft(DateTime.utc(2026, 9, 29)), 11);
    expect(list.first.daysLeft(DateTime.utc(2026, 12, 1)), 0);
    await service.restore('a');
    expect(calls.last, {'action': 'restore', 'organizationId': 'a', 'operationId': 'op'});
  });
  test('create sends all eight fields, trimmed, with the caller\'s operation', () async {
    final sent = <Map<String, dynamic>>[];
    final service = OrganizationSettingsService(
      transport: (name, data) async {
        expect(name, 'organizationSettings');
        sent.add(data);
        return {'organizationId': 'newOrg'};
      },
    );
    final id = await service.create({'name': ' Daily+ ', 'phone': null}, operationId: 'op1');
    expect(id, 'newOrg');
    expect(sent.single, {
      'action': 'create', 'operationId': 'op1',
      'fields': {
        'name': 'Daily+', 'address': '', 'phone': '', 'email': '',
        'taxCode': '', 'bankName': '', 'bankAccountNumber': '', 'bankAccountName': '',
      },
    });
    expect(() => service.create({'createdBy': 'x'}, operationId: 'op2'), throwsArgumentError);
  });
}
