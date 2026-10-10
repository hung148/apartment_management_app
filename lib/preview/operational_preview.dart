part of 'team_preview_store.dart';

extension OperationalPreview on TeamPreviewStore {
  num? _bookingRoomRate(Map room, Object? amount, String currency) {
    if (amount is! num) return null;
    final source = room['currency'] as String? ?? 'VND';
    if (source == currency) return amount;
    final conversion = OrganizationMoney.shared.forOrganization('preview');
    if (conversion == null) return null;
    return conversion.convertMinor(
          (amount * (source == 'USD' ? 100 : 1)).round(),
          source,
          currency,
        ) /
        (currency == 'USD' ? 100 : 1);
  }

  Map<String, dynamic>? _operationalPreview(
    String name,
    Map<String, dynamic> d,
  ) {
    if (!['propertyLayout', 'invoices', 'bookingWorkspace'].contains(name)) {
      return null;
    }
    if (d['organizationId'] != 'preview' ||
        assignedOnly && d['buildingId'] != 'riverside') {
      reject();
    }
    final manager = [
          'owner',
          'administrator',
          'manager',
        ].contains(workspaceRole),
        finance = manager || workspaceRole == 'accountant',
        refund = [
          'owner',
          'administrator',
          'accountant',
        ].contains(workspaceRole),
        book = manager || workspaceRole == 'receptionist';
    if (name == 'propertyLayout' && !manager ||
        name == 'invoices' && !finance ||
        name == 'bookingWorkspace' && !book && workspaceRole != 'accountant') {
      reject();
    }
    final b = record(buildings, d['buildingId']),
        key = '$name-$workspaceRole-${d['operationId']}';
    if (d['operationId'] != null && completed.containsKey(key)) {
      return completed[key]!;
    }
    void changed(Map r) {
      r['revision'] =
          '${int.parse((r['revision'] as String? ?? '1:0').split(':').first) + 1}:0';
    }

    if (name == 'propertyLayout') {
      if (d['action'] == 'read') {
        return {
          'record': {
            'name': b['name'],
            'revision': b['revision'] ?? '1:0',
            'layout': {
              'floors': b['floors'] ?? 1,
              'roomPrefix': b['roomPrefix'] ?? '',
              'roomType': b['roomType'] ?? '',
              'roomArea': b['roomArea'] ?? 0,
              'floorRoomCounts': b['floorRoomCounts'] ?? [0],
            },
          },
        };
      }
      if (d['revision'] != (b['revision'] ?? '1:0')) {
        throw FirebaseFunctionsException(code: 'aborted', message: 'Changed');
      }
      b.addAll(Map<String, dynamic>.from(d['layout'] as Map));
      changed(b);
      return completed[key] = {'buildingId': b['id']};
    }
    final zone = b['timeZone'];
    if (zone == null) {
      throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'Timezone',
      );
    }
    if (name == 'invoices') {
      if (d['action'] == 'history') {
        return {
          'records': invoiceHistories[d['invoiceId']] ?? [],
          'nextCursor': null,
        };
      }
      void audit(Map<String, dynamic> row, Map<String, dynamic>? before) {
        invoiceHistories.putIfAbsent(row['id'] as String, () => []).insert(0, {
          'id': key,
          'action': d['action'],
          'actorId': 'preview-$workspaceRole',
          'createdAt': '2026-09-27T12:00:00Z',
          'reason': d['reason'],
          'before': before == null
              ? null
              : {
                  'totalMinor': before['totalMinor'],
                  'paidAmount':
                      (before['paidMinor'] as num) /
                      (before['currency'] == 'USD' ? 100 : 1),
                  'status': before['status'],
                },
          'after': {
            'totalMinor': row['totalMinor'],
            'paidAmount':
                (row['paidMinor'] as num) /
                (row['currency'] == 'USD' ? 100 : 1),
            'status': row['status'],
          },
        });
      }

      const fees = [
        'internetFee',
        'cableTVFee',
        'hotWaterFee',
        'lateFee',
        'taxAmount',
      ];
      Map<String, dynamic> projection(Map<String, dynamic> row) => {
        ...row,
        'canEdit': manager && priceOverride,
        'canSettle': finance && row['direction'] == 'expense',
        'canReverse': refund && row['direction'] == 'expense',
      };
      if (d['action'] == 'list') {
        return {
          'records': operationalInvoices
              .where((r) => r['buildingId'] == b['id'])
              .map(projection)
              .toList(),
          'nextCursor': null,
          'canCreate': finance,
          'canPrice': manager && priceOverride,
        };
      }
      if (d['action'] == 'read') {
        return {
          'record': projection(record(operationalInvoices, d['invoiceId'])),
        };
      }
      if (d['action'] == 'tenants') {
        return {
          'records': tenants
              .where(
                (t) => t['buildingId'] == b['id'] && t['isMainTenant'] == true,
              )
              .toList(),
          'today': '2026-09-27',
          'timeZone': zone,
          'currency': b['currency'] ?? 'VND',
        };
      }
      if (!finance) reject();
      if (['quote', 'create'].contains(d['action'])) {
        final start = DateTime.tryParse('${d['startDate']}T00:00:00Z'),
            end = DateTime.tryParse('${d['endDate']}T00:00:00Z');
        if (start == null ||
            end == null ||
            !end.isAfter(start) ||
            end.difference(start).inDays > 366) {
          throw FirebaseFunctionsException(
            code: 'invalid-argument',
            message: 'Period',
          );
        }
        final buildingRent = d['kind'] == 'buildingRent',
            contract = b['rentalContract'] as Map?,
            tenant = buildingRent ? null : record(tenants, d['tenantId']);
        if (buildingRent && contract == null) {
          throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'Contract',
          );
        }
        final currency = buildingRent
                ? b['currency'] ?? 'VND'
                : tenant!['currency'] ?? 'VND',
            direction = buildingRent && contract!['direction'] == 'rentIn'
                ? 'expense'
                : 'income',
            base =
                (buildingRent
                        ? contract!['amountMinor']
                        : tenant!['monthlyRentMinor'])
                    as num;
        double total = 0;
        int days = 0;
        for (
          var date = start;
          date.isBefore(end);
          date = date.add(const Duration(days: 1))
        ) {
          final day = date.toIso8601String().substring(0, 10),
              first = buildingRent
                  ? contract!['startDate'] as String
                  : tenant!['moveInLocalDate'] as String? ?? '2026-09-01',
              last = buildingRent
                  ? contract!['endDate']
                  : tenant!['moveOutDate'];
          if (day.compareTo(first) < 0 ||
              (last != null && day.compareTo(last as String) >= 0)) {
            continue;
          }
          num rate = base;
          for (final v in tenant?['rentSchedule'] as List? ?? []) {
            if ((v['effectiveDate'] as String).compareTo(day) <= 0) {
              rate = v['amountMinor'] as num;
            }
          }
          total += rate / DateTime.utc(date.year, date.month + 1, 0).day;
          days++;
        }
        if (d['kind'] == 'charge') {
          total =
              (d['unitPriceMinor'] as num) * (d['quantityMilli'] as num) / 1000;
        }
        final values = Map<String, dynamic>.from(d['feesMinor'] as Map),
            amount = total.round(),
            gross =
                amount + fees.fold<int>(0, (v, k) => v + (values[k] as int));
        final quote = {
          'amountMinor': amount,
          'totalMinor': gross,
          'days': days,
          'lines': <Map<String, dynamic>>[],
          'timeZone': zone,
          'startDate': d['startDate'],
          'endDate': d['endDate'],
          'dueDate': d['dueDate'],
          'feesMinor': values,
          'currency': currency,
          'direction': direction,
          'tenantName': buildingRent
              ? contract!['partyName']
              : tenant!['fullName'],
          'quoteRevision': 'preview-quote',
        };
        if (d['action'] == 'quote') return {'record': quote};
        if (operationalInvoices.any(
          (r) =>
              r['kind'] == d['kind'] &&
              r['tenantId'] == d['tenantId'] &&
              r['startDate'] == d['startDate'] &&
              r['status'] != 'cancelled',
        )) {
          throw FirebaseFunctionsException(
            code: 'already-exists',
            message: 'Duplicate period',
          );
        }
        final row = <String, dynamic>{
          ...quote,
          'id': key,
          'revision': '1:0',
          'buildingId': b['id'],
          'tenantId': d['tenantId'],
          'kind': d['kind'],
          'paidMinor': 0,
          'status': 'pending',
        };
        operationalInvoices.insert(0, row);
        audit(row, null);
        return completed[key] = {'invoiceId': key};
      }
      final row = record(operationalInvoices, d['invoiceId']);
      final previous = Map<String, dynamic>.from(row);
      if (row['revision'] != d['revision']) {
        throw FirebaseFunctionsException(code: 'aborted', message: 'Changed');
      }
      if (d['action'] == 'edit') {
        if (!manager || !priceOverride) reject();
        row['feesMinor'] = d['feesMinor'];
        row['totalMinor'] =
            (row['amountMinor'] as int) +
            fees.fold<int>(0, (n, k) => n + (d['feesMinor'][k] as int));
        row['dueDate'] = d['dueDate'];
      }
      if (d['action'] == 'void') {
        if (!manager || !priceOverride) reject();
        if (row['paidMinor'] != 0) {
          throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'Refund first',
          );
        }
        row['status'] = 'cancelled';
      }
      if (['payExpense', 'reverseExpense'].contains(d['action'])) {
        if (row['direction'] != 'expense' ||
            d['action'] == 'reverseExpense' && !refund) {
          reject();
        }
        final next =
            (row['paidMinor'] as int) +
            (d['action'] == 'payExpense' ? 1 : -1) * (d['amountMinor'] as int);
        if (next < 0 || next > (row['totalMinor'] as int)) {
          throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'Amount',
          );
        }
        row['paidMinor'] = next;
        row['status'] = next == row['totalMinor']
            ? 'paid'
            : next == 0
            ? 'pending'
            : 'partial';
      }
      changed(row);
      audit(row, previous);
      return completed[key] = {'invoiceId': row['id']};
    }
    Map<String, dynamic> projection(Map<String, dynamic> row) => {
      ...row,
      'timeZone': zone,
      'canManage': book,
      'canCollect': book || workspaceRole == 'accountant',
      'canRefund': refund,
    };
    if (d['action'] == 'list') {
      return {
        'records': operationalBookings
            .where((r) => r['buildingId'] == b['id'])
            .map(projection)
            .toList(),
        'nextCursor': null,
        'canManage': book,
        'timeZone': zone,
      };
    }
    // Saved nightly prices (2026-10-09, Tom): owner, administrator and
    // manager may add and remove them, like the server's template.
    if (d['action'] == 'prices') {
      if (!manager) reject();
      final many = d['pricesMinor'];
      final prices = many is List ? many.cast<Object?>() : [d['priceMinor']];
      if (prices.isEmpty || prices.any((p) => p is! int || p <= 0)) {
        throw FirebaseFunctionsException(
          code: 'invalid-argument',
          message: 'booking_invalid-argument',
        );
      }
      final id = b['id'] as String;
      final list = buildingPriceLists[id] = nightPricesOf(id);
      if (d['remove'] == true) {
        list.remove(prices.single);
      } else {
        final add = prices.cast<int>().toSet().where((p) => !list.contains(p));
        if (list.length + add.length > 12) {
          throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'booking_saved_prices_full',
          );
        }
        list.addAll(add);
      }
      list.sort();
      return {
        'buildingId': id,
        'currency': 'VND',
        'savedNightPricesMinor': List.of(list),
      };
    }
    if (d['action'] == 'rooms') {
      return {
        'canPrice': manager && priceOverride,
        'canSavePrices': manager,
        'canCollect': book,
        'today': previewToday,
        'records': [
          for (final r in rooms.where(
            (r) =>
                // 2026-10-04: every room takes short stays.
                r['buildingId'] == b['id'],
          ))
            {
              ...r,
              // Room prices in minor units, like the server (B2 / 2026-10-03).
              'nightlyPriceMinor': switch (r['nightlyPrice'] ??
                  r['dailyPrice']) {
                final num v => (v * (r['currency'] == 'USD' ? 100 : 1)).round(),
                _ => null,
              },
              'hourlyPriceMinor': switch (r['hourlyPrice']) {
                final num v => (v * (r['currency'] == 'USD' ? 100 : 1)).round(),
                _ => null,
              },
              'savedNightPricesMinor': (r['currency'] ?? 'VND') == 'VND'
                  ? nightPricesOf(b['id'] as String)
                  : <int>[],
            },
        ],
        'timeZone': zone,
      };
    }
    if (d['action'] == 'read') {
      return {
        'record': projection(record(operationalBookings, d['bookingId'])),
      };
    }
    if (['quote', 'save'].contains(d['action'])) {
      if (!book) reject();
      final room = record(rooms, d['roomId']),
          start = DateTime.tryParse(
            (d['startLocal'] as String).replaceAll(' ', 'T'),
          ),
          end = DateTime.tryParse(
            (d['endLocal'] as String).replaceAll(' ', 'T'),
          );
      if (start == null || end == null || !end.isAfter(start)) {
        throw FirebaseFunctionsException(
          code: 'invalid-argument',
          message: 'Dates',
        );
      }
      final currency = d['inputCurrency'] ?? room['currency'] ?? 'VND',
          scale = currency == 'USD' ? 100 : 1,
          hourlyMinor = d['pricingType'] == 'hourly'
              ? (d['hourlyPriceMinor'] as int?)
              : null,
          rate = hourlyMinor != null
              ? hourlyMinor / scale
              : d['pricingType'] == 'nightly'
              ? _bookingRoomRate(
                  room,
                  room['nightlyPrice'] ?? room['dailyPrice'],
                  currency as String,
                )
              : _bookingRoomRate(
                  room,
                  room['${d['pricingType']}Price'],
                  currency as String,
                );
      if (rate == null) {
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'Rate',
        );
      }
      final nights = DateTime.utc(
        end.year,
        end.month,
        end.day,
      ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
      final custom = (d['nightPricesMinor'] as List?)?.cast<int>();
      // Like the server: without "Đổi giá" only the room's price and its
      // saved prices, in the room's own currency.
      if (custom != null && !(manager && priceOverride)) {
        final own = room['nightlyPrice'] ?? room['dailyPrice'];
        final ok = {
          if (currency == (room['currency'] ?? 'VND')) ...[
            ...nightPricesOf(b['id'] as String),
            if (own is num) (own * scale).round(),
          ],
        };
        if (custom.isEmpty || !custom.every(ok.contains)) reject();
      }
      final calculatedAmount = custom != null
          ? custom.fold<int>(0, (a, b) => a + b)
          : (rate *
                    scale *
                    (d['pricingType'] == 'hourly'
                        ? end.difference(start).inMinutes / 60
                        : d['pricingType'] == 'nightly'
                        ? nights
                        : (end.difference(start).inMinutes / 1440).ceil()))
                .round();
      final surcharges = [
        for (final s in (d['surcharges'] as List? ?? const []))
          Map<String, dynamic>.from(s as Map),
      ];
      // Per person (2026-10-04): × the number of guests, once.
      final guests = (d['numberOfGuests'] as int?) ?? 1;
      int line(Map s) =>
          (s['amountMinor'] as int) * (s['basis'] == 'person' ? guests : 1);
      final surchargesMinor = surcharges.fold<int>(0, (a, s) => a + line(s));
      // An agreed room price (Fix 5, 2026-10-09), like the server: needs
      // "Đổi giá" and a reason; left out of an edit it is kept; null removes it.
      final current = d['bookingId'] == null
          ? null
          : operationalBookings
                .where((v) => v['id'] == d['bookingId'])
                .firstOrNull;
      final had = current?['priceOverride'] as Map?;
      final canPriceHere = manager && priceOverride;
      final why = '${d['overrideReason'] ?? ''}'.trim();
      if (d['overrideMinor'] != null && (!canPriceHere || why.isEmpty)) {
        reject();
      }
      if (d.containsKey('overrideMinor') &&
          d['overrideMinor'] == null &&
          had != null &&
          !canPriceHere) {
        reject();
      }
      final agreedMinor =
          d['overrideMinor'] as int? ??
          (!d.containsKey('overrideMinor') && had != null
              ? ((had['total'] as num) * scale).round()
              : null);
      final base = agreedMinor ?? calculatedAmount;
      final amount = base + surchargesMinor;
      final quote = {
        'totalMinor': amount,
        'baseMinor': base,
        'surchargesMinor': surchargesMinor,
        if (agreedMinor != null) ...{
          'calculatedMinor': calculatedAmount,
          'agreedMinor': agreedMinor,
          'agreedReason': d['overrideMinor'] != null ? why : had?['reason'],
        },
        'guests': guests,
        'surchargeLines': [
          for (final s in surcharges)
            {
              'label': s['label'],
              'basis': s['basis'] == 'person' ? 'person' : 'room',
              'unitMinor': s['amountMinor'],
              'count': s['basis'] == 'person' ? guests : 1,
              'totalMinor': line(s),
            },
        ],
        if (d['pricingType'] == 'nightly') 'nights': nights,
        'pricingType': d['pricingType'],
        'currency': currency,
        'roomRevision': room['revision'],
        'timeZone': zone,
        'startTime': start.toIso8601String(),
        'endTime': end.toIso8601String(),
      };
      if (d['action'] == 'quote') return {'record': quote};
      Map<String, dynamic> row;
      if (d['revision'] == null) {
        if (operationalBookings.any(
          (v) =>
              v['roomId'] == room['id'] &&
              ['pending', 'confirmed', 'checkedIn'].contains(v['status']) &&
              DateTime.parse(v['endTime'] as String).isAfter(start) &&
              DateTime.parse(v['startTime'] as String).isBefore(end),
        )) {
          throw FirebaseFunctionsException(
            code: 'already-exists',
            message: 'Overlap',
          );
        }
        row = {
          'id': d['bookingId'],
          'revision': '1:0',
          'buildingId': b['id'],
          'status': 'pending',
          'paidAmount': 0,
          'depositPaidAmount': 0,
          'depositRefundedAmount': 0,
        };
        operationalBookings.insert(0, row);
      } else {
        row = record(operationalBookings, d['bookingId']);
        if (row['revision'] != d['revision']) {
          throw FirebaseFunctionsException(code: 'aborted', message: 'Changed');
        }
      }
      row.addAll({
        ...quote,
        'roomId': room['id'],
        'guestName': d['guestName'],
        'guestPhone': d['guestPhone'],
        'notes': d['notes'],
        'startLocal': d['startLocal'],
        'endLocal': d['endLocal'],
        'pricingType': d['pricingType'],
        'totalPrice': amount / scale,
        'depositAmount': (d['depositMinor'] as num) / scale,
        for (final k in [
          'guestIdNumber',
          'guests',
          'numberOfGuests',
          'staffInChargeId',
          'platform',
          'contactChannel',
          'depositNote',
        ])
          if (d.containsKey(k)) k: d[k],
        'surcharges': [
          for (final s in surcharges)
            {
              'label': s['label'],
              'amount': line(s) / scale,
              if (s['basis'] == 'person') ...{
                'basis': 'person',
                'unitAmount': (s['amountMinor'] as int) / scale,
                'count': guests,
              },
            },
        ],
        'hourlyPrice': hourlyMinor == null ? null : hourlyMinor / scale,
        'nightPrices': custom?.map((v) => v / scale).toList(),
      });
      if (d['overrideMinor'] != null) {
        row['priceOverride'] = {
          'total': (d['overrideMinor'] as int) / scale,
          'calculatedTotal': calculatedAmount / scale,
          'reason': why,
          'byName': 'Preview $workspaceRole',
          'at': '${previewToday}T00:00:00.000Z',
        };
      } else if (d.containsKey('overrideMinor') && had != null) {
        row['priceOverride'] = null;
      }
      // A deposit taken with the booking (2026-10-04) is a payment toward the total.
      final deposit = d['deposit'] as Map?;
      if (deposit != null) {
        final paid = ((row['paidAmount'] as num) * scale).round();
        if (!book || row['depositPayment'] != null) reject();
        if ((deposit['amountMinor'] as int) + paid > amount) {
          throw FirebaseFunctionsException(
            code: 'invalid-argument',
            message: 'booking_deposit_too_large',
          );
        }
        if ((deposit['paidOn'] as String).compareTo(previewToday) > 0) {
          throw FirebaseFunctionsException(
            code: 'invalid-argument',
            message: 'booking_deposit_date',
          );
        }
        row['paidAmount'] = (paid + (deposit['amountMinor'] as int)) / scale;
        row['depositPayment'] = {
          'amount': (deposit['amountMinor'] as int) / scale,
          'paymentMethod': deposit['method'],
          'paidOn': deposit['paidOn'],
        };
      }
      changed(row);
      return completed[key] = {'id': row['id']};
    }
    final row = record(operationalBookings, d['bookingId']);
    if (row['revision'] != d['revision']) {
      throw FirebaseFunctionsException(code: 'aborted', message: 'Changed');
    }
    final action = d['command'],
        scale = row['currency'] == 'USD' ? 100 : 1,
        amount = (d['amountMinor'] as num? ?? 0) / scale;
    if (action == 'status') {
      if (!book) reject();
      row['status'] = d['status'];
    }
    if (action == 'payment') {
      row['paidAmount'] = (row['paidAmount'] as num) + amount;
    }
    if (action == 'deposit') {
      row['depositPaidAmount'] = (row['depositPaidAmount'] as num) + amount;
    }
    if (action == 'refund') {
      if (!refund) reject();
      row['depositRefundedAmount'] =
          (row['depositRefundedAmount'] as num) + amount;
    }
    if (action == 'refundRent') {
      if (!refund) reject();
      row['paidAmount'] = (row['paidAmount'] as num) - amount;
    }
    if (action == 'checkout') {
      if (!book) reject();
      row['status'] = 'checkedOut';
      row['paidAmount'] = row['totalPrice'];
    }
    changed(row);
    return completed[key] = {'id': row['id']};
  }
}
