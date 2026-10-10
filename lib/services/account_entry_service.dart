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

  /// One workplace, ready, nothing to settle first: the account check opens
  /// that workspace directly.
  bool get opensOneWorkplace =>
      mode != 'conflict' &&
      state == 'ready' &&
      !needsVerifiedEmail &&
      workplaces.length == 1 &&
      !waitingIds.contains(workplaces.single.id);

  /// What is kept on the device to open the workspace at once next time
  /// (2026-10-09, speed): only a check that opened one workplace.
  Map<String, dynamic>? toSaved() {
    if (!opensOneWorkplace) return null;
    final o = workplaces.single;
    return {
      'mode': mode,
      'id': o.id,
      'name': o.name,
      'createdBy': o.createdBy,
      'createdAt': o.createdAt.toIso8601String(),
      'accessVersion': o.accessVersion,
    };
  }

  /// The saved check, shown (locked) until the fresh one arrives. Null when
  /// there is none or it is not usable.
  static AccountEntry? fromSaved(Map<String, dynamic>? saved) {
    if (saved == null) return null;
    final id = saved['id'], mode = saved['mode'];
    if (id is! String || id.isEmpty || mode is! String) return null;
    if (!const {'normal', 'owner', 'staff'}.contains(mode)) return null;
    return AccountEntry(
      mode: mode,
      canCreate: false,
      workplaces: [
        Organization(
          id: id,
          name: saved['name'] as String? ?? '',
          createdBy: saved['createdBy'] as String? ?? '',
          createdAt:
              DateTime.tryParse(saved['createdAt'] as String? ?? '') ??
              DateTime(2000),
          inviteCode: '',
          accessVersion: saved['accessVersion'] as int? ?? 2,
        ),
      ],
    );
  }
}

/// No cached grants: entry and every refresh recheck the server after claiming
/// invitations. Fail closed when the backend cannot supply the account policy.
class AccountEntryService {
  final TeamTransport transport;
  AccountEntryService({required this.transport});
  DateTime? _lastClaim;
  bool _needsVerifiedEmail = false;
  Future<AccountEntry> load() async {
    final claimDue =
        _lastClaim == null ||
        DateTime.now().difference(_lastClaim!).inSeconds >= 15;
    bool joined(Map<String, dynamic> claimed) =>
        (claimed['results'] as List? ?? const []).any(
          (r) => r is Map && r['status'] == 'joined',
        );
    final listed = await _list();
    final info = listed.invitations;
    if (info != null) {
      // Speed (2026-10-09): the list says whether invitations wait to be
      // claimed; only then is the claim asked for (usually one call, not two).
      // A claim that joined a new organization lists again. A failed claim
      // still fails the entry.
      _needsVerifiedEmail = info['needsVerifiedEmail'] == true;
      if (info['pending'] == true && claimDue) {
        final claimed = await transport('claimMyInvitations', {});
        _lastClaim = DateTime.now();
        _needsVerifiedEmail = claimed['needsVerifiedEmail'] == true;
        if (joined(claimed)) return (await _list()).entry(_needsVerifiedEmail);
      }
      return listed.entry(_needsVerifiedEmail);
    }
    // A server that does not say: claim every time, as before.
    if (!claimDue) return listed.entry(_needsVerifiedEmail);
    final claimed = await transport('claimMyInvitations', {});
    _needsVerifiedEmail = claimed['needsVerifiedEmail'] == true;
    _lastClaim = DateTime.now();
    if (joined(claimed)) return (await _list()).entry(_needsVerifiedEmail);
    return listed.entry(_needsVerifiedEmail);
  }

  /// All pages of the organization list. The verified-email flag comes from
  /// the claim, which may finish later, so it is filled in at the end.
  /// [invitations]: what the first page says about invitations waiting to
  /// be claimed (null from a server that does not say).
  Future<
    ({
      AccountEntry Function(bool needsVerifiedEmail) entry,
      Map<String, dynamic>? invitations,
    })
  >
  _list() async {
    String? cursor;
    String? mode;
    String state = 'ready';
    String? staffConflict;
    bool canCreate = false;
    bool canMerge = false;
    final workplaces = <Organization>[];
    final waiting = <String>{};
    final seen = <String>{};
    Map<String, dynamic>? invitations;
    do {
      final page = await transport('listMyOrganizations', {'cursor': ?cursor});
      if (cursor == null && page['invitations'] is Map) {
        invitations = Map<String, dynamic>.from(page['invitations'] as Map);
      }
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
    final finalMode = mode;
    return (
      invitations: invitations,
      entry: (bool needsVerifiedEmail) => AccountEntry(
        mode: finalMode,
        state: state,
        canCreate: canCreate,
        canMerge: canMerge,
        workplaces: workplaces,
        waitingIds: waiting,
        staffConflict: staffConflict,
        // Claiming an invitation requires verified email. Existing ownership is
        // established independently by the server's account policy and membership.
        needsVerifiedEmail: needsVerifiedEmail && finalMode != 'owner',
      ),
    );
  }
}
