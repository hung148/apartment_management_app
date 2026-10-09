import '../models/organization_model.dart';
import 'team_service.dart';

class AccountEntry {
  final String mode;
  final String state;
  final String? staffConflict;
  final bool needsVerifiedEmail;
  final bool canCreate;
  final bool canMerge;
  final List<Organization> workplaces;
  final Set<String> waitingIds;
  const AccountEntry({
    required this.mode,
    this.state = 'ready',
    required this.canCreate,
    this.canMerge = false,
    required this.workplaces,
    this.waitingIds = const {},
    this.staffConflict,
    this.needsVerifiedEmail = false,
  });
  bool get staffOnly => mode == 'staff';
}

/// No cached grants: entry and every refresh recheck the server after claiming
/// invitations. Fail closed when the backend cannot supply the account policy.
class AccountEntryService {
  final TeamTransport transport;
  AccountEntryService({required this.transport});
  DateTime? _lastClaim;
  bool _needsVerifiedEmail = false;
  Future<AccountEntry> load() async {
    if (_lastClaim == null ||
        DateTime.now().difference(_lastClaim!).inSeconds >= 15) {
      final claimed = await transport('claimMyInvitations', {});
      _needsVerifiedEmail = claimed['needsVerifiedEmail'] == true;
      _lastClaim = DateTime.now();
    }
    String? cursor;
    String? mode;
    String state = 'ready';
    String? staffConflict;
    bool canCreate = false;
    bool canMerge = false;
    final workplaces = <Organization>[];
    final waiting = <String>{};
    final seen = <String>{};
    do {
      final page = await transport('listMyOrganizations', {'cursor': ?cursor});
      final policy = page['accountPolicy'];
      if (policy is! Map ||
          !const {
            'normal',
            'owner',
            'staff',
            'conflict',
          }.contains(policy['mode'])) {
        throw StateError('Account policy unavailable');
      }
      if (mode != null && mode != policy['mode'])
        throw StateError('Account policy changed');
      mode = policy['mode'] as String;
      state = policy['entryState'] as String? ?? 'ready';
      staffConflict ??= policy['staffConflict'] as String?;
      canCreate = policy['canCreate'] == true;
      canMerge = policy['canMerge'] == true;
      for (final raw in page['records'] as List) {
        final r = Map<String, dynamic>.from(raw as Map);
        final id = r['id'] as String;
        if (r['waiting'] == true) waiting.add(id);
        workplaces.add(
          Organization(
            id: id,
            name: r['name'] as String? ?? '',
            createdBy: r['createdBy'] as String? ?? '',
            createdAt:
                DateTime.tryParse(r['createdAt'] as String? ?? '') ??
                DateTime(2000),
            updatedAt: DateTime.tryParse(r['updatedAt'] as String? ?? ''),
            inviteCode: '',
            accessVersion: r['accessVersion'] as int? ?? 1,
          ),
        );
      }
      cursor = page['nextCursor'] as String?;
      if (cursor != null && !seen.add(cursor))
        throw StateError('Repeated directory page');
    } while (cursor != null);
    return AccountEntry(
      mode: mode,
      state: state,
      canCreate: canCreate,
      canMerge: canMerge,
      workplaces: workplaces,
      waitingIds: waiting,
      staffConflict: staffConflict,
      // Claiming an invitation requires verified email. Existing ownership is
      // established independently by the server's account policy and membership.
      needsVerifiedEmail: _needsVerifiedEmail && mode != 'owner',
    );
  }
}
