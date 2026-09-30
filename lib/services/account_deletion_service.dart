import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import 'team_service.dart' show TeamTransport;

/// Someone who can take over an organization when its owner leaves.
class DeletionCandidate {
  final String userId;
  final String name;
  const DeletionCandidate(this.userId, this.name);
}

/// What deleting the account does to one organization.
/// plan: 'leave' (you are removed), 'close' (closes for everyone, kept 30
/// days), or 'decide' (owner chooses: hand over to a candidate, or close).
class DeletionPlanItem {
  final String organizationId;
  final String name;
  final int accessVersion;
  final String plan;
  final int otherMembers;
  final List<DeletionCandidate> candidates;
  const DeletionPlanItem({
    required this.organizationId,
    required this.name,
    required this.accessVersion,
    required this.plan,
    required this.otherMembers,
    required this.candidates,
  });
}

class DeletionPreview {
  final bool recentLogin;
  final List<DeletionPlanItem> organizations;
  const DeletionPreview(this.recentLogin, this.organizations);
}

/// Server-side account deletion. The server removes memberships, hands over
/// or closes owned organizations and deletes personal records; the app then
/// deletes the Firebase login itself.
class AccountDeletionService {
  final TeamTransport _transport;
  final String Function() _newOperationId;
  AccountDeletionService({TeamTransport? transport, String Function()? newOperationId})
      : _transport = transport ?? _firebase,
        _newOperationId = newOperationId ?? (() => const Uuid().v4());

  static Future<Map<String, dynamic>> _firebase(String callable, Map<String, dynamic> data) async {
    final response = await FirebaseFunctions.instance.httpsCallable(callable).call(data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<DeletionPreview> preview() async {
    final data = await _transport('deleteMyAccount', {'action': 'preview'});
    final items = <DeletionPlanItem>[
      for (final raw in (data['organizations'] as List? ?? const []))
        if (raw is Map && raw['organizationId'] is String)
          DeletionPlanItem(
            organizationId: raw['organizationId'] as String,
            name: raw['name'] as String? ?? '',
            accessVersion: raw['accessVersion'] is int ? raw['accessVersion'] as int : 1,
            plan: const {'leave', 'close', 'decide'}.contains(raw['plan']) ? raw['plan'] as String : 'leave',
            otherMembers: raw['otherMembers'] is int ? raw['otherMembers'] as int : 0,
            candidates: [
              for (final c in (raw['candidates'] as List? ?? const []))
                if (c is Map && c['userId'] is String)
                  DeletionCandidate(c['userId'] as String, c['name'] as String? ?? ''),
            ],
          ),
    ];
    // Decisions first, then closes, then plain leaves; names alphabetically.
    const order = {'decide': 0, 'close': 1, 'leave': 2};
    items.sort((a, b) {
      final byPlan = order[a.plan]!.compareTo(order[b.plan]!);
      return byPlan != 0 ? byPlan : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return DeletionPreview(data['recentLogin'] == true, items);
  }

  /// [decisions]: organizationId -> null to close, or the userId to hand over to.
  /// Only 'decide' organizations need an entry.
  Future<Map<String, dynamic>> delete(Map<String, String?> decisions, {String? operationId}) {
    return _transport('deleteMyAccount', {
      'action': 'delete',
      'operationId': operationId ?? _newOperationId(),
      'decisions': {
        for (final e in decisions.entries)
          e.key: e.value == null ? {'action': 'close'} : {'action': 'transfer', 'to': e.value},
      },
    });
  }
}
