part of 'team_preview_store.dart';

extension OperationalPreview on TeamPreviewStore {
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
        name == 'invoices' && !finance && workspaceRole != 'viewer' ||
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
    if (d['action'] == 'rooms') {
      return {
        'canPrice': manager && priceOverride,
        'records': rooms
            .where(
              (r) =>
                  r['buildingId'] == b['id'] &&
                  ['both', 'hourly'].contains(r['rentalMode']),
            )
            .toList(),
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
      final currency = room['currency'] ?? 'VND',
          scale = currency == 'USD' ? 100 : 1,
          rate = room['${d['pricingType']}Price'] as num?;
      if (rate == null) {
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'Rate',
        );
      }
      final calculatedAmount =
          (rate *
                  scale *
                  (d['pricingType'] == 'hourly'
                      ? end.difference(start).inMinutes / 60
                      : (end.difference(start).inMinutes / 1440).ceil()))
              .round();
      final amount = d['overrideMinor'] as int? ?? calculatedAmount;
      final quote = {
        'totalMinor': amount,
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
      });
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
