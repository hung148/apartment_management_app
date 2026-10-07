/// Address of a page inside a version-2 organization (U1):
/// `/org/{organizationId}/{section}/{page}/{recordId}?p={propertyId}`
/// (record: an open booking, room or tenant — U1 step 2).
/// Section, page and property are optional; the workspace fills in the first
/// one the person may use and rewrites the address.
class OrgLocation {
  final String organizationId;
  final String? section;
  final String? page;
  final String? propertyId;
  final String? record;
  const OrgLocation(
    this.organizationId, {
    this.section,
    this.page,
    this.propertyId,
    this.record,
  });

  static final _id = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
  static final _word = RegExp(r'^[A-Za-z]{1,40}$');

  /// Null when [address] is not an organization address or is malformed.
  static OrgLocation? parse(String? address) {
    if (address == null) return null;
    final uri = Uri.tryParse(address);
    if (uri == null) return null;
    final parts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (parts.length < 2 || parts.length > 5 || parts.first != 'org') {
      return null;
    }
    if (!_id.hasMatch(parts[1])) return null;
    final section = parts.length > 2 ? parts[2] : null;
    final page = parts.length > 3 ? parts[3] : null;
    final record = parts.length > 4 ? parts[4] : null;
    if (record != null && !_id.hasMatch(record)) return null;
    if ((section != null && !_word.hasMatch(section)) ||
        (page != null && !_word.hasMatch(page))) {
      return null;
    }
    final property = uri.queryParameters['p'];
    return OrgLocation(
      parts[1],
      section: section,
      page: page,
      propertyId: property != null && _id.hasMatch(property) ? property : null,
      record: record,
    );
  }

  String get address {
    final path = [
      'org',
      organizationId,
      ?section,
      if (section != null && page != null) page!,
      if (section != null && page != null && record != null) record!,
    ].join('/');
    return '/$path${propertyId != null ? '?p=$propertyId' : ''}';
  }

  @override
  bool operator ==(Object other) =>
      other is OrgLocation &&
      other.organizationId == organizationId &&
      other.section == section &&
      other.page == page &&
      other.propertyId == propertyId &&
      other.record == record;

  @override
  int get hashCode =>
      Object.hash(organizationId, section, page, propertyId, record);
}
