// Preview (widget tests): building prices (PRICE_DEFAULTS.md, 2026-10-26) —
// a small copy of functions/building_prices.js. Rooms keep their prices in
// major units (as in the store); the building keeps `defaultPrices` in minor
// units, `electricityPriceMinor`, and the rooms' `priceFollows`.
part of 'team_preview_store.dart';

const _priceKinds = ['roomPrice', 'nightlyPrice'];

extension BuildingPricesPreview on TeamPreviewStore {
  int _priceScale(Object? currency) => currency == 'USD' ? 100 : 1;

  Map<String, dynamic> previewDefaults(Map b) {
    final p = (b['defaultPrices'] as Map?) ?? const {};
    return {
      'roomPriceMinor': p['roomPriceMinor'],
      'nightlyPriceMinor': p['nightlyPriceMinor'],
      'waterMonthMinor': p['waterMonthMinor'],
      'waterBasis': p['waterBasis'] == 'room' ? 'room' : 'person',
    };
  }

  Map<String, bool> previewFollows(Map room) {
    final f = (room['priceFollows'] as Map?) ?? const {};
    return {for (final k in _priceKinds) k: f[k] == true};
  }

  /// A new room left without a price takes the building's (2026-10-28).
  Map<String, dynamic> previewWithBuildingPrices(Map ratesMinor, Map defaults) => {
    ...ratesMinor,
    for (final k in _priceKinds)
      if (ratesMinor[k] == null && defaults['${k}Minor'] != null)
        k: defaults['${k}Minor'],
  };

  /// A new room follows a building price it was given unchanged.
  Map<String, bool> previewFollowsFor(Map ratesMinor, Map defaults) => {
    for (final k in _priceKinds)
      k: defaults['${k}Minor'] != null && ratesMinor[k] == defaults['${k}Minor'],
  };

  int? _roomMinor(Map room, String k) {
    final v = room[k] as num?;
    return v == null ? null : (v * _priceScale(room['currency'] ?? 'VND')).round();
  }

  Map<String, dynamic> buildingPricesPreview(Map<String, dynamic> d) {
    final b = record(buildings, d['buildingId']);
    final canPrice = workspaceRole != 'manager' || priceOverride;
    final currency = b['currency'] ?? 'VND';
    final revision = '${b['pricesRevision'] ?? 0}:0';
    final mine = rooms.where((r) => r['buildingId'] == b['id']).toList();
    if (d['action'] == 'readPrices') {
      return {
        'record': {
          'revision': revision,
          'currency': currency,
          'today': previewToday,
          'canPrice': canPrice,
          'canBackdate': workspaceRole != 'manager',
          'defaults': previewDefaults(b),
          'hourTemplates': [
            for (final t in buildingHourTemplates[b['id']] ?? const [])
              Map<String, dynamic>.from(t),
          ],
          'canSaveTemplates': canPrice,
          'electricity': {
            'priceMinor': b['electricityPriceMinor'],
            'tiered': false,
            'from': b['electricityFrom'],
            'upcoming': const [],
            'propertyRevision': '${b['pricesRevision'] ?? 0}:0',
            'earliestDate': null,
          },
          'rooms': [
            for (final r in mine)
              {
                'id': r['id'],
                'roomNumber': r['roomNumber'],
                'currency': r['currency'] ?? 'VND',
                'roomPriceMinor': _roomMinor(r, 'roomPrice'),
                'nightlyPriceMinor': _roomMinor(r, 'nightlyPrice'),
                'follows': previewFollows(r),
                'electricity': {
                  'own': r['ownElectricityMinor'] != null,
                  'ownPriceMinor': r['ownElectricityMinor'],
                  'lastReadingDate': null,
                },
              },
          ],
        },
      };
    }
    if (!canPrice) {
      throw FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'Denied',
      );
    }
    final key = 'prices-$workspaceRole-${d['operationId']}';
    if (completed.containsKey(key)) return completed[key]!;
    if (d['revision'] != revision) {
      throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'price_changed',
      );
    }
    final next = Map<String, dynamic>.from(d['defaults'] as Map);
    final apply = (d['apply'] as Map?) ?? const {};
    List ticked(String k) => (apply[k] as List?) ?? const [];
    for (final k in [..._priceKinds, 'electricity']) {
      if (ticked(k).isNotEmpty &&
          (k == 'electricity'
              ? d['electricity'] == null
              : next['${k}Minor'] == null)) {
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'price_apply_without_price',
        );
      }
    }
    b['defaultPrices'] = next;
    var count = 0;
    for (final r in mine) {
      if ((r['currency'] ?? 'VND') != currency) continue;
      final follows = previewFollows(r);
      var changed = false;
      for (final k in _priceKinds) {
        final price = next['${k}Minor'] as int?;
        if (price == null) continue;
        // A room with no price takes the building's unasked (2026-10-28).
        if (follows[k]! ||
            ticked(k).contains(r['id']) ||
            _roomMinor(r, k) == null) {
          follows[k] = true;
          if (_roomMinor(r, k) != price) {
            r[k] = price / _priceScale(currency);
            changed = true;
          }
        }
      }
      if (ticked('electricity').contains(r['id'])) {
        r['ownElectricityMinor'] = null;
        changed = true;
      }
      r['priceFollows'] = follows;
      if (changed) count++;
    }
    final e = d['electricity'] as Map?;
    if (e != null) {
      b['electricityPriceMinor'] = e['priceMinor'];
      b['electricityFrom'] = e['effectiveDate'];
    }
    b['pricesRevision'] = ((b['pricesRevision'] as int?) ?? 0) + 1;
    return completed[key] = {'buildingId': b['id'], 'rooms': count};
  }
}
