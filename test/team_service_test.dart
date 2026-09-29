import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';

void main() {
  test(
    'pagination sends selected organization and server cursor without mixing pages',
    () async {
      final calls = <Map<String, dynamic>>[];
      final service = TeamService(
        transport: (name, data) async {
          expect(name, 'readTeam');
          calls.add(data);
          return {
            'records': [
              {'id': data['cursor'] ?? 'first'},
            ],
            'nextCursor': data['cursor'] == null ? 'next' : null,
          };
        },
      );
      final first = await service.page('a', TeamView.staff, limit: 1);
      final second = await service.page(
        'a',
        TeamView.staff,
        limit: 1,
        cursor: first.nextCursor,
      );
      expect(first.records.single['id'], 'first');
      expect(second.records.single['id'], 'next');
      expect(second.nextCursor, isNull);
      await service.page('b', TeamView.staff);
      expect(calls.last['organizationId'], 'b');
      expect(calls.last.containsKey('cursor'), isFalse);
    },
  );
  test(
    'own access represents revoked and absent memberships accurately',
    () async {
      final service = TeamService(
        transport: (_, data) async => {
          'record': data['organizationId'] == 'a'
              ? {'status': 'revoked'}
              : null,
        },
      );
      expect((await service.myAccess('a'))!['status'], 'revoked');
      expect(await service.myAccess('b'), isNull);
    },
  );
  test(
    'retry retains exact immutable payload and operation id after uncertain failure',
    () async {
      final calls = <Map<String, dynamic>>[];
      final service = TeamService(
        transport: (_, data) async {
          calls.add(data);
          if (calls.length == 1) throw StateError('network timeout');
          return {'status': 'active'};
        },
      );
      final fields = <String, dynamic>{
        'access': {'role': 'receptionist'},
      };
      final operation = service.prepare('org', TeamAction.invite, fields);
      (fields['access'] as Map)['role'] = 'owner';
      (operation.payload['access'] as Map)['role'] = 'administrator';
      await expectLater(service.execute(operation), throwsStateError);
      expect(await service.execute(operation), {'status': 'active'});
      expect(calls[0], calls[1]);
      expect((calls[1]['access'] as Map)['role'], 'receptionist');
      expect(calls[1]['operationId'], operation.id);
      expect(
        service.prepare('org', TeamAction.invite, fields).id,
        isNot(operation.id),
      );
    },
  );
  test('reserved fields and invalid pages cannot reach transport', () async {
    final service = TeamService(
      transport: (_, _) async => throw StateError('must not call'),
    );
    for (final key in ['organizationId', 'action', 'operationId']) {
      expect(
        () => service.prepare('a', TeamAction.invite, {key: 'bad'}),
        throwsArgumentError,
      );
    }
    await expectLater(
      service.page('a', TeamView.myAccess),
      throwsArgumentError,
    );
    await expectLater(
      service.page('a', TeamView.staff, limit: 101),
      throwsArgumentError,
    );
    await expectLater(
      service.page('a', TeamView.staff, actorId: 'b'),
      throwsArgumentError,
    );
  });
  test(
    'authorization errors propagate without returning cached records',
    () async {
      var revoked = false;
      final service = TeamService(
        transport: (_, _) async {
          if (revoked) throw StateError('permission-denied');
          return {
            'records': [
              {'id': 'private'},
            ],
            'nextCursor': null,
          };
        },
      );
      expect((await service.page('a', TeamView.staff)).records.length, 1);
      revoked = true;
      await expectLater(service.page('a', TeamView.staff), throwsStateError);
    },
  );
}

