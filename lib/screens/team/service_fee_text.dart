import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../../services/team_service.dart' show serverReason;
import '../../utils/app_number.dart';
import '../../utils/localizations/app_localizations.dart';

/// Shared wording and number handling for B5 service fees (SERVICE_FEES.md).
class FeeText {
  final BuildContext context;
  FeeText(this.context);
  bool get vi => AppTranslations.of(context).locale.languageCode == 'vi';
  String tr(String en, String vi) => this.vi ? vi : en;

  // One number style in every language (2026-10-05, Tom): money
  // 5,000,000 VND · 2,000.50 USD; quantities 1200.5 (no thousands mark).
  String money(num minor, String currency) => appMoneyMinor(minor, currency);

  String quantity(int milli) => appQuantityMilli(milli);

  String basis(String b) => switch (b) {
    'room' => tr('Per room', 'Theo phòng'),
    'person' => tr('Per person', 'Theo người'),
    _ => tr('By quantity', 'Theo số lượng'),
  };

  /// "100.000 VND / người / kỳ" or "15.000 VND / kg".
  String rate(Map fee, Map terms, String currency) {
    final unit = fee['basis'] == 'person'
        ? tr(' / person', ' / người')
        : fee['basis'] == 'quantity'
        ? ' / ${(fee['unitLabel'] as String?)?.isNotEmpty == true ? fee['unitLabel'] : tr('unit', 'đơn vị')}'
        : tr(' / room', ' / phòng');
    final period = fee['basis'] == 'quantity' ? '' : tr(' / period', ' / kỳ');
    return '${money(terms['rateMinor'] as num, terms['currency'] as String? ?? currency)}$unit$period';
  }

  /// [prefix]: false when a label next to it already says "partial periods".
  String rule(Map? rule, {bool prefix = true}) {
    if (rule == null) return '';
    final p = prefix ? tr('Partial periods: ', 'Ở không đủ kỳ: ') : '';
    switch (rule['mode']) {
      case 'days':
        return '$p${tr('by days stayed', 'tính theo số ngày ở')}';
      case 'checkDate':
        return rule['day'] == 'first'
            ? tr(
                'Counts people present on the first day',
                'Tính người có mặt ngày đầu kỳ',
              )
            : tr(
                'Counts people present on the last day',
                'Tính người có mặt ngày cuối kỳ',
              );
      default:
        final steps = (rule['steps'] as List)
            .map(
              (s) => tr(
                'from ${s['minDays']} days: ${s['percent']}%',
                'từ ${s['minDays']} ngày: ${s['percent']}%',
              ),
            )
            .join(', ');
        return '$p$steps';
    }
  }

  String terms(Map fee, Map? terms, String currency) {
    if (terms == null) return tr('Not charged today', 'Hiện không thu');
    return [
      rate(fee, terms, currency),
      if ((terms['includedPeople'] as int? ?? 0) > 0)
        tr(
          'first ${terms['includedPeople']} people free',
          '${terms['includedPeople']} người đầu miễn phí',
        ),
    ].join(' · ');
  }

  /// One invoice line: "Le Van Chinh: 10/30 ngày → 33.333 VND".
  String line(Map l, String currency, {String unitLabel = ''}) {
    if (l['quantityMilli'] != null) {
      return '${l['name']}: ${quantity(l['quantityMilli'] as int)}${unitLabel.isEmpty ? '' : ' $unitLabel'} = ${money(l['amountMinor'] as num, currency)}';
    }
    final days = tr(
      '${l['days']}/${l['periodDays']} days',
      '${l['days']}/${l['periodDays']} ngày',
    );
    return l['free'] == true
        ? '${l['name']}: $days = ${tr('free', 'miễn phí')}'
        : '${l['name']}: $days = ${money(l['amountMinor'] as num, currency)}';
  }

  static const errors = [
    'service_fee_boundary_required',
    'service_fee_not_in_force',
    'service_tenant_not_in_room',
    'service_no_billable_charge',
    'invoice_period_exists',
    'service_currency_mismatch',
    'invoice_backdate_owner_required',
    'service_fee_past_billed',
    'service_fee_date_exists',
    'service_fee_name_exists',
    'service_changed',
    'service_fee_limit',
    'service_fee_history_limit',
    'service_invalid_period',
    'service_invalid_quantity',
    'service_fee_not_found',
    'service_amount_too_large',
  ];

  /// A message the person can act on. [uncertain]: the save may have happened.
  String error(Object e, {bool uncertain = false}) {
    final key = serverReason(e, errors);
    switch (key) {
      case 'service_fee_boundary_required':
        return tr(
          'The price changes inside this period. Bill up to the change date, then from it.',
          'Giá thay đổi trong kỳ này. Lập hóa đơn đến ngày đổi giá, rồi một hóa đơn từ ngày đó.',
        );
      case 'service_fee_not_in_force':
        return tr(
          'This fee does not apply to the room on these dates.',
          'Phí này không áp dụng cho phòng trong những ngày này.',
        );
      case 'service_tenant_not_in_room':
        return tr(
          'This tenant did not live in this room during the period.',
          'Khách này không ở phòng này trong kỳ đã chọn.',
        );
      case 'service_no_billable_charge':
        return tr(
          'Nothing to charge for this period (everyone may be free).',
          'Kỳ này không có khoản phải thu (có thể tất cả đều được miễn).',
        );
      case 'invoice_period_exists':
        return tr(
          'This fee is already billed to this tenant for overlapping days.',
          'Phí này đã có hóa đơn trùng ngày cho khách này.',
        );
      case 'service_currency_mismatch':
        return tr(
          "The tenant's currency differs from the property's.",
          'Tiền tệ của khách khác với tiền tệ của tòa nhà.',
        );
      case 'invoice_backdate_owner_required':
        return tr(
          'Dates before today need the "Enter past dates" permission. Ask the owner to add it to your role.',
          'Ngày trước hôm nay cần quyền "Nhập ngày trong quá khứ". Nhờ chủ nhà thêm quyền này cho vai trò của bạn.',
        );
      case 'service_fee_past_billed':
        return tr(
          'Invoices already cover earlier dates. Choose a date on or after the last billed day.',
          'Đã có hóa đơn cho những ngày trước. Chọn ngày áp dụng từ ngày cuối đã lập hóa đơn trở đi.',
        );
      case 'service_fee_date_exists':
        return tr(
          'A change already exists on that date. Choose another date.',
          'Đã có thay đổi vào ngày này. Hãy chọn ngày khác.',
        );
      case 'service_fee_name_exists':
        return tr(
          'Another fee already has this name.',
          'Đã có phí khác cùng tên.',
        );
      case 'service_changed':
        return tr(
          'Someone else just changed these fees. Reload, then try again.',
          'Có người vừa thay đổi các phí này. Tải lại rồi thử lại.',
        );
      case 'service_fee_limit':
        return tr(
          'A property can have at most 30 fees.',
          'Mỗi tòa nhà có tối đa 30 loại phí.',
        );
      case 'service_fee_history_limit':
        return tr(
          'This fee has too many dated changes.',
          'Phí này đã có quá nhiều lần thay đổi.',
        );
      case 'service_invalid_period':
        return tr('Check the dates.', 'Kiểm tra lại ngày.');
      case 'service_invalid_quantity':
        return tr('Enter a quantity above 0.', 'Nhập số lượng lớn hơn 0.');
      case 'service_fee_not_found':
        return tr(
          'This fee no longer exists. Reload.',
          'Phí này không còn. Hãy tải lại.',
        );
      case 'service_amount_too_large':
        return tr('The amount is too large.', 'Số tiền quá lớn.');
    }
    if (e is FirebaseFunctionsException && e.code == 'permission-denied') {
      return tr(
        'You do not have permission to do this.',
        'Bạn không có quyền làm việc này.',
      );
    }
    return uncertain
        ? tr(
            'Save was not confirmed. Retry the same request, or reload before changing anything.',
            'Chưa xác nhận lưu. Thử lại đúng yêu cầu này, hoặc tải lại trước khi sửa.',
          )
        : tr(
            'Could not complete this. Check your connection and try again.',
            'Chưa thực hiện được. Kiểm tra kết nối rồi thử lại.',
          );
  }

  /// Network-type failures may have saved; keep the request for an exact retry.
  static bool uncertain(Object e) =>
      e is! FirebaseFunctionsException ||
      [
        'unavailable',
        'internal',
        'deadline-exceeded',
        'unknown',
      ].contains(e.code);
}

/// "5,000,000" / "2,000.50" → minor units; null when invalid (negative,
/// too many decimals, too large). VND has no decimals; USD has cents.
int? parseMinor(String input, String currency) =>
    appParseMoney(input, currency);

/// Calendar date "YYYY-MM-DD" and day arithmetic without time zones.
bool feeDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final parsed = DateTime.tryParse(value);
  return parsed != null && parsed.toIso8601String().substring(0, 10) == value;
}

String addDays(String date, int days) => DateTime.utc(
  int.parse(date.substring(0, 4)),
  int.parse(date.substring(5, 7)),
  int.parse(date.substring(8, 10)),
).add(Duration(days: days)).toIso8601String().substring(0, 10);

/// Inclusive "from–to" for display from a server end-exclusive period.
String periodText(String start, String endExclusive) =>
    '$start – ${addDays(endExclusive, -1)}';
